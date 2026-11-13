# GROMACS tool

Container images and runner for the [lysozyme-in-water experiment](../../docs/experiment.md).
The runner executes a reviewed [protocol bundle](../../experiments/lysozyme-water/README.md)
unchanged: it checks the inputs, prepares the system, runs minimization, NVT, NPT
and production, analyses the trajectory and records provenance and checksums.
Everything on this page runs locally without Azure; see
[Run in Discovery](../../docs/run-in-discovery.md) for the cloud workflow.

| File | Purpose |
| --- | --- |
| [run.sh](run.sh) | The runner: `prepare`, `smoke` (2 ps per dynamics stage) and `run` (protocol as written) |
| [test.sh](test.sh) | Offline safeguard tests with a mocked GROMACS |
| [Dockerfile](Dockerfile) | CPU image (Debian GROMACS 2025.2); `discovery` target adds Python for Discovery |
| [Dockerfile.gpu](Dockerfile.gpu) | CUDA image built from checksum-pinned GROMACS 2025.2 source |
| [tool.cpu.yaml](tool.cpu.yaml), [tool.gpu.yaml](tool.gpu.yaml) | Discovery tool definitions |

## Protocol

The runner reads a protocol bundle, by default
[experiments/lysozyme-water/v1](../../experiments/lysozyme-water/v1): five
hand-written MDP files, the prepared structure, provenance and checksums. It is
committed and ready to use. `run.sh prepare` completes a new version's directory
and refuses to overwrite one; see
[Publishing a new version](../../experiments/lysozyme-water/README.md#publishing-a-new-version).

## Run locally

The CPU container avoids a host GROMACS installation. Podman is used below;
Docker supports the same build/run commands. Build downloads packages, but the
simulation itself has no network access. Allow local CPU time, memory and disk
space; no Azure subscription is involved. Start with the `smoke` profile below:
it shortens each dynamics stage to 2 ps and saves data every 0.1 ps, without
shortening minimization. These 6 ps only test the software path; they are not
an equilibrated system or useful scientific sampling.

```bash
podman build -t localhost/discovery-lysozyme:baseline tools/gromacs
mkdir -p tools/gromacs/results
podman run --rm --network none --cpus 2 --memory 2g \
  -v "$PWD/experiments/lysozyme-water/v1:/input:ro" \
  -v "$PWD/tools/gromacs/results:/output" \
  localhost/discovery-lysozyme:baseline smoke /input /output/smoke-01 20261008 2
```

For the protocol's full 100 ps-per-stage durations, replace `smoke` with `run` and use a new
output name such as `/output/baseline-01`. It took 42 minutes on a
`Standard_D4s_v6` node in Discovery (about 11 ns/day on two threads); laptops
can be several times slower, and a GPU is much faster.

Alternatively, with GROMACS 2024+ (thread-MPI) available as `gmx`:

```bash
bash tools/gromacs/run.sh smoke \
  experiments/lysozyme-water/v1 \
  tools/gromacs/results/smoke-01 20261008 2
```

The output directory must be new. Failed runs remain available for inspection;
do not delete them merely to retry. Use a new run name after addressing the cause.
For independent runs, change both the output name and seed. The seed controls
initial velocities and counterion placement, not bitwise reproducibility across
different hardware or GROMACS builds.

The container installs Debian's GROMACS package; preserve the built image digest
alongside results for long-term reproduction. The runner also saves the exact
GROMACS version and effective simulation parameters. Package repositories and the
base-image tag can change, so rebuilding later is not an immutable environment.

### CPU or GPU

`GROMACS_ACCELERATION=cpu` is the default. Explicit `gpu` mode offloads short-range
nonbonded forces during NVT, NPT and production; minimization, PME, bonded forces
and updates remain on CPU. GPU mode requires a CUDA-enabled GROMACS build and a
compatible NVIDIA device. It fails without either; it does not fall back to CPU.
The selected mode is recorded in `run-provenance.txt`. No MDP settings change
when switching acceleration.

Build the CUDA runner with the checksum-pinned GROMACS 2025.2 source:

```bash
podman build -f tools/gromacs/Dockerfile.gpu --target gpu \
  -t localhost/discovery-lysozyme:gpu tools/gromacs
```

The image targets A100/H100 (SM 80/90), CUDA 12.6 and x86-64 AVX2 CPUs; SM 8.6
laptop GPUs such as the RTX A2000 also run it. Building requires no GPU, but
execution needs a compatible host driver and NVIDIA Container Toolkit. On a
Podman version with NVIDIA CDI support and a configured CDI device:

```bash
podman run --rm --network none --device nvidia.com/gpu=all --cpus 2 --memory 8g \
  -e GROMACS_ACCELERATION=gpu \
  -v "$PWD/experiments/lysozyme-water/v1:/input:ro" \
  -v "$PWD/tools/gromacs/results:/output" \
  localhost/discovery-lysozyme:gpu smoke /input /output/smoke-gpu-01 20261008 2
```

Docker uses `--gpus all` instead of the Podman CDI device flag. See the
[NVIDIA Container Toolkit guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/).
On WSL 2 the Windows NVIDIA driver is enough; replace the CDI flag with
`--device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib`.
Review GROMACS LGPL and NVIDIA container redistribution terms before publishing
images. Preserve image digests; the pinned source does not freeze base images or
package repositories. A small system may not benefit from offloading on every GPU.

## Validation status

The CPU version was tested both locally and on Azure; the GPU version was tested
locally. All runs used the v1 protocol, seed `20261008` and GROMACS 2025.2.

| Profile | Where | Hardware | Result |
| --- | --- | --- | --- |
| `run` (100 ps per stage) | Microsoft Discovery, run by the agent from Studio | `Standard_D4s_v6` node pool, 2 CPU threads | Completed in 42 minutes at about 11 ns/day; checksums passed, 101-frame production trajectory and all analyses produced ([results](../../docs/experiment.md#results)) |
| `smoke` (2 ps per stage) | Microsoft Discovery, run by the agent from Studio | `Standard_D4s_v6` node pool, 2 CPU threads | Completed in 3.5 minutes; protocol attached as a storage asset and mounted read-only, checksums passed |
| `smoke` | Local container, offline | 2 CPU threads | Completed in under 3 minutes; 23,961 atoms, the four expected disulfides, minimization converged, checksums passed |
| `smoke` | Local container under WSL 2, offline | NVIDIA RTX A2000 Laptop GPU | Completed; short-range forces on the GPU, production at 41.9 ns/day versus 3.9 ns/day on 2 local CPU threads, checksums passed |

The GPU smoke run agreed with the CPU smoke run within the variation expected between
independent 2 ps trajectories:

| Production average or final value | CPU | GPU |
| --- | --- | --- |
| Temperature | 299.0 K | 300.7 K |
| Density | 1012.3 kg/m³ | 1011.5 kg/m³ |
| Final backbone RMSD | 0.054 nm | 0.051 nm |
| Final radius of gyration | 1.412 nm | 1.416 nm |

[test.sh](test.sh) also covers the failure paths: invalid protocols, unsupported
acceleration modes and GPU failures without CPU fallback.

Not yet done: the glycerol comparisons. Neither the smoke runs nor the 100 ps
run support scientific convergence or formulation-performance claims.

## Inspect the results

| Output | Meaning |
| --- | --- |
| `run-status.txt` | `completed` means all scripted steps returned successfully. It is not scientific approval. `failed` requires inspection of logs. |
| `run-provenance.txt` | Records profile, acceleration, seed and threads; copied/effective parameter files record actual step counts. |
| `protocol-summary.tsv` | Per stage: integrator, time step, steps, duration, temperature, pressure coupling and restraints, as executed. |
| `preparation.log`, stage logs | Molecular assignments, preprocessing messages, minimization convergence and simulation diagnostics. |
| `backbone-rmsd.xvg` | Change in the protein backbone relative to the production starting structure, after alignment; time in ns, distance in nm. |
| `radius-of-gyration.xvg` | How spread out the protein is; use the file's axis labels and units. |
| `thermodynamics.xvg` | Production temperature, pressure, density and potential energy. Read column legends and units. |
| `md.xtc`, `centered.xtc`, `md.tpr`, `md.gro` | Raw/centered trajectories and matching simulation/final structures. |
| `gromacs-version.txt`, provenance and checksum files | Inputs, chosen seed, software and effective protocol for audit and reproduction. |

See [Interpreting results](../../docs/experiment.md#interpreting-results) before
drawing any conclusion from these files.