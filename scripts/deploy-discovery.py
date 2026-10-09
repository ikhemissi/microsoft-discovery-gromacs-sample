import argparse
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urljoin, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

import yaml


ROOT = Path(__file__).resolve().parents[1]
EXPERIMENT = ROOT / "experiments" / "lysozyme-water"
ARM = "https://management.azure.com"
ARM_VERSION = "2026-06-01"
DATA_VERSION = "2026-02-01-preview"
IMAGE = "discovery-lysozyme:discovery-cpu"


def capture(arguments, input_text=None):
    result = subprocess.run(
        arguments, input=input_text, capture_output=True, text=True, cwd=ROOT,
        timeout=120,
    )
    if result.returncode:
        raise RuntimeError(
            f"{arguments[0]} {arguments[1]} failed (exit {result.returncode}); "
            "check authentication, permissions and local prerequisites."
        )
    return result.stdout.strip()


def settings(environment):
    required = (
        "AZURE_ENV_NAME", "AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP", "AZURE_LOCATION",
        "AZURE_CONTAINER_REGISTRY_NAME", "AZURE_CONTAINER_REGISTRY_ENDPOINT",
        "DISCOVERY_WORKSPACE_ID", "DISCOVERY_PROJECT_ID",
        "DISCOVERY_CHAT_MODEL_ID", "DISCOVERY_NODE_POOL_ID",
    )
    missing = [key for key in required if not environment.get(key)]
    if missing:
        raise ValueError("Missing azd outputs: " + ", ".join(missing))
    values = {key: environment[key] for key in required}
    if not re.fullmatch(r"[A-Za-z0-9_-]+", values["AZURE_ENV_NAME"]):
        raise ValueError("Unsafe azd environment name")
    workspace = values["DISCOVERY_WORKSPACE_ID"]
    scope = (
        f"/subscriptions/{values['AZURE_SUBSCRIPTION_ID']}/resourceGroups/"
        f"{values['AZURE_RESOURCE_GROUP']}/providers/Microsoft.Discovery/"
    )
    if not workspace.startswith(scope + "workspaces/") or not re.fullmatch(r"[A-Za-z0-9-]+", workspace[len(scope + "workspaces/"):]):
        raise ValueError("Workspace must belong to the configured subscription and resource group")
    if values["DISCOVERY_PROJECT_ID"] != workspace + "/projects/" + values["DISCOVERY_PROJECT_ID"].rsplit("/", 1)[-1]:
        raise ValueError("Project must belong to the configured workspace")
    if values["DISCOVERY_CHAT_MODEL_ID"] != workspace + "/chatModelDeployments/" + values["DISCOVERY_CHAT_MODEL_ID"].rsplit("/", 1)[-1]:
        raise ValueError("Chat model must belong to the configured workspace")
    if not re.fullmatch(re.escape(scope) + r"supercomputers/[A-Za-z0-9-]+/nodePools/[A-Za-z0-9-]+", values["DISCOVERY_NODE_POOL_ID"]):
        raise ValueError("Node pool must belong to the configured subscription and resource group")
    for key in ("DISCOVERY_PROJECT_ID", "DISCOVERY_CHAT_MODEL_ID", "DISCOVERY_NODE_POOL_ID"):
        if not re.fullmatch(r"[A-Za-z0-9-]+", values[key].rsplit("/", 1)[-1]):
            raise ValueError(f"Invalid resource name in {key}")
    registry = values["AZURE_CONTAINER_REGISTRY_ENDPOINT"]
    if registry != values["AZURE_CONTAINER_REGISTRY_NAME"] + ".azurecr.io":
        raise ValueError("Registry name and endpoint do not match")
    values["model"] = environment.get("DISCOVERY_CHAT_MODEL_DEPLOYMENT_NAME") or values["DISCOVERY_CHAT_MODEL_ID"].rsplit("/", 1)[-1]
    if not re.fullmatch(r"[A-Za-z0-9-]+", values["model"]):
        raise ValueError("Invalid chat-model deployment name")
    values["model_id"] = workspace + "/chatModelDeployments/" + values["model"]
    values["endpoint"] = "https://" + workspace.rsplit("/", 1)[-1] + ".workspace.discovery.azure.com"
    values["project"] = values["DISCOVERY_PROJECT_ID"].rsplit("/", 1)[-1]
    values["artifact_dir"] = ROOT / ".azure" / values["AZURE_ENV_NAME"] / "discovery"
    return values


def definitions(values, image):
    tool = yaml.safe_load((EXPERIMENT / "tool.cpu.yaml").read_text())
    agent = yaml.safe_load((EXPERIMENT / "agent.yaml").read_text())
    tool = copy.deepcopy(tool)
    agent = copy.deepcopy(agent)
    if not re.fullmatch(r"[A-Za-z0-9-]{3,24}", tool["name"]):
        raise ValueError("Tool ARM name must have 3-24 alphanumeric or hyphen characters")
    tool["infra"][0]["image"]["acr"] = image
    tool_id = (
        f"/subscriptions/{values['AZURE_SUBSCRIPTION_ID']}/resourceGroups/"
        f"{values['AZURE_RESOURCE_GROUP']}/providers/Microsoft.Discovery/tools/{tool['name']}"
    )
    if agent["model"]["id"] != "{{CHAT-MODEL}}":
        raise ValueError("Expected the agent chat-model placeholder")
    tools = agent["discoveryExtensions"]["tools"]
    if len(tools) != 1 or tools[0]["toolId"] != "{{gromacsToolId}}":
        raise ValueError("Expected exactly one GROMACS tool placeholder")
    agent["model"]["id"] = values["model"]
    tools[0]["toolId"] = tool_id
    if "{{" in json.dumps(agent):
        raise ValueError("Unresolved agent placeholders")
    if agent["discoveryExtensions"]["humanInTheLoop"] != "Enabled" or tools[0]["confirmation"] != "Enabled":
        raise ValueError("Agent and tool confirmation must remain enabled")
    extensions = agent["discoveryExtensions"]
    payload = {
        "name": agent["name"],
        "humanInTheLoop": extensions["humanInTheLoop"],
        "tools": tools,
        "discoveryExtensions": {
            key: value for key, value in extensions.items()
            if key not in ("humanInTheLoop", "tools", "knowledgeBases")
        },
        "foundryDetails": {
            "description": agent["description"],
            "definition": {
                "kind": agent["kind"], "model": agent["model"]["id"],
                "instructions": agent["instructions"],
            },
        },
    }
    if "knowledgeBases" in extensions:
        payload["knowledgeBases"] = extensions["knowledgeBases"]
    return tool, agent, payload, tool_id


class RejectRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


class Azure:
    def __init__(self, subscription, endpoint):
        self.subscription = subscription
        self.endpoint = endpoint

    def request(self, method, url, body=None, allow_missing=False):
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.netloc not in (
            urlparse(ARM).netloc, urlparse(self.endpoint).netloc
        ):
            raise ValueError("Refusing to send credentials to an unexpected endpoint")
        audience = ARM + "/" if parsed.netloc == urlparse(ARM).netloc else "https://discovery.azure.com/"
        token = capture([
            "az", "account", "get-access-token", "--subscription", self.subscription,
            "--resource", audience, "--query", "accessToken", "--output", "tsv",
            "--only-show-errors",
        ])
        request = Request(
            url, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        )
        try:
            with build_opener(RejectRedirects()).open(request, timeout=60) as response:
                content = response.read()
                return response.status, json.loads(content) if content else {}, dict(response.headers)
        except HTTPError as error:
            if allow_missing and error.code == 404:
                return 404, {}, {}
            raise RuntimeError(f"Discovery request failed: {method} {parsed.path} (HTTP {error.code})") from None


def arm_url(resource_id):
    return ARM + resource_id + "?api-version=" + ARM_VERSION


def wait_ready(azure, url, operation=False, timeout=1800):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        _, body, _ = azure.request("GET", url)
        state = body.get("status") if operation else body.get("properties", {}).get("provisioningState")
        if state == "Succeeded":
            return body
        if state in ("Failed", "Canceled", "Cancelled"):
            raise RuntimeError(f"Deployment ended with {state}: {urlparse(url).path}")
        if not state:
            raise RuntimeError("Deployment response is missing its authoritative status")
        print(f"Waiting: {state}", flush=True)
        time.sleep(10)
    raise TimeoutError("Deployment timed out; inspect Azure before retrying. No operation was canceled.")


def resolve_image(values):
    digest = capture([
        "az", "acr", "repository", "show", "--name", values["AZURE_CONTAINER_REGISTRY_NAME"],
        "--subscription", values["AZURE_SUBSCRIPTION_ID"], "--image", IMAGE,
        "--query", "digest", "--output", "tsv", "--only-show-errors",
    ])
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("ACR did not return a valid image digest")
    return values["AZURE_CONTAINER_REGISTRY_ENDPOINT"] + "/" + IMAGE.split(":")[0] + "@" + digest


def publish_image(values, engine):
    if not shutil.which(engine):
        raise ValueError(f"Missing container engine: {engine}")
    registry = values["AZURE_CONTAINER_REGISTRY_ENDPOINT"]
    tagged = registry + "/" + IMAGE
    subprocess.run([
        engine, "build", "--target", "discovery", "--platform", "linux/amd64",
        "--tag", tagged, str(EXPERIMENT),
    ], check=True, cwd=ROOT)
    token = capture([
        "az", "acr", "login", "--name", values["AZURE_CONTAINER_REGISTRY_NAME"],
        "--subscription", values["AZURE_SUBSCRIPTION_ID"], "--expose-token",
        "--query", "accessToken", "--output", "tsv", "--only-show-errors",
    ])
    with tempfile.TemporaryDirectory(prefix="discovery-acr-") as directory:
        command = [engine, "--config", directory] if engine == "docker" else [engine]
        auth = ["--authfile", str(Path(directory) / "auth.json")] if engine == "podman" else []
        capture(command + ["login"] + auth + [
            registry, "--username", "00000000-0000-0000-0000-000000000000", "--password-stdin",
        ], input_text=token)
        subprocess.run(command + ["push"] + auth + [tagged], check=True, cwd=ROOT)
    return resolve_image(values)


def export(values, key, value):
    capture(["azd", "env", "set", key, value, "--environment", values["AZURE_ENV_NAME"]])


def verify_agent(deployed, expected):
    if deployed.get("provisioningState") != "Succeeded":
        raise RuntimeError("Agent read-back did not report Succeeded")
    for field in ("name", "humanInTheLoop", "tools", "discoveryExtensions"):
        if deployed.get(field) != expected[field]:
            raise RuntimeError(f"Agent read-back mismatch: {field}")
    latest = deployed.get("foundryDetails", {}).get("versions", {}).get("latest", {})
    definition = latest.get("definition", {})
    for field, value in expected["foundryDetails"]["definition"].items():
        if definition.get(field) != value:
            raise RuntimeError(f"Agent latest-version read-back mismatch: {field}")
    if not latest.get("version"):
        raise RuntimeError("Agent read-back is missing its latest version")
    return latest["version"]


def save_artifacts(values, tool, agent, payload, tool_id, location):
    directory = values["artifact_dir"]
    directory.mkdir(parents=True, exist_ok=True)
    body = {
        "location": location, "tags": {"category": tool["category"]},
        "properties": {"version": tool["version"], "definitionContent": tool},
    }
    (directory / "tool-arm-body.json").write_text(json.dumps(body, indent=2) + "\n")
    (directory / "agent.resolved.yaml").write_text(yaml.safe_dump(agent, sort_keys=False))
    (directory / "agent-payload.json").write_text(json.dumps(payload, indent=2) + "\n")
    (directory / "bindings.json").write_text(json.dumps({
        "SERVICE_GROMACS_TOOL_RESOURCE_ID": tool_id,
        "DISCOVERY_CHAT_MODEL_DEPLOYMENT_NAME": values["model"],
        "SERVICE_GROMACS_TOOL_IMAGE": tool["infra"][0]["image"]["acr"],
    }, indent=2) + "\n")
    return body


def deploy(values, dry_run=False, engine="podman", skip_publish=False):
    tagged = values["AZURE_CONTAINER_REGISTRY_ENDPOINT"] + "/" + IMAGE
    tool, agent, payload, tool_id = definitions(values, tagged)
    if dry_run:
        save_artifacts(values, tool, agent, payload, tool_id, values["AZURE_LOCATION"])
        publication = "reuse CPU image" if skip_publish else "publish CPU image"
        print(f"DRY RUN: verify resources -> {publication} -> register tool -> upsert agent")
        print(f"Model: {values['model']}\nTool: {tool_id}\nArtifacts: {values['artifact_dir']}")
        return
    azure = Azure(values["AZURE_SUBSCRIPTION_ID"], values["endpoint"])
    for key in ("DISCOVERY_WORKSPACE_ID", "DISCOVERY_PROJECT_ID", "model_id", "DISCOVERY_NODE_POOL_ID"):
        wait_ready(azure, arm_url(values[key]))
    _, workspace, _ = azure.request("GET", arm_url(values["DISCOVERY_WORKSPACE_ID"]))
    if skip_publish:
        image = resolve_image(values)
    else:
        image = publish_image(values, engine)
    tool, agent, payload, tool_id = definitions(values, image)
    body = save_artifacts(values, tool, agent, payload, tool_id, workspace["location"])
    print(f"Registering CPU tool: {tool['name']}", flush=True)
    azure.request("PUT", arm_url(tool_id), body)
    wait_ready(azure, arm_url(tool_id))
    export(values, "SERVICE_GROMACS_TOOL_RESOURCE_ID", tool_id)
    export(values, "SERVICE_GROMACS_TOOL_IMAGE", image)
    export(values, "DISCOVERY_CHAT_MODEL_DEPLOYMENT_NAME", values["model"])
    print(f"Upserting agent: {agent['name']} (model {values['model']})", flush=True)
    url = values["endpoint"] + "/projects/" + values["project"] + ":upsertAgent?api-version=" + DATA_VERSION
    status, _, headers = azure.request("POST", url, payload)
    operation = next((value for key, value in headers.items() if key.lower() == "operation-location"), None)
    if operation:
        wait_ready(azure, urljoin(values["endpoint"], operation), operation=True)
    elif status == 202:
        raise RuntimeError("Agent update accepted without an operation URL; cannot verify completion")
    agent_url = values["endpoint"] + "/projects/" + values["project"] + "/agents/" + agent["name"] + "?api-version=" + DATA_VERSION
    _, deployed, _ = azure.request("GET", agent_url)
    version = verify_agent(deployed, payload)
    export(values, "SERVICE_GROMACS_AGENT_NAME", agent["name"])
    print(f"Discovery tool and agent version {version} deployed and verified. No simulation was submitted.")


def main():
    parser = argparse.ArgumentParser(description="Temporary azd Discovery CPU tool and agent deployment hook")
    parser.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()
    dry_run = arguments.dry_run or os.environ.get("DISCOVERY_DEPLOY_DRY_RUN", "false").lower() == "true"
    skip_publish = os.environ.get("DISCOVERY_SKIP_IMAGE_PUBLISH", "false").lower() == "true"
    engine = os.environ.get("DISCOVERY_CONTAINER_ENGINE", "podman")
    if engine not in ("podman", "docker"):
        raise ValueError("DISCOVERY_CONTAINER_ENGINE must be podman or docker")
    deploy(settings(os.environ), dry_run, engine, skip_publish)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, TimeoutError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"Deployment failed: {error}", file=sys.stderr)
        sys.exit(1)