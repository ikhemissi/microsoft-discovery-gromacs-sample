# Lysozyme In Water: First Discovery Experiment

## Purpose

Learn the research workflow on a small public protein before adding an ingredient.
The question is: **how does lysozyme move in water during a short simulation?**
GROMACS calculates molecular motion; Discovery can organize the inputs, invoke
the tool and help explain its outputs. This is an educational baseline, not a
validated formulation study or evidence of protein protection.

The first milestone is a complete water-only run. Glycerol comparisons are the
second milestone and are not implemented yet. No Azure resources or jobs are
created by these scripts.

## Inputs And Assumptions

| Item | Baseline choice |
| --- | --- |
| Protein | Hen egg-white lysozyme, public PDB entry 1AKI, chain A, 129 residues. |
| Preparation | Keep protein ATOM records; remove crystallographic waters; rebuild hydrogens with GROMACS. Unexpected alternate locations or a changed source checksum stop preparation. |
| Molecular parameters | GROMACS-bundled OPLS-AA protein parameters and SPC/E water. These are explicit choices, not the upstream helper's CHARMM defaults. |
| Chemistry | Standard pdb2gmx protonation/terminus assignments and geometry-detected disulfides; no explicit pH model. Review these assignments before scientific use. |
| Disulfides | Expect Cys6-Cys127, Cys30-Cys115, Cys64-Cys80 and Cys76-Cys94. Confirm them in the preparation log/topology. |
| Solvent | Water and neutralizing counterions only; no added salt or glycerol. |
| Box | Dodecahedron with 1.0 nm initial protein-to-box clearance. |
| Conditions | 300 K; 1 bar during pressure equilibration and production. |
| Minimization | Steepest descent, up to 50,000 steps, force threshold 1,000 kJ/mol/nm. Failure to reach it stops the run. |
| Equilibration | 100 ps at fixed volume, then 100 ps at controlled pressure, with protein position restraints. |
| Production | 100 ps without position restraints: 50,000 steps at 0.002 ps per step. This is not sufficient to establish equilibrium or formulation efficacy. |
| Outputs | Coordinates and energies every 1 ps; fixed velocity and ion-placement seed; two CPU threads by default. |

The ion-placement input uses a cutoff electrostatic calculation solely to generate
the temporary input for replacing waters with ions. Minimization and dynamics use
PME electrostatics. No preprocessing warnings are bypassed. Numerical instabilities
stop the workflow rather than trigger silent changes to the scientific protocol.

## Prepare The Data

Run from the repository root. Preparation requires Bash, curl, awk and sha256sum.
It downloads the public structure, checks its pinned fingerprint, and records
source, retrieval time and input checksums. It does not execute downloaded code.

```bash
bash experiments/lysozyme-water/run.sh prepare experiments/lysozyme-water/input
bash experiments/lysozyme-water/test.sh experiments/lysozyme-water/input
```

The destination must not already exist. Keep an existing verified bundle for
reproducibility; use a new directory when preparing a different protocol version.
The generated input and result directories are git-ignored. The bundle contains
the original PDB, selected protein, five parameter files, runner and provenance.
If RCSB updates the source file, inspect that change before updating the pinned hash.

## Run Locally

The CPU container avoids a host GROMACS installation. Podman is used below;
Docker supports the same build/run commands. Build downloads packages, but the
simulation itself has no network access. Allow local CPU time, memory and disk
space; no Azure subscription is involved. Start with the `smoke` profile below:
it shortens each dynamics stage to 2 ps and saves data every 0.1 ps, without
shortening minimization. These 6 ps only test the software path; they are not
an equilibrated system or useful scientific sampling.

```bash
podman build -t localhost/discovery-lysozyme:baseline experiments/lysozyme-water
mkdir -p experiments/lysozyme-water/results
podman run --rm --network none --cpus 2 --memory 2g \
  -v "$PWD/experiments/lysozyme-water/input:/input:ro" \
  -v "$PWD/experiments/lysozyme-water/results:/output" \
  localhost/discovery-lysozyme:baseline smoke /input /output/smoke-01 20261008 2
```

For the 100 ps-per-stage baseline, replace `smoke` with `run` and use a new
output name such as `/output/baseline-01`. CPU execution may take substantially
longer than an interactive demonstration; measure before promising a live run.

Alternatively, with GROMACS 2024+ (thread-MPI) available as `gmx`:

```bash
bash experiments/lysozyme-water/run.sh smoke \
  experiments/lysozyme-water/input \
  experiments/lysozyme-water/results/smoke-01 20261008 2
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

## Validation Status

On 2026-10-08, the complete `smoke` profile passed locally with GROMACS
2025.2 (Debian package 2025.2-1), two CPU threads and networking disabled.
The system contained 23,961 atoms; the four expected disulfides were formed;
minimization converged in 388 steps. Each dynamics stage ran for 2 ps, and
the production trajectory contained 21 frames spanning 0-2 ps. RMSD,
radius-of-gyration and thermodynamic outputs were generated and input/output
checksums passed. Failure-path tests also passed.

The longer `run` profile was started but stopped during fixed-volume
equilibration due to local runtime; it has not been verified end to end.
Discovery execution and glycerol comparisons have not been run. No scientific
convergence or formulation-performance claim follows from the smoke test.

## Inspect The Results

| Output | Meaning |
| --- | --- |
| `run-status.txt` | `completed` means all scripted steps returned successfully. It is not scientific approval. `failed` requires inspection of logs. |
| `run-provenance.txt` | Distinguishes the `smoke` and `run` profiles; copied/effective parameter files record their actual step counts. |
| `preparation.log`, stage logs | Molecular assignments, preprocessing messages, minimization convergence and simulation diagnostics. |
| `backbone-rmsd.xvg` | Change in the protein backbone relative to the production starting structure, after alignment; time in ns, distance in nm. |
| `radius-of-gyration.xvg` | How spread out the protein is; use the file's axis labels and units. |
| `thermodynamics.xvg` | Production temperature, pressure, density and potential energy. Read column legends and units. |
| `md.xtc`, `centered.xtc`, `md.tpr`, `md.gro` | Raw/centered trajectories and matching simulation/final structures. |
| `gromacs-version.txt`, provenance and checksum files | Inputs, chosen seed, software and effective protocol for audit and reproduction. |

Before interpretation, check all stages, not just production plots: correct
protein/disulfides, sensible density and temperature, absence of instability,
trajectory continuity and no systematic drift. Instantaneous pressure fluctuates
strongly in small systems; do not demand every frame equal 1 bar. The script's
checks are necessary technical checks, not a complete equilibration assessment.

An unchanged protein over 100 ps does not demonstrate protection, thermodynamic
stability or retained activity. Differences between individual short trajectories
can be sampling noise. Preserve inconclusive results rather than force a ranking.

## Use In Discovery

The Terraform deployment supplies infrastructure only. Build/register the
[upstream GROMACS tool and agent](https://github.com/microsoft/discovery/tree/ddecc27bba4e3dec2a47f7f9a3c4f143a0c89b6d/agents/gromacs)
separately using its deployment guide, reviewing its container dependencies,
parameter licenses and compute settings. The local CPU image above is a test
runner, not a replacement Discovery tool registration. A cloud job is billable.

1. First verify the baseline locally and review the scientific assumptions.
2. Upload the complete generated input directory as a Discovery data asset and
   attach it to the GROMACS conversation. Confirm the files are directly under
   the tool's read-only `/input` mount, not a nested directory.
3. Ask the tool to run the attached procedure with two CPU threads. Use a new
   output directory for every attempt. Do not ask the agent to invent settings.
4. Download the result bundle and check `run-status.txt` and stage logs before
   asking for interpretation. The upstream tool wrapper may finish even when a
   generated script fails; a completed tool invocation is not proof of success.

Suggested first prompt:

> Run the attached lysozyme-in-water technical smoke test. Use the GROMACS tool
> to execute `bash /input/run.sh smoke /input /output/smoke-01 20261008 2`
> through a checked subprocess call. Verify the input checksums. Do not change
> molecular parameters, durations, protonation, constraints or warning handling.
> If any step fails, stop and report the relevant logs; do not retry with altered
> chemistry. Confirm that `/output/smoke-01/run-status.txt` says `completed`.
> Return the output directory, software version, actual simulated durations,
> diagnostic findings and the RMSD and radius-of-gyration data with units.
> Explain the 2 ps-per-stage results as a technical test only, not a formulation
> result, a glycerol comparison or evidence of protein protection.

Discovery execution must be verified separately after tool registration. The
local test does not verify cloud mounts, permissions, scheduling or agent behavior.

## Next: Add Glycerol

The proposed comparison is 0%, 10% and 20% glycerol by **solvent mass**:
glycerol mass divided by the combined water and glycerol mass, excluding protein
and ions. Do not substitute molecule counts or solution volume percentages.

Before implementation, an MD-experienced reviewer should approve glycerol
parameters compatible with the protein/water force field, protonation, temperature,
salt conditions, box composition and equilibration/convergence criteria. Allocate
at least three independent replicas per condition and choose durations based on
the question and sampling evidence, not the 100 ps demonstration setting.
Add hydration and protein-glycerol interaction analyses; compare uncertainty, not
only trajectories. A second review should approve conclusions before presentation.

## Literature And Provenance

- [PDB 1AKI](https://www.rcsb.org/structure/1AKI): public starting coordinates,
  1.5 angstrom X-ray structure, not a prepared simulation system.
- [Upstream lysozyme inputs](https://github.com/microsoft/discovery/tree/ddecc27bba4e3dec2a47f7f9a3c4f143a0c89b6d/agents/gromacs/tools/gromacs/example-input-files/lysozyme):
  workflow inspiration. This sample uses its own explicit OPLS-AA/SPC/E protocol,
  C-rescale pressure coupling, all-bond constraints and 100 ps stage durations.
- Ghattyvenkatakrishna and Carri (2014),
  [Effect of glycerol-water binary mixtures on the structure and dynamics of protein solutions](https://doi.org/10.1080/07391102.2013.773562):
  published 20 ns lysozyme simulations at 0%, 10%, 20%, 30% and 100% glycerol by
  weight. This motivates stage two; the current baseline is not a reproduction
  of its methods or results. Full methods/parameter availability must be checked.
- [GROMACS parameter reference](https://manual.gromacs.org/2025.2/user-guide/mdp-options.html):
  definitions and units of the simulation settings.