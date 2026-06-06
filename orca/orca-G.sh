#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-G  (Gibbs Free Energy via Frequency Analysis)
#
#  Version:    1.0.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-03-06
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Gibbs free energy module. Auto-detects optimized structure/wavefunction
#    files in current project, then performs ORCA frequency calculation and
#    extracts thermodynamic quantities (including Final Gibbs free energy).
#
#    Optional atom-constraint modes:
#      --fix  "1-3,8"   Fix these atoms, relax others (constrained pre-opt)
#      --free "1-3,8"   Relax these atoms, fix all others (constrained pre-opt)
#
#  Output:
#    G/
#      preopt.inp / preopt.out / preopt.xyz   (only when constraints are used)
#      freq.inp / freq.out
#      G_summary.txt
#
#  External dependencies: ORCA
#
#  Usage:
#    bash iqcap-G.sh [options]
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-G"
IQCAP_VERSION="1.0.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration
###############################################################################
ORCA_BIN=""

XYZ_FILE=""
GBW_FILE=""
OUTPUT_DIR="G"

NPROCS=16
MAXCORE=4096
CHARGE=0
MULT=1
TEMP_K=298.15

OPT_LEVEL=""
FREQ_LEVEL=""
OPT_LEVEL_CLI=0
FREQ_LEVEL_CLI=0

FIX_SPEC=""
FREE_SPEC=""

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
    --xyz)         XYZ_FILE="$2";      shift 2 ;;
    --gbw)         GBW_FILE="$2";      shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2";    shift 2 ;;
    --nprocs)      NPROCS="$2";        shift 2 ;;
    --maxcore)     MAXCORE="$2";       shift 2 ;;
    --charge)      CHARGE="$2";        shift 2 ;;
    --mult)        MULT="$2";          shift 2 ;;
    --temp)        TEMP_K="$2";        shift 2 ;;
    --opt-level)   OPT_LEVEL="$2"; OPT_LEVEL_CLI=1; shift 2 ;;
    --freq-level)  FREQ_LEVEL="$2"; FREQ_LEVEL_CLI=1; shift 2 ;;
    --fix)         FIX_SPEC="$2";      shift 2 ;;
    --free)        FREE_SPEC="$2";     shift 2 ;;
    --orca-bin)    ORCA_BIN="$2";      shift 2 ;;
    -V|--version)
      echo "$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME"
      echo "Module:    $IQCAP_MODULE (Gibbs Free Energy via Frequency Analysis)"
      echo "Author:    $IQCAP_AUTHOR"
      echo "Copyright: $IQCAP_COPYRIGHT"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME
Module: $IQCAP_MODULE (Gibbs Free Energy via Frequency Analysis)

Usage: bash iqcap-G.sh [options]

Input (auto-detected if omitted):
  --xyz FILE          Structure file (priority auto-detect: ./opt.xyz, optimization/opt.xyz, then *.xyz)
  --gbw FILE          Wavefunction file for MOREAD (auto-detected if omitted)

Charge / multiplicity:
  --charge INT        Molecular charge (default: 0)
  --mult INT          Spin multiplicity (default: 1)

Theory level:
  --opt-level STR     Constrained pre-optimization level (default: optimization/iqcap_orca.env or PBE0 D3BJ TZVP)
  --freq-level STR    Frequency level (default: same as --opt-level)
  --temp FLOAT        Temperature in K for thermochemistry (default: 298.15)

Atom constraints (mutually exclusive):
  --fix STR           Fix listed atoms, relax all others (e.g. "1-3,8,10")
  --free STR          Relax listed atoms, fix all others (e.g. "1-3,8,10")

Compute resources:
  --nprocs INT        Number of parallel processes (default: 16)
  --maxcore INT       Memory per process in MB (default: 4096)

Path overrides:
  --orca-bin PATH     ORCA executable path (or directory containing orca)

Output:
  --output-dir DIR    Output folder (default: G)

Info:
  -h, --help          Show this help message
  -V, --version       Show version information

Workflow:
  1) Auto-detect opt.xyz/opt.gbw (or user-provided files)
  2) If --fix/--free is provided: constrained pre-optimization (preopt.*)
  3) Frequency calculation (freq.*)
  4) Extract Gibbs free energy and write G_summary.txt
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$OPT_LEVEL_CLI" -eq 0 ]]; then
  if [[ -f "optimization/iqcap_orca.env" ]]; then
    # shellcheck disable=SC1090
    source "optimization/iqcap_orca.env"
    [[ -n "${IQCAP_ORCA_BASE:-}" ]] && OPT_LEVEL="$IQCAP_ORCA_BASE"
  fi
  [[ -z "$OPT_LEVEL" ]] && OPT_LEVEL="PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX"
fi
[[ "$FREQ_LEVEL_CLI" -eq 0 ]] && FREQ_LEVEL="$OPT_LEVEL"

###############################################################################
# Helpers: path resolution
###############################################################################
expand_path() {
  local p="$1"
  [[ "$p" == "~"* ]] && p="${HOME}${p:1}"
  echo "$p"
}

abspath() {
  local p
  p="$(expand_path "$1")"
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd)
  else
    (cd "$(dirname "$p")" && printf "%s/%s\n" "$(pwd)" "$(basename "$p")")
  fi
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
  local user_bin="$1"
  shift
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
# Helpers: input auto-detection
###############################################################################
auto_detect_xyz() {
  local xyz=""
  if [[ -n "$XYZ_FILE" ]]; then
    XYZ_FILE="$(expand_path "$XYZ_FILE")"
    [[ -f "$XYZ_FILE" ]] || { echo "XYZ file not found: $XYZ_FILE" >&2; return 1; }
    echo "$(abspath "$XYZ_FILE")"
    return 0
  fi

  local candidates=("opt.xyz" "optimization/opt.xyz")
  for xyz in "${candidates[@]}"; do
    if [[ -f "$xyz" ]]; then
      echo "$(abspath "$xyz")"
      return 0
    fi
  done

  shopt -s nullglob
  local cwd_xyz=( ./*.xyz )
  shopt -u nullglob
  if [[ "${#cwd_xyz[@]}" -gt 0 ]]; then
    echo "$(abspath "${cwd_xyz[0]}")"
    return 0
  fi

  xyz="$(find . -maxdepth 3 -type f -name '*.xyz' 2>/dev/null | sort | head -n1)"
  [[ -n "$xyz" ]] && { echo "$(abspath "$xyz")"; return 0; }

  echo "Cannot auto-detect any XYZ file. Please provide --xyz FILE" >&2
  return 1
}

auto_detect_gbw() {
  local xyz_abs="$1"
  local gbw=""

  if [[ -n "$GBW_FILE" ]]; then
    GBW_FILE="$(expand_path "$GBW_FILE")"
    [[ -f "$GBW_FILE" ]] || { echo "GBW file not found: $GBW_FILE" >&2; return 1; }
    echo "$(abspath "$GBW_FILE")"
    return 0
  fi

  local xyz_dir xyz_base
  xyz_dir="$(dirname "$xyz_abs")"
  xyz_base="$(basename "$xyz_abs" .xyz)"

  if [[ -f "$xyz_dir/$xyz_base.gbw" ]]; then
    echo "$(abspath "$xyz_dir/$xyz_base.gbw")"
    return 0
  fi

  if [[ -f "opt.gbw" ]]; then
    echo "$(abspath "opt.gbw")"
    return 0
  fi
  if [[ -f "optimization/opt.gbw" ]]; then
    echo "$(abspath "optimization/opt.gbw")"
    return 0
  fi

  shopt -s nullglob
  local gbws_in_xyz_dir=( "$xyz_dir"/*.gbw )
  shopt -u nullglob
  if [[ "${#gbws_in_xyz_dir[@]}" -gt 0 ]]; then
    echo "$(abspath "${gbws_in_xyz_dir[0]}")"
    return 0
  fi

  gbw="$(find . -maxdepth 3 -type f -name '*.gbw' 2>/dev/null | sort | head -n1)"
  [[ -n "$gbw" ]] && { echo "$(abspath "$gbw")"; return 0; }

  return 1
}

###############################################################################
# Helpers: constraints
###############################################################################
build_fixed_zero_based() {
  local xyz_file="$1" mode="$2" spec="$3"
  python3 - "$xyz_file" "$mode" "$spec" <<'PYFIX'
import re
import sys

xyz_file, mode, spec = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(xyz_file, 'r', encoding='utf-8', errors='ignore') as f:
        line1 = f.readline().strip()
    natoms = int(line1)
except Exception:
    print("Failed to read atom count from XYZ", file=sys.stderr)
    sys.exit(2)

def parse_spec(s):
    out = []
    for part in re.split(r'[,\s]+', s.strip()):
        if not part:
            continue
        if '-' in part:
            a, b = part.split('-', 1)
            a = int(a)
            b = int(b)
            if a <= b:
                out.extend(range(a, b + 1))
            else:
                out.extend(range(a, b - 1, -1))
        else:
            out.append(int(part))
    return sorted(set(out))

selected = parse_spec(spec)
if not selected:
    print("Empty atom selection", file=sys.stderr)
    sys.exit(3)

for i in selected:
    if i < 1 or i > natoms:
        print(f"Atom index out of range: {i} (valid: 1..{natoms})", file=sys.stderr)
        sys.exit(4)

if mode == 'fix':
    fixed = selected
elif mode == 'free':
    selected_set = set(selected)
    fixed = [i for i in range(1, natoms + 1) if i not in selected_set]
else:
    print(f"Unknown mode: {mode}", file=sys.stderr)
    sys.exit(5)

fixed_zero = [str(i - 1) for i in fixed]
print(' '.join(fixed_zero))
PYFIX
}

make_constraints_block() {
  local fixed_zero_list="$1"
  [[ -z "$fixed_zero_list" ]] && return 0

  echo "%geom"
  echo "  Constraints"
  local idx
  for idx in $fixed_zero_list; do
    echo "    { C $idx C }"
  done
  echo "  end"
  echo "end"
}

###############################################################################
# Helpers: ORCA input/output
###############################################################################
write_orca_opt_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" xyz_source="$5" moinp="$6" constraints_block="$7"

  {
    echo "! $level opt"
    if [[ -n "$moinp" ]]; then
      echo "! MOREAD"
    fi
    echo "%maxcore  $MAXCORE"
    echo "%pal nprocs   $NPROCS end"
    if [[ -n "$moinp" ]]; then
      echo "%moinp \"$moinp\""
    fi
    if [[ -n "$constraints_block" ]]; then
      printf "%s\n" "$constraints_block"
    fi
    echo "* xyz   $charge   $mult"
    awk 'NR>2 {print $0}' "$xyz_source"
    echo " *"
  } > "$inp_file"
}

write_orca_freq_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" xyz_source="$5" moinp="$6" temp_k="$7"

  {
    echo "! $level freq"
    if [[ -n "$moinp" ]]; then
      echo "! MOREAD"
    fi
    echo "%maxcore  $MAXCORE"
    echo "%pal nprocs   $NPROCS end"
    if [[ -n "$moinp" ]]; then
      echo "%moinp \"$moinp\""
    fi
    echo "%freq"
    echo "  Temp $temp_k"
    echo "end"
    echo "* xyz   $charge   $mult"
    awk 'NR>2 {print $0}' "$xyz_source"
    echo " *"
  } > "$inp_file"
}

check_orca_normal() {
  local out_file="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -q "ORCA TERMINATED NORMALLY" "$out_file" 2>/dev/null
  else
    grep -q "ORCA TERMINATED NORMALLY" "$out_file" 2>/dev/null
  fi
}

check_opt_converged() {
  local out_file="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -q "THE OPTIMIZATION HAS CONVERGED|OPTIMIZATION RUN DONE" "$out_file" 2>/dev/null
  else
    grep -Eq "THE OPTIMIZATION HAS CONVERGED|OPTIMIZATION RUN DONE" "$out_file" 2>/dev/null
  fi
}

###############################################################################
# Validation
###############################################################################
if [[ -n "$FIX_SPEC" && -n "$FREE_SPEC" ]]; then
  echo "--fix and --free are mutually exclusive. Choose one." >&2
  exit 1
fi

ORCA_EXE="$(resolve_bin_any "$ORCA_BIN" "orca")" || {
  echo "Cannot find ORCA executable. Use --orca-bin PATH" >&2
  exit 1
}

XYZ_ABS="$(auto_detect_xyz)"
GBW_ABS="$(auto_detect_gbw "$XYZ_ABS" || true)"

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(abspath "$OUTPUT_DIR")"

###############################################################################
# Banner
###############################################################################
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " Module: $IQCAP_MODULE"
echo "========================================"
echo "  ORCA:      $ORCA_EXE"
echo "  XYZ:       $XYZ_ABS"
if [[ -n "$GBW_ABS" ]]; then
  echo "  GBW:       $GBW_ABS"
else
  echo "  GBW:       (not found, continue without MOREAD)"
fi
echo "  Charge:    $CHARGE"
echo "  Mult:      $MULT"
echo "  Temp (K):  $TEMP_K"
echo "  Output:    $OUTPUT_DIR"
echo "========================================"

###############################################################################
# Step 1: optional constrained pre-optimization
###############################################################################
WORK_XYZ="$XYZ_ABS"
WORK_GBW="$GBW_ABS"

if [[ -n "$FIX_SPEC" || -n "$FREE_SPEC" ]]; then
  MODE="fix"
  SPEC="$FIX_SPEC"
  if [[ -n "$FREE_SPEC" ]]; then
    MODE="free"
    SPEC="$FREE_SPEC"
  fi

  FIXED_ZERO="$(build_fixed_zero_based "$XYZ_ABS" "$MODE" "$SPEC")"
  CONSTRAINTS_BLOCK="$(make_constraints_block "$FIXED_ZERO")"

  if [[ -z "$FIXED_ZERO" ]]; then
    echo "[*] Constraint mode requested, but no atoms need to be fixed after expansion."
    echo "    Skip constrained pre-optimization and run direct frequency."
  else
    echo "[*] Running constrained pre-optimization ($MODE: $SPEC)"
    PREOPT_INP="$OUTPUT_DIR/preopt.inp"
    PREOPT_OUT="$OUTPUT_DIR/preopt.out"

    write_orca_opt_input "$PREOPT_INP" "$OPT_LEVEL" "$CHARGE" "$MULT" "$XYZ_ABS" "$WORK_GBW" "$CONSTRAINTS_BLOCK"

    pushd "$OUTPUT_DIR" >/dev/null
    "$ORCA_EXE" preopt.inp > preopt.out
    popd >/dev/null

    check_orca_normal "$PREOPT_OUT" || {
      echo "Constrained pre-optimization did not terminate normally. Check: $PREOPT_OUT" >&2
      exit 1
    }
    check_opt_converged "$PREOPT_OUT" || {
      echo "Constrained pre-optimization did not converge. Check: $PREOPT_OUT" >&2
      exit 1
    }

    if [[ -f "$OUTPUT_DIR/preopt.xyz" ]]; then
      WORK_XYZ="$OUTPUT_DIR/preopt.xyz"
    else
      echo "Cannot find preopt.xyz after constrained optimization." >&2
      exit 1
    fi
    if [[ -f "$OUTPUT_DIR/preopt.gbw" ]]; then
      WORK_GBW="$OUTPUT_DIR/preopt.gbw"
    fi
  fi
fi

###############################################################################
# Step 2: frequency calculation
###############################################################################
echo "[*] Running frequency calculation for thermochemistry"

FREQ_INP="$OUTPUT_DIR/freq.inp"
FREQ_OUT="$OUTPUT_DIR/freq.out"

write_orca_freq_input "$FREQ_INP" "$FREQ_LEVEL" "$CHARGE" "$MULT" "$WORK_XYZ" "$WORK_GBW" "$TEMP_K"

pushd "$OUTPUT_DIR" >/dev/null
"$ORCA_EXE" freq.inp > freq.out
popd >/dev/null

check_orca_normal "$FREQ_OUT" || {
  echo "Frequency run did not terminate normally. Check: $FREQ_OUT" >&2
  exit 1
}

# Keep a clear copy of the geometry actually used for thermochemistry.
cp "$WORK_XYZ" "$OUTPUT_DIR/opt.xyz"

###############################################################################
# Step 3: extract thermochemistry summary
###############################################################################
SUMMARY_FILE="$OUTPUT_DIR/G_summary.txt"

python3 - "$FREQ_OUT" "$SUMMARY_FILE" "$TEMP_K" "$HA_TO_EV" "$HA_TO_KCAL" "$HA_TO_KJ" <<'PYTHERMO'
import re
import sys

out_file, summary_file, temp_k, ha_to_ev, ha_to_kcal, ha_to_kj = sys.argv[1:7]
temp_k = float(temp_k)
ha_to_ev = float(ha_to_ev)
ha_to_kcal = float(ha_to_kcal)
ha_to_kj = float(ha_to_kj)

txt = open(out_file, 'r', encoding='utf-8', errors='ignore').read()

def pick(patterns):
    for p in patterns:
        m = list(re.finditer(p, txt, flags=re.IGNORECASE))
        if m:
            try:
                return float(m[-1].group(1))
            except Exception:
                pass
    return None

e_sp = pick([r'FINAL\s+SINGLE\s+POINT\s+ENERGY\s+([-+]?\d+\.\d+(?:[Ee][-+]?\d+)?)'])
zpe = pick([r'Zero\s+point\s+energy\s*\.\.\.\s*([-+]?\d+\.\d+(?:[Ee][-+]?\d+)?)'])
eth = pick([r'Total\s+thermal\s+energy\s*\.\.\.\s*([-+]?\d+\.\d+(?:[Ee][-+]?\d+)?)'])
h = pick([r'Total\s+enthalpy\s*\.\.\.\s*([-+]?\d+\.\d+(?:[Ee][-+]?\d+)?)'])
g = pick([
    r'Final\s+Gibbs\s+free\s+energy\s*\.\.\.\s*([-+]?\d+\.\d+(?:[Ee][-+]?\d+)?)',
    r'Final\s+Gibbs\s+Free\s+Energy\s*\.\.\.\s*([-+]?\d+\.\d+(?:[Ee][-+]?\d+)?)',
])

def format_energy(label, value):
    if value is None:
        return f"{label:<28}: N/A"
    return (
        f"{label:<28}: {value: .12f} Eh"
        f"   ({value * ha_to_ev: .6f} eV, {value * ha_to_kcal: .6f} kcal/mol, {value * ha_to_kj: .6f} kJ/mol)"
    )

lines = [
    "========================================",
    " IQCAP Gibbs Free Energy Summary",
    "========================================",
    f"Temperature (K)               : {temp_k:.2f}",
    "",
    format_energy("Final single-point energy", e_sp),
    format_energy("Zero-point energy", zpe),
    format_energy("Total thermal energy", eth),
    format_energy("Total enthalpy", h),
    format_energy("Final Gibbs free energy", g),
    "",
    f"Source output                 : {out_file}",
    "========================================",
]

with open(summary_file, 'w', encoding='utf-8') as f:
    f.write("\n".join(lines) + "\n")

if g is None:
    print("WARNING: Final Gibbs free energy not found in ORCA output.")
    print(f"Summary written to: {summary_file}")
else:
    print(f"Final Gibbs free energy: {g:.12f} Eh")
    print(f"Summary written to: {summary_file}")
PYTHERMO

echo "[*] Done. Results in: $OUTPUT_DIR"
