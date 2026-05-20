#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-opt  (Geometry Optimization)
#
#  Version:    1.6.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-04-04
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Standalone geometry optimization module. Three calculation modes:
#      Mode 1: Direct publication-quality optimization (optimization/ with no subfolders)
#      Mode 2: Two-step: low_opt/ (simple) -> optimization/ (publication quality)
#      Mode 3: Single-point only at publication quality (optimization/, creates ATTENTION_single_point)
#
#  Output: optimization/
#    Mode 1: optimization/opt.inp, opt.out, opt.xyz
#    Mode 2: optimization/low_opt/opt.*, then optimization/opt.*
#    Mode 3: optimization/opt.xyz (copy of input), optimization/sp.*, ATTENTION_single_point
#    Always (on success): optimization/iqcap_orca.env — ORCA baseline for downstream modules
#
#  Theory presets: --method 0..4 (default 1) set PBE / PBE0 / B3LYP / M06-2X / ωB97X-D3 families;
#  override any piece with --opt-low / --opt-pub / --sp-level after --method on the command line.
#
#  External dependencies: ORCA, orca_2aim, orca_2mkl (for molden/wfn for downstream reuse)
#
#  Usage:
#    bash iqcap-opt.sh --mode 1|2|3 [options]
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-opt"
IQCAP_VERSION="1.6.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration
###############################################################################
ORCA_BIN=""
ORCA_2AIM_BIN=""
ORCA_2MKL_BIN=""
XYZ_FILE="0.xyz"
NPROCS=16
MAXCORE=4096
OUTPUT_DIR="optimization"

# Mode: 1=direct pub opt, 2=low+pub opt, 3=single-point only
MODE=1

# Method preset (0–4). Fills OPT_LEVEL_* / SP_LEVEL unless overridden by --opt-low / --opt-pub / --sp-level.
METHOD=1

# Filled by apply_method_preset (after CLI); empty until then
OPT_LEVEL_LOW=""
OPT_LEVEL_PUB=""
SP_LEVEL=""

N_CHARGE=0
N_MULT=1

###############################################################################
# CLI
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --xyz)        XYZ_FILE="$2";     shift 2 ;;
    --mode)       MODE="$2";        shift 2 ;;
    --method)     METHOD="$2";      shift 2 ;;
    --output-dir) OUTPUT_DIR="$2";  shift 2 ;;
    --nprocs)     NPROCS="$2";      shift 2 ;;
    --maxcore)    MAXCORE="$2";     shift 2 ;;
    --n-charge)   N_CHARGE="$2";    shift 2 ;;
    --n-mult)     N_MULT="$2";      shift 2 ;;
    --opt-low)    OPT_LEVEL_LOW="$2";  shift 2 ;;
    --opt-pub)    OPT_LEVEL_PUB="$2";  shift 2 ;;
    --sp-level)   SP_LEVEL="$2";    shift 2 ;;
    --orca-bin)   ORCA_BIN="$2";    shift 2 ;;
    --orca-2aim-bin) ORCA_2AIM_BIN="$2"; shift 2 ;;
    --orca-2mkl-bin) ORCA_2MKL_BIN="$2"; shift 2 ;;
    -V|--version)
      echo "$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME"
      echo "Module: $IQCAP_MODULE (Geometry Optimization)"
      echo "Author: $IQCAP_AUTHOR"
      echo "Copyright: $IQCAP_COPYRIGHT"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME
Module: $IQCAP_MODULE (Geometry Optimization)

Usage: bash iqcap-opt.sh --mode 1|2|3 [options]

  --mode INT           Calculation mode (required):
                        1 = Direct publication-quality optimization (no subfolders)
                        2 = Two-step: low_opt/ (simple) -> optimization/ (pub)
                        3 = Single-point only (creates ATTENTION_single_point)

  --method INT         Theory preset (default: 1). Sets --opt-low / --opt-pub / --sp-level unless you override those later on the command line:
                        0 = PBE D3BJ def2-SVP def2/J opt (quick)
                        1 = PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt
                        2 = B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX opt
                        3 = M06-2X def2-TZVP(-f) def2/J RIJCOSX opt
                        4 = ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX opt
                       Mode 2 uses a def2-SVP low step for methods 1–4; if low == pub (method 0), only one optimization is run.
                       Writes optimization/iqcap_orca.env so iqcap-basic_elect_analysis, iqcap-elect_interaction, iqcap-G, and iqcap-adsorption_energy default to the same ORCA baseline.

  --xyz FILE           Input XYZ (default: 0.xyz)
  --output-dir DIR     Output folder (default: optimization)
  --nprocs INT         Parallel processes (default: 16)
  --maxcore INT        Memory per process in MB (default: 4096)
  --n-charge INT       Charge (default: 0)
  --n-mult INT         Multiplicity (default: 1)
  --opt-low STR        Low optimization level (mode 2; default from --method)
  --opt-pub STR        Publication optimization level (default from --method)
  --sp-level STR       Single-point level for mode 3 (default: <opt-pub base> tightSCF)
  --orca-bin PATH      ORCA executable path
  --orca-2aim-bin PATH orca_2aim path (for wfn, enables downstream reuse)
  --orca-2mkl-bin PATH orca_2mkl path (for molden, enables downstream reuse)

Output structure:
  Mode 1: optimization/opt.inp, opt.out, opt.xyz
  Mode 2: optimization/low_opt/opt.*, then optimization/opt.*
  Mode 3: optimization/opt.xyz (input copy), optimization/sp.*, ATTENTION_single_point

opt.xyz is also written to project root for downstream iqcap-basic_elect_analysis.sh

When orca_2aim and orca_2mkl are available, TZVP.molden.input and TZVP.wfn are
generated in optimization/ for reuse by iqcap-basic_elect_analysis (avoids redundant SP).
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

###############################################################################
# Helpers
###############################################################################
apply_method_preset() {
  local pub_def="" low_def=""
  case "$METHOD" in
    0)
      pub_def="PBE D3BJ def2-SVP def2/J opt"
      low_def="$pub_def"
      ;;
    1)
      pub_def="PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
      low_def="PBE0 D3BJ def2-SVP def2/J RIJCOSX opt"
      ;;
    2)
      pub_def="B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
      low_def="B3LYP D3BJ def2-SVP def2/J RIJCOSX opt"
      ;;
    3)
      pub_def="M06-2X def2-TZVP(-f) def2/J RIJCOSX opt"
      low_def="M06-2X def2-SVP def2/J RIJCOSX opt"
      ;;
    4)
      pub_def="ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX opt"
      low_def="ωB97X-D3 def2-SVP def2/J RIJCOSX opt"
      ;;
    *)
      echo "Invalid --method: $METHOD (expected 0, 1, 2, 3, or 4)" >&2
      exit 1
      ;;
  esac
  [[ -z "$OPT_LEVEL_PUB" ]] && OPT_LEVEL_PUB="$pub_def"
  [[ -z "$OPT_LEVEL_LOW" ]] && OPT_LEVEL_LOW="$low_def"
  [[ -z "$SP_LEVEL" ]] && SP_LEVEL="${OPT_LEVEL_PUB% opt} tightSCF"
}

write_iqcap_orca_env() {
  local base="${OPT_LEVEL_PUB% opt}"
  mkdir -p "$OUTPUT_DIR"
  {
    echo "# Written by iqcap-opt.sh — sourced by other IQCAP modules for matching ORCA theory."
    echo "IQCAP_METHOD=$METHOD"
    printf 'IQCAP_ORCA_BASE=%q\n' "$base"
  } > "$OUTPUT_DIR/iqcap_orca.env"
}

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

# Generate TZVP.molden.input and TZVP.wfn in optimization/ for downstream reuse
gen_molden_wfn_for_reuse() {
  local orca_prefix="$1"
  [[ "$MAY_REUSE" -eq 0 ]] && return 0
  [[ -f "$OUTPUT_DIR/${orca_prefix}.gbw" ]] || return 0
  pushd "$OUTPUT_DIR" >/dev/null
  "$ORCA_2AIM_EXE" "$orca_prefix" 2>/dev/null || true
  "$ORCA_2MKL_EXE" "$orca_prefix" -emolden 2>/dev/null || true
  if [[ -f "${orca_prefix}.molden.input" ]]; then
    cp "${orca_prefix}.molden.input" TZVP.molden.input
    echo "  TZVP.molden.input generated (for downstream reuse)"
  fi
  if [[ -f "${orca_prefix}.wfn" ]]; then
    cp "${orca_prefix}.wfn" TZVP.wfn
    echo "  TZVP.wfn generated (for downstream reuse)"
  fi
  popd >/dev/null
}

apply_method_preset

###############################################################################
# Pre-checks
###############################################################################
[[ "$MODE" =~ ^[123]$ ]] || { echo "Invalid --mode. Use 1, 2, or 3." >&2; exit 1; }
[[ -f "$XYZ_FILE" ]] || { echo "XYZ file not found: $XYZ_FILE" >&2; exit 1; }

ORCA_EXE="$(resolve_bin_any "$ORCA_BIN" "orca")" || { echo "Cannot find ORCA executable" >&2; exit 1; }
ORCA_2AIM_EXE="$(resolve_bin_any "$ORCA_2AIM_BIN" "orca_2aim")" || true
ORCA_2MKL_EXE="$(resolve_bin_any "$ORCA_2MKL_BIN" "orca_2mkl")" || true
MAY_REUSE=$([[ -n "$ORCA_2AIM_EXE" && -n "$ORCA_2MKL_EXE" ]] && echo 1 || echo 0)

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " Module: $IQCAP_MODULE"
echo "========================================"
echo "  Mode:    $MODE"
echo "  Method:  $METHOD  (opt-pub: $OPT_LEVEL_PUB)"
echo "  ORCA:    $ORCA_EXE"
[[ "$MAY_REUSE" -eq 1 ]] && echo "  orca_2aim / orca_2mkl: enabled (downstream reuse)"
echo "  Output:  $PWD/$OUTPUT_DIR/"
echo "========================================"

###############################################################################
# Mode 1: Direct publication-quality optimization
###############################################################################
if [[ "$MODE" -eq 1 ]]; then
  echo "[*] Mode 1: Direct publication-quality optimization"
  pushd "$OUTPUT_DIR" >/dev/null
  write_orca_input "opt.inp" "$OPT_LEVEL_PUB" "$N_CHARGE" "$N_MULT" "../$XYZ_FILE"
  "$ORCA_EXE" opt.inp > opt.out
  popd >/dev/null

  if [[ -f "$OUTPUT_DIR/opt.xyz" ]]; then
    if check_orca_success "$OUTPUT_DIR/opt.out"; then
      cp "$OUTPUT_DIR/opt.xyz" opt.xyz
      echo "  opt.xyz -> $OUTPUT_DIR/opt.xyz and ./opt.xyz"
    else
      echo "WARNING: Optimization may not have converged. Check $OUTPUT_DIR/opt.out" >&2
      cp "$OUTPUT_DIR/opt.xyz" opt.xyz 2>/dev/null || true
    fi
    gen_molden_wfn_for_reuse "opt"
    write_iqcap_orca_env
  else
    echo "ERROR: opt.xyz not generated" >&2
    exit 1
  fi
fi

###############################################################################
# Mode 2: Low opt -> Publication opt
###############################################################################
if [[ "$MODE" -eq 2 ]]; then
  echo "[*] Mode 2: Two-step optimization"
  LOW_DIR="$OUTPUT_DIR/low_opt"
  mkdir -p "$LOW_DIR"

  echo "  Step 1: Low-level optimization in $LOW_DIR/"
  pushd "$LOW_DIR" >/dev/null
  write_orca_input "opt.inp" "$OPT_LEVEL_LOW" "$N_CHARGE" "$N_MULT" "../../$XYZ_FILE"
  "$ORCA_EXE" opt.inp > opt.out
  popd >/dev/null

  if [[ ! -f "$LOW_DIR/opt.xyz" ]]; then
    echo "ERROR: Low optimization failed, opt.xyz not generated" >&2
    exit 1
  fi

  if [[ "$OPT_LEVEL_LOW" == "$OPT_LEVEL_PUB" ]]; then
    echo "  Low and pub ORCA levels are identical; skipping second optimization"
    cp -f "$LOW_DIR/opt.xyz" "$OUTPUT_DIR/opt.xyz"
    cp -f "$LOW_DIR/opt.inp" "$OUTPUT_DIR/opt.inp"
    cp -f "$LOW_DIR/opt.out" "$OUTPUT_DIR/opt.out"
    [[ -f "$LOW_DIR/opt.gbw" ]] && cp -f "$LOW_DIR/opt.gbw" "$OUTPUT_DIR/opt.gbw"
    [[ -f "$LOW_DIR/opt.property.txt" ]] && cp -f "$LOW_DIR/opt.property.txt" "$OUTPUT_DIR/opt.property.txt"
  else
    echo "  Step 2: Publication-quality optimization in $OUTPUT_DIR/"
    pushd "$OUTPUT_DIR" >/dev/null
    write_orca_input "opt.inp" "$OPT_LEVEL_PUB" "$N_CHARGE" "$N_MULT" "low_opt/opt.xyz"
    "$ORCA_EXE" opt.inp > opt.out
    popd >/dev/null
  fi

  if [[ -f "$OUTPUT_DIR/opt.xyz" ]]; then
    if check_orca_success "$OUTPUT_DIR/opt.out"; then
      cp "$OUTPUT_DIR/opt.xyz" opt.xyz
      echo "  opt.xyz -> $OUTPUT_DIR/opt.xyz and ./opt.xyz"
    else
      echo "WARNING: Pub optimization may not have converged." >&2
      cp "$OUTPUT_DIR/opt.xyz" opt.xyz 2>/dev/null || true
    fi
    gen_molden_wfn_for_reuse "opt"
    write_iqcap_orca_env
  else
    echo "ERROR: opt.xyz not generated" >&2
    exit 1
  fi
fi

###############################################################################
# Mode 3: Single-point only
###############################################################################
if [[ "$MODE" -eq 3 ]]; then
  echo "[*] Mode 3: Single-point only (no geometry optimization)"
  cp "$XYZ_FILE" "$OUTPUT_DIR/opt.xyz"
  cp "$XYZ_FILE" opt.xyz

  cat > "$OUTPUT_DIR/ATTENTION_single_point" <<'ATTN'
================================================================================
ATTENTION: Single-point calculation only - NO geometry optimization performed
================================================================================
This run used Mode 3 of iqcap-opt.sh. The structure (opt.xyz) is a direct copy
of the input XYZ file. No geometry optimization was carried out.
Use opt.xyz with caution for downstream analyses.
================================================================================
ATTN
  echo "  Created $OUTPUT_DIR/ATTENTION_single_point"

  pushd "$OUTPUT_DIR" >/dev/null
  write_orca_input "sp.inp" "$SP_LEVEL" "$N_CHARGE" "$N_MULT" "opt.xyz"
  echo "  Running single-point at publication level..."
  "$ORCA_EXE" sp.inp > sp.out
  popd >/dev/null
  gen_molden_wfn_for_reuse "sp"
  write_iqcap_orca_env
  echo "  opt.xyz -> $OUTPUT_DIR/opt.xyz and ./opt.xyz"
fi

echo ""
echo "========================================"
echo " iqcap-opt complete. Run iqcap-basic_elect_analysis.sh next."
echo "========================================"
