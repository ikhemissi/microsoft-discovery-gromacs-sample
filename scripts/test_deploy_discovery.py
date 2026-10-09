import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import yaml


SPEC = importlib.util.spec_from_file_location("deploy_discovery", Path(__file__).with_name("deploy-discovery.py"))
deployment = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deployment)


class DiscoveryDeploymentTests(unittest.TestCase):
    def setUp(self):
        scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Discovery"
        self.environment = {
            "AZURE_ENV_NAME": "test", "AZURE_SUBSCRIPTION_ID": "00000000-0000-0000-0000-000000000000",
            "AZURE_LOCATION": "swedencentral",
            "AZURE_RESOURCE_GROUP": "rg-test", "AZURE_CONTAINER_REGISTRY_NAME": "acrtest",
            "AZURE_CONTAINER_REGISTRY_ENDPOINT": "acrtest.azurecr.io",
            "DISCOVERY_WORKSPACE_ID": scope + "/workspaces/ws-test",
            "DISCOVERY_PROJECT_ID": scope + "/workspaces/ws-test/projects/prj-test",
            "DISCOVERY_CHAT_MODEL_ID": scope + "/workspaces/ws-test/chatModelDeployments/gpt-5-4",
            "DISCOVERY_NODE_POOL_ID": scope + "/supercomputers/sc-test/nodePools/nodepool1",
        }
        self.values = deployment.settings(self.environment)
        self.image = "acrtest.azurecr.io/discovery-lysozyme@sha256:" + "a" * 64
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.values["artifact_dir"] = Path(self.directory.name)

    def live_agent(self):
        _, _, payload, _ = deployment.definitions(self.values, self.image)
        return {
            **payload, "location": "swedencentral", "provisioningState": "Succeeded",
            "foundryDetails": {"versions": {"latest": {
                "version": "1", "definition": payload["foundryDetails"]["definition"],
            }}},
        }

    def test_bindings_and_confirmation_preserve_source(self):
        sources = {name: (deployment.EXPERIMENT / name).read_bytes() for name in ("agent.yaml", "tool.cpu.yaml")}
        tool, agent, payload, tool_id = deployment.definitions(self.values, self.image)
        self.assertEqual(tool["infra"][0]["image"]["acr"], self.image)
        self.assertEqual(agent["model"]["id"], "gpt-5-4")
        self.assertEqual(payload["foundryDetails"]["definition"]["model"], "gpt-5-4")
        self.assertEqual(payload["tools"], [{"toolId": tool_id, "confirmation": "Enabled"}])
        self.assertEqual(payload["humanInTheLoop"], "Enabled")
        self.assertIn("bash /opt/lysozyme-water/run.sh PROFILE", payload["foundryDetails"]["definition"]["instructions"])
        self.assertIn("{{scriptName}}", tool["code_environments"][0]["command"])
        self.assertNotIn("{{", json.dumps(payload))
        for name, content in sources.items():
            self.assertEqual((deployment.EXPERIMENT / name).read_bytes(), content)

    def test_missing_and_cross_workspace_inputs_fail(self):
        with self.assertRaisesRegex(ValueError, "Missing azd outputs"):
            deployment.settings({})
        self.environment["DISCOVERY_PROJECT_ID"] = self.environment["DISCOVERY_PROJECT_ID"].replace("ws-test", "ws-other")
        with self.assertRaisesRegex(ValueError, "Project must belong"):
            deployment.settings(self.environment)

    def test_model_override_is_validated_in_same_workspace(self):
        self.environment["DISCOVERY_CHAT_MODEL_DEPLOYMENT_NAME"] = "gpt-other"
        values = deployment.settings(self.environment)
        self.assertEqual(values["model_id"], values["DISCOVERY_WORKSPACE_ID"] + "/chatModelDeployments/gpt-other")

    def test_dry_run_never_calls_azure_or_exports(self):
        with patch.object(deployment, "Azure") as azure, patch.object(deployment, "capture") as capture:
            deployment.deploy(self.values, dry_run=True)
        azure.assert_not_called()
        capture.assert_not_called()
        agent = yaml.safe_load((self.values["artifact_dir"] / "agent.resolved.yaml").read_text())
        self.assertEqual(agent["model"]["id"], "gpt-5-4")
        self.assertTrue((self.values["artifact_dir"] / "bindings.json").exists())

    def test_tool_failure_prevents_agent_and_output_export(self):
        azure = Mock()
        azure.request.return_value = (200, {"location": "swedencentral"}, {})
        azure.request.side_effect = lambda method, *args: (_ for _ in ()).throw(RuntimeError("tool failed")) if method == "PUT" else (200, {"location": "swedencentral"}, {})
        with patch.object(deployment, "Azure", return_value=azure), patch.object(deployment, "wait_ready"), patch.object(deployment, "publish_image", return_value=self.image), patch.object(deployment, "export") as export:
            with self.assertRaisesRegex(RuntimeError, "tool failed"):
                deployment.deploy(self.values)
        self.assertNotIn("POST", [call.args[0] for call in azure.request.call_args_list])
        export.assert_not_called()

    def test_deployment_order_and_verified_exports(self):
        events = []
        azure = Mock()

        def request(method, url, *args):
            events.append(method)
            if method == "POST":
                return 202, {}, {"Operation-Location": "/operations/op-test"}
            return 200, self.live_agent(), {}

        azure.request.side_effect = request
        with patch.object(deployment, "Azure", return_value=azure), patch.object(deployment, "wait_ready", side_effect=lambda *args, **kwargs: events.append("ready")), patch.object(deployment, "publish_image", return_value=self.image), patch.object(deployment, "export", side_effect=lambda values, key, value: events.append(key)):
            deployment.deploy(self.values)
        self.assertLess(events.index("PUT"), events.index("SERVICE_GROMACS_TOOL_RESOURCE_ID"))
        self.assertLess(events.index("SERVICE_GROMACS_TOOL_RESOURCE_ID"), events.index("POST"))
        self.assertLess(events.index("POST"), events.index("SERVICE_GROMACS_AGENT_NAME"))
        self.assertIn("DISCOVERY_CHAT_MODEL_DEPLOYMENT_NAME", events)

    def test_failed_operation_and_missing_status_stop(self):
        azure = Mock()
        azure.request.return_value = (200, {"status": "Failed", "result": {"status": "Succeeded"}}, {})
        with self.assertRaisesRegex(RuntimeError, "Failed"):
            deployment.wait_ready(azure, "https://ws-test.workspace.discovery.azure.com/operations/test", operation=True)
        azure.request.return_value = (200, {}, {})
        with self.assertRaisesRegex(RuntimeError, "authoritative status"):
            deployment.wait_ready(azure, "https://management.azure.com/test")

    def test_unexpected_operation_host_rejected_before_token(self):
        azure = deployment.Azure(self.values["AZURE_SUBSCRIPTION_ID"], self.values["endpoint"])
        with patch.object(deployment, "capture") as capture:
            with self.assertRaisesRegex(ValueError, "unexpected endpoint"):
                azure.request("GET", "https://example.com/operation")
        capture.assert_not_called()

    def test_redirects_do_not_forward_credentials(self):
        self.assertIsNone(deployment.RejectRedirects().redirect_request(
            None, None, 302, "Found", {}, "https://example.com/operation"
        ))

    def test_reuse_image_pins_digest_without_build(self):
        azure = Mock()
        azure.request.return_value = (200, self.live_agent(), {})
        with patch.object(deployment, "Azure", return_value=azure), patch.object(deployment, "wait_ready"), patch.object(deployment, "publish_image") as publish, patch.object(deployment, "capture", return_value="sha256:" + "a" * 64), patch.object(deployment, "export"):
            deployment.deploy(self.values, skip_publish=True)
        publish.assert_not_called()
        body = json.loads((self.values["artifact_dir"] / "tool-arm-body.json").read_text())
        self.assertEqual(body["properties"]["definitionContent"]["infra"][0]["image"]["acr"], self.image)

    def test_invalid_digest_rejected(self):
        with patch.object(deployment, "capture", return_value="not-a-digest"):
            with self.assertRaisesRegex(ValueError, "valid image digest"):
                deployment.resolve_image(self.values)

    def test_agent_accepted_without_operation_is_not_success(self):
        azure = Mock()
        azure.request.side_effect = lambda method, *args: (202, {}, {}) if method == "POST" else (200, {"location": "swedencentral"}, {})
        with patch.object(deployment, "Azure", return_value=azure), patch.object(deployment, "wait_ready"), patch.object(deployment, "publish_image", return_value=self.image), patch.object(deployment, "export") as export:
            with self.assertRaisesRegex(RuntimeError, "cannot verify completion"):
                deployment.deploy(self.values)
        self.assertNotIn("SERVICE_GROMACS_AGENT_NAME", [call.args[1] for call in export.call_args_list])

    def test_registry_credentials_are_ephemeral_and_use_stdin(self):
        for engine in ("podman", "docker"):
            captures = []

            def capture(arguments, input_text=None):
                captures.append((arguments, input_text))
                return "test-secret"

            with patch.object(deployment.shutil, "which", return_value=engine), patch.object(deployment.subprocess, "run"), patch.object(deployment, "capture", side_effect=capture), patch.object(deployment, "resolve_image", return_value=self.image):
                deployment.publish_image(self.values, engine)
            login, input_text = captures[-1]
            self.assertEqual(input_text, "test-secret")
            self.assertIn("--password-stdin", login)
            self.assertNotIn("test-secret", login)
            path = Path(login[login.index("--authfile") + 1]).parent if engine == "podman" else Path(login[login.index("--config") + 1])
            self.assertFalse(path.exists())

    def test_azd_workflow_keeps_provision_and_deploy_separate(self):
        configuration = yaml.safe_load((deployment.ROOT / "azure.yaml").read_text())
        self.assertEqual(configuration["workflows"]["up"]["steps"], [
            {"azd": "provision"}, {"azd": "hooks run postdeploy"},
        ])
        self.assertNotIn("postprovision", configuration["hooks"])
        self.assertFalse(configuration["hooks"]["postdeploy"]["continueOnError"])

    def test_agent_verification_uses_latest_foundry_version(self):
        _, _, payload, _ = deployment.definitions(self.values, self.image)
        self.assertEqual(deployment.verify_agent(self.live_agent(), payload), "1")

    def test_model_and_confirmation_mismatches_are_rejected(self):
        _, _, payload, _ = deployment.definitions(self.values, self.image)
        deployed = self.live_agent()
        deployed["foundryDetails"]["versions"]["latest"]["definition"]["model"] = "different-model"
        with self.assertRaisesRegex(RuntimeError, "mismatch: model"):
            deployment.verify_agent(deployed, payload)
        deployed = self.live_agent()
        deployed["tools"][0]["confirmation"] = "Disabled"
        with self.assertRaisesRegex(RuntimeError, "mismatch: tools"):
            deployment.verify_agent(deployed, payload)


if __name__ == "__main__":
    unittest.main()