#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -eq 1 ]] || { printf 'Usage: bash test.sh PREPARED_INPUT_DIRECTORY\n' >&2; exit 2; }
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
input_directory=$(cd -- "$1" && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT
runner="$script_directory/run.sh"

expect_failure() {
	if "$@" > "$temporary_directory/last-command.log" 2>&1; then
		printf 'Expected rejection: %s\n' "$*" >&2
		exit 1
	fi
}

bash -n "$runner"
bash "$runner" --help >/dev/null
(cd -- "$input_directory" && sha256sum --check --strict SHA256SUMS)
expect_failure bash "$runner" run
expect_failure bash "$runner" prepare "$input_directory"
expect_failure bash "$runner" run "$input_directory" "$temporary_directory/invalid-seed" -1
expect_failure bash "$runner" run "$input_directory" "$temporary_directory/invalid-threads" 42 0
expect_failure env GROMACS_ACCELERATION=auto bash "$runner" run "$input_directory" "$temporary_directory/invalid-mode"
grep -q 'GROMACS_ACCELERATION must be cpu or gpu' "$temporary_directory/last-command.log"
[[ ! -e "$temporary_directory/invalid-mode" ]]
expect_failure env GMX=false bash "$runner" run "$input_directory" "$input_directory"
grep -q 'Refusing to overwrite' "$temporary_directory/last-command.log"

cp -R -- "$input_directory" "$temporary_directory/corrupt-input"
printf '\nchanged\n' >> "$temporary_directory/corrupt-input/protein.pdb"
expect_failure env GMX=false bash "$runner" run "$temporary_directory/corrupt-input" "$temporary_directory/corrupt-output"
grep -q 'FAILED' "$temporary_directory/last-command.log"
[[ ! -e "$temporary_directory/corrupt-output" ]]

cp -R -- "$input_directory" "$temporary_directory/missing-input"
rm -- "$temporary_directory/missing-input/md.mdp"
expect_failure env GMX=false bash "$runner" run "$temporary_directory/missing-input" "$temporary_directory/missing-output"
grep -q 'Missing input: md.mdp' "$temporary_directory/last-command.log"

expect_failure env GMX=false bash "$runner" run "$input_directory" "$temporary_directory/failed-run"
[[ $(< "$temporary_directory/failed-run/run-status.txt") == failed ]]
[[ ! -e "$temporary_directory/failed-run/md.xtc" ]]
expect_failure env GMX=false bash "$runner" smoke "$input_directory" "$temporary_directory/smoke-run"
[[ $(< "$temporary_directory/smoke-run/run-status.txt") == failed ]]
for phase in nvt npt md; do
	grep -q '^nsteps = 1000$' "$temporary_directory/smoke-run/$phase.mdp"
	grep -q '^nsteps = 50000$' "$input_directory/$phase.mdp"
done

test_gmx() {
	case "$1" in
		--version)
			printf 'GPU support: %s\n' "${GMX_TEST_GPU_SUPPORT:-CUDA}"
			;;
		pdb2gmx)
			touch topol.top posre.itp
			;;
		mdrun)
			printf '%s\n' "$*" >> "$GMX_TEST_LOG"
			if [[ "$*" == *'-deffnm em '* ]]; then
				printf 'converged to Fmax < 1000\n' > em.log
			elif [[ "${GMX_TEST_FAIL_GPU:-false}" == true && "$*" == *'-nb gpu '* ]]; then
				printf 'No compatible GPU found.\n' >&2
				return 1
			fi
			;;
	esac
	return 0
}
export -f test_gmx
for mode in cpu gpu; do
	env GMX=test_gmx GMX_TEST_LOG="$temporary_directory/$mode-commands.log" \
		GROMACS_ACCELERATION="$mode" bash "$runner" smoke "$input_directory" "$temporary_directory/$mode-run" > "$temporary_directory/last-command.log" 2>&1
	[[ $(< "$temporary_directory/$mode-run/run-status.txt") == completed ]]
	grep -qx "acceleration=$mode" "$temporary_directory/$mode-run/run-provenance.txt"
	grep -Fxq 'mdrun -deffnm em -ntmpi 1 -ntomp 2 -nb cpu' "$temporary_directory/$mode-commands.log"
	for phase in nvt npt md; do
		grep -Fxq "mdrun -deffnm $phase -ntmpi 1 -ntomp 2 -nb $mode -pme cpu -bonded cpu -update cpu" "$temporary_directory/$mode-commands.log"
	done
done
expect_failure env GMX=test_gmx GMX_TEST_GPU_SUPPORT=disabled GROMACS_ACCELERATION=gpu \
	bash "$runner" smoke "$input_directory" "$temporary_directory/cpu-only-build"
grep -q 'requires a CUDA-enabled GROMACS build' "$temporary_directory/last-command.log"
[[ $(< "$temporary_directory/cpu-only-build/run-status.txt") == failed ]]
expect_failure env GMX=test_gmx GMX_TEST_FAIL_GPU=true GMX_TEST_LOG="$temporary_directory/no-gpu-commands.log" \
	GROMACS_ACCELERATION=gpu bash "$runner" smoke "$input_directory" "$temporary_directory/no-gpu"
[[ $(< "$temporary_directory/no-gpu/run-status.txt") == failed ]]
[[ $(wc -l < "$temporary_directory/no-gpu-commands.log") -eq 2 ]]
grep -q 'No compatible GPU found' "$temporary_directory/no-gpu/nvt-console.log"
printf 'PASS: safeguards, CPU/GPU stage arguments, provenance, unsupported build and GPU failure without fallback.\n'