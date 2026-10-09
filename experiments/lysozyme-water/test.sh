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
printf 'PASS: arguments, overwrite protection, input integrity, missing files and failure status.\n'