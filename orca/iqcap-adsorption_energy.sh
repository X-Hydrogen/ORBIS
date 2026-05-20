#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-adsorption_energy  (Adsorption Energy Analysis)
#
#  Version:    1.5.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-03-03
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Adsorption energy analysis module. Decomposes a complex into two
#    fragments, optimizes each independently at publication quality,
#    and computes the adsorption energy:
#      E_ads = E(complex) - E(frag1) - E(frag2)
#
#    Results are reported in Hartree, eV, kcal/mol, and kJ/mol.
#    VMD three-view rendering of the complex with adsorption energy
#    annotation is also generated.
#
#  Prerequisite:
#    iqcap-opt.sh must have been run first (optimization/ folder required).
#
#  Output structure:
#    adsorption_energy/
#      entirety/    - copy of optimization/ (complex, already optimized)
#      frag1/       - fragment 1 independent geometry optimization
#      frag2/       - fragment 2 independent geometry optimization
#      energy_summary.txt   - multi-unit energy report
#      energy_data.csv      - machine-readable energy data
#      molecule_{front,side,top}.png - three-view renders with E_ads
#
#  External dependencies: ORCA, VMD, Python 3 (Pillow, matplotlib)
#
#  Usage:
#    bash iqcap-adsorption_energy.sh --frag1-atoms "1-3" --frag2-atoms "4-6"
#    bash iqcap-adsorption_energy.sh   # interactive fragment selection
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-adsorption_energy"
IQCAP_VERSION="1.5.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration
###############################################################################
ORCA_BIN=""
ORCA_2AIM_BIN=""
ORCA_2MKL_BIN=""
VMD_BIN=""

XYZ_FILE="0.xyz"
NPROCS=16
MAXCORE=4096
OUTPUT_DIR="adsorption_energy"

# Fragment optimization level (default: iqcap_orca.env + opt, or method-1 fallback)
OPT_LEVEL_PUB=""
OPT_PUB_CLI=0

# Fragment definition
FRAG1_ATOMS=""
FRAG2_ATOMS=""

# Fragment charge / multiplicity (auto-inferred if empty)
FRAG1_CHARGE=""
FRAG1_MULT=""
FRAG2_CHARGE=""
FRAG2_MULT=""

# Total charge of complex (auto-read from optimization output)
TOTAL_CHARGE="auto"
TOTAL_MULT="auto"

# Visualization
MOL_ZOOM=1.00
PLOT_ONLY=0
ELEMENT_COLOR_OVERRIDES=()

###############################################################################
# Unit conversion constants (CODATA 2018)
###############################################################################
HA_TO_EV="27.211386245988"
HA_TO_KCAL="627.5094740631"
HA_TO_KJ="2625.4996394799"

###############################################################################
# CLI
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --xyz)            XYZ_FILE="$2";       shift 2 ;;
    --output-dir)     OUTPUT_DIR="$2";     shift 2 ;;
    --nprocs)         NPROCS="$2";         shift 2 ;;
    --maxcore)        MAXCORE="$2";        shift 2 ;;
    --frag1-atoms)    FRAG1_ATOMS="$2";    shift 2 ;;
    --frag2-atoms)    FRAG2_ATOMS="$2";    shift 2 ;;
    --frag1-charge)   FRAG1_CHARGE="$2";   shift 2 ;;
    --frag1-mult)     FRAG1_MULT="$2";     shift 2 ;;
    --frag2-charge)   FRAG2_CHARGE="$2";   shift 2 ;;
    --frag2-mult)     FRAG2_MULT="$2";     shift 2 ;;
    --total-charge)   TOTAL_CHARGE="$2";   shift 2 ;;
    --total-mult)     TOTAL_MULT="$2";     shift 2 ;;
    --opt-pub)        OPT_LEVEL_PUB="$2"; OPT_PUB_CLI=1; shift 2 ;;
    --mol-zoom)       MOL_ZOOM="$2";       shift 2 ;;
    --plot-only)      PLOT_ONLY=1;          shift 1 ;;
    --element-color)  ELEMENT_COLOR_OVERRIDES+=("$2"); shift 2 ;;
    --orca-bin)       ORCA_BIN="$2";       shift 2 ;;
    --orca-2aim-bin)  ORCA_2AIM_BIN="$2";  shift 2 ;;
    --orca-2mkl-bin)  ORCA_2MKL_BIN="$2";  shift 2 ;;
    --vmd-bin)        VMD_BIN="$2";        shift 2 ;;
    -V|--version)
      echo "$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME"
      echo "Module:    $IQCAP_MODULE (Adsorption Energy Analysis)"
      echo "Author:    $IQCAP_AUTHOR"
      echo "Copyright: $IQCAP_COPYRIGHT"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME
Module: $IQCAP_MODULE (Adsorption Energy Analysis)

Usage: bash iqcap-adsorption_energy.sh [options]

  Prerequisite: iqcap-opt.sh must have been run first (optimization/ folder).

  Computes adsorption energy: E_ads = E(complex) - E(frag1) - E(frag2)
  Each fragment is independently geometry-optimized at publication quality.

Fragment definition:
  --frag1-atoms STR    Fragment 1 atom indices (1-based, e.g. "1-3" or "1,2,3")
  --frag2-atoms STR    Fragment 2 atom indices (e.g. "4-6")
                       If not provided, interactive selection is used.

Fragment charge / multiplicity (recommended to set manually for charged systems):
  --frag1-charge INT   Fragment 1 charge (integer). If omitted, prompted interactively or auto-inferred.
  --frag1-mult INT     Fragment 1 multiplicity (auto-inferred if omitted)
  --frag2-charge INT   Fragment 2 charge (integer). If omitted, prompted interactively or auto-inferred.
  --frag2-mult INT     Fragment 2 multiplicity (auto-inferred if omitted)
  --total-charge INT   Total complex charge (auto from optimization/opt.out)
  --total-mult INT     Total complex multiplicity (auto from optimization/opt.out)

Theory level:
  --opt-pub STR        Fragment optimization level (default: iqcap_orca.env or PBE0 D3BJ TZVP RIJCOSX opt)

Compute resources:
  --nprocs INT         Number of parallel processes (default: 16)
  --maxcore INT        Memory per process in MB (default: 4096)

Visualization:
  --mol-zoom FLOAT     VMD zoom factor (default: 1.00)
  --plot-only            Skip all computation; re-render from existing data
  --element-color SPEC  Override element color (repeatable). SPEC formats:
                        "Na=#1f77b4" or "S=#ffcc00" or "Na=0.12/0.34/0.56" (RGB 0..1)
                        Multiple entries can be separated by ',' or ';'

Path overrides:
  --orca-bin PATH      ORCA executable path
  --orca-2aim-bin PATH orca_2aim path
  --orca-2mkl-bin PATH orca_2mkl path
  --vmd-bin PATH       VMD executable path

Info:
  -h, --help           Show this help message
  -V, --version        Show version information

Output structure:
  adsorption_energy/
    entirety/    - copy of optimization/ (complex)
    frag1/       - fragment 1 optimization
    frag2/       - fragment 2 optimization
    energy_summary.txt   - energy report
    energy_data.csv      - CSV energy data
    molecule_{front,side,top}.png - annotated renders

Python requirements: Pillow, matplotlib
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$OPT_PUB_CLI" -eq 0 ]]; then
  if [[ -f "optimization/iqcap_orca.env" ]]; then
    # shellcheck disable=SC1090
    source "optimization/iqcap_orca.env"
    [[ -n "${IQCAP_ORCA_BASE:-}" ]] && OPT_LEVEL_PUB="$IQCAP_ORCA_BASE opt"
  fi
  [[ -z "$OPT_LEVEL_PUB" ]] && OPT_LEVEL_PUB="PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
fi

# Pass element-color overrides to VMD/Python via env (consumed by embedded TCL)
ELEMENT_COLOR_OVERRIDES=(
  "Na=#FFAEB9"
  "B=#FFAEB9"
  "Li=#90EE90"
  "C=#8E8E8E"
  "F=#1cffe8"
  "${ELEMENT_COLOR_OVERRIDES[@]}"
)
export IQCAP_ELEMENT_COLORS
IQCAP_ELEMENT_COLORS="$(printf '%s;' "${ELEMENT_COLOR_OVERRIDES[@]}")"
IQCAP_ELEMENT_COLORS="${IQCAP_ELEMENT_COLORS%;}"

###############################################################################
# Helpers: path resolution
###############################################################################
expand_path() {
  local p="$1"
  [[ "$p" == "~"* ]] && p="${HOME}${p:1}"
  echo "$p"
}

resolve_bin() {
  local user_bin="$1" fallback="$2" candidate=""
  if [[ -n "$user_bin" ]]; then
    user_bin="$(expand_path "$user_bin")"
    [[ -x "$user_bin" ]] && { echo "$user_bin"; return 0; }
    [[ -d "$user_bin" && -x "$user_bin/$fallback" ]] && { echo "$user_bin/$fallback"; return 0; }
    return 1
  fi
  candidate="$(type -P "$fallback" 2>/dev/null || true)"
  [[ -n "$candidate" && -x "$candidate" ]] && { echo "$candidate"; return 0; }
  local candidates=()
  shopt -s nullglob
  candidates=( "$HOME/tools/$fallback" $HOME/tools/*/"$fallback" $HOME/tools/*/*/"$fallback" "/usr/local/bin/$fallback" "/usr/bin/$fallback" )
  shopt -u nullglob
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

resolve_bin_any() {
  local user_bin="$1"; shift
  local names=("$@") n candidate
  if [[ -n "$user_bin" ]]; then
    user_bin="$(expand_path "$user_bin")"
    [[ -x "$user_bin" ]] && { echo "$user_bin"; return 0; }
    if [[ -d "$user_bin" ]]; then
      for n in "${names[@]}"; do
        [[ -x "$user_bin/$n" ]] && { echo "$user_bin/$n"; return 0; }
      done
    fi
    return 1
  fi
  for n in "${names[@]}"; do
    candidate="$(resolve_bin "" "$n" || true)"
    [[ -n "$candidate" && -x "$candidate" ]] && { echo "$candidate"; return 0; }
  done
  return 1
}

###############################################################################
# Helpers: ORCA
###############################################################################
write_orca_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" xyz_source="$5"
  cat > "$inp_file" <<EOF
! $level
%maxcore  $MAXCORE
%pal nprocs   $NPROCS end
* xyz   $charge   $mult
$(awk 'NR>2 {print $0}' "$xyz_source")
 *
EOF
}

check_orca_success() {
  local out_file="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -q "THE OPTIMIZATION HAS CONVERGED|OPTIMIZATION RUN DONE|ORCA TERMINATED NORMALLY" "$out_file" 2>/dev/null
  else
    grep -Eq "THE OPTIMIZATION HAS CONVERGED|OPTIMIZATION RUN DONE|ORCA TERMINATED NORMALLY" "$out_file" 2>/dev/null
  fi
}

extract_final_energy() {
  local out_file="$1"
  grep "FINAL SINGLE POINT ENERGY" "$out_file" | tail -1 | awk '{print $NF}'
}

count_atoms_in_xyz() {
  local xyz_file="$1"
  awk 'NR==1 {print int($1); exit}' "$xyz_file"
}

single_point_level_from_opt_level() {
  local level="$1"
  awk '{
    out = ""
    for (i = 1; i <= NF; i++) {
      if (tolower($i) != "opt") {
        out = (out == "" ? $i : out " " $i)
      }
    }
    if (out == "") out = $0
    print out
  }' <<< "$level"
}

###############################################################################
# Helpers: fragment extraction
###############################################################################
extract_fragment_xyz() {
  local xyz_file="$1" atom_spec="$2" out_file="$3"
  python3 - "$xyz_file" "$atom_spec" "$out_file" <<'PYXYZ'
import sys, re
from pathlib import Path
def expand_indices(s):
    indices = []
    for part in re.split(r'[,\s]+', s.strip()):
        if not part: continue
        if '-' in part:
            a, b = part.split('-', 1)
            indices.extend(range(int(a), int(b) + 1))
        else:
            indices.append(int(part))
    return sorted(set(indices))
xyz_file, atom_spec, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
lines = Path(xyz_file).read_text().splitlines()
natom = int(lines[0].strip())
atoms = lines[2:2 + natom]
indices = expand_indices(atom_spec)
for i in indices:
    if i < 1 or i > natom:
        raise SystemExit(f"Atom index {i} out of range (1..{natom})")
selected = [atoms[i - 1] for i in indices]
with open(out_file, 'w') as f:
    f.write(f"{len(selected)}\n")
    f.write(f"Fragment from {xyz_file}\n")
    for line in selected:
        f.write(line.rstrip() + "\n")
PYXYZ
}

validate_fragment_partition() {
  local xyz_file="$1" frag1="$2" frag2="$3"
  python3 - "$xyz_file" "$frag1" "$frag2" <<'PYVAL'
import sys, re

def expand_indices(s):
    indices = []
    for part in re.split(r'[,\s]+', s.strip()):
        if not part:
            continue
        if '-' in part:
            a, b = part.split('-', 1)
            indices.extend(range(int(a), int(b) + 1))
        else:
            indices.append(int(part))
    return sorted(set(indices))

with open(sys.argv[1]) as f:
    natom = int(f.readline().strip())

f1 = expand_indices(sys.argv[2])
f2 = expand_indices(sys.argv[3])
expected = list(range(1, natom + 1))

if sorted(set(f1 + f2)) != expected:
    missing = set(expected) - set(f1 + f2)
    extra = set(f1 + f2) - set(expected)
    msg = "Fragment atoms must partition ALL complex atoms.\n"
    if missing:
        msg += f"  Missing atoms: {sorted(missing)}\n"
    if extra:
        msg += f"  Extra atoms: {sorted(extra)}\n"
    raise SystemExit(msg)

overlap = set(f1) & set(f2)
if overlap:
    raise SystemExit(f"Fragments overlap at atoms: {sorted(overlap)}")
PYVAL
}

###############################################################################
# Helpers: charge / multiplicity inference
###############################################################################
read_charge_mult_from_optimization() {
  local chg="" mult=""
  for f in "optimization/opt.out" "optimization/opt.inp"; do
    [[ -f "$f" ]] || continue
    chg=$(grep -m1 "Total Charge" "$f" 2>/dev/null | awk '{print $NF}')
    [[ -n "$chg" && "$chg" =~ ^-?[0-9]+$ ]] && break
    chg=$(grep -m1 "^\* xyz" "$f" 2>/dev/null | awk '{print $3}')
    [[ -n "$chg" && "$chg" =~ ^-?[0-9]+$ ]] && break
  done
  for f in "optimization/opt.out" "optimization/opt.inp"; do
    [[ -f "$f" ]] || continue
    mult=$(grep -m1 "Multiplicity" "$f" 2>/dev/null | awk '{print $NF}')
    [[ -n "$mult" && "$mult" =~ ^[0-9]+$ ]] && break
    mult=$(grep -m1 "^\* xyz" "$f" 2>/dev/null | awk '{print $4}')
    [[ -n "$mult" && "$mult" =~ ^[0-9]+$ ]] && break
  done
  echo "${chg:-0} ${mult:-1}"
}

infer_fragment_charge_mult() {
  local frag_xyz="$1" q_total="$2"
  python3 - "$frag_xyz" "$q_total" <<'PYINFER'
import sys
from pathlib import Path

zmap = {
    'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Ne':10,
    'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'Ar':18,
    'K':19,'Ca':20,'Sc':21,'Ti':22,'V':23,'Cr':24,'Mn':25,'Fe':26,
    'Co':27,'Ni':28,'Cu':29,'Zn':30,'Ga':31,'Ge':32,'As':33,'Se':34,
    'Br':35,'Kr':36,'Rb':37,'Sr':38,'Y':39,'Zr':40,'Nb':41,'Mo':42,
    'Ru':44,'Rh':45,'Pd':46,'Ag':47,'Cd':48,'In':49,'Sn':50,'Sb':51,
    'Te':52,'I':53,'Xe':54
}

lines = Path(sys.argv[1]).read_text().splitlines()
n = int(lines[0].strip())
total_z = 0
for ln in lines[2:2+n]:
    if not ln.strip():
        continue
    tok = ln.split()[0]
    sym = tok[0].upper() + (tok[1:].lower() if len(tok) > 1 else '')
    total_z += zmap.get(sym, 0)

q_total = int(sys.argv[2])
nel = total_z - q_total
mult = 1 if nel % 2 == 0 else 2
print(f"{q_total} {mult}")
PYINFER
}

compute_z_sum() {
  local xyz_file="$1"
  python3 - "$xyz_file" <<'PYZ'
import sys
from pathlib import Path
zmap = {
    'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Ne':10,
    'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'Ar':18,
    'K':19,'Ca':20,'Br':35,'I':53
}
lines = Path(sys.argv[1]).read_text().splitlines()
n = int(lines[0].strip())
total = 0
for ln in lines[2:2+n]:
    if not ln.strip(): continue
    tok = ln.split()[0]
    sym = tok[0].upper() + (tok[1:].lower() if len(tok) > 1 else '')
    total += zmap.get(sym, 0)
print(total)
PYZ
}

infer_closed_shell_charges() {
  local frag1_xyz="$1" frag2_xyz="$2" q_total="$3"
  python3 - "$frag1_xyz" "$frag2_xyz" "$q_total" <<'PYINFER'
import sys
from pathlib import Path

zmap = {
    'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Ne':10,
    'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'Ar':18,
    'K':19,'Ca':20,'Sc':21,'Ti':22,'V':23,'Cr':24,'Mn':25,'Fe':26,
    'Co':27,'Ni':28,'Cu':29,'Zn':30,'Br':35,'I':53
}

def z_sum(path):
    lines = Path(path).read_text().splitlines()
    n = int(lines[0].strip())
    total = 0
    for ln in lines[2:2+n]:
        if not ln.strip(): continue
        tok = ln.split()[0]
        sym = tok[0].upper() + (tok[1:].lower() if len(tok) > 1 else '')
        total += zmap.get(sym, 0)
    return total

Z1 = z_sum(sys.argv[1])
Z2 = z_sum(sys.argv[2])
Q_total = int(sys.argv[3])

best = None
best_score = 1e9
for q1 in range(-10, 11):
    q2 = Q_total - q1
    n1, n2 = Z1 - q1, Z2 - q2
    if n1 < 0 or n2 < 0:
        continue
    if n1 % 2 != 0 or n2 % 2 != 0:
        continue
    score = abs(q1) + abs(q2)
    if score < best_score:
        best_score = score
        best = (q1, q2)

if best is None:
    for q1 in range(-10, 11):
        q2 = Q_total - q1
        n1, n2 = Z1 - q1, Z2 - q2
        if n1 < 0 or n2 < 0:
            continue
        score = abs(q1) + abs(q2)
        if score < best_score:
            best_score = score
            best = (q1, q2)

if best is None:
    print("0 0")
else:
    print(f"{best[0]} {best[1]}")
PYINFER
}

###############################################################################
# Interactive fragment selection
###############################################################################
interactive_fragment_selection() {
  local xyz_file="$1"
  python3 - "$xyz_file" <<'PYSELECT'
import sys
from pathlib import Path

xyz_file = sys.argv[1]
lines = Path(xyz_file).read_text().splitlines()
natom = int(lines[0].strip())
atoms = lines[2:2 + natom]

print("")
print("=" * 60)
print("  Fragment Selection")
print("=" * 60)
print(f"  Total atoms: {natom}")
print("")
print(f"  {'Index':>6s}  {'Element':>8s}  {'X':>12s}  {'Y':>12s}  {'Z':>12s}")
print(f"  {'-'*6}  {'-'*8}  {'-'*12}  {'-'*12}  {'-'*12}")

for i, line in enumerate(atoms):
    parts = line.split()
    if len(parts) >= 4:
        print(f"  {i+1:6d}  {parts[0]:>8s}  {parts[1]:>12s}  {parts[2]:>12s}  {parts[3]:>12s}")

print("")
print("  Enter atom indices for Fragment 1 (e.g. 1-3 or 1,2,3).")
print("  Remaining atoms will be assigned to Fragment 2.")
print("")
PYSELECT

  read -rp "  Fragment 1 atoms: " FRAG1_ATOMS
  echo ""

  FRAG2_ATOMS=$(python3 - "$xyz_file" "$FRAG1_ATOMS" <<'PYREST'
import sys, re
from pathlib import Path

xyz_file = sys.argv[1]
frag1_spec = sys.argv[2]

lines = Path(xyz_file).read_text().splitlines()
natom = int(lines[0].strip())

def expand_indices(s):
    indices = []
    for part in re.split(r'[,\s]+', s.strip()):
        if not part: continue
        if '-' in part:
            a, b = part.split('-', 1)
            indices.extend(range(int(a), int(b) + 1))
        else:
            indices.append(int(part))
    return sorted(set(indices))

f1 = set(expand_indices(frag1_spec))
all_atoms = set(range(1, natom + 1))
f2 = sorted(all_atoms - f1)

parts = []
i = 0
while i < len(f2):
    start = f2[i]
    end = start
    while i + 1 < len(f2) and f2[i + 1] == end + 1:
        i += 1
        end = f2[i]
    if start == end:
        parts.append(str(start))
    else:
        parts.append(f"{start}-{end}")
    i += 1

print(",".join(parts))
PYREST
  )

  echo "  Fragment 1: $FRAG1_ATOMS"
  echo "  Fragment 2: $FRAG2_ATOMS"
  echo ""
}

###############################################################################
# VMD preamble for publication-quality rendering
###############################################################################
vmd_quality_preamble() {
  cat <<'TCLPRE'
display projection   Orthographic
display resize       2400 1800
display shadows      off
display ambientocclusion off
display aoambient    0.70
display aodirect     0.40
display depthcue     off
color Display Background white
axes location Off
TCLPRE
}

vmd_element_color_overrides() {
  cat <<'TCLEL'
# Optional element color overrides from env(IQCAP_ELEMENT_COLORS)
if {[info exists ::env(IQCAP_ELEMENT_COLORS)] && $::env(IQCAP_ELEMENT_COLORS) ne ""} {
  set spec $::env(IQCAP_ELEMENT_COLORS)
  regsub -all {[,;]+} $spec " " spec
  set cid 32
  foreach tok $spec {
    if {![regexp {^([A-Za-z][A-Za-z]?)=(.+)$} $tok -> el val]} { continue }
    set labels [list $el [string toupper $el] [string tolower $el] [string totitle [string tolower $el]]]
    set r ""; set g ""; set b ""
    if {[regexp {^#[0-9A-Fa-f]{6}$} $val]} {
      set hex [string range $val 1 end]
      scan $hex "%2x%2x%2x" r8 g8 b8
      set r [expr {$r8 / 255.0}]
      set g [expr {$g8 / 255.0}]
      set b [expr {$b8 / 255.0}]
    } elseif {[regexp {^([0-9]*\.?[0-9]+)/([0-9]*\.?[0-9]+)/([0-9]*\.?[0-9]+)$} $val -> rr gg bb]} {
      set r $rr; set g $gg; set b $bb
    } else {
      continue
    }
    catch { color change rgb $cid $r $g $b }
    foreach label $labels {
      catch { color Element $label $cid }
      catch { color Name $label $cid }
      catch { color Type $label $cid }
    }
    incr cid
  }
}
TCLEL
}

###############################################################################
# Three-view rendering with adsorption energy annotation
###############################################################################
render_molecule_with_eads() {
  local xyz_file="$1" out_dir="$2" e_ads_kcal="$3" e_ads_kj="$4" e_ads_ev="$5"
  local abs_out_dir
  abs_out_dir="$(cd "$out_dir" && pwd)"

  {
    vmd_quality_preamble
    cat <<'TCLBONDS'
# Add bonds that VMD may not infer (e.g. Li-S). Distance threshold in Angstrom.
proc add_bonds_by_distance { molid elem1 elem2 max_dist } {
  set sel1 [atomselect $molid "element $elem1"]
  set sel2 [atomselect $molid "element $elem2"]
  set idx1 [$sel1 get index]
  set idx2 [$sel2 get index]
  set coords1 [$sel1 get {x y z}]
  set coords2 [$sel2 get {x y z}]
  $sel1 delete
  $sel2 delete
  set n1 [llength $idx1]
  set n2 [llength $idx2]
  for {set i 0} {$i < $n1} {incr i} {
    set c1 [lindex $coords1 $i]
    for {set j 0} {$j < $n2} {incr j} {
      set c2 [lindex $coords2 $j]
      set d [veclength [vecsub $c1 $c2]]
      if {$d > 0.1 && $d < $max_dist} {
        catch { topo addbond [lindex $idx1 $i] [lindex $idx2 $j] }
      }
    }
  }
}
# Remove same-element bonds longer than max_keep (A). VMD XYZ connectivity often keeps spurious B-B bonds.
# Typical workflow: prune B-B > 1.6 A then add_bonds_by_distance B B 1.72 to restore covalent B-B (~1.65 A).
proc prune_same_element_bonds_beyond { molid elem max_keep } {
  set sel [atomselect $molid all]
  set idxlist [$sel list]
  set elemlist [$sel get element]
  set coords [$sel get {x y z}]
  array set elem_at {}
  array set crd_at {}
  foreach ix $idxlist e $elemlist c $coords {
    set elem_at($ix) $e
    set crd_at($ix) $c
  }
  foreach pair [topo -molid $molid getbondlist none] {
    set i [lindex $pair 0]
    set j [lindex $pair 1]
    if {![info exists elem_at($i)] || ![info exists elem_at($j)]} { continue }
    if {[string equal -nocase $elem_at($i) $elem] && [string equal -nocase $elem_at($j) $elem]} {
      set d [veclength [vecsub $crd_at($i) $crd_at($j)]]
      if {$d > $max_keep} {
        catch { topo -molid $molid delbond $i $j }
      }
    }
  }
  $sel delete
}
TCLBONDS
    cat <<EOF

mol new "$xyz_file" type xyz waitfor all
EOF
    vmd_element_color_overrides
    cat <<EOF
if {[catch {package require topotools} err] == 0} {
  add_bonds_by_distance top Li S 2.8
  add_bonds_by_distance top Na S 3.3
  prune_same_element_bonds_beyond top B 1.6
  add_bonds_by_distance top B B 1.72
}
mol delrep 0 top

mol representation CPK 0.8 0.3 30.0 30.0
mol color Element
mol selection all
mol material Glossy
mol addrep top

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$abs_out_dir/molecule_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$abs_out_dir/molecule_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$abs_out_dir/molecule_top.tga"

quit
EOF
  } > "$abs_out_dir/render_molecule.tcl"

  "$VMD_EXE" -dispdev text -e "$abs_out_dir/render_molecule.tcl" > "$abs_out_dir/molecule_render.out" 2>&1

  for v in front side top; do
    [[ -f "$abs_out_dir/molecule_${v}.tga" ]] || { echo "Missing molecule_${v}.tga" >&2; return 1; }
  done

  python3 - "$abs_out_dir" "$e_ads_kcal" "$e_ads_kj" "$e_ads_ev" <<'PYANN'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out_dir = Path(sys.argv[1])
e_kcal = sys.argv[2]
e_kj = sys.argv[3]
e_ev = sys.argv[4]

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"]):
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

footer = (f"Adsorption Energy:  "
          f"E_ads = {e_kcal} kcal/mol  "
          f"({e_kj} kJ/mol,  {e_ev} eV)")

for view in ("front", "side", "top"):
    tga = out_dir / f"molecule_{view}.tga"
    png = out_dir / f"molecule_{view}.png"
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        footer_h = max(80, int(0.07 * h))
        canvas = Image.new("RGBA", (w, h + footer_h), (255, 255, 255, 255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas)
        fn = _font(bold=True, size=max(32, int(0.024 * w)))
        fb = draw.textbbox((0, 0), footer, font=fn)
        draw.text(
            ((w - (fb[2] - fb[0])) / 2, h + (footer_h - (fb[3] - fb[1])) / 2),
            footer, fill=(30, 30, 30, 255), font=fn,
        )
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYANN
}

###############################################################################
# Energy summary generation
###############################################################################
generate_energy_summary() {
  local summary_file="$1" csv_file="$2" e_complex="$3" e_frag1="$4" e_frag2="$5"
  python3 - "$summary_file" "$csv_file" "$e_complex" "$e_frag1" "$e_frag2" \
           "$HA_TO_EV" "$HA_TO_KCAL" "$HA_TO_KJ" <<'PYSUM'
import sys

summary_file = sys.argv[1]
csv_file     = sys.argv[2]
E_complex    = float(sys.argv[3])
E_frag1      = float(sys.argv[4])
E_frag2      = float(sys.argv[5])
HA2EV        = float(sys.argv[6])
HA2KCAL      = float(sys.argv[7])
HA2KJ        = float(sys.argv[8])

E_ads_ha  = E_complex - E_frag1 - E_frag2

def conv(ha):
    return ha, ha * HA2EV, ha * HA2KCAL, ha * HA2KJ

lines = []
lines.append("=" * 90)
lines.append("  ADSORPTION ENERGY SUMMARY")
lines.append("  E_ads = E(complex) - E(frag1) - E(frag2)")
lines.append("=" * 90)
lines.append("")
lines.append(f"  {'':20s} {'Hartree':>16s} {'eV':>14s} {'kcal/mol':>14s} {'kJ/mol':>14s}")
lines.append(f"  {'-'*20} {'-'*16} {'-'*14} {'-'*14} {'-'*14}")

for label, E in [("Complex (entirety)", E_complex),
                 ("Fragment 1", E_frag1),
                 ("Fragment 2", E_frag2)]:
    ha, ev, kcal, kj = conv(E)
    lines.append(f"  {label:20s} {ha:16.10f} {ev:14.6f} {kcal:14.4f} {kj:14.4f}")

lines.append("")
lines.append(f"  {'':20s} {'Hartree':>16s} {'eV':>14s} {'kcal/mol':>14s} {'kJ/mol':>14s}")
lines.append(f"  {'-'*20} {'-'*16} {'-'*14} {'-'*14} {'-'*14}")

ha, ev, kcal, kj = conv(E_ads_ha)
lines.append(f"  {'E_ads':20s} {ha:16.10f} {ev:14.6f} {kcal:14.4f} {kj:14.4f}")

lines.append("")
if E_ads_ha < 0:
    lines.append(f"  Interpretation: Adsorption is EXOTHERMIC (E_ads < 0)")
    lines.append(f"  The complex is more stable than the separated fragments by {abs(kcal):.2f} kcal/mol")
else:
    lines.append(f"  Interpretation: Adsorption is ENDOTHERMIC (E_ads > 0)")
    lines.append(f"  The complex is less stable than the separated fragments by {kcal:.2f} kcal/mol")

lines.append("")
lines.append("=" * 90)

summary = "\n".join(lines)
print(summary)

with open(summary_file, "w") as f:
    f.write(summary + "\n")

with open(csv_file, "w") as f:
    f.write("species,E_Hartree,E_eV,E_kcal_mol,E_kJ_mol\n")
    for label, E in [("complex", E_complex), ("frag1", E_frag1), ("frag2", E_frag2)]:
        ha, ev, kcal, kj = conv(E)
        f.write(f"{label},{ha:.12f},{ev:.8f},{kcal:.6f},{kj:.6f}\n")
    f.write("\n")
    f.write("quantity,dE_Hartree,dE_eV,dE_kcal_mol,dE_kJ_mol\n")
    ha, ev, kcal, kj = conv(E_ads_ha)
    f.write(f"adsorption_energy,{ha:.12f},{ev:.8f},{kcal:.6f},{kj:.6f}\n")

print(f"\n  Summary: {summary_file}")
print(f"  CSV:     {csv_file}")

# Output formatted values for shell consumption (last 3 lines)
print(f"EADS_KCAL={kcal:.2f}")
print(f"EADS_KJ={kj:.2f}")
print(f"EADS_EV={ev:.4f}")
PYSUM
}

###############################################################################
# Pre-checks
###############################################################################
if [[ ! -d "optimization" ]]; then
  echo "========================================" >&2
  echo " ERROR: optimization/ folder not found." >&2
  echo "" >&2
  echo " Geometry optimization has not been completed." >&2
  echo " Please run iqcap-opt.sh first:" >&2
  echo "" >&2
  echo "   bash iqcap-opt.sh --mode 1" >&2
  echo "" >&2
  echo "========================================" >&2
  exit 1
fi

if [[ ! -f "optimization/opt.xyz" ]]; then
  echo "ERROR: optimization/opt.xyz not found. Please run iqcap-opt.sh first." >&2
  exit 1
fi

if [[ ! -f "optimization/opt.out" ]]; then
  echo "ERROR: optimization/opt.out not found. Please run iqcap-opt.sh first." >&2
  exit 1
fi

OPT_XYZ="optimization/opt.xyz"

if [[ "$PLOT_ONLY" -eq 0 ]]; then
  ORCA_EXE="$(resolve_bin_any "$ORCA_BIN" "orca")" || {
    echo "Cannot find ORCA executable" >&2; exit 1
  }
fi

VMD_EXE="$(resolve_bin_any "$VMD_BIN" "vmd" "VMD")" || {
  echo "Cannot find VMD executable" >&2; exit 1
}

python3 -c "from PIL import Image" >/dev/null 2>&1 || {
  echo "ERROR: Python Pillow required. Install: pip install Pillow" >&2; exit 1
}

###############################################################################
# Read total charge/mult from optimization
###############################################################################
if [[ "$TOTAL_CHARGE" == "auto" || "$TOTAL_MULT" == "auto" ]]; then
  _cm=$(read_charge_mult_from_optimization)
  _auto_chg=$(echo "$_cm" | awk '{print $1}')
  _auto_mult=$(echo "$_cm" | awk '{print $2}')
  [[ "$TOTAL_CHARGE" == "auto" ]] && TOTAL_CHARGE="$_auto_chg"
  [[ "$TOTAL_MULT" == "auto" ]] && TOTAL_MULT="$_auto_mult"
fi

###############################################################################
# Fragment selection (interactive or CLI)
###############################################################################
if [[ "$PLOT_ONLY" -eq 0 ]]; then
  if [[ -z "$FRAG1_ATOMS" || -z "$FRAG2_ATOMS" ]]; then
    DISPLAY_XYZ="$XYZ_FILE"
    [[ -f "$DISPLAY_XYZ" ]] || DISPLAY_XYZ="$OPT_XYZ"
    interactive_fragment_selection "$DISPLAY_XYZ"
  fi

  validate_fragment_partition "$OPT_XYZ" "$FRAG1_ATOMS" "$FRAG2_ATOMS"
fi

###############################################################################
# Fragment charges and multiplicities (manual input or inference)
###############################################################################
mkdir -p "$OUTPUT_DIR"

if [[ "$PLOT_ONLY" -eq 0 ]]; then
  extract_fragment_xyz "$OPT_XYZ" "$FRAG1_ATOMS" "$OUTPUT_DIR/frag1_tmp.xyz"
  extract_fragment_xyz "$OPT_XYZ" "$FRAG2_ATOMS" "$OUTPUT_DIR/frag2_tmp.xyz"

  if [[ -z "$FRAG1_CHARGE" || -z "$FRAG2_CHARGE" ]]; then
    _q1q2=$(infer_closed_shell_charges "$OUTPUT_DIR/frag1_tmp.xyz" "$OUTPUT_DIR/frag2_tmp.xyz" "$TOTAL_CHARGE")
    _inf_q1=$(echo "$_q1q2" | awk '{print $1}')
    _inf_q2=$(echo "$_q1q2" | awk '{print $2}')

    echo ""
    echo "  Total complex charge: $TOTAL_CHARGE"
    echo "  Inferred (closed-shell):  frag1 charge = $_inf_q1,  frag2 charge = $_inf_q2"
    echo "  (Fragment charges must sum to total: Q1 + Q2 = $TOTAL_CHARGE)"
    echo ""

    if [[ -t 0 ]]; then
      if [[ -z "$FRAG1_CHARGE" ]]; then
        read -rp "  Enter Fragment 1 charge (integer) [$_inf_q1]: " _input1
        FRAG1_CHARGE="${_input1:-$_inf_q1}"
      fi
      if [[ -z "$FRAG2_CHARGE" ]]; then
        read -rp "  Enter Fragment 2 charge (integer) [$_inf_q2]: " _input2
        FRAG2_CHARGE="${_input2:-$_inf_q2}"
      fi
    else
      echo "  No TTY: using inferred fragment charges (use --frag1-charge/--frag2-charge to set manually)."
      [[ -z "$FRAG1_CHARGE" ]] && FRAG1_CHARGE="$_inf_q1"
      [[ -z "$FRAG2_CHARGE" ]] && FRAG2_CHARGE="$_inf_q2"
    fi

    _sum=$((FRAG1_CHARGE + FRAG2_CHARGE))
    if [[ "$_sum" -ne "$TOTAL_CHARGE" ]]; then
      echo ""
      echo "  WARNING: Q(frag1) + Q(frag2) = $FRAG1_CHARGE + $FRAG2_CHARGE = $_sum != total charge $TOTAL_CHARGE" >&2
      echo "  Please check. Continuing anyway." >&2
      echo ""
    fi
  fi

  if [[ -z "$FRAG1_MULT" ]]; then
    _cm1=$(infer_fragment_charge_mult "$OUTPUT_DIR/frag1_tmp.xyz" "$FRAG1_CHARGE")
    FRAG1_MULT=$(echo "$_cm1" | awk '{print $2}')
  fi

  if [[ -z "$FRAG2_MULT" ]]; then
    _cm2=$(infer_fragment_charge_mult "$OUTPUT_DIR/frag2_tmp.xyz" "$FRAG2_CHARGE")
    FRAG2_MULT=$(echo "$_cm2" | awk '{print $2}')
  fi

  rm -f "$OUTPUT_DIR/frag1_tmp.xyz" "$OUTPUT_DIR/frag2_tmp.xyz"
fi

###############################################################################
# Banner
###############################################################################
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " $IQCAP_FULLNAME"
echo " Module: $IQCAP_MODULE (Adsorption Energy Analysis)"
echo "========================================"
echo "  ORCA:       ${ORCA_EXE:-"(not required for --plot-only)"}"
echo "  VMD:        $VMD_EXE"
echo "  Output:     $PWD/$OUTPUT_DIR/"
echo ""
echo "  Complex:    $OPT_XYZ  (charge=$TOTAL_CHARGE  mult=$TOTAL_MULT)"
echo "  Fragment 1: atoms $FRAG1_ATOMS  (charge=$FRAG1_CHARGE  mult=$FRAG1_MULT)"
echo "  Fragment 2: atoms $FRAG2_ATOMS  (charge=$FRAG2_CHARGE  mult=$FRAG2_MULT)"
echo "  Opt level:  $OPT_LEVEL_PUB"
echo "========================================"

###############################################################################
# 1) Copy optimization/ -> adsorption_energy/entirety/
###############################################################################
if [[ "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== Step 1: Preparing Entirety (Complex) ====="

  ENTIRETY_DIR="$OUTPUT_DIR/entirety"
  if [[ -d "$ENTIRETY_DIR" ]]; then
    echo "  entirety/ already exists, skipping copy."
  else
    cp -r optimization "$ENTIRETY_DIR"
    echo "  Copied optimization/ -> $ENTIRETY_DIR/"
  fi
fi

E_COMPLEX=$(extract_final_energy "optimization/opt.out")
if [[ -z "$E_COMPLEX" ]]; then
  echo "ERROR: Cannot extract energy from optimization/opt.out" >&2
  exit 1
fi
echo "  E(complex) = $E_COMPLEX Eh"

###############################################################################
# 2) Fragment 1 optimization
###############################################################################
if [[ "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== Step 2: Fragment 1 Geometry Optimization ====="

  FRAG1_DIR="$OUTPUT_DIR/frag1"
  mkdir -p "$FRAG1_DIR"

  extract_fragment_xyz "$OPT_XYZ" "$FRAG1_ATOMS" "$FRAG1_DIR/frag1_init.xyz"
  FRAG1_NATOMS="$(count_atoms_in_xyz "$FRAG1_DIR/frag1_init.xyz")"
  echo "  Fragment 1: $FRAG1_NATOMS atoms"
  echo "  Charge=$FRAG1_CHARGE  Mult=$FRAG1_MULT"

  if [[ "$FRAG1_NATOMS" -eq 1 ]]; then
    FRAG1_LEVEL_SP="$(single_point_level_from_opt_level "$OPT_LEVEL_PUB")"
    echo "  Single-atom fragment detected: skip geometry optimization, run single-point calculation."
    echo "  SP level: $FRAG1_LEVEL_SP"

    if [[ -f "$FRAG1_DIR/opt.out" ]] && check_orca_success "$FRAG1_DIR/opt.out" \
       && [[ -n "$(extract_final_energy "$FRAG1_DIR/opt.out" 2>/dev/null || true)" ]]; then
      echo "  Fragment 1 single-point calculation already completed, skipping."
    else
      echo "  Running publication-quality single-point calculation..."
      write_orca_input "$FRAG1_DIR/opt.inp" "$FRAG1_LEVEL_SP" "$FRAG1_CHARGE" "$FRAG1_MULT" "$FRAG1_DIR/frag1_init.xyz"
      pushd "$FRAG1_DIR" >/dev/null
      "$ORCA_EXE" opt.inp > opt.out 2>&1
      popd >/dev/null
    fi

    if check_orca_success "$FRAG1_DIR/opt.out"; then
      E_FRAG1=$(extract_final_energy "$FRAG1_DIR/opt.out")
      if [[ -z "$E_FRAG1" ]]; then
        echo "ERROR: Fragment 1 single-point run finished but energy was not found in $FRAG1_DIR/opt.out" >&2
        exit 1
      fi
      [[ -f "$FRAG1_DIR/opt.xyz" ]] || cp "$FRAG1_DIR/frag1_init.xyz" "$FRAG1_DIR/opt.xyz"
      echo "  Fragment 1 single-point calculation completed."
      echo "  E(frag1) = $E_FRAG1 Eh"
    else
      echo "ERROR: Fragment 1 single-point calculation failed. Check $FRAG1_DIR/opt.out" >&2
      exit 1
    fi
  elif [[ -f "$FRAG1_DIR/opt.out" ]] && check_orca_success "$FRAG1_DIR/opt.out"; then
    echo "  Fragment 1 optimization already completed, skipping."
  else
    echo "  Running publication-quality optimization..."
    write_orca_input "$FRAG1_DIR/opt.inp" "$OPT_LEVEL_PUB" "$FRAG1_CHARGE" "$FRAG1_MULT" "$FRAG1_DIR/frag1_init.xyz"
    pushd "$FRAG1_DIR" >/dev/null
    "$ORCA_EXE" opt.inp > opt.out 2>&1
    popd >/dev/null
  fi

  if [[ "$FRAG1_NATOMS" -ne 1 ]]; then
    if [[ -f "$FRAG1_DIR/opt.xyz" ]] && check_orca_success "$FRAG1_DIR/opt.out"; then
      E_FRAG1=$(extract_final_energy "$FRAG1_DIR/opt.out")
      echo "  Fragment 1 optimization converged."
      echo "  E(frag1) = $E_FRAG1 Eh"
    else
      echo "ERROR: Fragment 1 optimization failed. Check $FRAG1_DIR/opt.out" >&2
      exit 1
    fi
  fi

  ###############################################################################
  # 3) Fragment 2 optimization
  ###############################################################################
  echo ""
  echo "[*] ===== Step 3: Fragment 2 Geometry Optimization ====="

  FRAG2_DIR="$OUTPUT_DIR/frag2"
  mkdir -p "$FRAG2_DIR"

  extract_fragment_xyz "$OPT_XYZ" "$FRAG2_ATOMS" "$FRAG2_DIR/frag2_init.xyz"
  FRAG2_NATOMS="$(count_atoms_in_xyz "$FRAG2_DIR/frag2_init.xyz")"
  echo "  Fragment 2: $FRAG2_NATOMS atoms"
  echo "  Charge=$FRAG2_CHARGE  Mult=$FRAG2_MULT"

  if [[ "$FRAG2_NATOMS" -eq 1 ]]; then
    FRAG2_LEVEL_SP="$(single_point_level_from_opt_level "$OPT_LEVEL_PUB")"
    echo "  Single-atom fragment detected: skip geometry optimization, run single-point calculation."
    echo "  SP level: $FRAG2_LEVEL_SP"

    if [[ -f "$FRAG2_DIR/opt.out" ]] && check_orca_success "$FRAG2_DIR/opt.out" \
       && [[ -n "$(extract_final_energy "$FRAG2_DIR/opt.out" 2>/dev/null || true)" ]]; then
      echo "  Fragment 2 single-point calculation already completed, skipping."
    else
      echo "  Running publication-quality single-point calculation..."
      write_orca_input "$FRAG2_DIR/opt.inp" "$FRAG2_LEVEL_SP" "$FRAG2_CHARGE" "$FRAG2_MULT" "$FRAG2_DIR/frag2_init.xyz"
      pushd "$FRAG2_DIR" >/dev/null
      "$ORCA_EXE" opt.inp > opt.out 2>&1
      popd >/dev/null
    fi

    if check_orca_success "$FRAG2_DIR/opt.out"; then
      E_FRAG2=$(extract_final_energy "$FRAG2_DIR/opt.out")
      if [[ -z "$E_FRAG2" ]]; then
        echo "ERROR: Fragment 2 single-point run finished but energy was not found in $FRAG2_DIR/opt.out" >&2
        exit 1
      fi
      [[ -f "$FRAG2_DIR/opt.xyz" ]] || cp "$FRAG2_DIR/frag2_init.xyz" "$FRAG2_DIR/opt.xyz"
      echo "  Fragment 2 single-point calculation completed."
      echo "  E(frag2) = $E_FRAG2 Eh"
    else
      echo "ERROR: Fragment 2 single-point calculation failed. Check $FRAG2_DIR/opt.out" >&2
      exit 1
    fi
  elif [[ -f "$FRAG2_DIR/opt.out" ]] && check_orca_success "$FRAG2_DIR/opt.out"; then
    echo "  Fragment 2 optimization already completed, skipping."
  else
    echo "  Running publication-quality optimization..."
    write_orca_input "$FRAG2_DIR/opt.inp" "$OPT_LEVEL_PUB" "$FRAG2_CHARGE" "$FRAG2_MULT" "$FRAG2_DIR/frag2_init.xyz"
    pushd "$FRAG2_DIR" >/dev/null
    "$ORCA_EXE" opt.inp > opt.out 2>&1
    popd >/dev/null
  fi

  if [[ "$FRAG2_NATOMS" -ne 1 ]]; then
    if [[ -f "$FRAG2_DIR/opt.xyz" ]] && check_orca_success "$FRAG2_DIR/opt.out"; then
      E_FRAG2=$(extract_final_energy "$FRAG2_DIR/opt.out")
      echo "  Fragment 2 optimization converged."
      echo "  E(frag2) = $E_FRAG2 Eh"
    else
      echo "ERROR: Fragment 2 optimization failed. Check $FRAG2_DIR/opt.out" >&2
      exit 1
    fi
  fi
fi

###############################################################################
# 4) Adsorption energy calculation
###############################################################################
if [[ "$PLOT_ONLY" -eq 1 ]]; then
  FRAG1_DIR="$OUTPUT_DIR/frag1"
  FRAG2_DIR="$OUTPUT_DIR/frag2"
  E_FRAG1=$(extract_final_energy "$FRAG1_DIR/opt.out" 2>/dev/null) || true
  E_FRAG2=$(extract_final_energy "$FRAG2_DIR/opt.out" 2>/dev/null) || true
  if [[ -z "$E_COMPLEX" || -z "$E_FRAG1" || -z "$E_FRAG2" ]]; then
    echo "ERROR: Cannot read energies from existing output files for --plot-only" >&2
    [[ -z "$E_COMPLEX" ]] && echo "  Missing: E(complex) from optimization/opt.out" >&2
    [[ -z "$E_FRAG1" ]] && echo "  Missing: E(frag1) from $FRAG1_DIR/opt.out" >&2
    [[ -z "$E_FRAG2" ]] && echo "  Missing: E(frag2) from $FRAG2_DIR/opt.out" >&2
    exit 1
  fi
fi

echo ""
echo "[*] ===== Step 4: Adsorption Energy Calculation ====="

SUMMARY_OUTPUT=$(generate_energy_summary \
  "$OUTPUT_DIR/energy_summary.txt" \
  "$OUTPUT_DIR/energy_data.csv" \
  "$E_COMPLEX" "$E_FRAG1" "$E_FRAG2")

echo "$SUMMARY_OUTPUT" | grep -v "^EADS_"

EADS_KCAL=$(echo "$SUMMARY_OUTPUT" | grep "^EADS_KCAL=" | cut -d= -f2)
EADS_KJ=$(echo "$SUMMARY_OUTPUT" | grep "^EADS_KJ=" | cut -d= -f2)
EADS_EV=$(echo "$SUMMARY_OUTPUT" | grep "^EADS_EV=" | cut -d= -f2)

###############################################################################
# 5) Three-view rendering with adsorption energy annotation
###############################################################################
echo ""
echo "[*] ===== Step 5: Three-View Rendering ====="

render_molecule_with_eads "$(realpath "$OPT_XYZ")" "$OUTPUT_DIR" \
                          "$EADS_KCAL" "$EADS_KJ" "$EADS_EV"

###############################################################################
# 6) Adsorption energy bar chart
###############################################################################
echo ""
echo "[*] ===== Step 6: Adsorption Energy Diagram ====="

python3 - "$OUTPUT_DIR/energy_diagram.png" "$E_COMPLEX" "$E_FRAG1" "$E_FRAG2" \
         "$HA_TO_KCAL" "$HA_TO_KJ" <<'PYPLOT'
import sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

out_png    = sys.argv[1]
E_complex  = float(sys.argv[2])
E_frag1    = float(sys.argv[3])
E_frag2    = float(sys.argv[4])
HA2KCAL    = float(sys.argv[5])
HA2KJ      = float(sys.argv[6])

E_sum_frag = E_frag1 + E_frag2
E_ads_kcal = (E_complex - E_sum_frag) * HA2KCAL
E_ads_kj   = (E_complex - E_sum_frag) * HA2KJ

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

fig, ax = plt.subplots(figsize=(10, 7), dpi=300)

x_frag, x_complex = 1.5, 4.5
lw_level = 0.6

COL_FRAG = '#2244AA'
COL_COMPLEX = '#228B22'
COL_ARROW = '#CC3333'

ax.plot([x_frag - lw_level, x_frag + lw_level], [0, 0],
        color=COL_FRAG, lw=5.0, solid_capstyle='round', zorder=5)

ax.plot([x_complex - lw_level, x_complex + lw_level],
        [E_ads_kcal, E_ads_kcal],
        color=COL_COMPLEX, lw=5.0, solid_capstyle='round', zorder=5)

import numpy as np
t = np.linspace(0, 1, 200)
x_curve = x_frag + (x_complex - x_frag) * t
y_curve = E_ads_kcal * t**2
ax.plot(x_curve, y_curve, '--', color='#888888', lw=1.8, alpha=0.6, zorder=2)

ax.text(x_frag, 0.04 * max(abs(E_ads_kcal), 5) + 1.0,
        'Frag.1 + Frag.2\n(separated)',
        ha='center', fontsize=16, fontweight='bold', color=COL_FRAG)

ax.text(x_complex, E_ads_kcal + (0.04 if E_ads_kcal >= 0 else -0.06) * max(abs(E_ads_kcal), 5) + (1.0 if E_ads_kcal >= 0 else -2.0),
        'Complex\n(adsorbed)',
        ha='center', fontsize=16, fontweight='bold', color=COL_COMPLEX)

arr_x = 3.0
ax.annotate('', xy=(arr_x, E_ads_kcal), xytext=(arr_x, 0),
            arrowprops=dict(arrowstyle='<->', color=COL_ARROW, lw=2.5,
                           shrinkA=2, shrinkB=2))
mid_y = E_ads_kcal * 0.5
ax.text(arr_x - 0.15, mid_y,
        f'$E_{{ads}}$ = {E_ads_kcal:.1f}\nkcal/mol\n({E_ads_kj:.1f} kJ/mol)',
        ha='right', va='center', fontsize=14, fontweight='bold', color=COL_ARROW,
        bbox=dict(boxstyle='round,pad=0.2', fc='white', ec='none', alpha=0.85))

e_pad = max(5, abs(E_ads_kcal) * 0.3)
y_lo = min(0, E_ads_kcal) - e_pad
y_hi = max(0, E_ads_kcal) + e_pad
ax.set_ylim(y_lo, y_hi)
ax.set_xlim(0.0, 6.0)

ax.set_ylabel('Relative energy (kcal/mol)', fontsize=22, fontweight='bold')
ax.set_xlabel('', fontsize=1)
ax.set_xticks([])
ax.tick_params(axis='y', labelsize=18)
ax.tick_params(axis='both', width=2.0, length=6)
for spine in ax.spines.values():
    spine.set_linewidth(2.0)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['bottom'].set_visible(False)

ax.set_title('Adsorption Energy Diagram', fontsize=28, fontweight='bold', pad=18)
ax.axhline(y=0, color='#CCCCCC', lw=0.8, ls=':', zorder=1)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  Energy diagram: {out_png}")
PYPLOT

###############################################################################
# Summary
###############################################################################
echo ""
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION -- Adsorption Energy Analysis Complete"
echo "========================================"
echo "  Output directory: $PWD/$OUTPUT_DIR/"
echo ""
echo "  Entirety (complex):  $OUTPUT_DIR/entirety/"
echo "  Fragment 1:          $OUTPUT_DIR/frag1/"
echo "  Fragment 2:          $OUTPUT_DIR/frag2/"
echo ""
echo "  E(complex) = $E_COMPLEX Eh"
echo "  E(frag1)   = $E_FRAG1 Eh"
echo "  E(frag2)   = $E_FRAG2 Eh"
echo ""
echo "  Adsorption Energy:"
echo "    E_ads = $EADS_KCAL kcal/mol"
echo "    E_ads = $EADS_KJ kJ/mol"
echo "    E_ads = $EADS_EV eV"
echo ""
[[ -f "$OUTPUT_DIR/energy_summary.txt" ]]   && echo "  Energy summary:   energy_summary.txt"
[[ -f "$OUTPUT_DIR/energy_data.csv" ]]      && echo "  Energy data:      energy_data.csv"
[[ -f "$OUTPUT_DIR/energy_diagram.png" ]]   && echo "  Energy diagram:   energy_diagram.png"
[[ -f "$OUTPUT_DIR/molecule_front.png" ]]   && echo "  Three-view:       molecule_{front,side,top}.png"
echo "========================================"
