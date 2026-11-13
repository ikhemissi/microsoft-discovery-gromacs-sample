#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
	printf '%s\n' \
		'Usage: bash run.sh prepare PROTOCOL_DIRECTORY' \
		'       bash run.sh run INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY [SEED] [THREADS]' \
		'       bash run.sh smoke INPUT_DIRECTORY NEW_OUTPUT_DIRECTORY [SEED] [THREADS]' \
		'prepare adds the 1AKI structure, provenance and checksums to a directory holding the five MDP files.' \
		'run executes the protocol as written; smoke shortens each dynamics stage to 2 ps as a technical test.' \
		'Both require GROMACS 2024+ with thread-MPI; defaults: seed 20261008, 2 CPU threads.' \
		'GROMACS_ACCELERATION=cpu (default) or gpu; GPU mode requires CUDA and an NVIDIA device.'
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

protocol_files=(ions.mdp em.mdp nvt.mdp npt.mdp md.mdp)
structure_files=(source.pdb protein.pdb provenance.txt SHA256SUMS)

# Prints an MDP value; GROMACS treats '-' and '_' in names alike and ';' starts a comment.
mdp_value() {
	awk -v wanted="$2" '
		{ sub(/;.*/, "") }
		index($0, "=") {
			key = tolower(substr($0, 1, index($0, "=") - 1)); gsub(/[[:space:]]/, "", key); gsub(/-/, "_", key)
			value = substr($0, index($0, "=") + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			if (key == wanted) result = value
		}
		END { print result }
	' "$1"
}

# Catches protocol mistakes that grompp accepts but that crash or invalidate a run.
validate_protocol() {
	local stage dt constraints
	for stage in nvt npt md; do
		[[ $(mdp_value "$stage.mdp" integrator) == md ]] || fail "$stage.mdp must use integrator = md."
		dt=$(mdp_value "$stage.mdp" dt)
		constraints=$(mdp_value "$stage.mdp" constraints)
		if awk -v dt="${dt:-0.001}" 'BEGIN { exit !(dt > 0.001) }' && [[ "${constraints:-none}" == none ]]; then
			fail "$stage.mdp uses dt = $dt ps without bond constraints; use dt = 0.001 or constrain bonds."
		fi
		if [[ $(mdp_value "$stage.mdp" continuation) == yes && $(mdp_value "$stage.mdp" gen_vel) == yes ]]; then
			fail "$stage.mdp sets continuation = yes and gen_vel = yes; a continued stage must keep its velocities."
		fi
	done
	[[ $(mdp_value nvt.mdp gen_vel) == yes ]] || fail 'nvt.mdp must generate velocities (gen_vel = yes).'
	for stage in npt md; do
		[[ $(mdp_value "$stage.mdp" continuation) == yes ]] || fail "$stage.mdp must continue from the previous stage (continuation = yes)."
	done
	[[ $(mdp_value md.mdp nstxout_compressed) =~ ^[1-9][0-9]*$ ]] || fail 'md.mdp must write a compressed trajectory (nstxout-compressed > 0) for analysis.'
}

summarize_protocol() {
	local stage
	printf 'stage\tintegrator\tdt_ps\tnsteps\tduration_ps\tref_t_K\tpcoupl\tref_p_bar\tposition_restraints\n'
	for stage in em nvt npt md; do
		local integrator dt nsteps duration
		integrator=$(mdp_value "$stage.mdp" integrator)
		dt=$(mdp_value "$stage.mdp" dt)
		nsteps=$(mdp_value "$stage.mdp" nsteps)
		duration=-
		[[ "$integrator" == md ]] && duration=$(awk -v dt="$dt" -v n="$nsteps" 'BEGIN { printf "%g", dt * n }')
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$stage" "$integrator" "${dt:--}" "$nsteps" "$duration" \
			"$(mdp_value "$stage.mdp" ref_t)" "$(mdp_value "$stage.mdp" pcoupl)" "$(mdp_value "$stage.mdp" ref_p)" \
			"$([[ $(mdp_value "$stage.mdp" define) == *-DPOSRES* ]] && echo yes || echo no)"
	done
}

prepare() {
	local destination="$1"
	local structure_url='https://files.rcsb.org/download/1AKI.pdb'
	for dependency in curl awk sha256sum; do
		require_command "$dependency"
	done
	[[ -d "$destination" ]] || fail "Protocol directory not found: $destination"
	for filename in "${protocol_files[@]}"; do
		[[ -s "$destination/$filename" ]] || fail "Missing protocol file: $filename"
	done
	for filename in "${structure_files[@]}"; do
		[[ ! -e "$destination/$filename" ]] || fail "Refusing to overwrite existing path: $destination/$filename"
	done
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
	printf 'protocol=%s\nstructure_url=%s\nretrieved_utc=%s\nselection=ATOM records, chain A, 129 residues; crystallographic waters excluded\n' \
		"$(basename -- "$(dirname -- "$PWD")")/$(basename -- "$PWD")" "$structure_url" "$(date -u +%FT%TZ)" > provenance.txt
	sha256sum source.pdb protein.pdb ./*.mdp provenance.txt > SHA256SUMS
	printf 'Prepared inputs in %s\n' "$PWD"
}

run() {
	local input_directory="$1"
	local output_directory="$2"
	local seed="${3:-20261008}"
	local threads="${4:-2}"
	local profile="${5:-run}"
	local gmx="${GMX:-gmx}"
	local acceleration="${GROMACS_ACCELERATION:-cpu}"
	[[ "$acceleration" == cpu || "$acceleration" == gpu ]] || fail 'GROMACS_ACCELERATION must be cpu or gpu.'
	[[ "$seed" =~ ^[1-9][0-9]{0,8}$ ]] || fail 'SEED must be an integer from 1 to 999999999.'
	[[ "$threads" =~ ^[1-9][0-9]{0,2}$ ]] || fail 'THREADS must be an integer from 1 to 999.'
	require_command "$gmx"
	require_command sha256sum
	input_directory=$(cd -- "$input_directory" && pwd)
	for filename in "${structure_files[@]}" "${protocol_files[@]}"; do
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
		"$input_directory/SHA256SUMS" .
	mv SHA256SUMS input-SHA256SUMS
	validate_protocol
	sed -i "s/^gen_seed[[:space:]]*=.*/gen_seed = $seed/" nvt.mdp
	if [[ "$profile" == smoke ]]; then
		sed -i -e 's/^nsteps[[:space:]]*=.*/nsteps = 1000/' \
			-e 's/^nstxout-compressed[[:space:]]*=.*/nstxout-compressed = 50/' \
			-e 's/^nstenergy[[:space:]]*=.*/nstenergy = 50/' \
			-e 's/^nstlog[[:space:]]*=.*/nstlog = 50/' nvt.mdp npt.mdp md.mdp
	fi
	summarize_protocol > protocol-summary.tsv
	"$gmx" --version > gromacs-version.txt 2>&1
	if [[ "$acceleration" == gpu ]]; then
		grep -Eiq '^GPU support:[[:space:]]+CUDA' gromacs-version.txt || fail 'GPU mode requires a CUDA-enabled GROMACS build.'
	fi
	printf 'profile=%s\nseed=%s\nthreads=%s\nacceleration=%s\nforce_field=oplsaa\nwater_model=spce\nstarted_utc=%s\n' \
		"$profile" "$seed" "$threads" "$acceleration" "$(date -u +%FT%TZ)" > run-provenance.txt
	local dynamics_options=(-ntmpi 1 -ntomp "$threads" -nb "$acceleration" -pme cpu -bonded cpu -update cpu)

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
	"$gmx" mdrun -deffnm nvt "${dynamics_options[@]}" > nvt-console.log 2>&1
	printf 'Running the pressure-controlled stage.\n'
	"$gmx" grompp -f npt.mdp -c nvt.gro -r em.gro -t nvt.cpt -p topol.top -o npt.tpr -po npt-effective.mdp > npt-preprocess.log 2>&1
	"$gmx" mdrun -deffnm npt "${dynamics_options[@]}" > npt-console.log 2>&1
	printf 'Running the unrestrained stage.\n'
	"$gmx" grompp -f md.mdp -c npt.gro -t npt.cpt -p topol.top -o md.tpr -po md-effective.mdp > md-preprocess.log 2>&1
	"$gmx" mdrun -deffnm md "${dynamics_options[@]}" > md-console.log 2>&1
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