#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
	printf '%s\n' \
		'Usage: bash run.sh prepare INPUT_DIRECTORY' \
		'       bash run.sh run INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY [SEED] [THREADS]' \
		'       bash run.sh smoke INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY [SEED] [THREADS]' \
		'prepare downloads 1AKI and packages the baseline inputs; it runs no simulation.' \
		'run uses 100 ps per dynamics stage; smoke uses 2 ps and is only a technical test.' \
		'Both require GROMACS 2024+ with thread-MPI; defaults: seed 20261008, 2 CPU threads.'
}

fail() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

new_directory() {
	[[ ! -e "$1" ]] || fail "Refusing to overwrite existing path: $1"
	mkdir -p -- "$(dirname -- "$1")"
	mkdir -- "$1"
}

prepare() {
	local destination="$1"
	local source_directory
	source_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
	local structure_url='https://files.rcsb.org/download/1AKI.pdb'
	for dependency in curl awk sha256sum; do
		require_command "$dependency"
	done
	for filename in ions.mdp em.mdp nvt.mdp npt.mdp md.mdp; do
		[[ -s "$source_directory/$filename" ]] || fail "Missing protocol file: $filename"
	done
	new_directory "$destination"
	cp -- "$source_directory/run.sh" "$source_directory/"*.mdp "$destination/"
	cd -- "$destination"
	curl --fail --location --proto '=https' --proto-redir '=https' \
		--retry 3 --connect-timeout 15 --max-time 120 \
		"$structure_url" --output source.pdb
	printf '%s  source.pdb\n' 'c75d7a689617248cdd92dc6633531d2506fb9bef1e6e21e26c8f579ae6955abb' | sha256sum --check --strict
	awk '
		substr($0, 1, 6) == "ATOM  " && substr($0, 22, 1) == "A" {
			if (substr($0, 17, 1) != " ") exit 1
			print
			if (substr($0, 13, 4) == " CA ") residues++
		}
		END {
			if (residues != 129) exit 1
			print "TER"
			print "END"
		}
	' source.pdb > protein.pdb || fail 'Unexpected 1AKI structure; inspect chain A, alternate locations and residue count.'
	printf 'structure_url=%s\nretrieved_utc=%s\nselection=ATOM records, chain A, 129 residues; crystallographic waters excluded\n' \
		"$structure_url" "$(date -u +%FT%TZ)" > provenance.txt
	sha256sum source.pdb protein.pdb run.sh ./*.mdp provenance.txt > SHA256SUMS
	printf 'Prepared inputs in %s\n' "$PWD"
}

run() {
	local input_directory="$1"
	local output_directory="$2"
	local seed="${3:-20261008}"
	local threads="${4:-2}"
	local profile="${5:-run}"
	local gmx="${GMX:-gmx}"
	[[ "$seed" =~ ^[1-9][0-9]{0,8}$ ]] || fail 'SEED must be an integer from 1 to 999999999.'
	[[ "$threads" =~ ^[1-9][0-9]{0,2}$ ]] || fail 'THREADS must be an integer from 1 to 999.'
	require_command "$gmx"
	require_command sha256sum
	input_directory=$(cd -- "$input_directory" && pwd)
	for filename in protein.pdb source.pdb run.sh provenance.txt SHA256SUMS ions.mdp em.mdp nvt.mdp npt.mdp md.mdp; do
		[[ -s "$input_directory/$filename" ]] || fail "Missing input: $filename"
	done
	(cd -- "$input_directory" && sha256sum --check --strict SHA256SUMS)
	new_directory "$output_directory"
	cd -- "$output_directory"
	trap 'exit_code=$?; if ((exit_code != 0)); then printf "failed\n" > run-status.txt; fi' EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
	printf 'running\n' > run-status.txt
	cp -- "$input_directory/"*.mdp "$input_directory/protein.pdb" \
		"$input_directory/source.pdb" "$input_directory/provenance.txt" \
		"$input_directory/run.sh" "$input_directory/SHA256SUMS" .
	mv SHA256SUMS input-SHA256SUMS
	sed -i "s/^gen_seed[[:space:]]*=.*/gen_seed = $seed/" nvt.mdp
	if [[ "$profile" == smoke ]]; then
		sed -i -e 's/^nsteps[[:space:]]*=.*/nsteps = 1000/' \
			-e 's/^nstxout-compressed[[:space:]]*=.*/nstxout-compressed = 50/' \
			-e 's/^nstenergy[[:space:]]*=.*/nstenergy = 50/' \
			-e 's/^nstlog[[:space:]]*=.*/nstlog = 50/' nvt.mdp npt.mdp md.mdp
	fi
	"$gmx" --version > gromacs-version.txt 2>&1
	printf 'profile=%s\nseed=%s\nthreads=%s\nforce_field=oplsaa\nwater_model=spce\nstarted_utc=%s\n' \
		"$profile" "$seed" "$threads" "$(date -u +%FT%TZ)" > run-provenance.txt

	printf 'Preparing the protein, water and counterions (%s profile).\n' "$profile"
	"$gmx" pdb2gmx -f protein.pdb -o processed.gro -p topol.top \
		-ff oplsaa -water spce -ignh > preparation.log 2>&1
	"$gmx" editconf -f processed.gro -o boxed.gro -c -d 1.0 -bt dodecahedron >> preparation.log 2>&1
	"$gmx" solvate -cp boxed.gro -cs spc216.gro -o solvated.gro -p topol.top >> preparation.log 2>&1
	"$gmx" grompp -f ions.mdp -c solvated.gro -p topol.top -o ions.tpr -po ions-effective.mdp >> preparation.log 2>&1
	printf 'SOL\n' | "$gmx" genion -s ions.tpr -o neutralized.gro -p topol.top \
		-pname NA -nname CL -neutral -seed "$seed" >> preparation.log 2>&1

	printf 'Minimizing energy.\n'
	"$gmx" grompp -f em.mdp -c neutralized.gro -p topol.top -o em.tpr -po em-effective.mdp > em-preprocess.log 2>&1
	"$gmx" mdrun -deffnm em -ntmpi 1 -ntomp "$threads" -nb cpu > em-console.log 2>&1
	grep -q 'converged to Fmax <' em.log || fail 'Minimization did not meet its force threshold; inspect em.log.'
	printf 'Running the fixed-volume stage.\n'
	"$gmx" grompp -f nvt.mdp -c em.gro -r em.gro -p topol.top -o nvt.tpr -po nvt-effective.mdp > nvt-preprocess.log 2>&1
	"$gmx" mdrun -deffnm nvt -ntmpi 1 -ntomp "$threads" -nb cpu -pme cpu > nvt-console.log 2>&1
	printf 'Running the pressure-controlled stage.\n'
	"$gmx" grompp -f npt.mdp -c nvt.gro -r em.gro -t nvt.cpt -p topol.top -o npt.tpr -po npt-effective.mdp > npt-preprocess.log 2>&1
	"$gmx" mdrun -deffnm npt -ntmpi 1 -ntomp "$threads" -nb cpu -pme cpu > npt-console.log 2>&1
	printf 'Running the unrestrained stage.\n'
	"$gmx" grompp -f md.mdp -c npt.gro -t npt.cpt -p topol.top -o md.tpr -po md-effective.mdp > md-preprocess.log 2>&1
	"$gmx" mdrun -deffnm md -ntmpi 1 -ntomp "$threads" -nb cpu -pme cpu > md-console.log 2>&1
	if grep -Eiq 'LINCS WARNING|constraint warning|can not be settled' ./*.log; then
		fail 'Numerical instability detected; inspect logs before interpreting any output.'
	fi

	printf 'Analyzing the trajectory.\n'
	printf 'Protein\nSystem\n' | "$gmx" trjconv -s md.tpr -f md.xtc \
		-o centered.xtc -pbc mol -center > analysis.log 2>&1
	printf 'Backbone\nBackbone\n' | "$gmx" rms -s md.tpr -f centered.xtc \
		-o backbone-rmsd.xvg -tu ns >> analysis.log 2>&1
	"$gmx" gyrate -s md.tpr -f centered.xtc -sel 'group Protein' \
		-o radius-of-gyration.xvg -tu ns >> analysis.log 2>&1
	printf 'Temperature\nPressure\nDensity\nPotential\n0\n' | "$gmx" energy \
		-f md.edr -o thermodynamics.xvg >> analysis.log 2>&1
	"$gmx" check -f md.xtc > trajectory-check.log 2>&1
	sha256sum protein.pdb ./*.mdp topol.top ./*.itp > run-SHA256SUMS
	printf 'completed\n' > run-status.txt
	trap - EXIT INT TERM
	printf '%s profile finished in %s. This is a workflow demonstration, not a formulation result.\n' "$profile" "$PWD"
}

case "${1:-}" in
	-h|--help)
		usage
		;;
	prepare)
		[[ $# -eq 2 ]] || { usage >&2; exit 2; }
		prepare "$2"
		;;
	run|smoke)
		[[ $# -ge 3 && $# -le 5 ]] || { usage >&2; exit 2; }
		run "$2" "$3" "${4:-20261008}" "${5:-2}" "$1"
		;;
	*)
		usage >&2
		exit 2
		;;
esac