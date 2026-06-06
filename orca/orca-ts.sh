#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-ts  (Transition State & Reaction Path Analysis Engine)
#
#  Version:    1.5.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-04-04
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Transition state and reaction path analysis module of IQCAP.
#    Automates the complete workflow from reactant/product structures
#    to transition state search, verification, IRC path tracing, and
#    publication-quality energy profile visualization.
#
#    Pipeline:
#      1. Endpoint geometry optimization (optional, skippable)
#      2. NEB-CI (or NEB-TS) path search for TS guess
#      3. OptTS + NumFreq for TS optimization and verification
#      4. IRC in both directions for reaction path confirmation
#      5. Single-point energy refinement (optionally at a higher level)
#      6. Energy summary in Hartree / eV / kcal·mol⁻¹ / kJ·mol⁻¹
#      7. Publication-quality energy profile and IRC path plots
#      8. VMD three-view rendering of the TS structure
#
#  Disclaimer:
#    This software is a workflow orchestration and analysis platform.
#    It does NOT include the third-party programs themselves (ORCA,
#    Multiwfn, VMD). Users must obtain and install those programs
#    independently under their respective licenses.
#
#  External dependencies (must be pre-installed):
#    ORCA          -  Quantum chemistry engine (orca)
#    VMD           -  Molecular visualization (TachyonInternal renderer)
#    Python 3      -  With packages: numpy, Pillow, matplotlib
#
#  Theory presets: --method 0..4 (default 1), same families as iqcap-opt.sh;
#  override with --opt-level / --opt-pub / --sp-level after --method on the CLI.
#
#  Usage:
#    bash iqcap-ts.sh [options]
#    bash iqcap-ts.sh --help
#    bash iqcap-ts.sh --version
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-ts"
IQCAP_VERSION="1.5.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration
###############################################################################
ORCA_BIN=""
VMD_BIN=""

REACTANT_XYZ="reactant.xyz"
PRODUCT_XYZ="product.xyz"
TS_GUESS_XYZ=""

CHARGE=0
MULT=1
NPROCS=16
MAXCORE=4096
FREE_ATOMS=""

# ============================================================================
# Optimization Level (OPT_LEVEL) - Transition State Search
# ============================================================================
# Default from --method (default 1 = PBE0 … RIJCOSX), same publication string as
# iqcap-opt.sh --opt-pub (without trailing " opt"; this script adds " opt" where needed).
# Legacy: --mode sets --method (1→0, 2→2, 3→1).
#
# Algorithm accuracy and system-specific recommendations for TS optimization:
#
# 【有机反应/主族元素 (Organic Reactions/Main Group)】
#   粗算 (Quick):     "PBE D3BJ def2-SVP def2/J opt"
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#   高精度 (High):    "M06-2X def2-TZVP(-f) def2/J RIJCOSX opt"
#                     或 "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX opt"
#
# 【金属配合物反应 (Metal Complex Reactions)】
#   粗算 (Quick):     "PBE D3BJ def2-SVP def2/J opt"
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#   高精度 (High):    "TPSSh D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#
# 【过渡金属催化 (Transition Metal Catalysis)】
#   粗算 (Quick):     "PBE D3BJ def2-SVP def2/J opt"
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#   高精度 (High):    "TPSSh D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#
# 【含色散相互作用 (Dispersion Interactions)】
#   粗算 (Quick):     "PBE D3BJ def2-SVP def2/J opt"
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#   高精度 (High):    "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX opt"
#                     或 "M06-2X def2-TZVP(-f) def2/J RIJCOSX opt"
#
# 【自由基反应 (Radical Reactions)】
#   粗算 (Quick):     "UPBE D3BJ def2-SVP def2/J opt"
#   论文级别 (Pub):   "UPBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
#   高精度 (High):    "UM06-2X def2-TZVP(-f) def2/J RIJCOSX opt"
#                     或 "UωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX opt"
#
# 说明 (Notes):
#   - PBE/PBE0: 对过渡态搜索更稳定，推荐用于粗算和论文级别
#   - opt: 几何优化关键词 (geometry optimization keyword)
#   - 过渡态搜索建议先用较小基组快速定位，再用大基组精修
#   - 对于NEB方法，粗算基组通常足够
# ============================================================================
# Method preset (0–4). Fills OPT_LEVEL unless set by --opt-level / --opt-pub.
METHOD=1
# Filled by apply_ts_method_preset after CLI
OPT_LEVEL=""

# ============================================================================
# Single-Point Refinement Level (SP_REFINE_LEVEL)
# ============================================================================
# Algorithm accuracy for single-point energy refinement after TS optimization:
#
# 【有机反应/主族元素 (Organic Reactions/Main Group)】
#   粗算 (Quick):     使用OPT_LEVEL + tightSCF (默认)
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "M06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【金属配合物反应 (Metal Complex Reactions)】
#   粗算 (Quick):     使用OPT_LEVEL + tightSCF (默认)
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "TPSSh D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【过渡金属催化 (Transition Metal Catalysis)】
#   粗算 (Quick):     使用OPT_LEVEL + tightSCF (默认)
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "TPSSh D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【含色散相互作用 (Dispersion Interactions)】
#   粗算 (Quick):     使用OPT_LEVEL + tightSCF (默认)
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "M06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【自由基反应 (Radical Reactions)】
#   粗算 (Quick):     使用OPT_LEVEL + tightSCF (默认)
#   论文级别 (Pub):   "UPBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "UM06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "UωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 说明 (Notes):
#   - 如果为空，将使用 OPT_LEVEL + tightSCF
#   - 建议使用比优化更大的基组以获得更准确的能垒
#   - tightSCF: 严格SCF收敛 (tight SCF convergence)
# ============================================================================
SP_REFINE_LEVEL=""

# NEB parameters
NEB_METHOD="NEB-CI"
NEB_NIMAGES=8
NEB_MAXITER=500

# IRC parameters
IRC_MAXITER=50
IRC_STEPSIZE=0.3
IRC_MAXDISP=0.5

# Module switches
RUN_OPT_ENDPOINTS=1
RUN_NEB=1
RUN_OPTTS=1
RUN_FREQ=1
RUN_IRC=1
RUN_SP_REFINE=1
RUN_EPROFILE=1
RUN_IRC_PLOT=1
RUN_TS_RENDER=1
RUN_TS_PANEL=1
RUN_MODE_PROJ=1
RUN_IRC_COORDS=1
RUN_NEB_CONV=1
RUN_IRC_ANIM=1
RUN_TS_TRAJ_OVERLAY=1
RUN_CINEB_IMAGE_PLOT=1
RUN_CINEB_OVERLAY=1
MONITOR_BONDS=""
PLOT_ONLY=0
ELEMENT_COLOR_OVERRIDES=()

# Visualization parameters
MOL_ZOOM=1.00

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
    --reactant)         REACTANT_XYZ="$2";    shift 2 ;;
    --product)          PRODUCT_XYZ="$2";     shift 2 ;;
    --ts-guess)         TS_GUESS_XYZ="$2";    shift 2 ;;
    --charge)           CHARGE="$2";          shift 2 ;;
    --mult)             MULT="$2";            shift 2 ;;
    --nprocs)           NPROCS="$2";          shift 2 ;;
    --maxcore)          MAXCORE="$2";         shift 2 ;;
    --method)           METHOD="$2";          shift 2 ;;
    --mode)
      case "$2" in
        1) METHOD=0 ;;
        2) METHOD=2 ;;
        3) METHOD=1 ;;
        *) echo "Invalid --mode value: $2 (expected 1, 2, or 3)" >&2; exit 1 ;;
      esac
      shift 2 ;;
    --opt-level|--opt-pub|--ts-level) OPT_LEVEL="$2"; shift 2 ;;
    --sp-level)         SP_REFINE_LEVEL="$2"; shift 2 ;;
    --free-atoms)       FREE_ATOMS="$2";      shift 2 ;;
    --neb-method)       NEB_METHOD="$2";      shift 2 ;;
    --neb-nimages)      NEB_NIMAGES="$2";     shift 2 ;;
    --neb-maxiter)      NEB_MAXITER="$2";     shift 2 ;;
    --irc-maxiter)      IRC_MAXITER="$2";     shift 2 ;;
    --irc-stepsize)     IRC_STEPSIZE="$2";    shift 2 ;;
    --irc-maxdisp)      IRC_MAXDISP="$2";     shift 2 ;;
    --mol-zoom)         MOL_ZOOM="$2";        shift 2 ;;
    --vmd-bin)          VMD_BIN="$2";         shift 2 ;;
    --skip-opt-endpoints|--no-endpoint-opt) RUN_OPT_ENDPOINTS=0; shift 1 ;;
    --no-neb)           RUN_NEB=0;            shift 1 ;;
    --no-optts)         RUN_OPTTS=0;          shift 1 ;;
    --no-freq)          RUN_FREQ=0;           shift 1 ;;
    --no-irc)           RUN_IRC=0;            shift 1 ;;
    --no-sp-refine)     RUN_SP_REFINE=0;      shift 1 ;;
    --no-eprofile)      RUN_EPROFILE=0;       shift 1 ;;
    --no-irc-plot)      RUN_IRC_PLOT=0;       shift 1 ;;
    --no-ts-render)     RUN_TS_RENDER=0;      shift 1 ;;
    --no-ts-panel)      RUN_TS_PANEL=0;       shift 1 ;;
    --no-mode-proj)     RUN_MODE_PROJ=0;      shift 1 ;;
    --no-irc-coords)    RUN_IRC_COORDS=0;     shift 1 ;;
    --no-neb-conv)      RUN_NEB_CONV=0;       shift 1 ;;
    --no-irc-anim)      RUN_IRC_ANIM=0;       shift 1 ;;
    --no-ts-trajectory-overlay) RUN_TS_TRAJ_OVERLAY=0; shift 1 ;;
    --no-cineb-image-plot) RUN_CINEB_IMAGE_PLOT=0; shift 1 ;;
    --no-cineb-overlay) RUN_CINEB_OVERLAY=0; shift 1 ;;
    --plot-only)          PLOT_ONLY=1;          shift 1 ;;
    --element-color)    ELEMENT_COLOR_OVERRIDES+=("$2"); shift 2 ;;
    --monitor-bonds)    MONITOR_BONDS="$2";   shift 2 ;;
    -V|--version)
      echo "$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME"
      echo "Module:    $IQCAP_MODULE (Transition State & Reaction Path Analysis Engine)"
      echo "Author:    $IQCAP_AUTHOR"
      echo "Copyright: $IQCAP_COPYRIGHT"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME
Module: $IQCAP_MODULE (Transition State & Reaction Path Analysis Engine)

Usage: bash iqcap-ts.sh [options]

Input structures:
  --reactant FILE       Reactant structure in XYZ format (default: reactant.xyz)
  --product FILE        Product structure in XYZ format (default: product.xyz)
  --ts-guess FILE       TS initial guess (skip NEB when provided)

Charge / multiplicity:
  --charge INT          Molecular charge (default: 0)
  --mult INT            Spin multiplicity (default: 1)

Compute resources:
  --nprocs INT          Number of parallel processes (default: 16)
  --maxcore INT         Memory per process in MB (default: 4096)

Theory presets (same as iqcap-opt.sh):
  --method INT          Theory preset (default: 1). Sets OPT/SP defaults unless you override with --opt-level / --sp-level later on the command line:
                        0 = PBE D3BJ def2-SVP def2/J
                        1 = PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX
                        2 = B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX
                        3 = M06-2X def2-TZVP(-f) def2/J RIJCOSX
                        4 = ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX

  --mode INT            Legacy alias (sets --method): 1→0, 2→2, 3→1 (old quick presets)

Theory levels:
  --opt-level STR       ORCA theory for geometry / NEB / TS / IRC (manual override)
  --opt-pub STR         Same as --opt-level (name aligned with iqcap-opt.sh)
  --ts-level STR        Alias of --opt-level
                        (default: from --method, same as iqcap-opt --opt-pub without trailing " opt")
  --sp-level STR        ORCA theory for SP energy refinement
                        (default: <opt level> tightSCF, same rule as iqcap-opt.sh)
  --free-atoms STR      Keep only listed atoms free during NEB and TS opt; freeze the rest
                        Example: "1-5,7"

NEB parameters:
  --neb-method STR      NEB-CI (default) or NEB-TS
  --neb-nimages INT     Number of NEB images (default: 8)
  --neb-maxiter INT     Max NEB iterations (default: 500)

IRC parameters:
  --irc-maxiter INT     Max IRC steps per direction (default: 50)
  --irc-stepsize FLOAT  IRC step size in Bohr*amu^0.5 (default: 0.3)
  --irc-maxdisp FLOAT   IRC max displacement (default: 0.5)

Module switches:
  --skip-opt-endpoints  Skip ORCA optimization of reactant/product; use the given
                        XYZ files directly for NEB-CI / NEB-TS (for already-converged
                        endpoints). Same as --no-endpoint-opt.
  --no-endpoint-opt    Alias of --skip-opt-endpoints
  --no-neb              Skip NEB (requires --ts-guess)
  --no-optts            Skip TS optimization (use NEB or guess directly)
  --no-freq             Skip frequency verification
  --no-irc              Skip IRC path tracing
  --no-sp-refine        Skip single-point energy refinement
  --no-eprofile         Skip energy profile plot
  --no-irc-plot         Skip IRC path plot
  --no-ts-render        Skip VMD TS structure rendering
  --no-ts-panel         Skip TS validation panel
  --no-mode-proj        Skip TS mode projection bar chart
  --no-irc-coords       Skip IRC internal coordinates plot
  --no-neb-conv         Skip NEB convergence diagnostics plot
  --no-irc-anim         Skip IRC animation GIF
  --no-ts-trajectory-overlay  Skip TS trajectory overlay (three views)
  --no-cineb-image-plot Skip CINEB image-energy profile plot
  --no-cineb-overlay    Skip CINEB image overlay rendering (three views)
  --plot-only             Skip all computation; re-render/re-plot from existing data

Visualization:
  --mol-zoom FLOAT      VMD zoom factor (default: 1.00)
  --monitor-bonds STR   Atom pairs for IRC tracking, e.g. "1-2,2-3" (1-based)
  --element-color SPEC  Override element color (repeatable). SPEC formats:
                        "Na=#1f77b4" or "S=#ffcc00" or "Na=0.12/0.34/0.56" (RGB 0..1)
                        Multiple entries can be separated by ',' or ';'

Path overrides:
  --vmd-bin PATH        VMD executable path (auto-detected)

Info:
  -h, --help            Show this help message
  -V, --version         Show version information

Workflow:
  1. (Optional) Optimize reactant and product endpoints
  2. NEB-CI/NEB-TS path search -> TS guess
  3. OptTS + NumFreq -> optimized TS with frequency verification
  4. IRC (both directions) -> reaction path confirmation
  5. SP refinement on R/TS/P (optionally at higher level)
  6. Energy summary in Hartree / eV / kcal/mol / kJ/mol
  7. Publication-quality energy profile and IRC path plots
  8. VMD three-view rendering of TS structure

Python requirements: numpy, Pillow, matplotlib

Note: This software orchestrates third-party programs for computation
and visualization. It does NOT include ORCA or VMD.
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

###############################################################################
# Theory preset (same numbering as iqcap-opt.sh)
###############################################################################
apply_ts_method_preset() {
  [[ -n "$OPT_LEVEL" ]] && return 0
  local pub_def=""
  case "$METHOD" in
    0)
      pub_def="PBE D3BJ def2-SVP def2/J opt"
      ;;
    1)
      pub_def="PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
      ;;
    2)
      pub_def="B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX opt"
      ;;
    3)
      pub_def="M06-2X def2-TZVP(-f) def2/J RIJCOSX opt"
      ;;
    4)
      pub_def="ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX opt"
      ;;
    *)
      echo "Invalid --method: $METHOD (expected 0, 1, 2, 3, or 4)" >&2
      exit 1
      ;;
  esac
  OPT_LEVEL="${pub_def% opt}"
}
apply_ts_method_preset

# Pass element-color overrides to VMD/Python via env (consumed by embedded TCL / Python)
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
# Default SP level to OPT level if not specified
###############################################################################
[[ -n "$SP_REFINE_LEVEL" ]] || SP_REFINE_LEVEL="$OPT_LEVEL tightSCF"

###############################################################################
# Helpers: path resolution (shared with other iqcap modules)
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
# Helpers: ORCA input writers
###############################################################################
write_orca_sp_input() {
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

write_orca_opt_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" xyz_source="$5"
  cat > "$inp_file" <<EOF
! $level opt
%maxcore  $MAXCORE
%pal nprocs   $NPROCS end
* xyz   $charge   $mult
$(awk 'NR>2 {print $0}' "$xyz_source")
 *
EOF
}

write_orca_neb_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" \
        reactant="$5" product="$6" method="$7" nimages="$8" maxiter="$9" constraints_block="${10:-}"
  {
    cat <<EOF
! $method $level
%maxcore  $MAXCORE
%pal nprocs   $NPROCS end
EOF
    if [[ -n "$constraints_block" ]]; then
      cat <<EOF
%geom
$constraints_block
end
EOF
    fi
    cat <<EOF
%neb
  NImages  $nimages
  Product  "$product"
  MaxIter  $maxiter
end
* xyzfile   $charge   $mult   $reactant
EOF
  } > "$inp_file"
}

write_orca_optts_freq_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" xyz_source="$5" constraints_block="$6"
  {
    cat <<EOF
! OptTS NumFreq $level
%maxcore  $MAXCORE
%pal nprocs   $NPROCS end
%geom
  Calc_Hess true
  NumHess   true
EOF
    if [[ -n "$constraints_block" ]]; then
      printf "%s\n" "$constraints_block"
    fi
    cat <<EOF
end
* xyz   $charge   $mult
$(awk 'NR>2 {print $0}' "$xyz_source")
 *
EOF
  } > "$inp_file"
}

###############################################################################
# Helpers: atom constraints for NEB/TS
###############################################################################
build_fixed_zero_based() {
  local xyz_file="$1" mode="$2" spec="$3"
  python3 - "$xyz_file" "$mode" "$spec" <<'PYFIX'
import re
import sys

xyz_file, mode, spec = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(xyz_file, 'r', encoding='utf-8', errors='ignore') as handle:
        natoms = int(handle.readline().strip())
except Exception:
    print('Failed to read atom count from XYZ', file=sys.stderr)
    sys.exit(2)

def parse_spec(text):
  items = []
  for part in re.split(r'[\s,]+', text.strip()):
    if not part:
      continue
    if '-' in part:
      start_s, end_s = part.split('-', 1)
      start = int(start_s)
      end = int(end_s)
      step = 1 if start <= end else -1
      items.extend(range(start, end + step, step))
    else:
      items.append(int(part))
  return sorted(set(items))

selected = parse_spec(spec)
if not selected:
    print('Empty atom selection', file=sys.stderr)
    sys.exit(3)

for idx in selected:
    if idx < 1 or idx > natoms:
        print(f'Atom index out of range: {idx} (valid: 1..{natoms})', file=sys.stderr)
        sys.exit(4)

if mode == 'fix':
    fixed = selected
elif mode == 'free':
    selected_set = set(selected)
    fixed = [idx for idx in range(1, natoms + 1) if idx not in selected_set]
else:
    print(f'Unknown mode: {mode}', file=sys.stderr)
    sys.exit(5)

print(' '.join(str(idx - 1) for idx in fixed))
PYFIX
}

make_constraints_block() {
  local fixed_zero_list="$1"
  [[ -z "$fixed_zero_list" ]] && return 0

  echo "  Constraints"
  local idx
  for idx in $fixed_zero_list; do
    echo "    { C $idx C }"
  done
  echo "  end"
}

write_orca_irc_input() {
  local inp_file="$1" level="$2" charge="$3" mult="$4" xyz_source="$5" \
        maxiter="$6" stepsize="$7" maxdisp="$8"
  local hess_base; hess_base="$(basename "$inp_file" .inp)"
  cat > "$inp_file" <<EOF
! IRC $level
%maxcore  $MAXCORE
%pal nprocs   $NPROCS end
%irc
  MaxIter        $maxiter
  InitHess       read
  Hess_Filename  "${hess_base}.hess"
  Direction      both
  PrintLevel     1
end
* xyz   $charge   $mult
$(awk 'NR>2 {print $0}' "$xyz_source")
 *
EOF
}

###############################################################################
# Helpers: ORCA output parsing
###############################################################################
extract_final_energy() {
  local out_file="$1"
  grep "FINAL SINGLE POINT ENERGY" "$out_file" | tail -1 | awk '{print $NF}'
}

check_orca_success() {
  local out_file="$1" label="$2"
  if ! grep -q "ORCA TERMINATED NORMALLY" "$out_file" 2>/dev/null; then
    echo "WARNING: ORCA may not have terminated normally for $label" >&2
    echo "  Check $out_file for details." >&2
    return 1
  fi
  return 0
}

check_opt_convergence() {
  local out_file="$1" label="$2"
  if ! grep -qE "THE OPTIMIZATION HAS CONVERGED|OPTIMIZATION RUN DONE" "$out_file" 2>/dev/null; then
    echo "ERROR: $label optimization did not converge" >&2
    echo "  Check $out_file for details." >&2
    return 1
  fi
  return 0
}

###############################################################################
# Helper: extract the TS guess from NEB output
###############################################################################
extract_neb_ts_guess() {
  local neb_dir="$1" out_xyz="$2"
  python3 - "$neb_dir" "$out_xyz" <<'PYNEB'
import sys, re, shutil
from pathlib import Path

neb_dir = Path(sys.argv[1])
out_xyz = Path(sys.argv[2])

converged = sorted(neb_dir.glob("*NEB*converged*.xyz"))
if converged:
    shutil.copy2(str(converged[0]), str(out_xyz))
    lines = converged[0].read_text().splitlines()
    comment = lines[1] if len(lines) > 1 else ""
    em = re.search(r'E\s+([-\d.]+)', comment)
    e_str = f"  E = {em.group(1)} Eh" if em else ""
    print(f"  TS guess from NEB converged file: {converged[0].name}{e_str}")

out_file = neb_dir / "neb.out"
if out_file.exists():
    text = out_file.read_text(encoding="utf-8", errors="ignore")

    energies = {}
    ci_idx = None
    for m in re.finditer(r'PATH SUMMARY(.*?)(?=Straight line|Timings|\Z)', text, re.DOTALL):
        block = m.group(1)
        for line in block.strip().splitlines():
            line_s = line.strip()
            parts = line_s.split()
            if len(parts) >= 3:
                try:
                    img_idx = int(parts[0])
                    energy = float(parts[2])
                    energies[img_idx] = energy
                    if '<= CI' in line or '<=CI' in line:
                        ci_idx = img_idx
                except ValueError:
                    continue

    if energies:
        img_indices = sorted(energies.keys())
        e_ref = energies[img_indices[0]]
        if ci_idx is None:
            inner = [i for i in img_indices if i != img_indices[0] and i != img_indices[-1]]
            ci_idx = max(inner, key=lambda i: energies[i]) if inner else img_indices[0]
        print(f"  Climbing image: {ci_idx}  E = {energies[ci_idx]:.10f} Eh")
        print(f"  NEB image energies (kcal/mol relative to image 0):")
        for i in sorted(energies):
            de = (energies[i] - e_ref) * 627.5094740631
            marker = " <-- CI" if i == ci_idx else ""
            print(f"    {i:4d}  {energies[i]:.10f}  ({de:+.2f}){marker}")

if out_xyz.exists():
    sys.exit(0)

if not energies:
    raise SystemExit("Cannot parse NEB PATH SUMMARY and no converged file found")

candidates = [
    neb_dir / f"neb.im{ci_idx}.xyz",
    neb_dir / f"neb_im{ci_idx}.xyz",
]
for cand in candidates:
    if cand.exists():
        shutil.copy2(str(cand), str(out_xyz))
        print(f"  TS guess extracted from: {cand.name}")
        sys.exit(0)

trj_candidates = sorted(neb_dir.glob("*MEP*trj*.xyz"))
for trj in trj_candidates:
    lines = trj.read_text().splitlines()
    if not lines:
        continue
    natom = int(lines[0].strip())
    frame_len = natom + 2
    n_frames = len(lines) // frame_len
    if ci_idx < n_frames:
        start = ci_idx * frame_len
        frame_lines = lines[start:start + frame_len]
        out_xyz.write_text("\n".join(frame_lines) + "\n")
        print(f"  TS guess extracted from trajectory: {trj.name} frame {ci_idx}")
        sys.exit(0)

raise SystemExit(f"Cannot find geometry for NEB image {ci_idx}")
PYNEB
}

###############################################################################
# Helper: parse frequencies from ORCA output
###############################################################################
parse_frequencies() {
  local out_file="$1"
  python3 - "$out_file" <<'PYFREQ'
import sys, re

out_file = sys.argv[1]
text = open(out_file, encoding="utf-8", errors="ignore").read()

freq_blocks = list(re.finditer(
    r'VIBRATIONAL FREQUENCIES\s*\n-+\s*\n.*?Scaling.*?\n(.*?)(?=\n\s*NORMAL MODES|\n\s*-{20,})',
    text, re.DOTALL
))
if not freq_blocks:
    print("ERROR: Cannot find VIBRATIONAL FREQUENCIES section")
    sys.exit(1)
freq_block = freq_blocks[-1]

freqs = []
imaginary = []
for line in freq_block.group(1).strip().splitlines():
    m = re.match(r'\s*(\d+):\s+([-\d.]+)\s+cm\*\*-1', line)
    if m:
        idx, val = int(m.group(1)), float(m.group(2))
        freqs.append((idx, val))
        if val < -10.0:
            imaginary.append((idx, val))

n_imag = len(imaginary)
print(f"FREQ_N_IMAG={n_imag}")
if imaginary:
    for idx, val in imaginary:
        print(f"FREQ_IMAGINARY={idx}:{val:.2f}")

if n_imag == 1:
    print("FREQ_STATUS=OK")
    print(f"  Frequency verification: PASSED (1 imaginary frequency: {imaginary[0][1]:.2f} cm-1)")
elif n_imag == 0:
    print("FREQ_STATUS=NO_IMAG")
    print("  Frequency verification: FAILED (no imaginary frequencies -- not a TS)")
else:
    print(f"FREQ_STATUS=MULTI_IMAG")
    print(f"  Frequency verification: WARNING ({n_imag} imaginary frequencies -- higher-order saddle point)")
    for idx, val in imaginary:
        print(f"    Mode {idx}: {val:.2f} cm-1")
PYFREQ
}

###############################################################################
# Helper: parse IRC energies from ORCA output
###############################################################################
parse_irc_path() {
  local out_file="$1" data_file="$2"
  python3 - "$out_file" "$data_file" <<'PYIRC'
import sys, re
from pathlib import Path

out_file = sys.argv[1]
data_file = Path(sys.argv[2])
text = open(out_file, encoding="utf-8", errors="ignore").read()

m = re.search(
    r'IRC PATH SUMMARY.*?Step\s+E\(Eh\)\s+dE.*?\n(.*?)(?=\n\s*$|\n\s*Timings|\n\s*Total|\Z)',
    text, re.DOTALL
)
if not m:
    print("  IRC: Cannot find IRC PATH SUMMARY section")
    data_file.write_text("# direction  step  E(Eh)\n")
    sys.exit(0)

steps = []
ts_step = None
for line in m.group(1).strip().splitlines():
    line_s = line.strip()
    if not line_s or line_s.startswith('-'):
        continue
    parts = line_s.split()
    if len(parts) >= 2:
        try:
            step = int(parts[0])
            energy = float(parts[1])
            is_ts = '<= TS' in line or '<=TS' in line
            steps.append((step, energy, is_ts))
            if is_ts:
                ts_step = step
        except ValueError:
            continue

if not steps:
    print("  IRC: No steps parsed from IRC PATH SUMMARY")
    data_file.write_text("# direction  step  E(Eh)\n")
    sys.exit(0)

if ts_step is None:
    energies_only = [e for _, e, _ in steps]
    ts_idx_in_list = energies_only.index(max(energies_only))
    ts_step = steps[ts_idx_in_list][0]

bwd = [(s, e) for s, e, _ in steps if s < ts_step]
ts_pt = [(s, e) for s, e, _ in steps if s == ts_step]
fwd = [(s, e) for s, e, _ in steps if s > ts_step]

with data_file.open("w") as f:
    f.write("# direction  step  E(Eh)\n")
    for s, e in sorted(bwd, key=lambda x: -x[0]):
        f.write(f"backward  {ts_step - s}  {e:.12f}\n")
    for s, e in ts_pt:
        f.write(f"forward   0  {e:.12f}\n")
    for s, e in fwd:
        f.write(f"forward   {s - ts_step}  {e:.12f}\n")

print(f"  IRC path: {len(bwd)} backward + 1 TS + {len(fwd)} forward = {len(steps)} points")
if bwd:
    bwd_sorted = sorted(bwd, key=lambda x: x[0])
    print(f"  Backward endpoint (reactant side): E = {bwd_sorted[0][1]:.10f} Eh")
if fwd:
    fwd_sorted = sorted(fwd, key=lambda x: x[0])
    print(f"  Forward endpoint (product side):   E = {fwd_sorted[-1][1]:.10f} Eh")
PYIRC
}

###############################################################################
# Helper: extract last frame from IRC trajectory xyz
###############################################################################
extract_last_xyz_frame() {
  local trj_file="$1" out_file="$2"
  python3 - "$trj_file" "$out_file" <<'PYFRAME'
import sys
from pathlib import Path

trj = Path(sys.argv[1])
out = Path(sys.argv[2])

if not trj.exists():
    raise SystemExit(f"Trajectory file not found: {trj}")

lines = trj.read_text().strip().splitlines()
if not lines:
    raise SystemExit(f"Empty trajectory file: {trj}")

natom = int(lines[0].strip())
frame_len = natom + 2
n_frames = len(lines) // frame_len

if n_frames < 1:
    raise SystemExit(f"No complete frames in: {trj}")

last_start = (n_frames - 1) * frame_len
frame = lines[last_start:last_start + frame_len]
out.write_text("\n".join(frame) + "\n")
PYFRAME
}

###############################################################################
# VMD preamble for publication-quality rendering
###############################################################################
vmd_quality_preamble() {
  cat <<'TCLPRE'
display projection   Orthographic
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
# TS three-view rendering (VMD + Pillow annotation)
###############################################################################
render_ts_three_views() {
  local xyz_file="$1" out_dir="$2" imag_freq="$3"

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
render TachyonInternal "$out_dir/ts_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/ts_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/ts_top.tga"

quit
EOF
  } > "$out_dir/render_ts.tcl"

  "$VMD_EXE" -dispdev text -e "$out_dir/render_ts.tcl" > "$out_dir/ts_render.out" 2>&1

  for v in front side top; do
    [[ -f "$out_dir/ts_${v}.tga" ]] || { echo "Missing ts_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" "$imag_freq" <<'PYTS'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out_dir = Path(sys.argv[1])
imag_freq = sys.argv[2]

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"]):
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

for view in ("front", "side", "top"):
    tga = out_dir / f"ts_{view}.tga"
    png = out_dir / f"ts_{view}.png"
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        footer_h = max(70, int(0.06 * h))
        canvas = Image.new("RGBA", (w, h + footer_h), (255, 255, 255, 255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas)
        fn = _font(bold=True, size=max(32, int(0.024 * w)))
        footer = f"Transition State    v1 = {imag_freq} cm-1"
        fb = draw.textbbox((0, 0), footer, font=fn)
        draw.text(
            ((w - (fb[2] - fb[0])) / 2, h + (footer_h - (fb[3] - fb[1])) / 2),
            footer, fill=(30, 30, 30, 255), font=fn,
        )
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYTS
}

###############################################################################
# TS trajectory overlay: three views (front, side, top) with IRC path overlay
###############################################################################
render_ts_trajectory_overlay_three_views() {
  local trj_file="$1" out_dir="$2"
  [[ -f "$trj_file" ]] || { echo "Trajectory file not found: $trj_file" >&2; return 1; }
  local trj_abs; trj_abs="$(realpath "$trj_file")"
  local tcl_file="$out_dir/render_ts_trajectory_overlay.tcl"

  {
    vmd_quality_preamble
    cat <<'TCLBONDS'
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

mol new "$trj_abs" type xyz waitfor all
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
mol color Frame
mol selection all
mol material Transparent
material change opacity Transparent 0.35
mol addrep top

set nf [molinfo top get numframes]
if {\$nf < 2} {
  puts "Warning: trajectory has only \$nf frame(s), overlay may look static"
}
set last [expr {\$nf - 1}]
set step [expr {\$nf > 40 ? \$nf / 40 : 1}]
if {\$step < 1} { set step 1 }
mol drawframes top 0 0:\$step:\$last

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/ts_traj_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/ts_traj_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/ts_traj_top.tga"

quit
EOF
  } > "$tcl_file"

  "$VMD_EXE" -dispdev text -e "$tcl_file" > "$out_dir/ts_trajectory_overlay_render.out" 2>&1
  for v in front side top; do
    [[ -f "$out_dir/ts_traj_${v}.tga" ]] || { echo "Missing ts_traj_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" <<'PYTRAJ'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out_dir = Path(sys.argv[1])

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"]):
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

for view in ("front", "side", "top"):
    tga = out_dir / f"ts_traj_{view}.tga"
    png = out_dir / f"ts_traj_{view}.png"
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        footer_h = max(60, int(0.05 * h))
        canvas = Image.new("RGBA", (w, h + footer_h), (255, 255, 255, 255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas)
        fn = _font(bold=True, size=max(28, int(0.022 * w)))
        footer = "IRC trajectory overlay"
        fb = draw.textbbox((0, 0), footer, font=fn)
        draw.text(
            ((w - (fb[2] - fb[0])) / 2, h + (footer_h - (fb[3] - fb[1])) / 2),
            footer, fill=(40, 40, 40, 255), font=fn,
        )
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYTRAJ
}

###############################################################################
# CINEB image energies: parse NEB image energies and write data tables
###############################################################################
parse_neb_image_energies() {
  local neb_dir="$1" out_dat="$2" out_csv="$3"
  python3 - "$neb_dir" "$out_dat" "$out_csv" <<'PYCINEBDAT'
import sys, re
from pathlib import Path

HA2KCAL = 627.5094740631

neb_dir = Path(sys.argv[1])
out_dat = Path(sys.argv[2])
out_csv = Path(sys.argv[3])

def parse_from_neb_out(neb_out: Path):
  if not neb_out.exists():
    return None
  text = neb_out.read_text(encoding="utf-8", errors="ignore")
  best_rows = []
  for m in re.finditer(r'PATH SUMMARY(.*?)(?=Straight line|Timings|\\Z)', text, re.DOTALL | re.IGNORECASE):
    rows = []
    for line in m.group(1).splitlines():
      s = line.strip()
      if not s or s.startswith('-'):
        continue
      parts = s.split()
      if len(parts) < 3:
        continue
      try:
        idx = int(parts[0])
        energy = float(parts[2])
      except ValueError:
        continue
      is_ci = ('<= CI' in line) or ('<=CI' in line)
      rows.append((idx, energy, is_ci))
    if len(rows) > len(best_rows):
      best_rows = rows
  if len(best_rows) < 2:
    return None

  energies = {}
  ci_idx = None
  for idx, e, is_ci in best_rows:
    energies[idx] = e
    if is_ci:
      ci_idx = idx
  return energies, ci_idx, "neb.out PATH SUMMARY"

def parse_xyz_trajectory_energies(xyz_file: Path):
  if not xyz_file.exists():
    return None
  lines = xyz_file.read_text(encoding="utf-8", errors="ignore").splitlines()
  energies = {}
  i = 0
  frame_idx = 0
  while i < len(lines):
    s = lines[i].strip()
    if not s:
      i += 1
      continue
    try:
      natom = int(s)
    except ValueError:
      i += 1
      continue
    if i + 1 >= len(lines):
      break
    comment = lines[i + 1]
    em = re.search(r'\\bE(?:nergy)?\\b\\s*[=:]?\\s*([+-]?\\d+(?:\\.\\d+)?)', comment)
    if em:
      try:
        energies[frame_idx] = float(em.group(1))
      except ValueError:
        pass
    i += natom + 2
    frame_idx += 1

  if len(energies) < 2:
    return None
  return energies, None, f"{xyz_file.name} comments"

parsed = parse_from_neb_out(neb_dir / "neb.out")
if parsed is None:
  candidates = [
    neb_dir / "neb_NEB-CI_converged.xyz",
    neb_dir / "neb_NEB-TS_converged.xyz",
    neb_dir / "neb_MEP_trj.xyz",
    neb_dir / "neb_MEP_ALL_trj.xyz",
    neb_dir / "neb_MEP.allxyz",
    neb_dir / "neb_initial_path_trj.xyz",
  ]
  best = None
  best_n = -1
  for c in candidates:
    p = parse_xyz_trajectory_energies(c)
    if p is None:
      continue
    n = len(p[0])
    if n > best_n:
      best = p
      best_n = n
  parsed = best

if parsed is None:
  out_dat.write_text("# image_idx E(Eh) dE(kcal/mol) is_ci\n")
  out_csv.write_text("image_idx,E_Hartree,dE_kcal_mol,is_ci\n")
  print("  CINEB image energies: no parseable NEB image energies found")
  sys.exit(0)

energies, ci_idx, source = parsed
idxs = sorted(energies)
if len(idxs) < 2:
  out_dat.write_text("# image_idx E(Eh) dE(kcal/mol) is_ci\n")
  out_csv.write_text("image_idx,E_Hartree,dE_kcal_mol,is_ci\n")
  print("  CINEB image energies: insufficient image points")
  sys.exit(0)

if ci_idx is None:
  inner = [i for i in idxs if i != idxs[0] and i != idxs[-1]]
  if inner:
    ci_idx = max(inner, key=lambda k: energies[k])
  else:
    ci_idx = max(idxs, key=lambda k: energies[k])

e0 = energies[idxs[0]]
imax = max(idxs, key=lambda k: energies[k])
barrier_kcal = (energies[imax] - e0) * HA2KCAL

with out_dat.open("w", encoding="utf-8") as f:
  f.write("# image_idx E(Eh) dE(kcal/mol) is_ci\n")
  for i in idxs:
    de = (energies[i] - e0) * HA2KCAL
    f.write(f"{i:4d}  {energies[i]: .12f}  {de: .6f}  {1 if i == ci_idx else 0}\n")

with out_csv.open("w", encoding="utf-8") as f:
  f.write("image_idx,E_Hartree,dE_kcal_mol,is_ci\n")
  for i in idxs:
    de = (energies[i] - e0) * HA2KCAL
    f.write(f"{i},{energies[i]:.12f},{de:.6f},{1 if i == ci_idx else 0}\n")

print(f"  CINEB image energies: {len(idxs)} images (source: {source})")
print(f"  Forward barrier from image 0: {barrier_kcal:.2f} kcal/mol (max image {imax})")
print(f"  Data: {out_dat}")
print(f"  CSV:  {out_csv}")
PYCINEBDAT
}

###############################################################################
# CINEB image energy profile (VASP-like image plot)
###############################################################################
generate_cineb_image_plot() {
  local data_file="$1" out_png="$2"
  python3 - "$data_file" "$out_png" "$HA_TO_EV" <<'PYCINEBPLOT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

data_file = sys.argv[1]
out_png = sys.argv[2]
KCAL_PER_EV = 23.06054783

idx, e_ha, de_kcal, is_ci = [], [], [], []
with open(data_file, encoding='utf-8', errors='ignore') as f:
  for line in f:
    s = line.strip()
    if not s or s.startswith('#'):
      continue
    p = s.split()
    if len(p) < 4:
      continue
    idx.append(int(p[0]))
    e_ha.append(float(p[1]))
    de_kcal.append(float(p[2]))
    is_ci.append(int(p[3]))

if len(idx) < 2:
  print('  CINEB image plot: insufficient data; skip')
  sys.exit(0)

x = np.array(idx)
y_kcal = np.array(de_kcal)
order = np.argsort(x)
x = x[order]
y_kcal = y_kcal[order]
is_ci_arr = np.array(is_ci)[order]

if np.any(is_ci_arr == 1):
  ci_i = int(np.where(is_ci_arr == 1)[0][0])
else:
  inner = np.arange(1, len(x) - 1) if len(x) > 2 else np.arange(len(x))
  ci_i = int(inner[np.argmax(y_kcal[inner])]) if len(inner) else int(np.argmax(y_kcal))

x_ci = x[ci_i]
y_eV = y_kcal / KCAL_PER_EV
y_ci = y_eV[ci_i]
barrier_eV = float(np.max(y_eV) - y_eV[0])

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

fig, ax = plt.subplots(figsize=(10, 6), dpi=300)
ax.plot(x, y_eV, 'o-', color='#2c3e50', lw=2.2, ms=6, mfc='white', mec='#2c3e50', zorder=3)
ax.scatter([x_ci], [y_ci], s=90, c='#c0392b', edgecolors='white', linewidths=1.2, zorder=5)

ax.axhline(y=0.0, color='#aaaaaa', lw=0.9, ls='--', zorder=1)
ax.axvline(x=x_ci, color='#bbbbbb', lw=0.8, ls=':', zorder=1)

ax.annotate('', xy=(x_ci, y_ci), xytext=(x_ci, y_eV[0]),
      arrowprops=dict(arrowstyle='<->', color='#c0392b', lw=2.0, shrinkA=2, shrinkB=2))
ax.text(x_ci + 0.3, y_eV[0] + 0.55 * max(0.02, y_ci - y_eV[0]),
  f'$\\Delta E^\\ddagger_{{fwd}}$ = {barrier_eV:.3f} eV',
    fontsize=12, color='#c0392b', fontweight='bold', ha='left', va='center',
    bbox=dict(boxstyle='round,pad=0.25', fc='white', ec='none', alpha=0.88))

ax.text(x[0], y_eV[0] - max(0.02, 0.05 * (np.max(y_eV) - np.min(y_eV) + 1e-9)), 'R',
    color='#1f77b4', fontsize=12, fontweight='bold', ha='center')
ax.text(x[-1], y_eV[-1] - max(0.02, 0.05 * (np.max(y_eV) - np.min(y_eV) + 1e-9)), 'P',
    color='#2ca02c', fontsize=12, fontweight='bold', ha='center')

ax.set_xlabel('CINEB image index', fontsize=16, fontweight='bold')
ax.set_ylabel('Relative energy (eV)', fontsize=16, fontweight='bold')
ax.set_title('CINEB Image Energy Profile', fontsize=22, fontweight='bold', pad=12)
ax.set_xticks(x)
ax.tick_params(axis='both', labelsize=17, width=1.5, length=5)
for s in ax.spines.values():
  s.set_linewidth(1.6)

ymin = min(np.min(y_eV), 0.0)
ymax = np.max(y_eV)
ypad = max(0.04, 0.16 * (ymax - ymin + 1e-9))
ax.set_ylim(ymin - ypad, ymax + ypad)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f'  CINEB image plot: {out_png}')
PYCINEBPLOT
}

###############################################################################
# CINEB images overlay: three views (front, side, top)
###############################################################################
render_cineb_overlay_three_views() {
  local trj_file="$1" out_dir="$2"
  [[ -f "$trj_file" ]] || { echo "NEB trajectory not found: $trj_file" >&2; return 1; }
  local trj_abs; trj_abs="$(realpath "$trj_file")"
  local tcl_file="$out_dir/render_cineb_overlay.tcl"

  local nframes
  nframes="$(python3 - "$trj_abs" <<'PYNFRAMES'
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore').splitlines()
i = 0
nf = 0
while i < len(lines):
    s = lines[i].strip()
    if not s:
        i += 1
        continue
    try:
        nat = int(s)
    except ValueError:
        i += 1
        continue
    if i + nat + 1 >= len(lines):
        break
    nf += 1
    i += nat + 2
print(nf)
PYNFRAMES
)"
  echo "  CINEB overlay source: $trj_file ($nframes frames)"

  {
  vmd_quality_preamble
  cat <<'TCLBONDS'
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

mol new "$trj_abs" type xyz waitfor all
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

# Overlay all CINEB images as transparent element-colored structures.
mol representation CPK 0.8 0.3 30.0 30.0
mol color Element
mol selection all
mol material Transparent
material change opacity Transparent 0.30
mol addrep top

set nf [molinfo top get numframes]
if {\$nf < 2} {
  puts "Warning: NEB trajectory has only \$nf frame(s), overlay may look static"
}
set last [expr {\$nf - 1}]
set step [expr {\$nf > 24 ? \$nf / 24 : 1}]
if {\$step < 1} { set step 1 }
mol drawframes top 0 0:\$step:\$last

# Add faint dynamic Li-S bonds to show the bond-forming region in overlays.
set li_s_cutoff 3.10
mol representation DynamicBonds \$li_s_cutoff 0.12 24.0
mol color ColorID 8
mol selection "(element Li or element S)"
mol material Transparent
material change opacity Transparent 0.4
mol addrep top
mol drawframes top 1 0:\$step:\$last

# Highlight the middle image to make superposition easier to read.
set mid [expr {\$nf / 2}]
mol representation CPK 0.9 0.3 30.0 30.0
mol color Element
mol selection all
mol material Glossy
mol addrep top
mol drawframes top 2 \$mid:\$mid

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/cineb_overlay_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/cineb_overlay_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/cineb_overlay_top.tga"

quit
EOF
  } > "$tcl_file"

  "$VMD_EXE" -dispdev text -e "$tcl_file" > "$out_dir/cineb_overlay_render.out" 2>&1
  for v in front side top; do
  [[ -f "$out_dir/cineb_overlay_${v}.tga" ]] || { echo "Missing cineb_overlay_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" <<'PYCINEBPNG'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out_dir = Path(sys.argv[1])

def _font(bold=False, size=20):
  for n in (["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"] if bold
        else ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"]):
    try:
      return ImageFont.truetype(n, size)
    except Exception:
      continue
  return ImageFont.load_default()

for view in ("front", "side", "top"):
  tga = out_dir / f"cineb_overlay_{view}.tga"
  png = out_dir / f"cineb_overlay_{view}.png"
  with Image.open(tga) as src:
    src = src.convert("RGBA")
    w, h = src.size
    footer_h = max(60, int(0.05 * h))
    canvas = Image.new("RGBA", (w, h + footer_h), (255, 255, 255, 255))
    canvas.paste(src, (0, 0))
    draw = ImageDraw.Draw(canvas)
    fn = _font(bold=True, size=max(28, int(0.022 * w)))
    footer = "CINEB image overlay"
    fb = draw.textbbox((0, 0), footer, font=fn)
    draw.text(
      ((w - (fb[2] - fb[0])) / 2, h + (footer_h - (fb[3] - fb[1])) / 2),
      footer, fill=(40, 40, 40, 255), font=fn,
    )
    canvas.save(png, format="PNG")
  print(f"  {png}")
PYCINEBPNG
}

###############################################################################
# [NEW-1] TS Validation Panel: freq spectrum + mode arrows + IRC curve
###############################################################################
generate_ts_validation_panel() {
  local ts_out="$1" irc_data="$2" out_png="$3" imag_freq="$4"
  python3 - "$ts_out" "$irc_data" "$out_png" "$imag_freq" <<'PYPANEL'
import sys, re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from pathlib import Path

ts_out   = sys.argv[1]
irc_data = sys.argv[2]
out_png  = sys.argv[3]
imag_str = sys.argv[4]

text = open(ts_out, encoding="utf-8", errors="ignore").read()

freq_blocks = list(re.finditer(
    r'VIBRATIONAL FREQUENCIES\s*\n-+\s*\n.*?Scaling.*?\n(.*?)(?=\n\s*NORMAL MODES|\n\s*-{20,})',
    text, re.DOTALL))
freqs = []
if freq_blocks:
    for line in freq_blocks[-1].group(1).strip().splitlines():
        m = re.match(r'\s*(\d+):\s+([-\d.]+)\s+cm\*\*-1', line)
        if m:
            freqs.append((int(m.group(1)), float(m.group(2))))

mode_blocks = list(re.finditer(
    r'NORMAL MODES\s*\n-+\s*\n.*?normalized.*?\n\n(.*?)(?=\n-{20,}|\n\s*IR SPECTRUM)',
    text, re.DOTALL))
modes = {}
if mode_blocks:
    block = mode_blocks[-1].group(1).strip()
    col_headers = []
    for line in block.splitlines():
        parts = line.split()
        if not parts:
            continue
        try:
            vals = [int(x) for x in parts]
            col_headers = vals
            continue
        except ValueError:
            pass
        try:
            row_idx = int(parts[0])
            vals = [float(x) for x in parts[1:]]
            for i, col in enumerate(col_headers):
                if i < len(vals):
                    if col not in modes:
                        modes[col] = []
                    modes[col].append(vals[i])
        except (ValueError, IndexError):
            continue

coord_blocks = list(re.finditer(
    r'CARTESIAN COORDINATES \(ANGSTROEM\)\s*\n-+\s*\n(.*?)(?=\n\s*-{5,}|\n\s*$)',
    text, re.DOTALL))
atoms = []
if coord_blocks:
    for line in coord_blocks[-1].group(1).strip().splitlines():
        parts = line.split()
        if len(parts) >= 4:
            try:
                atoms.append((parts[0], float(parts[1]), float(parts[2]), float(parts[3])))
            except ValueError:
                continue

fig = plt.figure(figsize=(16, 5.5), dpi=150)
gs = GridSpec(1, 3, width_ratios=[1.0, 1.0, 1.2], wspace=0.32)

ax1 = fig.add_subplot(gs[0])
if freqs:
    vib_freqs = [(i, f) for i, f in freqs if abs(f) > 10]
    indices = [i for i, _ in vib_freqs]
    values = [f for _, f in vib_freqs]
    colors = ['#c0392b' if f < 0 else '#2c3e50' for f in values]
    ax1.bar(range(len(values)), values, color=colors, width=0.6, edgecolor='none')
    ax1.set_xticks(range(len(values)))
    ax1.set_xticklabels([str(i) for i in indices], fontsize=8)
    ax1.axhline(0, color='gray', lw=0.5, ls='--')
    for j, (idx, f) in enumerate(vib_freqs):
        if f < 0:
            ax1.annotate(f'{f:.0f}', (j, f), textcoords="offset points",
                         xytext=(0, -14), ha='center', fontsize=8, color='#c0392b',
                         fontweight='bold')
ax1.set_xlabel('Mode', fontsize=10)
ax1.set_ylabel('Frequency (cm$^{-1}$)', fontsize=10)
ax1.set_title('Vibrational Spectrum', fontsize=11, fontweight='bold')

ax2 = fig.add_subplot(gs[1])
imag_mode_idx = None
for i, f in freqs:
    if f < -10:
        imag_mode_idx = i
        break

if atoms and imag_mode_idx is not None and imag_mode_idx in modes:
    disp = modes[imag_mode_idx]
    natom = len(atoms)
    coords = np.array([[a[1], a[2], a[3]] for a in atoms])
    elem = [a[0] for a in atoms]
    dx = np.array(disp).reshape(natom, 3)

    u = coords[:, 0] - coords[:, 1]
    v = coords[:, 2]
    elem_colors = {'H': '#999999', 'C': '#8E8E8E', 'N': '#3498db', 'O': '#e74c3c',
         'S': '#f1c40f', 'F': '#1cffe8', 'Cl': '#27ae60', 'Br': '#8b4513',
         'P': '#e67e22', 'Li': '#90EE90', 'Na': '#FFAEB9', 'B': '#FFAEB9'}
    elem_sizes = {'H': 120, 'C': 250, 'N': 250, 'O': 250, 'S': 300,
                  'F': 220, 'Cl': 280, 'Br': 300, 'P': 280, 'Li': 280, 'Na': 300}

    import os, re
    spec = os.environ.get("IQCAP_ELEMENT_COLORS", "").strip()
    if spec:
        for tok in re.split(r'[,;]\s*', spec):
            if not tok or '=' not in tok:
                continue
            el, val = tok.split('=', 1)
            el = el.strip()
            val = val.strip()
            if re.fullmatch(r'#[0-9A-Fa-f]{6}', val):
                elem_colors[el] = val

    for i in range(natom):
        for j in range(i+1, natom):
            dist = np.linalg.norm(coords[i] - coords[j])
            if dist < 2.0:
                ax2.plot([u[i], u[j]], [v[i], v[j]], 'k-', lw=1.5, alpha=0.4, zorder=1)

    for i, e in enumerate(elem):
        c = elem_colors.get(e, '#7f8c8d')
        s = elem_sizes.get(e, 200)
        ax2.scatter(u[i], v[i], s=s, c=c, edgecolors='k', lw=0.5, zorder=3)
        ax2.annotate(e, (u[i], v[i]), ha='center', va='center', fontsize=8,
                     fontweight='bold', zorder=4)

    scale = 2.0
    for i in range(natom):
        arrow_u = dx[i, 0] - dx[i, 1]
        arrow_v = dx[i, 2]
        mag = np.sqrt(arrow_u**2 + arrow_v**2)
        if mag > 0.01:
            ax2.annotate('', xy=(u[i] + arrow_u*scale, v[i] + arrow_v*scale),
                         xytext=(u[i], v[i]),
                         arrowprops=dict(arrowstyle='->', color='#c0392b',
                                        lw=max(1.0, mag*4), mutation_scale=12))

ax2.set_aspect('equal')
ax2.set_title(f'Imaginary Mode ({imag_str} cm$^{{-1}}$)', fontsize=11, fontweight='bold')
ax2.set_xlabel('Projected coordinate (\u00c5)', fontsize=10)
ax2.tick_params(labelsize=8)

ax3 = fig.add_subplot(gs[2])
irc_path = Path(irc_data)
if irc_path.exists() and irc_path.stat().st_size > 30:
    steps_bwd, steps_fwd, e_bwd, e_fwd = [], [], [], []
    for line in irc_path.read_text().splitlines():
        if line.startswith('#') or not line.strip():
            continue
        parts = line.split()
        if len(parts) >= 3:
            direction = parts[0]
            step = int(parts[1])
            energy = float(parts[2])
            if direction == 'backward':
                steps_bwd.append(-step)
                e_bwd.append(energy)
            else:
                steps_fwd.append(step)
                e_fwd.append(energy)

    all_steps = steps_bwd + steps_fwd
    all_e = e_bwd + e_fwd
    if all_e:
        e_ts_val = max(all_e)
        e_rel = [(e - e_ts_val) * 627.5094740631 for e in all_e]
        order = np.argsort(all_steps)
        xs = np.array(all_steps)[order]
        ys = np.array(e_rel)[order]
        ax3.plot(xs, ys, 'o-', color='#c0392b', ms=3, lw=1.2, mfc='white', mec='#c0392b')
        ax3.axhline(0, color='gray', lw=0.5, ls='--')
        ax3.axvline(0, color='gray', lw=0.5, ls=':')
        ax3.fill_between(xs[xs <= 0], ys[np.where(xs <= 0)], alpha=0.08, color='#3498db')
        ax3.fill_between(xs[xs >= 0], ys[np.where(xs >= 0)], alpha=0.08, color='#e67e22')
        ax3.text(xs[0]*0.5, min(ys)*0.5, 'R side', ha='center', fontsize=9, color='#3498db')
        ax3.text(xs[-1]*0.5, min(ys)*0.5, 'P side', ha='center', fontsize=9, color='#e67e22')
else:
    ax3.text(0.5, 0.5, 'No IRC data', transform=ax3.transAxes, ha='center', va='center',
             fontsize=12, color='gray')
ax3.set_xlabel('IRC step (backward \u2190 TS \u2192 forward)', fontsize=10)
ax3.set_ylabel('Relative energy (kcal/mol)', fontsize=10)
ax3.set_title('IRC Energy Path', fontsize=11, fontweight='bold')
ax3.tick_params(labelsize=8)

fig.suptitle('Transition State Validation', fontsize=14, fontweight='bold', y=1.02)
fig.savefig(out_png, dpi=150, bbox_inches='tight', facecolor='white')
plt.close(fig)
print(f"  TS validation panel: {out_png}")
PYPANEL
}

###############################################################################
# [NEW-2] IRC Internal Coordinates Evolution Plot
###############################################################################
generate_irc_coords_plot() {
  local trj_file="$1" out_png="$2" monitor_bonds="$3"
  python3 - "$trj_file" "$out_png" "$monitor_bonds" <<'PYCOORDS'
import sys, re, itertools
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

trj_file = sys.argv[1]
out_png = sys.argv[2]
monitor_str = sys.argv[3] if len(sys.argv) > 3 else ""

lines = Path(trj_file).read_text().splitlines()
if not lines:
    print("  IRC coords: empty trajectory")
    sys.exit(0)

frames = []
i = 0
while i < len(lines):
    line = lines[i].strip()
    if not line:
        i += 1
        continue
    try:
        natom = int(line)
    except ValueError:
        i += 1
        continue
    comment = lines[i+1] if i+1 < len(lines) else ""
    em = re.search(r'E\s+([-\d.]+)', comment)
    energy = float(em.group(1)) if em else 0.0
    atoms_data = []
    for j in range(natom):
        parts = lines[i+2+j].split()
        atoms_data.append((parts[0], float(parts[1]), float(parts[2]), float(parts[3])))
    frames.append({'energy': energy, 'atoms': atoms_data})
    i += 2 + natom

if len(frames) < 3:
    print("  IRC coords: too few frames")
    sys.exit(0)

natom = len(frames[0]['atoms'])
elements = [a[0] for a in frames[0]['atoms']]

def get_coords(frame):
    return np.array([[a[1], a[2], a[3]] for a in frame['atoms']])

def bond_label(i, j):
    return f"r({elements[i]}{i+1}\u2013{elements[j]}{j+1})"

def angle_label(i, j, k):
    return f"\u2220{elements[i]}{i+1}\u2013{elements[j]}{j+1}\u2013{elements[k]}{k+1}"

user_pairs = []
if monitor_str:
    for token in monitor_str.split(','):
        idx = [int(x) - 1 for x in token.strip().split('-')]
        if len(idx) == 2:
            user_pairs.append(tuple(idx))

all_pairs = list(itertools.combinations(range(natom), 2))
all_dists = {pair: [] for pair in all_pairs}
for frame in frames:
    coords = get_coords(frame)
    for pair in all_pairs:
        d = np.linalg.norm(coords[pair[0]] - coords[pair[1]])
        all_dists[pair].append(d)

pair_variation = {}
for pair, dists in all_dists.items():
    pair_variation[pair] = max(dists) - min(dists)

if user_pairs:
    plot_pairs = user_pairs
else:
    sorted_pairs = sorted(pair_variation.items(), key=lambda x: -x[1])
    n_show = min(6, len(sorted_pairs))
    plot_pairs = [p for p, _ in sorted_pairs[:n_show] if pair_variation[p] > 0.05]
    if not plot_pairs:
        plot_pairs = [p for p, _ in sorted_pairs[:3]]

all_angles = []
if natom >= 3:
    for j in range(natom):
        for i in range(natom):
            if i == j:
                continue
            for k in range(i+1, natom):
                if k == j:
                    continue
                all_angles.append((i, j, k))

angle_data = {}
for triple in all_angles:
    vals = []
    for frame in frames:
        coords = get_coords(frame)
        v1 = coords[triple[0]] - coords[triple[1]]
        v2 = coords[triple[2]] - coords[triple[1]]
        cos_a = np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-15)
        cos_a = np.clip(cos_a, -1, 1)
        vals.append(np.degrees(np.arccos(cos_a)))
    angle_data[triple] = vals

angle_variation = {t: max(v) - min(v) for t, v in angle_data.items()}
sorted_angles = sorted(angle_variation.items(), key=lambda x: -x[1])
plot_angles = [t for t, var in sorted_angles[:3] if var > 5.0]

n_mid = len(frames) // 2
ts_step = 0
energies = [f['energy'] for f in frames]
ts_idx = energies.index(max(energies))
x_steps = list(range(-ts_idx, len(frames) - ts_idx))

has_angles = len(plot_angles) > 0
fig, axes = plt.subplots(2 if has_angles else 1, 1,
                         figsize=(10, 8 if has_angles else 5), dpi=150,
                         sharex=True)
if not has_angles:
    axes = [axes]

cmap = plt.cm.Set1
ax_bond = axes[0]
for idx, pair in enumerate(plot_pairs):
    color = cmap(idx % 9)
    label = bond_label(pair[0], pair[1])
    ax_bond.plot(x_steps, all_dists[pair], 'o-', color=color, ms=2.5, lw=1.5,
                 label=label, mfc='white', mec=color)

ax_bond.axvline(0, color='gray', lw=0.8, ls=':', label='TS')
ax_bond.axvspan(x_steps[0], 0, alpha=0.04, color='#3498db')
ax_bond.axvspan(0, x_steps[-1], alpha=0.04, color='#e67e22')
ax_bond.set_ylabel('Bond length (\u00c5)', fontsize=11)
ax_bond.set_title('IRC: Key Bond Length Evolution', fontsize=12, fontweight='bold')
ax_bond.legend(fontsize=9, loc='best', framealpha=0.9)
ax_bond.tick_params(labelsize=9)

if has_angles:
    ax_ang = axes[1]
    for idx, triple in enumerate(plot_angles):
        color = cmap((idx + len(plot_pairs)) % 9)
        label = angle_label(triple[0], triple[1], triple[2])
        ax_ang.plot(x_steps, angle_data[triple], 's-', color=color, ms=2.5, lw=1.5,
                    label=label, mfc='white', mec=color)
    ax_ang.axvline(0, color='gray', lw=0.8, ls=':')
    ax_ang.set_ylabel('Bond angle (\u00b0)', fontsize=11)
    ax_ang.set_title('IRC: Key Bond Angle Evolution', fontsize=12, fontweight='bold')
    ax_ang.legend(fontsize=9, loc='best', framealpha=0.9)
    ax_ang.tick_params(labelsize=9)

axes[-1].set_xlabel('IRC step (backward \u2190 TS \u2192 forward)', fontsize=11)
fig.tight_layout()
fig.savefig(out_png, dpi=150, bbox_inches='tight', facecolor='white')
plt.close(fig)
print(f"  IRC internal coordinates: {out_png}")
PYCOORDS
}

###############################################################################
# [NEW-3] TS Imaginary Mode Projection onto Internal Coordinates
###############################################################################
generate_mode_projection() {
  local ts_out="$1" out_png="$2"
  python3 - "$ts_out" "$out_png" <<'PYMODEPROJ'
import sys, re, itertools
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ts_out = sys.argv[1]
out_png = sys.argv[2]

text = open(ts_out, encoding="utf-8", errors="ignore").read()

coord_blocks = list(re.finditer(
    r'CARTESIAN COORDINATES \(ANGSTROEM\)\s*\n-+\s*\n(.*?)(?=\n\s*-{5,}|\n\s*$)',
    text, re.DOTALL))
atoms = []
if coord_blocks:
    for line in coord_blocks[-1].group(1).strip().splitlines():
        parts = line.split()
        if len(parts) >= 4:
            try:
                atoms.append((parts[0], float(parts[1]), float(parts[2]), float(parts[3])))
            except ValueError:
                continue

if not atoms:
    print("  Mode projection: no atom coordinates found")
    sys.exit(0)

natom = len(atoms)
coords = np.array([[a[1], a[2], a[3]] for a in atoms])
elem = [a[0] for a in atoms]

freq_blocks = list(re.finditer(
    r'VIBRATIONAL FREQUENCIES\s*\n-+\s*\n.*?Scaling.*?\n(.*?)(?=\n\s*NORMAL MODES|\n\s*-{20,})',
    text, re.DOTALL))
freqs = []
if freq_blocks:
    for line in freq_blocks[-1].group(1).strip().splitlines():
        m = re.match(r'\s*(\d+):\s+([-\d.]+)\s+cm\*\*-1', line)
        if m:
            freqs.append((int(m.group(1)), float(m.group(2))))

imag_idx = None
imag_freq = 0
for i, f in freqs:
    if f < -10:
        imag_idx = i
        imag_freq = f
        break

if imag_idx is None:
    print("  Mode projection: no imaginary frequency")
    sys.exit(0)

mode_blocks = list(re.finditer(
    r'NORMAL MODES\s*\n-+\s*\n.*?normalized.*?\n\n(.*?)(?=\n-{20,}|\n\s*IR SPECTRUM)',
    text, re.DOTALL))
modes = {}
if mode_blocks:
    block = mode_blocks[-1].group(1).strip()
    col_headers = []
    for line in block.splitlines():
        parts = line.split()
        if not parts:
            continue
        try:
            vals = [int(x) for x in parts]
            col_headers = vals
            continue
        except ValueError:
            pass
        try:
            row_idx = int(parts[0])
            vals = [float(x) for x in parts[1:]]
            for k, col in enumerate(col_headers):
                if k < len(vals):
                    if col not in modes:
                        modes[col] = []
                    modes[col].append(vals[k])
        except (ValueError, IndexError):
            continue

if imag_idx not in modes:
    print("  Mode projection: imaginary mode not found in NORMAL MODES")
    sys.exit(0)

disp_raw = np.array(modes[imag_idx]).reshape(natom, 3)

atomic_mass = {'H': 1.008, 'He': 4.003, 'Li': 6.941, 'Be': 9.012, 'B': 10.81,
               'C': 12.011, 'N': 14.007, 'O': 15.999, 'F': 18.998, 'Ne': 20.180,
               'Na': 22.990, 'Mg': 24.305, 'Al': 26.982, 'Si': 28.086, 'P': 30.974,
               'S': 32.065, 'Cl': 35.453, 'Ar': 39.948, 'K': 39.098, 'Ca': 40.078,
               'Br': 79.904, 'I': 126.904}
disp = np.zeros_like(disp_raw)
for i in range(natom):
    m = atomic_mass.get(elem[i], 12.0)
    disp[i] = disp_raw[i] * np.sqrt(m)

bond_labels = []
bond_projections = []
for i, j in itertools.combinations(range(natom), 2):
    r_vec = coords[j] - coords[i]
    r_len = np.linalg.norm(r_vec)
    if r_len > 3.0:
        continue
    r_hat = r_vec / r_len
    delta_r = np.dot(disp[j] - disp[i], r_hat)
    bond_labels.append(f"r({elem[i]}{i+1}\u2013{elem[j]}{j+1})")
    bond_projections.append(delta_r)

angle_labels = []
angle_projections = []
if natom >= 3:
    for j_at in range(natom):
        neighbors = []
        for k_at in range(natom):
            if k_at != j_at:
                d = np.linalg.norm(coords[k_at] - coords[j_at])
                if d < 3.0:
                    neighbors.append(k_at)
        for i_at, k_at in itertools.combinations(neighbors, 2):
            v1 = coords[i_at] - coords[j_at]
            v2 = coords[k_at] - coords[j_at]
            r1 = np.linalg.norm(v1)
            r2 = np.linalg.norm(v2)
            cos_a = np.dot(v1, v2) / (r1 * r2 + 1e-15)
            cos_a = np.clip(cos_a, -1, 1)
            angle0 = np.arccos(cos_a)

            eps = 0.005
            for at_idx in range(natom):
                coords_p = coords.copy()
                coords_p[at_idx] += disp[at_idx] * eps
            v1p = (coords + disp * eps)[i_at] - (coords + disp * eps)[j_at]
            v2p = (coords + disp * eps)[k_at] - (coords + disp * eps)[j_at]
            cos_ap = np.dot(v1p, v2p) / (np.linalg.norm(v1p) * np.linalg.norm(v2p) + 1e-15)
            cos_ap = np.clip(cos_ap, -1, 1)
            angle_p = np.arccos(cos_ap)

            d_angle = np.degrees(angle_p - angle0) / eps
            label = f"\u2220{elem[i_at]}{i_at+1}\u2013{elem[j_at]}{j_at+1}\u2013{elem[k_at]}{k_at+1}"
            angle_labels.append(label)
            angle_projections.append(d_angle)

all_labels = bond_labels + angle_labels
all_projs = bond_projections + [a * 0.01 for a in angle_projections]
all_types = ['bond'] * len(bond_labels) + ['angle'] * len(angle_labels)

if not all_labels:
    print("  Mode projection: no internal coordinates found")
    sys.exit(0)

order = np.argsort([abs(x) for x in all_projs])[::-1]
all_labels = [all_labels[i] for i in order]
all_projs = [all_projs[i] for i in order]
all_types = [all_types[i] for i in order]

fig, ax = plt.subplots(figsize=(max(6, len(all_labels)*0.8), 5), dpi=150)
colors = ['#c0392b' if p < 0 else '#2980b9' for p in all_projs]
bars = ax.barh(range(len(all_labels)), all_projs, color=colors, height=0.6, edgecolor='none')

ax.set_yticks(range(len(all_labels)))
ax.set_yticklabels(all_labels, fontsize=10)
ax.invert_yaxis()
ax.axvline(0, color='gray', lw=0.5)
ax.set_xlabel('Displacement projection (a.u.)', fontsize=11)
ax.set_title(f'Imaginary Mode Decomposition ({imag_freq:.0f} cm$^{{-1}}$)',
             fontsize=12, fontweight='bold')

for i, p in enumerate(all_projs):
    ha = 'left' if p >= 0 else 'right'
    offset = 0.002 if p >= 0 else -0.002
    label_t = 'stretch' if all_types[i] == 'bond' else 'bend'
    if p < 0:
        label_t = 'compress' if all_types[i] == 'bond' else 'bend'
    ax.text(p + offset, i, f' {label_t}', va='center', ha=ha, fontsize=8, color='#555')

ax.text(0.98, 0.02, f'\u03bd = {imag_freq:.1f} cm$^{{-1}}$', transform=ax.transAxes,
        ha='right', va='bottom', fontsize=10, color='#c0392b',
        bbox=dict(facecolor='#ffeaa7', alpha=0.8, edgecolor='none', boxstyle='round,pad=0.3'))

fig.tight_layout()
fig.savefig(out_png, dpi=150, bbox_inches='tight', facecolor='white')
plt.close(fig)
print(f"  Mode projection: {out_png}")
PYMODEPROJ
}

###############################################################################
# [NEW-4] NEB Convergence Diagnostics Panel
###############################################################################
generate_neb_convergence() {
  local neb_out="$1" out_png="$2"
  python3 - "$neb_out" "$out_png" <<'PYNEBCONV'
import sys, re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

neb_out = sys.argv[1]
out_png = sys.argv[2]

text = open(neb_out, encoding="utf-8", errors="ignore").read()

iters = []
for line in text.splitlines():
    parts = line.split()
    if len(parts) >= 6 and parts[0] in ('LBFGS', 'CG', 'FIRE', 'SD'):
        try:
            it = int(parts[1])
            hei = int(parts[2])
            de = float(parts[3])
            maxfp = float(parts[4])
            rmsfp = float(parts[5])
            ds = float(parts[6]) if len(parts) > 6 else 0.0
            maxfci = float(parts[7]) if len(parts) > 7 else None
            rmsfci = float(parts[8]) if len(parts) > 8 else None
            iters.append({'it': it, 'hei': hei, 'de': de, 'maxfp': maxfp,
                          'rmsfp': rmsfp, 'ds': ds, 'maxfci': maxfci, 'rmsfci': rmsfci})
        except (ValueError, IndexError):
            continue

if not iters:
    print("  NEB convergence: no iteration data found")
    sys.exit(0)

conv_m = re.search(
    r'CI-NEB convergence.*?RMS\(Fp\)\s+([\d.]+)\s+([\d.]+).*?MAX\(\|Fp\|\)\s+([\d.]+)\s+([\d.]+).*?RMS\(FCI\)\s+([\d.]+)\s+([\d.]+).*?MAX\(\|FCI\|\)\s+([\d.]+)\s+([\d.]+)',
    text, re.DOTALL)

ci_start = None
for i, d in enumerate(iters):
    if d['maxfci'] is not None:
        ci_start = i
        break

its = [d['it'] for d in iters]
maxfp = [d['maxfp'] for d in iters]
rmsfp = [d['rmsfp'] for d in iters]
de_vals = [d['de'] * 627.5094740631 for d in iters]

has_ci = any(d['maxfci'] is not None for d in iters)

fig = plt.figure(figsize=(14, 5), dpi=150)
gs = GridSpec(1, 3 if has_ci else 2, wspace=0.30)

ax1 = fig.add_subplot(gs[0])
ax1.semilogy(its, maxfp, 'o-', color='#c0392b', ms=3, lw=1.2, label='max(|Fp|)')
ax1.semilogy(its, rmsfp, 's-', color='#2980b9', ms=3, lw=1.2, label='RMS(Fp)')
ax1.axhline(0.005, color='#c0392b', ls='--', lw=0.8, alpha=0.6)
ax1.axhline(0.0025, color='#2980b9', ls='--', lw=0.8, alpha=0.6)
ax1.text(its[-1], 0.005, ' tol', va='bottom', fontsize=7, color='#c0392b')
ax1.text(its[-1], 0.0025, ' tol', va='bottom', fontsize=7, color='#2980b9')
if ci_start is not None:
    ax1.axvline(its[ci_start], color='green', ls=':', lw=1, alpha=0.7)
    ax1.text(its[ci_start], ax1.get_ylim()[1], ' CI on', fontsize=7, color='green',
             va='top', rotation=90)
ax1.set_xlabel('Iteration', fontsize=10)
ax1.set_ylabel('Force (Eh/Bohr)', fontsize=10)
ax1.set_title('Band Forces', fontsize=11, fontweight='bold')
ax1.legend(fontsize=8, loc='upper right')
ax1.tick_params(labelsize=8)

ax2 = fig.add_subplot(gs[1])
ax2.plot(its, de_vals, 'o-', color='#8e44ad', ms=3, lw=1.2)
ax2.set_xlabel('Iteration', fontsize=10)
ax2.set_ylabel('E(CI) \u2013 E(R)  (kcal/mol)', fontsize=10)
ax2.set_title('Barrier Height Convergence', fontsize=11, fontweight='bold')
if ci_start is not None:
    ax2.axvline(its[ci_start], color='green', ls=':', lw=1, alpha=0.7)
ax2.tick_params(labelsize=8)

if has_ci:
    ax3 = fig.add_subplot(gs[2])
    ci_its = [d['it'] for d in iters if d['maxfci'] is not None]
    ci_maxf = [d['maxfci'] for d in iters if d['maxfci'] is not None]
    ci_rmsf = [d['rmsfci'] for d in iters if d['rmsfci'] is not None]
    ax3.semilogy(ci_its, ci_maxf, 'o-', color='#e67e22', ms=3, lw=1.2, label='max(|FCI|)')
    ax3.semilogy(ci_its, ci_rmsf, 's-', color='#27ae60', ms=3, lw=1.2, label='RMS(FCI)')
    ax3.axhline(0.0005, color='#e67e22', ls='--', lw=0.8, alpha=0.6)
    ax3.axhline(0.00025, color='#27ae60', ls='--', lw=0.8, alpha=0.6)
    ax3.text(ci_its[-1], 0.0005, ' tol', va='bottom', fontsize=7, color='#e67e22')
    ax3.text(ci_its[-1], 0.00025, ' tol', va='bottom', fontsize=7, color='#27ae60')
    ax3.set_xlabel('Iteration', fontsize=10)
    ax3.set_ylabel('CI Force (Eh/Bohr)', fontsize=10)
    ax3.set_title('Climbing Image Forces', fontsize=11, fontweight='bold')
    ax3.legend(fontsize=8, loc='upper right')
    ax3.tick_params(labelsize=8)

fig.suptitle('NEB-CI Convergence Diagnostics', fontsize=13, fontweight='bold', y=1.02)
fig.savefig(out_png, dpi=150, bbox_inches='tight', facecolor='white')
plt.close(fig)
print(f"  NEB convergence: {out_png}")
PYNEBCONV
}

###############################################################################
# [NEW-5] IRC Animation GIF
###############################################################################
generate_irc_animation() {
  local trj_file="$1" out_dir="$2" vmd_exe="$3"
  python3 - "$trj_file" "$out_dir" "$vmd_exe" <<'PYIRCGIF'
import sys, re, subprocess, tempfile, itertools, shutil
import numpy as np
from pathlib import Path

trj_file = sys.argv[1]
out_dir  = Path(sys.argv[2])
vmd_exe  = sys.argv[3]

lines = Path(trj_file).read_text().splitlines()
frames = []
i = 0
while i < len(lines):
    line = lines[i].strip()
    if not line:
        i += 1
        continue
    try:
        natom = int(line)
    except ValueError:
        i += 1
        continue
    comment = lines[i+1] if i+1 < len(lines) else ""
    em = re.search(r'E\s+([-\d.]+)', comment)
    energy = float(em.group(1)) if em else 0.0
    atoms_data = []
    for j in range(natom):
        parts = lines[i+2+j].split()
        atoms_data.append((parts[0], float(parts[1]), float(parts[2]), float(parts[3])))
    frames.append({'energy': energy, 'atoms': atoms_data, 'raw': lines[i:i+2+natom]})
    i += 2 + natom

if len(frames) < 3:
    print("  IRC animation: too few frames")
    sys.exit(0)

energies = [f['energy'] for f in frames]
ts_idx = energies.index(max(energies))
e_ts = energies[ts_idx]
natom = len(frames[0]['atoms'])
elem = [a[0] for a in frames[0]['atoms']]

def get_coords(f):
    return np.array([[a[1], a[2], a[3]] for a in f['atoms']])

all_pairs = []
for ii, jj in itertools.combinations(range(natom), 2):
    dists = [np.linalg.norm(get_coords(f)[ii] - get_coords(f)[jj]) for f in frames]
    variation = max(dists) - min(dists)
    if variation > 0.05:
        all_pairs.append((ii, jj, variation))
all_pairs.sort(key=lambda x: -x[2])
key_pairs = [(p[0], p[1]) for p in all_pairs[:3]]

tmpdir = Path(tempfile.mkdtemp(prefix="irc_anim_"))

step = max(1, len(frames) // 40)
selected = list(range(0, len(frames), step))
if (len(frames) - 1) not in selected:
    selected.append(len(frames) - 1)
if ts_idx not in selected:
    selected.append(ts_idx)
    selected.sort()

# Li-S bond fix for VMD (same as in render_ts_three_views)
TCL_ADD_BONDS_PROC = r"""
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
""".strip().split('\n')

views = [
    ("front", ""),
    ("side",  "rotate y by 90"),
    ("top",   "rotate x by 90"),
]

for frame_num, fi in enumerate(selected):
    frame_xyz = tmpdir / f"frame_{frame_num:04d}.xyz"
    frame_xyz.write_text("\n".join(frames[fi]['raw']) + "\n")

    tcl = tmpdir / f"render_{frame_num:04d}.tcl"
    tcl_lines = [
        'display projection Orthographic',
        'display shadows off',
        'display ambientocclusion off',
        'display depthcue off',
        'color Display Background white',
        'axes location Off',
        # Optional element color overrides from env(IQCAP_ELEMENT_COLORS)
        'if {[info exists ::env(IQCAP_ELEMENT_COLORS)] && $::env(IQCAP_ELEMENT_COLORS) ne ""} {',
        '  set spec $::env(IQCAP_ELEMENT_COLORS)',
        '  regsub -all {[,;]+} $spec " " spec',
        '  set cid 32',
        '  foreach tok $spec {',
        '    if {![regexp {^([A-Za-z][A-Za-z]?)=(.+)$} $tok -> el val]} { continue }',
        '    set r ""; set g ""; set b ""',
        '    if {[regexp {^#[0-9A-Fa-f]{6}$} $val]} {',
        '      set hex [string range $val 1 end]',
        '      scan $hex "%2x%2x%2x" r8 g8 b8',
        '      set r [expr {$r8 / 255.0}]',
        '      set g [expr {$g8 / 255.0}]',
        '      set b [expr {$b8 / 255.0}]',
        '    } elseif {[regexp {^([0-9]*\\.?[0-9]+)/([0-9]*\\.?[0-9]+)/([0-9]*\\.?[0-9]+)$} $val -> rr gg bb]} {',
        '      set r $rr; set g $gg; set b $bb',
        '    } else { continue }',
        '    catch { color change rgb $cid $r $g $b }',
        '    catch { color Element $el $cid }',
        '    incr cid',
        '  }',
        '}',
    ] + TCL_ADD_BONDS_PROC + [
        f'mol new "{frame_xyz}" type xyz waitfor all',
        'if {[catch {package require topotools} err] == 0} { add_bonds_by_distance top Li S 2.8; add_bonds_by_distance top Na S 3.3; prune_same_element_bonds_beyond top B 1.6; add_bonds_by_distance top B B 1.72 }',
        'mol delrep 0 top',
        'mol representation CPK 0.8 0.3 30.0 30.0',
        'mol color Element',
        'mol selection all',
        'mol material Glossy',
        'mol addrep top',
    ]
    for vname, vrot in views:
        tga = tmpdir / f"frame_{frame_num:04d}_{vname}.tga"
        tcl_lines.append('display resetview')
        if vrot:
            tcl_lines.append(vrot)
        tcl_lines.append(f'render TachyonInternal "{tga}"')
    tcl_lines.append('quit')
    tcl.write_text("\n".join(tcl_lines) + "\n")
    subprocess.run([vmd_exe, "-dispdev", "text", "-e", str(tcl)],
                   capture_output=True, timeout=60)

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("  IRC animation: Pillow not available")
    sys.exit(0)

def _font(size=16, bold=False):
    names = (["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"] if bold
             else ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"])
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

view_frames = {v: [] for v, _ in views}
for frame_num, fi in enumerate(selected):
    imgs = {}
    for vname, _ in views:
        tga = tmpdir / f"frame_{frame_num:04d}_{vname}.tga"
        if not tga.exists():
            break
        imgs[vname] = Image.open(tga).convert("RGBA")
    if len(imgs) != len(views):
        continue

    irc_step = fi - ts_idx
    e_rel = (energies[fi] - e_ts) * 627.5094740631
    is_ts = (fi == ts_idx)
    coords_fi = get_coords(frames[fi])
    bond_strs = []
    for ii, jj in key_pairs:
        d = np.linalg.norm(coords_fi[ii] - coords_fi[jj])
        bond_strs.append(f"r({elem[ii]}{ii+1}-{elem[jj]}{jj+1})={d:.3f}\u00c5")

    for vname, _ in views:
        img = imgs[vname]
        w, h = img.size
        bar_h = max(60, int(h * 0.10))
        canvas = Image.new("RGBA", (w, h + bar_h), (255, 255, 255, 255))
        canvas.paste(img, (0, 0))
        draw = ImageDraw.Draw(canvas)

        fn_title = _font(size=max(18, int(w * 0.024)), bold=True)
        fn_data = _font(size=max(14, int(w * 0.018)))

        label_step = "TS" if is_ts else f"IRC step: {irc_step:+d}"
        label_e = f"\u0394E = {e_rel:.1f} kcal/mol"
        draw.text((10, h + 4), label_step,
                  fill=(192, 57, 43, 255) if is_ts else (30, 30, 30, 255), font=fn_title)
        draw.text((10, h + 4 + int(bar_h * 0.45)), label_e, fill=(44, 62, 80, 255), font=fn_data)

        if bond_strs:
            draw.text((w * 0.35, h + 4 + int(bar_h * 0.45)), "  ".join(bond_strs),
                      fill=(100, 100, 100, 255), font=fn_data)

        draw.text((w - 80, h + 4), vname, fill=(150, 150, 150, 255), font=fn_data)

        prog_x = int((fi / max(1, len(frames) - 1)) * (w - 20)) + 10
        draw.rectangle([10, h + bar_h - 8, w - 10, h + bar_h - 4], fill=(220, 220, 220, 255))
        draw.rectangle([10, h + bar_h - 8, prog_x, h + bar_h - 4], fill=(192, 57, 43, 255))

        view_frames[vname].append(canvas.convert("RGB"))

for vname, _ in views:
    vf = view_frames[vname]
    if not vf:
        continue
    gif_path = out_dir / f"irc_movie_{vname}.gif"
    vf[0].save(str(gif_path), save_all=True, append_images=vf[1:],
               duration=200, loop=0, optimize=True)
    print(f"  IRC animation ({vname}): {gif_path}")

shutil.rmtree(tmpdir, ignore_errors=True)
PYIRCGIF
}

###############################################################################
# Energy summary and profile plot (Python)
###############################################################################
generate_energy_summary() {
  local summary_file="$1" csv_file="$2" e_r="$3" e_ts="$4" e_p="$5" imag_freq="$6"
  python3 - "$summary_file" "$csv_file" "$e_r" "$e_ts" "$e_p" "$imag_freq" \
           "$HA_TO_EV" "$HA_TO_KCAL" "$HA_TO_KJ" <<'PYSUM'
import sys

summary_file = sys.argv[1]
csv_file     = sys.argv[2]
E_R          = float(sys.argv[3])
E_TS         = float(sys.argv[4])
E_P          = float(sys.argv[5])
imag_freq    = sys.argv[6]
HA2EV        = float(sys.argv[7])
HA2KCAL      = float(sys.argv[8])
HA2KJ        = float(sys.argv[9])

dE_fwd_ha  = E_TS - E_R
dE_rev_ha  = E_TS - E_P
dE_rxn_ha  = E_P  - E_R

def conv(ha):
    return ha, ha * HA2EV, ha * HA2KCAL, ha * HA2KJ

lines = []
lines.append("=" * 90)
lines.append("  ENERGY SUMMARY  --  Transition State & Reaction Path Analysis")
lines.append("=" * 90)
lines.append("")
lines.append(f"  Imaginary frequency: {imag_freq} cm-1")
lines.append("")
lines.append(f"  {'':20s} {'Hartree':>16s} {'eV':>14s} {'kcal/mol':>14s} {'kJ/mol':>14s}")
lines.append(f"  {'-'*20} {'-'*16} {'-'*14} {'-'*14} {'-'*14}")

for label, E in [("Reactant", E_R), ("Transition State", E_TS), ("Product", E_P)]:
    ha, ev, kcal, kj = conv(E)
    lines.append(f"  {label:20s} {ha:16.10f} {ev:14.6f} {kcal:14.4f} {kj:14.4f}")

lines.append("")
lines.append(f"  {'':20s} {'Hartree':>16s} {'eV':>14s} {'kcal/mol':>14s} {'kJ/mol':>14s}")
lines.append(f"  {'-'*20} {'-'*16} {'-'*14} {'-'*14} {'-'*14}")

for label, dE in [
    ("dE_fwd (R->TS)", dE_fwd_ha),
    ("dE_rev (P->TS)", dE_rev_ha),
    ("dE_rxn (R->P)",  dE_rxn_ha),
]:
    ha, ev, kcal, kj = conv(dE)
    lines.append(f"  {label:20s} {ha:16.10f} {ev:14.6f} {kcal:14.4f} {kj:14.4f}")

lines.append("")
lines.append("=" * 90)

summary = "\n".join(lines)
print(summary)

with open(summary_file, "w") as f:
    f.write(summary + "\n")

with open(csv_file, "w") as f:
    f.write("species,E_Hartree,E_eV,E_kcal_mol,E_kJ_mol\n")
    for label, E in [("reactant", E_R), ("ts", E_TS), ("product", E_P)]:
        ha, ev, kcal, kj = conv(E)
        f.write(f"{label},{ha:.12f},{ev:.8f},{kcal:.6f},{kj:.6f}\n")
    f.write("\n")
    f.write("barrier,dE_Hartree,dE_eV,dE_kcal_mol,dE_kJ_mol\n")
    for label, dE in [("forward", dE_fwd_ha), ("reverse", dE_rev_ha), ("reaction", dE_rxn_ha)]:
        ha, ev, kcal, kj = conv(dE)
        f.write(f"{label},{ha:.12f},{ev:.8f},{kcal:.6f},{kj:.6f}\n")

print(f"\n  Summary: {summary_file}")
print(f"  CSV:     {csv_file}")
PYSUM
}

###############################################################################
# Publication-quality energy profile plot
###############################################################################
generate_energy_profile_plot() {
  local plot_file="$1" e_r="$2" e_ts="$3" e_p="$4" imag_freq="$5"
  python3 - "$plot_file" "$e_r" "$e_ts" "$e_p" "$imag_freq" \
           "$HA_TO_KCAL" "$HA_TO_KJ" <<'PYPLOT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

out_png    = sys.argv[1]
E_R        = float(sys.argv[2])
E_TS       = float(sys.argv[3])
E_P        = float(sys.argv[4])
imag_freq  = sys.argv[5]
HA2KCAL    = float(sys.argv[6])
HA2KJ      = float(sys.argv[7])

dE_fwd = (E_TS - E_R) * HA2KCAL
dE_rev = (E_TS - E_P) * HA2KCAL
dE_rxn = (E_P  - E_R) * HA2KCAL
dE_P   = dE_rxn

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

fig, ax = plt.subplots(figsize=(10, 7), dpi=300)

x_R, x_TS, x_P = 1.0, 3.0, 5.0
lw_level = 0.4

COL_R  = '#2244AA'
COL_TS = '#CC3333'
COL_P  = '#228B22'

ax.plot([x_R - lw_level, x_R + lw_level], [0, 0],
        color=COL_R, lw=4.5, solid_capstyle='round', zorder=5)
ax.plot([x_TS - lw_level, x_TS + lw_level], [dE_fwd, dE_fwd],
        color=COL_TS, lw=4.5, solid_capstyle='round', zorder=5)
ax.plot([x_P - lw_level, x_P + lw_level], [dE_P, dE_P],
        color=COL_P, lw=4.5, solid_capstyle='round', zorder=5)

t = np.linspace(0, 1, 300)
a_coeff = 4 * dE_P
b_coeff = -4 * (dE_P + dE_fwd)
c_coeff = dE_P + 4 * dE_fwd
y_curve = a_coeff * t**3 + b_coeff * t**2 + c_coeff * t
x_curve = x_R + (x_P - x_R) * t
ax.plot(x_curve, y_curve, '--', color='#888888', lw=1.8, alpha=0.6, zorder=2)

ax.text(x_R, -0.06 * abs(dE_fwd) - 2.0, 'Reactant', ha='center', fontsize=18,
        fontweight='bold', color=COL_R)
ax.text(x_TS, dE_fwd + 0.04 * abs(dE_fwd) + 1.5, 'TS', ha='center', fontsize=18,
        fontweight='bold', color=COL_TS)
ax.text(x_P, dE_P - 0.06 * abs(dE_fwd) - 2.0, 'Product', ha='center', fontsize=18,
        fontweight='bold', color=COL_P)

arr_x = 2.0
ax.annotate('', xy=(arr_x, dE_fwd), xytext=(arr_x, 0),
            arrowprops=dict(arrowstyle='<->', color=COL_TS, lw=2.2, shrinkA=2, shrinkB=2))
mid_fwd = dE_fwd * 0.5
ax.text(arr_x - 0.12, mid_fwd,
        f'$\\Delta E^\\ddagger$ = {dE_fwd:.1f}\nkcal/mol\n({dE_fwd * HA2KJ / HA2KCAL:.1f} kJ/mol)',
        ha='right', va='center', fontsize=13, fontweight='bold', color=COL_TS,
        bbox=dict(boxstyle='round,pad=0.2', fc='white', ec='none', alpha=0.85))

arr_x2 = 4.0
ax.annotate('', xy=(arr_x2, dE_fwd), xytext=(arr_x2, dE_P),
            arrowprops=dict(arrowstyle='<->', color='#8B4513', lw=2.2, shrinkA=2, shrinkB=2))
mid_rev = (dE_fwd + dE_P) * 0.5
ax.text(arr_x2 + 0.12, mid_rev,
        f'$\\Delta E^\\ddagger_{{rev}}$ = {dE_rev:.1f}\nkcal/mol\n({dE_rev * HA2KJ / HA2KCAL:.1f} kJ/mol)',
        ha='left', va='center', fontsize=13, fontweight='bold', color='#8B4513',
        bbox=dict(boxstyle='round,pad=0.2', fc='white', ec='none', alpha=0.85))

if abs(dE_P) > 0.5:
    arr_x3 = 5.6
    y_lo, y_hi = (0, dE_P) if dE_P > 0 else (dE_P, 0)
    ax.annotate('', xy=(arr_x3, y_hi), xytext=(arr_x3, y_lo),
                arrowprops=dict(arrowstyle='<->', color='#555555', lw=1.8, shrinkA=2, shrinkB=2))
    ax.text(arr_x3 + 0.12, (y_lo + y_hi) / 2,
            f'$\\Delta E_{{rxn}}$ = {dE_rxn:.1f}\nkcal/mol',
            ha='left', va='center', fontsize=12, color='#555555',
            bbox=dict(boxstyle='round,pad=0.15', fc='white', ec='none', alpha=0.85))

ax.text(0.02, 0.02,
        f'$\\nu_1$ = {imag_freq} cm$^{{-1}}$',
        transform=ax.transAxes, fontsize=13, color='#666666',
        style='italic', va='bottom')

e_pad = max(5, abs(dE_fwd) * 0.2)
y_lo_lim = min(0, dE_P) - e_pad
y_hi_lim = dE_fwd + e_pad
ax.set_ylim(y_lo_lim, y_hi_lim)
ax.set_xlim(0.0, 6.5)

ax.set_ylabel('Relative energy (kcal/mol)', fontsize=22, fontweight='bold')
ax.set_xlabel('Reaction coordinate', fontsize=22, fontweight='bold')
ax.set_xticks([])
ax.tick_params(axis='y', labelsize=18)
ax.tick_params(axis='both', width=2.0, length=6)
for spine in ax.spines.values():
    spine.set_linewidth(2.0)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['bottom'].set_visible(False)

ax.set_title('Energy Profile', fontsize=28, fontweight='bold', pad=18)
ax.axhline(y=0, color='#CCCCCC', lw=0.8, ls=':', zorder=1)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  Energy profile: {out_png}")
PYPLOT
}

###############################################################################
# Publication-quality energy profile plot (eV-only)
###############################################################################
generate_energy_profile_plot_ev() {
  local plot_file="$1" e_r="$2" e_ts="$3" e_p="$4" imag_freq="$5"
  python3 - "$plot_file" "$e_r" "$e_ts" "$e_p" "$imag_freq" \
     "$HA_TO_EV" <<'PYPLOTEV'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

out_png    = sys.argv[1]
E_R        = float(sys.argv[2])
E_TS       = float(sys.argv[3])
E_P        = float(sys.argv[4])
imag_freq  = sys.argv[5]
HA2EV      = float(sys.argv[6])

dE_fwd = (E_TS - E_R) * HA2EV
dE_rev = (E_TS - E_P) * HA2EV
dE_rxn = (E_P  - E_R) * HA2EV
dE_P   = dE_rxn

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

fig, ax = plt.subplots(figsize=(10, 7), dpi=300)

x_R, x_TS, x_P = 1.0, 3.0, 5.0
lw_level = 0.4

COL_R  = '#2244AA'
COL_TS = '#CC3333'
COL_P  = '#228B22'

ax.plot([x_R - lw_level, x_R + lw_level], [0, 0],
  color=COL_R, lw=4.5, solid_capstyle='round', zorder=5)
ax.plot([x_TS - lw_level, x_TS + lw_level], [dE_fwd, dE_fwd],
  color=COL_TS, lw=4.5, solid_capstyle='round', zorder=5)
ax.plot([x_P - lw_level, x_P + lw_level], [dE_P, dE_P],
  color=COL_P, lw=4.5, solid_capstyle='round', zorder=5)

t = np.linspace(0, 1, 300)
a_coeff = 4 * dE_P
b_coeff = -4 * (dE_P + dE_fwd)
c_coeff = dE_P + 4 * dE_fwd
y_curve = a_coeff * t**3 + b_coeff * t**2 + c_coeff * t
x_curve = x_R + (x_P - x_R) * t
ax.plot(x_curve, y_curve, '--', color='#888888', lw=1.8, alpha=0.6, zorder=2)

ax.text(x_R, -0.06 * abs(dE_fwd) - 0.10, 'Reactant', ha='center', fontsize=18,
  fontweight='bold', color=COL_R)
ax.text(x_TS, dE_fwd + 0.04 * abs(dE_fwd) + 0.08, 'TS', ha='center', fontsize=18,
  fontweight='bold', color=COL_TS)
ax.text(x_P, dE_P - 0.06 * abs(dE_fwd) - 0.10, 'Product', ha='center', fontsize=18,
  fontweight='bold', color=COL_P)

arr_x = 2.0
ax.annotate('', xy=(arr_x, dE_fwd), xytext=(arr_x, 0),
      arrowprops=dict(arrowstyle='<->', color=COL_TS, lw=2.2, shrinkA=2, shrinkB=2))
mid_fwd = dE_fwd * 0.5
ax.text(arr_x - 0.12, mid_fwd,
  f'$\\Delta E^\\ddagger$ = {dE_fwd:.3f} eV',
  ha='right', va='center', fontsize=13, fontweight='bold', color=COL_TS,
  bbox=dict(boxstyle='round,pad=0.2', fc='white', ec='none', alpha=0.85))

arr_x2 = 4.0
ax.annotate('', xy=(arr_x2, dE_fwd), xytext=(arr_x2, dE_P),
      arrowprops=dict(arrowstyle='<->', color='#8B4513', lw=2.2, shrinkA=2, shrinkB=2))
mid_rev = (dE_fwd + dE_P) * 0.5
ax.text(arr_x2 + 0.12, mid_rev,
  f'$\\Delta E^\\ddagger_{{rev}}$ = {dE_rev:.3f} eV',
  ha='left', va='center', fontsize=13, fontweight='bold', color='#8B4513',
  bbox=dict(boxstyle='round,pad=0.2', fc='white', ec='none', alpha=0.85))

if abs(dE_P) > 0.02:
    arr_x3 = 5.6
    y_lo, y_hi = (0, dE_P) if dE_P > 0 else (dE_P, 0)
    ax.annotate('', xy=(arr_x3, y_hi), xytext=(arr_x3, y_lo),
    arrowprops=dict(arrowstyle='<->', color='#555555', lw=1.8, shrinkA=2, shrinkB=2))
    ax.text(arr_x3 + 0.12, (y_lo + y_hi) / 2,
      f'$\\Delta E_{{rxn}}$ = {dE_rxn:.3f} eV',
      ha='left', va='center', fontsize=12, color='#555555',
      bbox=dict(boxstyle='round,pad=0.15', fc='white', ec='none', alpha=0.85))

ax.text(0.02, 0.02,
  f'$\\nu_1$ = {imag_freq} cm$^{{-1}}$',
  transform=ax.transAxes, fontsize=13, color='#666666',
  style='italic', va='bottom')

e_pad = max(0.18, abs(dE_fwd) * 0.2)
y_lo_lim = min(0, dE_P) - e_pad
y_hi_lim = dE_fwd + e_pad
ax.set_ylim(y_lo_lim, y_hi_lim)
ax.set_xlim(0.0, 6.5)

ax.set_ylabel('Relative energy (eV)', fontsize=22, fontweight='bold')
ax.set_xlabel('Reaction coordinate', fontsize=22, fontweight='bold')
ax.set_xticks([])
ax.tick_params(axis='y', labelsize=18)
ax.tick_params(axis='both', width=2.0, length=6)
for spine in ax.spines.values():
    spine.set_linewidth(2.0)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['bottom'].set_visible(False)

ax.set_title('Energy Profile', fontsize=28, fontweight='bold', pad=18)
ax.axhline(y=0, color='#CCCCCC', lw=0.8, ls=':', zorder=1)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  Energy profile (eV): {out_png}")
PYPLOTEV
}

###############################################################################
# IRC path plot
###############################################################################
generate_irc_path_plot() {
  local data_file="$1" plot_file="$2"
  python3 - "$data_file" "$plot_file" <<'PYIRCPLOT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

data_file = sys.argv[1]
out_png   = sys.argv[2]

HA2KCAL = 627.5094740631

directions, steps, energies = [], [], []
with open(data_file) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 3:
            directions.append(parts[0])
            steps.append(int(parts[1]))
            energies.append(float(parts[2]))

if not energies:
    print("  No IRC data available for plotting.")
    sys.exit(0)

E_TS = energies[0]
for i, d in enumerate(directions):
    if d == "forward" and steps[i] == 0:
        E_TS = energies[i]
        break

rel_E = [(e - E_TS) * HA2KCAL for e in energies]

bwd_x, bwd_y = [], []
fwd_x, fwd_y = [], []
for i, d in enumerate(directions):
    if d == "backward":
        bwd_x.append(-steps[i])
        bwd_y.append(rel_E[i])
    else:
        fwd_x.append(steps[i])
        fwd_y.append(rel_E[i])

x_all = sorted(bwd_x) + sorted(fwd_x)
y_all = [bwd_y[bwd_x.index(x)] if x in bwd_x else fwd_y[fwd_x.index(x)] for x in x_all]

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

fig, ax = plt.subplots(figsize=(10, 6), dpi=300)

ax.plot(x_all, y_all, 'o-', color='#CC3333', lw=2.0, markersize=5, markerfacecolor='white',
        markeredgecolor='#CC3333', markeredgewidth=1.5, zorder=5)

ax.axhline(y=0, color='#AAAAAA', lw=1.0, ls='--', zorder=1)
ax.axvline(x=0, color='#AAAAAA', lw=1.0, ls=':', zorder=1)

ax.set_xlabel('IRC step (backward \u2190 TS \u2192 forward)', fontsize=20, fontweight='bold')
ax.set_ylabel('Relative energy (kcal/mol)', fontsize=20, fontweight='bold')
ax.set_title('IRC Path', fontsize=26, fontweight='bold', pad=16)
ax.tick_params(labelsize=16)
ax.tick_params(axis='both', width=2.0, length=6)
for spine in ax.spines.values():
    spine.set_linewidth(2.0)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  IRC path plot: {out_png}")
PYIRCPLOT
}

###############################################################################
# Pre-checks
###############################################################################
if [[ "$PLOT_ONLY" -eq 0 ]]; then
  [[ -f "$REACTANT_XYZ" ]] || { echo "Reactant file not found: $REACTANT_XYZ" >&2; exit 1; }
  [[ -f "$PRODUCT_XYZ" ]]  || { echo "Product file not found: $PRODUCT_XYZ" >&2; exit 1; }

  if [[ "$RUN_NEB" -eq 0 && -z "$TS_GUESS_XYZ" && "$RUN_OPTTS" -eq 1 ]]; then
    echo "ERROR: --no-neb requires --ts-guess (or --no-optts)" >&2
    exit 1
  fi

  if [[ -n "$TS_GUESS_XYZ" ]]; then
    [[ -f "$TS_GUESS_XYZ" ]] || { echo "TS guess file not found: $TS_GUESS_XYZ" >&2; exit 1; }
    RUN_NEB=0
  fi

  ORCA_EXE="$(resolve_bin_any "$ORCA_BIN" "orca")" || {
    echo "Cannot find ORCA executable" >&2; exit 1
  }
fi

if [[ "$RUN_TS_RENDER" -eq 1 || "$RUN_TS_TRAJ_OVERLAY" -eq 1 || "$RUN_CINEB_OVERLAY" -eq 1 ]]; then
  VMD_EXE="$(resolve_bin_any "$VMD_BIN" "vmd" "VMD")" || {
    echo "Cannot find VMD executable" >&2; exit 1
  }
  python3 -c "from PIL import Image" >/dev/null 2>&1 || {
    echo "ERROR: Python Pillow required. Install: pip install Pillow" >&2; exit 1
  }
fi

if [[ "$RUN_EPROFILE" -eq 1 || "$RUN_IRC_PLOT" -eq 1 || "$RUN_CINEB_IMAGE_PLOT" -eq 1 ]]; then
  python3 -c "import matplotlib" >/dev/null 2>&1 || {
    echo "ERROR: Python matplotlib required. Install: pip install matplotlib" >&2; exit 1
  }
fi

BASE_NAME="$(basename "$PWD")"
PLOTS_DIR="${BASE_NAME}-PLOTS"

echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " $IQCAP_FULLNAME"
echo " Module: $IQCAP_MODULE (Transition State & Reaction Path Analysis)"
echo "========================================"
[[ "$PLOT_ONLY" -eq 1 ]] && echo "  Mode:      plot-only (no computation)" || echo "  ORCA:      $ORCA_EXE"
[[ "$RUN_TS_RENDER" -eq 1 || "$RUN_TS_TRAJ_OVERLAY" -eq 1 || "$RUN_CINEB_OVERLAY" -eq 1 ]] && echo "  VMD:       $VMD_EXE"
echo "  Working:   $PWD"
echo "  Reactant:  $REACTANT_XYZ"
echo "  Product:   $PRODUCT_XYZ"
[[ -n "$TS_GUESS_XYZ" ]] && echo "  TS guess:  $TS_GUESS_XYZ"
[[ -n "$FREE_ATOMS" ]] && echo "  Free atoms: $FREE_ATOMS"
echo "  Charge:    $CHARGE    Mult: $MULT"
echo "  Method:    $METHOD  (OPT: $OPT_LEVEL)"
[[ "$SP_REFINE_LEVEL" != "$OPT_LEVEL tightSCF" ]] && echo "  SP  level: $SP_REFINE_LEVEL"
if [[ "$PLOT_ONLY" -eq 1 ]]; then
  echo "  Endpoints: plot-only"
elif [[ "$RUN_OPT_ENDPOINTS" -eq 1 ]]; then
  echo "  Endpoints: ORCA geometry optimization"
else
  echo "  Endpoints: skipped (input XYZ → NEB)"
fi
echo "  NEB:       $( [[ "$RUN_NEB" -eq 1 ]] && echo "ON ($NEB_METHOD, $NEB_NIMAGES images)" || echo OFF )"
echo "  OptTS:     $( [[ "$RUN_OPTTS" -eq 1 ]] && echo ON || echo OFF )"
echo "  Freq:      $( [[ "$RUN_FREQ" -eq 1 ]] && echo ON || echo OFF )"
echo "  IRC:       $( [[ "$RUN_IRC" -eq 1 ]] && echo ON || echo OFF )"
echo "  SP refine: $( [[ "$RUN_SP_REFINE" -eq 1 ]] && echo ON || echo OFF )"
echo "========================================"

###############################################################################
# 1) Endpoint optimization (optional)
###############################################################################
REACTANT_OPT="$REACTANT_XYZ"
PRODUCT_OPT="$PRODUCT_XYZ"

if [[ "$PLOT_ONLY" -eq 1 ]]; then
  echo ""
  echo "[*] --plot-only: skipping computation, re-rendering from existing data..."
  TS_DIR="TS"
  [[ -f "$TS_DIR/ts.xyz" ]] && TS_OPT_XYZ="$TS_DIR/ts.xyz"
  [[ -f "OPT-R/opt_r.xyz" ]] && REACTANT_OPT="OPT-R/opt_r.xyz"
  [[ -f "OPT-P/opt_p.xyz" ]] && PRODUCT_OPT="OPT-P/opt_p.xyz"
fi

if [[ "$RUN_OPT_ENDPOINTS" -eq 1 && "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== Endpoint Geometry Optimization ====="

  OPT_R_DIR="OPT-R"
  mkdir -p "$OPT_R_DIR"
  echo "[*] Optimizing reactant..."
  write_orca_opt_input "$OPT_R_DIR/opt_r.inp" "$OPT_LEVEL" "$CHARGE" "$MULT" "$REACTANT_XYZ"
  pushd "$OPT_R_DIR" >/dev/null
  "$ORCA_EXE" opt_r.inp > opt_r.out 2>&1
  popd >/dev/null
  if check_orca_success "$OPT_R_DIR/opt_r.out" "reactant" && \
     check_opt_convergence "$OPT_R_DIR/opt_r.out" "reactant"; then
    [[ -f "$OPT_R_DIR/opt_r.xyz" ]] && REACTANT_OPT="$OPT_R_DIR/opt_r.xyz"
    echo "  Reactant optimized: $REACTANT_OPT"
  else
    echo "  WARNING: Using original reactant structure"
  fi

  OPT_P_DIR="OPT-P"
  mkdir -p "$OPT_P_DIR"
  echo "[*] Optimizing product..."
  write_orca_opt_input "$OPT_P_DIR/opt_p.inp" "$OPT_LEVEL" "$CHARGE" "$MULT" "$PRODUCT_XYZ"
  pushd "$OPT_P_DIR" >/dev/null
  "$ORCA_EXE" opt_p.inp > opt_p.out 2>&1
  popd >/dev/null
  if check_orca_success "$OPT_P_DIR/opt_p.out" "product" && \
     check_opt_convergence "$OPT_P_DIR/opt_p.out" "product"; then
    [[ -f "$OPT_P_DIR/opt_p.xyz" ]] && PRODUCT_OPT="$OPT_P_DIR/opt_p.xyz"
    echo "  Product optimized:  $PRODUCT_OPT"
  else
    echo "  WARNING: Using original product structure"
  fi
else
  echo ""
  if [[ "$PLOT_ONLY" -eq 1 ]]; then
    echo "[*] Endpoint optimization skipped (--plot-only)"
  elif [[ "$RUN_OPT_ENDPOINTS" -eq 0 ]]; then
    echo "[*] Skipping endpoint optimization; using $REACTANT_XYZ and $PRODUCT_XYZ for NEB (--skip-opt-endpoints / --no-endpoint-opt)"
  else
    echo "[*] Skipping endpoint optimization"
  fi
fi

###############################################################################
# 2) NEB path search
###############################################################################
TS_XYZ=""

if [[ "$RUN_NEB" -eq 1 && "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== NEB Path Search ($NEB_METHOD, $NEB_NIMAGES images) ====="

  NEB_DIR="NEB"
  mkdir -p "$NEB_DIR"

  cp "$REACTANT_OPT" "$NEB_DIR/reactant.xyz"
  cp "$PRODUCT_OPT"  "$NEB_DIR/product.xyz"

  FREE_ATOMS_NEB_CONSTRAINTS_BLOCK=""
  if [[ -n "$FREE_ATOMS" ]]; then
    FREE_ATOMS_NEB_FIXED_ZERO="$(build_fixed_zero_based "$NEB_DIR/reactant.xyz" free "$FREE_ATOMS")"
    FREE_ATOMS_NEB_CONSTRAINTS_BLOCK="$(make_constraints_block "$FREE_ATOMS_NEB_FIXED_ZERO")"
    if [[ -n "$FREE_ATOMS_NEB_FIXED_ZERO" ]]; then
      echo "[*] NEB free atoms: $FREE_ATOMS (freeze all other atoms)"
    else
      echo "[*] NEB free atoms: $FREE_ATOMS (no atoms need freezing)"
    fi
  fi

  write_orca_neb_input "$NEB_DIR/neb.inp" "$OPT_LEVEL" "$CHARGE" "$MULT" \
                       "reactant.xyz" "product.xyz" "$NEB_METHOD" "$NEB_NIMAGES" "$NEB_MAXITER" \
                       "$FREE_ATOMS_NEB_CONSTRAINTS_BLOCK"

  echo "[*] Running ORCA $NEB_METHOD (this may take a while)..."
  pushd "$NEB_DIR" >/dev/null
  "$ORCA_EXE" neb.inp > neb.out 2>&1
  popd >/dev/null

  if check_orca_success "$NEB_DIR/neb.out" "NEB"; then
    echo "[*] Extracting TS guess from NEB result..."
    extract_neb_ts_guess "$NEB_DIR" "$NEB_DIR/ts_guess_neb.xyz"
    if [[ -f "$NEB_DIR/ts_guess_neb.xyz" ]]; then
      TS_XYZ="$NEB_DIR/ts_guess_neb.xyz"
      echo "  TS guess: $TS_XYZ"
    else
      echo "  ERROR: Failed to extract TS guess from NEB" >&2
      exit 1
    fi
  else
    echo "  ERROR: NEB calculation failed" >&2
    exit 1
  fi
elif [[ -n "$TS_GUESS_XYZ" ]]; then
  TS_XYZ="$TS_GUESS_XYZ"
  echo ""
  echo "[*] Using provided TS guess: $TS_XYZ"
fi

###############################################################################
# 3) TS optimization + frequency calculation
###############################################################################
TS_OPT_XYZ=""
IMAG_FREQ=""
TS_ENERGY=""

if [[ "$RUN_OPTTS" -eq 1 && -n "$TS_XYZ" && "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== TS Optimization + Frequency Verification ====="

  TS_DIR="TS"
  mkdir -p "$TS_DIR"

  FREE_ATOMS_CONSTRAINTS_BLOCK=""
  if [[ -n "$FREE_ATOMS" ]]; then
    FREE_ATOMS_FIXED_ZERO="$(build_fixed_zero_based "$TS_XYZ" free "$FREE_ATOMS")"
    FREE_ATOMS_CONSTRAINTS_BLOCK="$(make_constraints_block "$FREE_ATOMS_FIXED_ZERO")"
    if [[ -n "$FREE_ATOMS_FIXED_ZERO" ]]; then
      echo "[*] TS free atoms: $FREE_ATOMS (freeze all other atoms)"
    else
      echo "[*] TS free atoms: $FREE_ATOMS (no atoms need freezing)"
    fi
  fi

  write_orca_optts_freq_input "$TS_DIR/ts.inp" "$OPT_LEVEL" "$CHARGE" "$MULT" "$TS_XYZ" "$FREE_ATOMS_CONSTRAINTS_BLOCK"

  echo "[*] Running ORCA OptTS + NumFreq..."
  pushd "$TS_DIR" >/dev/null
  "$ORCA_EXE" ts.inp > ts.out 2>&1
  popd >/dev/null

  if check_orca_success "$TS_DIR/ts.out" "OptTS"; then
    if check_opt_convergence "$TS_DIR/ts.out" "TS"; then
      [[ -f "$TS_DIR/ts.xyz" ]] && TS_OPT_XYZ="$TS_DIR/ts.xyz"
      TS_ENERGY="$(extract_final_energy "$TS_DIR/ts.out")"
      echo "  TS optimized: $TS_OPT_XYZ"
      echo "  TS energy:    $TS_ENERGY Eh"
    fi

    if [[ "$RUN_FREQ" -eq 1 ]]; then
      echo "[*] Parsing frequency results..."
      FREQ_RESULT="$(parse_frequencies "$TS_DIR/ts.out")"
      echo "$FREQ_RESULT"

      IMAG_FREQ="$(echo "$FREQ_RESULT" | grep "FREQ_IMAGINARY=" | head -1 | cut -d: -f2 || echo "")"
      FREQ_STATUS="$(echo "$FREQ_RESULT" | grep "FREQ_STATUS=" | cut -d= -f2 || echo "UNKNOWN")"

      if [[ "$FREQ_STATUS" == "OK" ]]; then
        echo "  Single imaginary frequency confirmed: $IMAG_FREQ cm-1"
      elif [[ "$FREQ_STATUS" == "NO_IMAG" ]]; then
        echo "  WARNING: No imaginary frequency found. This may not be a true TS." >&2
      elif [[ "$FREQ_STATUS" == "MULTI_IMAG" ]]; then
        echo "  WARNING: Multiple imaginary frequencies found. Higher-order saddle point." >&2
      fi
    fi
  else
    echo "  ERROR: TS optimization failed" >&2
    echo "  Check $TS_DIR/ts.out for details" >&2
  fi
elif [[ "$RUN_OPTTS" -eq 0 && -n "$TS_XYZ" && "$PLOT_ONLY" -eq 0 ]]; then
  TS_OPT_XYZ="$TS_XYZ"
  echo ""
  echo "[*] Skipping TS optimization (--no-optts), using: $TS_OPT_XYZ"
fi

###############################################################################
# 4) IRC calculation
###############################################################################
if [[ "$RUN_IRC" -eq 1 && -n "$TS_OPT_XYZ" && "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== IRC Path Tracing (both directions) ====="

  IRC_DIR="IRC"
  mkdir -p "$IRC_DIR"

  write_orca_irc_input "$IRC_DIR/irc.inp" "$OPT_LEVEL" "$CHARGE" "$MULT" "$TS_OPT_XYZ" \
                       "$IRC_MAXITER" "$IRC_STEPSIZE" "$IRC_MAXDISP"

  if [[ -n "${TS_DIR:-}" && -f "$TS_DIR/ts.hess" ]]; then
    cp "$TS_DIR/ts.hess" "$IRC_DIR/irc.hess"
    echo "  Copied Hessian from TS calculation"
  else
    echo "  WARNING: No .hess file found. IRC will calculate its own Hessian." >&2
    sed -i 's/InitHess  read/InitHess  calc_numfreq/' "$IRC_DIR/irc.inp"
  fi

  echo "[*] Running ORCA IRC..."
  pushd "$IRC_DIR" >/dev/null
  "$ORCA_EXE" irc.inp > irc.out 2>&1
  popd >/dev/null

  if check_orca_success "$IRC_DIR/irc.out" "IRC"; then
    echo "[*] Parsing IRC path..."
    parse_irc_path "$IRC_DIR/irc.out" "$IRC_DIR/irc_energies.dat"

    shopt -s nullglob
    IRC_FWD_TRJ=( "$IRC_DIR"/irc*IRC_F*trj*.xyz "$IRC_DIR"/irc*forward*trj*.xyz )
    IRC_BWD_TRJ=( "$IRC_DIR"/irc*IRC_B*trj*.xyz "$IRC_DIR"/irc*backward*trj*.xyz )
    shopt -u nullglob

    if [[ ${#IRC_FWD_TRJ[@]} -gt 0 ]]; then
      extract_last_xyz_frame "${IRC_FWD_TRJ[0]}" "$IRC_DIR/irc_fwd_endpoint.xyz"
      echo "  Forward endpoint: $IRC_DIR/irc_fwd_endpoint.xyz"
    fi
    if [[ ${#IRC_BWD_TRJ[@]} -gt 0 ]]; then
      extract_last_xyz_frame "${IRC_BWD_TRJ[0]}" "$IRC_DIR/irc_bwd_endpoint.xyz"
      echo "  Backward endpoint: $IRC_DIR/irc_bwd_endpoint.xyz"
    fi
  else
    echo "  WARNING: IRC calculation may have issues" >&2
    echo "  Check $IRC_DIR/irc.out for details" >&2
  fi
fi

###############################################################################
# 5) Single-point energy refinement
###############################################################################
E_R_FINAL=""
E_TS_FINAL=""
E_P_FINAL=""

if [[ "$RUN_SP_REFINE" -eq 1 && "$PLOT_ONLY" -eq 0 ]]; then
  echo ""
  echo "[*] ===== Single-Point Energy Refinement ====="
  echo "  SP level: $SP_REFINE_LEVEL"

  SP_DIR="SP-REFINE"
  mkdir -p "$SP_DIR"

  echo "[*] SP on reactant..."
  write_orca_sp_input "$SP_DIR/sp_r.inp" "$SP_REFINE_LEVEL" "$CHARGE" "$MULT" "$REACTANT_OPT"
  pushd "$SP_DIR" >/dev/null
  "$ORCA_EXE" sp_r.inp > sp_r.out 2>&1
  popd >/dev/null
  if check_orca_success "$SP_DIR/sp_r.out" "SP reactant"; then
    E_R_FINAL="$(extract_final_energy "$SP_DIR/sp_r.out")"
    echo "  E(R)  = $E_R_FINAL Eh"
  fi

  if [[ -n "$TS_OPT_XYZ" ]]; then
    echo "[*] SP on TS..."
    write_orca_sp_input "$SP_DIR/sp_ts.inp" "$SP_REFINE_LEVEL" "$CHARGE" "$MULT" "$TS_OPT_XYZ"
    pushd "$SP_DIR" >/dev/null
    "$ORCA_EXE" sp_ts.inp > sp_ts.out 2>&1
    popd >/dev/null
    if check_orca_success "$SP_DIR/sp_ts.out" "SP TS"; then
      E_TS_FINAL="$(extract_final_energy "$SP_DIR/sp_ts.out")"
      echo "  E(TS) = $E_TS_FINAL Eh"
    fi
  fi

  echo "[*] SP on product..."
  write_orca_sp_input "$SP_DIR/sp_p.inp" "$SP_REFINE_LEVEL" "$CHARGE" "$MULT" "$PRODUCT_OPT"
  pushd "$SP_DIR" >/dev/null
  "$ORCA_EXE" sp_p.inp > sp_p.out 2>&1
  popd >/dev/null
  if check_orca_success "$SP_DIR/sp_p.out" "SP product"; then
    E_P_FINAL="$(extract_final_energy "$SP_DIR/sp_p.out")"
    echo "  E(P)  = $E_P_FINAL Eh"
  fi

  if [[ -n "${IRC_DIR:-}" && -f "${IRC_DIR}/irc_fwd_endpoint.xyz" ]]; then
    echo "[*] SP on IRC forward endpoint..."
    write_orca_sp_input "$SP_DIR/sp_irc_fwd.inp" "$SP_REFINE_LEVEL" "$CHARGE" "$MULT" \
                        "$IRC_DIR/irc_fwd_endpoint.xyz"
    pushd "$SP_DIR" >/dev/null
    "$ORCA_EXE" sp_irc_fwd.inp > sp_irc_fwd.out 2>&1
    popd >/dev/null
    if check_orca_success "$SP_DIR/sp_irc_fwd.out" "SP IRC fwd"; then
      E_IRC_FWD="$(extract_final_energy "$SP_DIR/sp_irc_fwd.out")"
      echo "  E(IRC fwd endpoint) = $E_IRC_FWD Eh"
    fi
  fi

  if [[ -n "${IRC_DIR:-}" && -f "${IRC_DIR}/irc_bwd_endpoint.xyz" ]]; then
    echo "[*] SP on IRC backward endpoint..."
    write_orca_sp_input "$SP_DIR/sp_irc_bwd.inp" "$SP_REFINE_LEVEL" "$CHARGE" "$MULT" \
                        "$IRC_DIR/irc_bwd_endpoint.xyz"
    pushd "$SP_DIR" >/dev/null
    "$ORCA_EXE" sp_irc_bwd.inp > sp_irc_bwd.out 2>&1
    popd >/dev/null
    if check_orca_success "$SP_DIR/sp_irc_bwd.out" "SP IRC bwd"; then
      E_IRC_BWD="$(extract_final_energy "$SP_DIR/sp_irc_bwd.out")"
      echo "  E(IRC bwd endpoint) = $E_IRC_BWD Eh"
    fi
  fi
fi

if [[ -z "$E_R_FINAL" && -n "$REACTANT_OPT" ]]; then
  if [[ -f "OPT-R/opt_r.out" ]]; then
    E_R_FINAL="$(extract_final_energy "OPT-R/opt_r.out")"
  fi
fi
if [[ -z "$E_TS_FINAL" && -n "$TS_ENERGY" ]]; then
  E_TS_FINAL="$TS_ENERGY"
fi
if [[ -z "$E_TS_FINAL" ]]; then
  if [[ -f "SP-REFINE/sp_ts.out" ]]; then
    E_TS_FINAL="$(extract_final_energy "SP-REFINE/sp_ts.out")"
  elif [[ -f "TS/ts.out" ]]; then
    E_TS_FINAL="$(extract_final_energy "TS/ts.out")"
  fi
fi
if [[ -z "$E_P_FINAL" ]]; then
  if [[ -f "OPT-P/opt_p.out" ]]; then
    E_P_FINAL="$(extract_final_energy "OPT-P/opt_p.out")"
  fi
fi

if [[ -z "$IMAG_FREQ" && -f "${TS_DIR:-TS}/ts.out" ]]; then
  _freq_recover="$(parse_frequencies "${TS_DIR:-TS}/ts.out" 2>/dev/null)"
  _recovered="$(echo "$_freq_recover" | grep "FREQ_IMAGINARY=" | head -1 | cut -d: -f2)"
  [[ -n "$_recovered" ]] && IMAG_FREQ="$_recovered"
fi

###############################################################################
# 6) Energy summary
###############################################################################
if [[ -n "$E_R_FINAL" && -n "$E_TS_FINAL" && -n "$E_P_FINAL" ]]; then
  echo ""
  echo "[*] ===== Energy Analysis ====="

  mkdir -p "$PLOTS_DIR"
  generate_energy_summary "$PLOTS_DIR/energy_summary.txt" "$PLOTS_DIR/energy_data.csv" \
                          "$E_R_FINAL" "$E_TS_FINAL" "$E_P_FINAL" \
                          "${IMAG_FREQ:-N/A}"
else
  echo ""
  echo "[*] Incomplete energy data; skipping energy summary."
  [[ -z "$E_R_FINAL" ]]  && echo "  Missing: E(reactant)"
  [[ -z "$E_TS_FINAL" ]] && echo "  Missing: E(TS)"
  [[ -z "$E_P_FINAL" ]]  && echo "  Missing: E(product)"
fi

###############################################################################
# 7) Energy profile plot
###############################################################################
if [[ "$RUN_EPROFILE" -eq 1 && -n "$E_R_FINAL" && -n "$E_TS_FINAL" && -n "$E_P_FINAL" ]]; then
  echo ""
  echo "[*] ===== Energy Profile Visualization ====="
  mkdir -p "$PLOTS_DIR"
  generate_energy_profile_plot "$PLOTS_DIR/energy_profile.png" \
                               "$E_R_FINAL" "$E_TS_FINAL" "$E_P_FINAL" \
                               "${IMAG_FREQ:-N/A}"
  generate_energy_profile_plot_ev "$PLOTS_DIR/energy_profile_eV.png" \
                                  "$E_R_FINAL" "$E_TS_FINAL" "$E_P_FINAL" \
                                  "${IMAG_FREQ:-N/A}"
fi

###############################################################################
# 8) IRC path plot
###############################################################################
_irc_edat="${IRC_DIR:-IRC}/irc_energies.dat"
if [[ "$RUN_IRC_PLOT" -eq 1 && -f "$_irc_edat" ]]; then
  echo ""
  echo "[*] ===== IRC Path Visualization ====="
  mkdir -p "$PLOTS_DIR"
  generate_irc_path_plot "$_irc_edat" "$PLOTS_DIR/irc_path.png"
fi

###############################################################################
# 9) VMD TS rendering
###############################################################################
if [[ "$RUN_TS_RENDER" -eq 1 && -n "$TS_OPT_XYZ" ]]; then
  echo ""
  echo "[*] ===== TS Structure Rendering ====="
  mkdir -p "$PLOTS_DIR"
  render_ts_three_views "$(realpath "$TS_OPT_XYZ")" "$PLOTS_DIR" "${IMAG_FREQ:-N/A}"
fi

###############################################################################
# 10) TS Validation Panel
###############################################################################
_TS_OUT="${TS_DIR:-TS}/ts.out"
if [[ "$RUN_TS_PANEL" -eq 1 && -f "$_TS_OUT" ]]; then
  echo ""
  echo "[*] ===== TS Validation Panel ====="
  mkdir -p "$PLOTS_DIR"
  IRC_EDAT="${IRC_DIR:-IRC}/irc_energies.dat"
  generate_ts_validation_panel "$_TS_OUT" "$IRC_EDAT" \
                               "$PLOTS_DIR/ts_validation_panel.png" \
                               "${IMAG_FREQ:-N/A}"
fi

###############################################################################
# 11) TS Mode Projection
###############################################################################
if [[ "$RUN_MODE_PROJ" -eq 1 && -f "$_TS_OUT" ]]; then
  echo ""
  echo "[*] ===== TS Mode Projection ====="
  mkdir -p "$PLOTS_DIR"
  generate_mode_projection "$_TS_OUT" "$PLOTS_DIR/ts_mode_projection.png"
fi

###############################################################################
# 12) IRC Internal Coordinates
###############################################################################
IRC_FULL_TRJ=""
_irc_search="${IRC_DIR:-IRC}"
if [[ -d "$_irc_search" ]]; then
  shopt -s nullglob
  _trjs=( "${_irc_search}"/irc*Full*trj*.xyz "${_irc_search}"/irc*_trj.xyz )
  shopt -u nullglob
  [[ ${#_trjs[@]} -gt 0 ]] && IRC_FULL_TRJ="${_trjs[0]}"
fi
if [[ "$RUN_IRC_COORDS" -eq 1 && -n "$IRC_FULL_TRJ" ]]; then
  echo ""
  echo "[*] ===== IRC Internal Coordinates ====="
  mkdir -p "$PLOTS_DIR"
  generate_irc_coords_plot "$IRC_FULL_TRJ" "$PLOTS_DIR/irc_internal_coords.png" \
                           "$MONITOR_BONDS"
fi

###############################################################################
# 12b) TS trajectory overlay (three views: front, side, top)
###############################################################################
if [[ "$RUN_TS_TRAJ_OVERLAY" -eq 1 && -n "$IRC_FULL_TRJ" ]]; then
  echo ""
  echo "[*] ===== TS Trajectory Overlay (three views) ====="
  mkdir -p "$PLOTS_DIR"
  render_ts_trajectory_overlay_three_views "$IRC_FULL_TRJ" "$PLOTS_DIR"
fi

###############################################################################
# 13) CINEB image profile (from NEB image points)
###############################################################################
if [[ "$RUN_CINEB_IMAGE_PLOT" -eq 1 && -d "NEB" ]]; then
  echo ""
  echo "[*] ===== CINEB Image Energy Profile ====="
  mkdir -p "$PLOTS_DIR"
  parse_neb_image_energies "NEB" "$PLOTS_DIR/cineb_images.dat" "$PLOTS_DIR/cineb_images_energy.csv"
  generate_cineb_image_plot "$PLOTS_DIR/cineb_images.dat" "$PLOTS_DIR/cineb_image_energy.png"
fi

###############################################################################
# 14) CINEB image overlay (three views)
###############################################################################
NEB_IMAGE_TRJ=""
if [[ -d "NEB" ]]; then
  shopt -s nullglob
  _neb_trjs=(
    NEB/*cineb*initial*path*trj*.xyz
    NEB/*CINEB*initial*path*trj*.xyz
    NEB/*neb*initial*path*trj*.xyz
    NEB/*NEB*initial*path*trj*.xyz
    NEB/*initial*path*trj*.xyz
    NEB/cineb_initial_path_trj.xyz
    NEB/neb_initial_path_trj.xyz
    NEB/*NEB-CI*converged*.xyz
    NEB/*NEB-TS*converged*.xyz
    NEB/*MEP*trj*.xyz
    NEB/*MEP*.allxyz
  )
  shopt -u nullglob
  [[ ${#_neb_trjs[@]} -gt 0 ]] && NEB_IMAGE_TRJ="${_neb_trjs[0]}"
fi

if [[ "$RUN_CINEB_OVERLAY" -eq 1 && -n "$NEB_IMAGE_TRJ" ]]; then
  echo ""
  echo "[*] ===== CINEB Image Overlay (three views) ====="
  mkdir -p "$PLOTS_DIR"
  render_cineb_overlay_three_views "$NEB_IMAGE_TRJ" "$PLOTS_DIR"
fi

###############################################################################
# 15) NEB Convergence Diagnostics
###############################################################################
if [[ "$RUN_NEB_CONV" -eq 1 && -f "NEB/neb.out" ]]; then
  echo ""
  echo "[*] ===== NEB Convergence Diagnostics ====="
  mkdir -p "$PLOTS_DIR"
  generate_neb_convergence "NEB/neb.out" "$PLOTS_DIR/neb_convergence.png"
fi

###############################################################################
# 16) IRC Animation GIF
###############################################################################
if [[ "$RUN_IRC_ANIM" -eq 1 && -n "$IRC_FULL_TRJ" ]]; then
  echo ""
  echo "[*] ===== IRC Animation ====="
  mkdir -p "$PLOTS_DIR"
  _ANIM_VMD="${VMD_EXE:-}"
  if [[ -z "$_ANIM_VMD" ]]; then
    _ANIM_VMD="$(resolve_bin_any "${VMD_BIN:-}" "vmd" "VMD" 2>/dev/null)" || true
  fi
  if [[ -n "$_ANIM_VMD" ]]; then
    generate_irc_animation "$IRC_FULL_TRJ" "$PLOTS_DIR" "$_ANIM_VMD"
  else
    echo "  Skipping IRC animation (VMD not available)"
  fi
fi

###############################################################################
# Summary
###############################################################################
echo ""
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION -- TS & Reaction Path Analysis Complete"
echo "========================================"
[[ -d "OPT-R" ]]         && echo "  Optimized reactant: OPT-R/"
[[ -d "OPT-P" ]]         && echo "  Optimized product:  OPT-P/"
[[ -d "NEB" ]]            && echo "  NEB results:        NEB/"
[[ -d "TS" ]]             && echo "  TS optimization:    TS/"
[[ -n "$TS_OPT_XYZ" ]]   && echo "    TS structure:     $TS_OPT_XYZ"
[[ -n "$IMAG_FREQ" ]]     && echo "    Imaginary freq:   $IMAG_FREQ cm-1"
[[ -d "IRC" ]]            && echo "  IRC results:        IRC/"
[[ -d "SP-REFINE" ]]      && echo "  SP refinement:      SP-REFINE/"
if [[ -d "$PLOTS_DIR" ]]; then
  echo "  Visualization:      $PLOTS_DIR/"
  [[ -f "$PLOTS_DIR/energy_summary.txt" ]]       && echo "    Energy summary:        energy_summary.txt"
  [[ -f "$PLOTS_DIR/energy_data.csv" ]]          && echo "    Energy data:           energy_data.csv"
  [[ -f "$PLOTS_DIR/energy_profile.png" ]]       && echo "    Energy profile:        energy_profile.png"
  [[ -f "$PLOTS_DIR/energy_profile_eV.png" ]]    && echo "    Energy profile (eV):   energy_profile_eV.png"
  [[ -f "$PLOTS_DIR/irc_path.png" ]]             && echo "    IRC path plot:         irc_path.png"
  [[ -f "$PLOTS_DIR/ts_front.png" ]]             && echo "    TS renders:            ts_{front,side,top}.png"
  [[ -f "$PLOTS_DIR/ts_traj_front.png" ]]       && echo "    TS trajectory overlay: ts_traj_{front,side,top}.png"
  [[ -f "$PLOTS_DIR/cineb_images_energy.csv" ]] && echo "    CINEB energy CSV:      cineb_images_energy.csv"
  [[ -f "$PLOTS_DIR/cineb_image_energy.png" ]]  && echo "    CINEB image profile:   cineb_image_energy.png"
  [[ -f "$PLOTS_DIR/cineb_overlay_front.png" ]] && echo "    CINEB overlay:         cineb_overlay_{front,side,top}.png"
  [[ -f "$PLOTS_DIR/ts_validation_panel.png" ]]  && echo "    TS validation panel:   ts_validation_panel.png"
  [[ -f "$PLOTS_DIR/ts_mode_projection.png" ]]   && echo "    Mode projection:       ts_mode_projection.png"
  [[ -f "$PLOTS_DIR/irc_internal_coords.png" ]]  && echo "    IRC internal coords:   irc_internal_coords.png"
  [[ -f "$PLOTS_DIR/neb_convergence.png" ]]      && echo "    NEB convergence:       neb_convergence.png"
  [[ -f "$PLOTS_DIR/irc_movie_front.gif" ]]       && echo "    IRC animation:         irc_movie_{front,side,top}.gif"
fi
echo "========================================"

