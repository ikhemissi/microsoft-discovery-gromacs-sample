# Lysozyme in water: simulation protocols

A GROMACS simulation is defined by run-parameter (`.mdp`) files: plain-text
`key = value` settings for the integrator, time step, temperature, pressure,
cut-offs, constraints and output. Together with the structure and topology,
`gmx grompp` turns each MDP into a run input (`.tpr`) that `gmx mdrun` executes.

Scientists write MDP files by hand, usually starting from a tutorial, a lab
template, a paper's methods section or a generator such as CHARMM-GUI, then
adapt them to the force field and the study. Most settings are dictated by the
force field and water model; studies typically vary only temperature,
pressure, duration, seeds and output frequency. The MDPs are versioned with
the experiment, reviewed, and published with the results.

This sample follows the same model, as Microsoft's
[official GROMACS agent](https://github.com/microsoft/discovery/tree/main/agents/gromacs) does:

- **The protocol is data.** Each version is a directory uploaded as a Discovery
  storage asset, attached to a conversation and mounted read-only at `/input`.
  The tool image contains GROMACS and the runner, but no MDPs.
- **Scientists own the parameters.** The agent previews the attached protocol
  and runs it unchanged after your confirmation. It never writes or edits MDPs.
- **Every run is traceable.** The runner checks the MDPs, records the effective
  parameters `grompp` used (`*-effective.mdp`) and a `protocol-summary.tsv`.

## Version v1

[v1](v1) is an educational baseline for hen egg-white lysozyme (PDB 1AKI,
chain A) with OPLS-AA and SPC/E water, adapted from the classic GROMACS
"lysozyme in water" protocol.

| Stage | File | What it does | Key settings |
| --- | --- | --- | --- |
| Ions | [ions.mdp](v1/ions.mdp) | Input for `genion` to add counterions; nothing is simulated | `nsteps = 0` |
| Minimization | [em.mdp](v1/em.mdp) | Removes clashes from solvation | steepest descent, until max force < 1000 kJ/mol/nm |
| NVT | [nvt.mdp](v1/nvt.mdp) | Brings the system to 300 K at fixed volume, protein restrained | 2 fs steps, 100 ps, V-rescale thermostat, new velocities |
| NPT | [npt.mdp](v1/npt.mdp) | Adjusts density at 1 bar, protein restrained | 100 ps, C-rescale barostat, continues NVT |
| Production | [md.mdp](v1/md.mdp) | Unrestrained dynamics for analysis | 100 ps, 300 K, 1 bar, coordinates every 1 ps |

All stages share PME electrostatics, 1.0 nm cut-offs and a dispersion
correction. The 2 fs time step relies on constraining all bonds (LINCS).
Each file explains its settings in `;` comments. 100 ps is far too short for
scientific conclusions; the `smoke` profile shortens each dynamics stage to
2 ps as a technical check.

The directory also holds the prepared structure (`source.pdb`, `protein.pdb`),
`provenance.txt`, `SHA256SUMS` (checked by the runner) and `bundle.yaml`
(checked by the azd extension on upload).

## Publishing a new version

Published versions are immutable. To change a parameter, for example to run at
310 K or for longer:

1. Copy the MDP files into a new directory and edit them:

   ```bash
   mkdir experiments/lysozyme-water/v2
   cp experiments/lysozyme-water/v1/*.mdp experiments/lysozyme-water/v2/
   ```

   Keep `ref_t` and `gen_temp` consistent across stages, and keep `dt` within
   what the constraints allow.
2. Add the structure, provenance and checksums, then run the safeguards:

   ```bash
   bash tools/gromacs/run.sh prepare experiments/lysozyme-water/v2
   bash tools/gromacs/test.sh experiments/lysozyme-water/v2
   ```

3. Run the smoke profile locally (see [tools/gromacs](../../tools/gromacs/README.md#run-locally))
   and have the change reviewed.
4. Add a storage asset for `v2` in [infra/protocols.tf](../../infra/protocols.tf),
   a dataset in [azure.yaml](../../azure.yaml), then generate the manifest and upload:

   ```bash
   azd discovery data prepare <dataset> --local
   azd discovery data upload <dataset> --confirm
   ```

The tool and agent don't change: attach the new asset to a conversation and
ask the agent to run it.

## References

- [GROMACS MDP options](https://manual.gromacs.org/current/user-guide/mdp-options.html)
- [GROMACS lysozyme in water tutorial](http://www.mdtutorials.com/gmx/lysozyme/)
- [Microsoft Discovery storage assets](https://learn.microsoft.com/azure/microsoft-discovery/concept-files-storage-assets)
