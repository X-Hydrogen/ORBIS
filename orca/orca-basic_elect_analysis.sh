#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-basic_elect_analysis  (Basic Electronic Structure Analysis)
#
#  Version:    1.5.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-03-02
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Electronic structure analysis module. Performs multi-charge-state
#    single-point calculations, ESP mapping, frontier orbital analysis,
#    Fukui reactivity descriptors, charge
#    population, and bond order evaluation.
#
#  Prerequisite:
#    iqcap-opt.sh must have been run first. Requires optimization/ folder with opt.xyz.
#
#  Disclaimer:
#    This software is a workflow orchestration and analysis platform.
#    It does NOT include the third-party programs themselves (ORCA,
#    Multiwfn, VMD). Users must obtain and install those programs
#    independently under their respective licenses.
#
#  External dependencies (must be pre-installed):
#    ORCA          -  Quantum chemistry engine (orca, orca_2aim, orca_2mkl)
#    Multiwfn      -  Wavefunction analysis toolkit
#    VMD           -  Molecular visualization (TachyonInternal renderer)
#    Python 3      -  With packages: numpy, Pillow, matplotlib
#
#  Usage:
#    bash iqcap-basic_elect_analysis.sh [options]
#    bash iqcap-basic_elect_analysis.sh --help
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-basic_elect_analysis"
IQCAP_VERSION="1.5.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration
###############################################################################
ORCA_BIN=""
ORCA_2AIM_BIN=""
ORCA_2MKL_BIN=""
MULTIWFN_BIN=""
VMD_BIN=""

XYZ_FILE="0.xyz"
NPROCS=16
MAXCORE=4096

# ============================================================================
# Single-Point Calculation Level (SP_LEVEL)
# ============================================================================
# Algorithm accuracy and system-specific recommendations:
#
# 【有机体系 (Organic Systems)】
#   粗算 (Quick):     "B3LYP D3BJ def2-SVP def2/J RIJCOSX"
#   论文级别 (Pub):   "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "M06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【金属配合物 (Metal Complexes)】
#   粗算 (Quick):     "PBE D3BJ def2-SVP def2/J RIJCOSX"
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "TPSSh D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【过渡金属/重元素 (Transition Metals/Heavy Elements)】
#   粗算 (Quick):     "PBE D3BJ def2-SVP def2/J RIJCOSX"
#   论文级别 (Pub):   "PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "TPSSh D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "r2SCAN-3c" (全电子基组，无需D3)
#
# 【主族元素/无机 (Main Group/Inorganic)】
#   粗算 (Quick):     "B3LYP D3BJ def2-SVP def2/J RIJCOSX"
#   论文级别 (Pub):   "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "M06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【含色散相互作用 (Dispersion Interactions)】
#   粗算 (Quick):     "B3LYP D3BJ def2-SVP def2/J RIJCOSX"
#   论文级别 (Pub):   "B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "ωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "M06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 【自由基/开壳层 (Radicals/Open Shell)】
#   粗算 (Quick):     "UB3LYP D3BJ def2-SVP def2/J RIJCOSX"
#   论文级别 (Pub):   "UB3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#   高精度 (High):    "UM06-2X def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#                     或 "UωB97X-D3 def2-TZVP(-f) def2/J RIJCOSX tightSCF"
#
# 说明 (Notes):
#   - D3BJ: Grimme D3 with Becke–Johnson damping (recommended for GGA/hybrids)
#   - def2-SVP: 双ζ基组，适合粗算 (double-zeta, quick)
#   - def2-TZVP(-f): 三ζ基组，论文级别 (triple-zeta, publication)
#   - def2/J: 辅助基组 (auxiliary basis)
#   - RIJCOSX: 加速积分计算 (accelerated integral evaluation)
#   - tightSCF: 严格SCF收敛 (tight SCF convergence)
#   - 单点能计算建议使用比优化更大的基组以获得更准确能量
# ============================================================================
# Default filled after CLI: optimization/iqcap_orca.env (from iqcap-opt --method) or method-1 fallback
SP_LEVEL=""
SP_LEVEL_CLI=0

N_CHARGE=0
N_MULT=1
NP1_CHARGE=""
NP1_MULT=""
NM1_CHARGE=""
NM1_MULT=""

RUN_MULTIWFN=1
RUN_CDFT=1
RUN_ESP_PLOT=1
RUN_HOMO_LUMO_PLOT=1
RUN_FUKUI_PLOT=1
RUN_MOL_VIEW=1
RUN_CHARGES=1
RUN_BONDORDER=1

ESP_ISO=0.001
ESP_MIN=-0.05
ESP_MAX=0.05
ESP_ZOOM=1.00 #0.35
MOL_ZOOM=1.00 #0.70
MO_ISO=0.03
FUKUI_ISO=0.003
CUBE_STEP=0.15
PLOT_ONLY=0
ELEMENT_COLOR_OVERRIDES=()

###############################################################################
# CLI
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --xyz) XYZ_FILE="$2"; shift 2 ;;
    --sp-level) SP_LEVEL="$2"; SP_LEVEL_CLI=1; shift 2 ;;
    --n-charge) N_CHARGE="$2"; shift 2 ;;
    --n-mult) N_MULT="$2"; shift 2 ;;
    --np1-charge) NP1_CHARGE="$2"; shift 2 ;;
    --np1-mult) NP1_MULT="$2"; shift 2 ;;
    --nm1-charge) NM1_CHARGE="$2"; shift 2 ;;
    --nm1-mult) NM1_MULT="$2"; shift 2 ;;
    --nprocs) NPROCS="$2"; shift 2 ;;
    --maxcore) MAXCORE="$2"; shift 2 ;;
    --vmd-bin) VMD_BIN="$2"; shift 2 ;;
    --no-multiwfn) RUN_MULTIWFN=0; shift 1 ;;
    --no-cdft) RUN_CDFT=0; shift 1 ;;
    --no-esp-plot) RUN_ESP_PLOT=0; shift 1 ;;
    --no-mol-view) RUN_MOL_VIEW=0; shift 1 ;;
    --no-homo-lumo-plot) RUN_HOMO_LUMO_PLOT=0; shift 1 ;;
    --no-fukui-plot) RUN_FUKUI_PLOT=0; shift 1 ;;
    --no-charges) RUN_CHARGES=0; shift 1 ;;
    --no-bondorder) RUN_BONDORDER=0; shift 1 ;;
    --plot-only) PLOT_ONLY=1; shift 1 ;;
    --esp-iso) ESP_ISO="$2"; shift 2 ;;
    --esp-min) ESP_MIN="$2"; shift 2 ;;
    --esp-max) ESP_MAX="$2"; shift 2 ;;
    --esp-zoom) ESP_ZOOM="$2"; shift 2 ;;
    --mol-zoom) MOL_ZOOM="$2"; shift 2 ;;
    --mo-iso) MO_ISO="$2"; shift 2 ;;
    --fukui-iso) FUKUI_ISO="$2"; shift 2 ;;
    --cube-step) CUBE_STEP="$2"; shift 2 ;;
    --element-color) ELEMENT_COLOR_OVERRIDES+=("$2"); shift 2 ;;
    -V|--version)
      echo "$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME"
      echo "Module:    $IQCAP_MODULE (Core Workflow Engine)"
      echo "Author:    $IQCAP_AUTHOR"
      echo "Copyright: $IQCAP_COPYRIGHT"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME
Module: $IQCAP_MODULE (Core Workflow Engine)

Usage: bash iqcap-basic_elect_analysis.sh [options]

  Prerequisite: Run iqcap-opt.sh first. Requires optimization/ folder.

Input:
  --xyz FILE          Reference XYZ (for ATOM_Z_SUM etc., default: 0.xyz; geometry from optimization/opt.xyz)

Charge / multiplicity:
  --n-charge INT      Neutral state charge (default: 0)
  --n-mult INT        Neutral state multiplicity (default: 1)
  --np1-charge INT    N+1 (anion) state charge (auto: N_CHARGE - 1)
  --np1-mult INT      N+1 state multiplicity (auto-inferred)
  --nm1-charge INT    N-1 (cation) state charge (auto: N_CHARGE + 1)
  --nm1-mult INT      N-1 state multiplicity (auto-inferred)

Compute resources:
  --nprocs INT        Number of parallel processes (default: 16)
  --maxcore INT       Memory per process in MB (default: 4096)

Theory level:
  --sp-level STR      ORCA single-point level (default: optimization/iqcap_orca.env if present, else PBE0 D3BJ TZVP tightSCF)

Module switches:
  --no-multiwfn       Skip all Multiwfn-based analyses
  --no-cdft           Skip conceptual DFT analysis
  --no-esp-plot       Skip ESP three-view rendering
  --no-mol-view       Skip pure molecule three-view rendering
  --no-homo-lumo-plot Skip HOMO/LUMO panel rendering
  --no-fukui-plot     Skip Fukui 2x2 panel rendering
  --no-charges        Skip Hirshfeld charge analysis
  --no-bondorder      Skip Mayer bond order analysis
  --plot-only          Skip all computation; re-render from existing data

Visualization parameters:
  --esp-iso FLOAT     Density isosurface for ESP mapping (default: 0.001)
  --esp-min FLOAT     ESP color-scale minimum in a.u. (default: -0.05)
  --esp-max FLOAT     ESP color-scale maximum in a.u. (default: 0.05)
  --esp-zoom FLOAT    VMD zoom factor for ESP views (default: 1.00)
  --mol-zoom FLOAT    VMD zoom factor for molecule views (default: 1.00)
  --mo-iso FLOAT      Orbital isovalue for HOMO/LUMO (default: 0.03)
  --fukui-iso FLOAT   Fukui function isovalue (default: 0.003)
  --cube-step FLOAT   Cube file grid spacing in Bohr (default: 0.15)
  --element-color SPEC Override element color (repeatable). SPEC formats:
                      "Na=#1f77b4" or "S=#ffcc00" or "Na=0.12/0.34/0.56" (RGB 0..1)
                      Multiple entries can be separated by ',' or ';'

Path overrides:
  --vmd-bin PATH      VMD executable path (auto-detected)

Info:
  -h, --help          Show this help message
  -V, --version       Show version information

External program auto-detection:
  Multiwfn: multiwfn / Multiwfn / Multiwfn_noGUI
  VMD:      vmd / VMD

Python requirements: numpy, Pillow, matplotlib

Note: This software orchestrates third-party programs for computation
and visualization. It does NOT include ORCA, Multiwfn, or VMD.
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$SP_LEVEL_CLI" -eq 0 ]]; then
  if [[ -f "optimization/iqcap_orca.env" ]]; then
    # shellcheck disable=SC1090
    source "optimization/iqcap_orca.env"
    [[ -n "${IQCAP_ORCA_BASE:-}" ]] && SP_LEVEL="$IQCAP_ORCA_BASE tightSCF"
  fi
  [[ -z "$SP_LEVEL" ]] && SP_LEVEL="PBE0 D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
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
  local user_bin="$1"
  shift
  local names=("$@")
  local n candidate

  # User-provided path can be an executable file or a directory containing one
  if [[ -n "$user_bin" ]]; then
    user_bin="$(expand_path "$user_bin")"
    if [[ -x "$user_bin" ]]; then
      echo "$user_bin"
      return 0
    fi
    if [[ -d "$user_bin" ]]; then
      for n in "${names[@]}"; do
        candidate="$user_bin/$n"
        if [[ -x "$candidate" ]]; then
          echo "$candidate"
          return 0
        fi
      done
    fi
    return 1
  fi

  # Try all candidate executable names
  for n in "${names[@]}"; do
    candidate="$(resolve_bin "" "$n" || true)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

calc_atomic_number_sum() {
  local xyz_file="$1"
  python3 - "$xyz_file" <<'PY'
import sys
from pathlib import Path

symbols = [
    "H","He","Li","Be","B","C","N","O","F","Ne","Na","Mg","Al","Si","P","S","Cl","Ar",
    "K","Ca","Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn","Ga","Ge","As","Se","Br","Kr",
    "Rb","Sr","Y","Zr","Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn","Sb","Te","I","Xe",
]
zmap = {s: i + 1 for i, s in enumerate(symbols)}

xyz = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").splitlines()
if len(xyz) < 3:
    raise SystemExit("XYZ format error: too few lines")

total = 0
for ln in xyz[2:]:
    ln = ln.strip()
    if not ln:
        continue
    tok = ln.split()[0]
    sym = tok[0].upper() + tok[1:].lower()
    if sym not in zmap:
        raise SystemExit(f"Unsupported element symbol in XYZ: {tok}")
    total += zmap[sym]
print(total)
PY
}

infer_default_multiplicity() {
  local charge="$1"
  local nelec=$((ATOM_Z_SUM - charge))
  if (( nelec % 2 == 0 )); then
    echo 1
  else
    echo 2
  fi
}

validate_state_parity() {
  local charge="$1"
  local mult="$2"
  local label="$3"
  local nelec=$((ATOM_Z_SUM - charge))

  (( nelec > 0 )) || { echo "Invalid electron count for $label state: $nelec" >&2; exit 1; }
  (( mult >= 1 )) || { echo "Invalid multiplicity for $label state: $mult" >&2; exit 1; }

  # Even electrons -> odd multiplicity; odd electrons -> even multiplicity
  if (( nelec % 2 == 0 && mult % 2 == 0 )); then
    echo "Inconsistent $label state: electrons=$nelec requires odd multiplicity, got $mult" >&2
    exit 1
  fi
  if (( nelec % 2 == 1 && mult % 2 == 1 )); then
    echo "Inconsistent $label state: electrons=$nelec requires even multiplicity, got $mult" >&2
    exit 1
  fi
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

run_orca_case() {
  local workdir="$1" prefix="$2" charge="$3" mult="$4" xyz_source="$5" run_mkl="$6"
  mkdir -p "$workdir"
  cp "$xyz_source" "$workdir/geom.xyz"
  pushd "$workdir" >/dev/null
  write_orca_input "${prefix}.inp" "$SP_LEVEL" "$charge" "$mult" "geom.xyz"
  "$ORCA_EXE" "${prefix}.inp" > s.out
  "$ORCA_2AIM_EXE" "$prefix"
  [[ "$run_mkl" -eq 1 ]] && "$ORCA_2MKL_EXE" "$prefix" -emolden
  popd >/dev/null
}

###############################################################################
# Helpers: cube file identification
###############################################################################
find_esp_cubes() {
  local cube_files=() density_cube="" esp_cube=""
  shopt -s nullglob; cube_files=( *.cub *.cube ); shopt -u nullglob
  [[ ${#cube_files[@]} -gt 0 ]] || { echo "No cube files found." >&2; return 1; }
  for f in "${cube_files[@]}"; do
    local lf; lf="$(echo "$f" | tr '[:upper:]' '[:lower:]')"
    [[ -z "$density_cube" && "$lf" =~ dens|density ]] && density_cube="$f"
    [[ -z "$esp_cube" && "$lf" =~ esp|totesp|potential ]] && esp_cube="$f"
  done
  [[ -n "$density_cube" ]] || density_cube="${cube_files[0]}"
  [[ -n "$esp_cube" ]] || { [[ "${#cube_files[@]}" -ge 2 ]] && esp_cube="${cube_files[1]}"; }
  [[ -n "$esp_cube" ]] || { echo "Cannot determine ESP cube." >&2; return 1; }
  echo "$density_cube|$esp_cube"
}

find_density_cube() {
  local cube_files=() density_cube=""
  shopt -s nullglob; cube_files=( *.cub *.cube ); shopt -u nullglob
  [[ ${#cube_files[@]} -gt 0 ]] || return 1
  for f in "${cube_files[@]}"; do
    local lf; lf="$(echo "$f" | tr '[:upper:]' '[:lower:]')"
    [[ "$lf" =~ dens|density ]] && { density_cube="$f"; break; }
  done
  [[ -n "$density_cube" ]] || density_cube="${cube_files[0]}"
  echo "$density_cube"
}

export_density_cube_for_fukui() {
  local molden_file="$1" out_cube="$2" log_file="$3"
  echo -e "5\n1\n4\n$CUBE_STEP\n\n2\n0\nq" | "$MULTIWFN_EXE" "$molden_file" > "$log_file"
  local density_src
  density_src="$(find_density_cube)" || { echo "Cannot find density cube in $PWD" >&2; return 1; }
  cp "$density_src" "$out_cube"
}

###############################################################################
# Common VMD preamble for publication-quality rendering
###############################################################################
vmd_quality_preamble() {
  cat <<'TCLPRE'
display projection   Orthographic
if {[display device] ne "text"} { display resize 2400 1800 }
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
# Format examples:
#   Na=#1f77b4;S=#ffcc00
#   Na=0.12/0.34/0.56
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
# ESP three-view rendering
###############################################################################
render_esp_three_views() {
  local out_dir="$1"
  local cube_pair density_cube esp_cube
  cube_pair="$(find_esp_cubes)" || return 1
  density_cube="${cube_pair%%|*}"
  esp_cube="${cube_pair##*|}"

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

mol new "$out_dir/$density_cube" type cube waitfor all
mol addfile "$out_dir/$esp_cube" type cube waitfor all
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

mol representation Isosurface $ESP_ISO 0 0 0 1 1
mol color Volume 1
mol selection all
material change opacity Transparent 0.50
mol material Transparent
mol addrep top

color scale method BGR
mol scaleminmax top 1 $ESP_MIN $ESP_MAX

display resetview
scale by $ESP_ZOOM
render TachyonInternal "$out_dir/esp_front.tga"

display resetview
rotate y by 90
scale by $ESP_ZOOM
render TachyonInternal "$out_dir/esp_side.tga"

display resetview
rotate x by 90
scale by $ESP_ZOOM
render TachyonInternal "$out_dir/esp_top.tga"

color scale method BWR
mol scaleminmax top 1 $ESP_MIN $ESP_MAX

display resetview
scale by $ESP_ZOOM
render TachyonInternal "$out_dir/esp_bwr_front.tga"

display resetview
rotate y by 90
scale by $ESP_ZOOM
render TachyonInternal "$out_dir/esp_bwr_side.tga"

display resetview
rotate x by 90
scale by $ESP_ZOOM
render TachyonInternal "$out_dir/esp_bwr_top.tga"

quit
EOF
  } > "$out_dir/render_esp.tcl"

  "$VMD_EXE" -dispdev text -e "$out_dir/render_esp.tcl" > "$out_dir/esp_render.out" 2>&1

  for v in front side top; do
    [[ -f "$out_dir/esp_${v}.tga" ]] || { echo "Missing esp_${v}.tga" >&2; return 1; }
    [[ -f "$out_dir/esp_bwr_${v}.tga" ]] || { echo "Missing esp_bwr_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" "$ESP_ISO" "$ESP_MIN" "$ESP_MAX" "$density_cube" "$esp_cube" <<'PYESP'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

out_dir = Path(sys.argv[1])
iso_value = float(sys.argv[2])
esp_min = float(sys.argv[3])
esp_max = float(sys.argv[4])
density_name = sys.argv[5]
esp_name = sys.argv[6]

def read_cube(path: Path):
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    natom = int(lines[2].split()[0])
    nx = int(lines[3].split()[0]); ny = int(lines[4].split()[0]); nz = int(lines[5].split()[0])
    data_start = 6 + abs(natom)
    vals = []
    for ln in lines[data_start:]:
        vals.extend(float(x) for x in ln.split())
    return np.array(vals, dtype=float).reshape((nx, ny, nz), order="C")

def estimate_surface_extrema(rho, esp, iso):
    # Approximate ESP extrema on isosurface via narrow shell around rho=iso.
    dr = np.abs(rho - iso)
    tol = max(1.0e-4, abs(iso) * 0.12)
    mask = dr <= tol
    if np.count_nonzero(mask) < 200:
        k = min(dr.size // 100, 5000)
        k = max(k, 500)
        idx = np.argpartition(dr.ravel(), k)[:k]
        vals = esp.ravel()[idx]
    else:
        vals = esp[mask]
    vals = vals[np.isfinite(vals)]
    if vals.size == 0:
        return esp_min, esp_max
    return float(np.min(vals)), float(np.max(vals))

def _font(bold=False, size=20):
    names = (
        ["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf", "NotoSans-Bold.ttf"]
        if bold else
        ["LiberationSans-Regular.ttf", "DejaVuSans.ttf", "NotoSans-Regular.ttf"]
    )
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

def bgr_color(v):
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return 0, int(255 * t), int(255 * (1 - t))
    t = (v - 0.5) / 0.5
    return int(255 * t), int(255 * (1 - t)), 0

def bwr_color(v):
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return int(255 * t), int(255 * t), 255
    t = (v - 0.5) / 0.5
    return 255, int(255 * (1 - t)), int(255 * (1 - t))

rho = read_cube(out_dir / density_name)
esp = read_cube(out_dir / esp_name)
surf_min, surf_max = estimate_surface_extrema(rho, esp, iso_value)

def annotate(tga_path, png_path, color_fn):
    with Image.open(tga_path) as src:
        src = src.convert("RGBA")
        w, h = src.size

        legend_w = max(200, int(0.16 * w))
        footer_h = max(85, int(0.07 * h))
        canvas = Image.new("RGBA", (w + legend_w, h + footer_h), (255, 255, 255, 255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas, "RGBA")

        arr = np.array(src.convert("RGB"))
        non_white = np.any(arr < 245, axis=2)
        ys, _ = np.where(non_white)
        obj_y0 = int(ys.min()) if ys.size > 0 else int(0.2 * h)
        obj_y1 = int(ys.max()) if ys.size > 0 else int(0.8 * h)
        obj_h = max(1, obj_y1 - obj_y0 + 1)
        obj_cy = (obj_y0 + obj_y1) // 2

        pad = max(18, int(0.02 * min(w, h)))
        bar_w = max(30, int(0.026 * w))
        bar_h = int(obj_h * 1.04)
        bar_h = min(max(bar_h, int(0.42 * h)), h - 2 * pad)
        x0 = w + int(legend_w * 0.28)
        y0 = max(pad, min(obj_cy - bar_h // 2, h - pad - bar_h))
        x1 = x0 + bar_w
        y1 = y0 + bar_h

        for yy in range(y0, y1 + 1):
            t = 1.0 - (yy - y0) / max(1, y1 - y0)
            c = color_fn(t)
            draw.line([(x0, yy), (x1, yy)], fill=(*c, 255))
        draw.rectangle([x0 - 1, y0 - 1, x1 + 1, y1 + 1], outline=(35, 35, 35, 255), width=2)

        fv = _font(bold=True, size=max(26, int(0.020 * w)))
        fn = _font(bold=False, size=max(32, int(0.024 * w)))
        uf = _font(False, max(19, int(0.015 * w)))

        top_txt = f"+{esp_max:.4f}"
        bot_txt = f"{esp_min:.4f}"
        unit_txt = "a.u."

        bb = draw.textbbox((0, 0), bot_txt, font=fv)
        # Put labels to the right side of bar to avoid overlap.
        draw.text((x1 + 16, y0 - 2), top_txt, fill=(28, 28, 28, 255), font=fv)
        draw.text((x1 + 16, y1 - (bb[3] - bb[1]) + 2), bot_txt, fill=(28, 28, 28, 255), font=fv)
        draw.text((x1 + 20, y1 + (bb[3] - bb[1]) + 8), unit_txt, fill=(85, 85, 85, 255), font=uf)

        footer_txt = (
            f"iso = {iso_value:.4g} a.u.      "
            f"surface ESP min/max = [{surf_min:.4f}, +{surf_max:.4f}] a.u."
        )
        fb = draw.textbbox((0, 0), footer_txt, font=fn)
        draw.text(
            ((canvas.width - (fb[2] - fb[0])) / 2, h + (footer_h - (fb[3] - fb[1])) / 2),
            footer_txt, fill=(30, 30, 30, 255), font=fn,
        )
        canvas.save(png_path, format="PNG")

for view in ("front", "side", "top"):
    annotate(str(out_dir / f"esp_{view}.tga"), str(out_dir / f"esp_{view}.png"), bgr_color)
    print(f"  {out_dir / f'esp_{view}.png'}")

for view in ("front", "side", "top"):
    annotate(str(out_dir / f"esp_bwr_{view}.tga"), str(out_dir / f"esp_bwr_{view}.png"), bwr_color)
    print(f"  {out_dir / f'esp_bwr_{view}.png'}")
PYESP
}

###############################################################################
# Pure molecule three-view rendering from xyz
###############################################################################
render_pure_molecule_three_views() {
  local xyz_file="$1"
  local out_dir="$2"
  local prefix="${3:-molecule}"
  local tcl_file="$out_dir/render_${prefix}.tcl"

  {
    vmd_quality_preamble
    cat <<'TCLBONDS'
# Add bonds that VMD may not infer from XYZ (e.g. Li-S). Distance threshold in Angstrom.
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
# Add Li-S bonds (VMD often does not infer them from XYZ; typical Li-S ~2.1-2.5 Angstrom)
# Requires TopoTools plugin (package require topotools)
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
render TachyonInternal "$out_dir/${prefix}_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/${prefix}_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/${prefix}_top.tga"

quit
EOF
  } > "$tcl_file"

  "$VMD_EXE" -dispdev text -e "$tcl_file" > "$out_dir/${prefix}_render.out" 2>&1
  for v in front side top; do
    [[ -f "$out_dir/${prefix}_${v}.tga" ]] || { echo "Missing ${prefix}_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" "$prefix" <<'PYMOL'
import sys
from pathlib import Path
from PIL import Image

out_dir = Path(sys.argv[1])
prefix = sys.argv[2]
for view in ("front", "side", "top"):
    tga = out_dir / f"{prefix}_{view}.tga"
    png = out_dir / f"{prefix}_{view}.png"
    with Image.open(tga) as img:
        img.convert("RGBA").save(png, format="PNG")
    print(f"  {png}")
PYMOL
}

###############################################################################
# Single orbital / Fukui view (one cube -> one TGA)
###############################################################################
render_signed_iso_view() {
  local cube_file="$1" out_tga="$2" iso="$3" tag="$4" palette="${5:-mo}"
  local out_dir; out_dir="$(dirname "$out_tga")"
  local tcl_file="$out_dir/render_${tag}.tcl"

  {
    vmd_quality_preamble
    if [[ "$palette" == "fukui" ]]; then
      cat <<'EOFCOL'
color change rgb 30 0.38 0.75 0.98
color change rgb 31 0.98 0.80 0.20
EOFCOL
    fi
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

mol new "$cube_file" type cube waitfor all
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

mol representation Isosurface $iso 0 0 0 1 1
mol color ColorID $([[ "$palette" == "fukui" ]] && echo 30 || echo 0)
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top

mol representation Isosurface -$iso 0 0 0 1 1
mol color ColorID $([[ "$palette" == "fukui" ]] && echo 31 || echo 1)
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top

display resetview
scale by $ESP_ZOOM
render TachyonInternal "$out_tga"
quit
EOF
  } > "$tcl_file"

  "$VMD_EXE" -dispdev text -e "$tcl_file" > "$out_dir/render_${tag}.out" 2>&1
  [[ -f "$out_tga" ]] || { echo "Render failed: $out_tga missing" >&2; return 1; }
}

###############################################################################
# Single orbital three views (one cube -> front, side, top TGAs)
###############################################################################
render_signed_iso_three_views() {
  local cube_file="$1" out_prefix="$2" iso="$3" tag="$4" palette="${5:-mo}"
  local out_dir; out_dir="$(dirname "$out_prefix")"
  local tcl_file="$out_dir/render_${tag}_3view.tcl"

  {
    vmd_quality_preamble
    if [[ "$palette" == "fukui" ]]; then
      cat <<'EOFCOL'
color change rgb 30 0.38 0.75 0.98
color change rgb 31 0.98 0.80 0.20
EOFCOL
    fi
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

mol new "$cube_file" type cube waitfor all
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

mol representation Isosurface $iso 0 0 0 1 1
mol color ColorID $([[ "$palette" == "fukui" ]] && echo 30 || echo 0)
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top

mol representation Isosurface -$iso 0 0 0 1 1
mol color ColorID $([[ "$palette" == "fukui" ]] && echo 31 || echo 1)
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top

display resetview
scale by $ESP_ZOOM
render TachyonInternal "${out_prefix}_front.tga"

display resetview
rotate y by 90
scale by $ESP_ZOOM
render TachyonInternal "${out_prefix}_side.tga"

display resetview
rotate x by 90
scale by $ESP_ZOOM
render TachyonInternal "${out_prefix}_top.tga"

quit
EOF
  } > "$tcl_file"

  "$VMD_EXE" -dispdev text -e "$tcl_file" > "$out_dir/render_${tag}_3view.out" 2>&1
  for v in front side top; do
    [[ -f "${out_prefix}_${v}.tga" ]] || { echo "Render failed: ${out_prefix}_${v}.tga missing" >&2; return 1; }
  done
}

###############################################################################
# HOMO/LUMO: three views each; output front, side, top (no combined 2x3 figure)
###############################################################################
render_homo_lumo_panel() {
  local out_dir="$1"
  [[ -f "$out_dir/HOMO.cub" && -f "$out_dir/LUMO.cub" ]] || {
    echo "Missing HOMO/LUMO cube files, skipping." >&2; return 1
  }

  render_signed_iso_three_views "$out_dir/HOMO.cub" "$out_dir/homo_view" "$MO_ISO" "homo" "mo"
  render_signed_iso_three_views "$out_dir/LUMO.cub" "$out_dir/lumo_view" "$MO_ISO" "lumo" "mo"

  python3 - "$out_dir" "$MO_ISO" <<'PYMO'
import sys
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out_dir = Path(sys.argv[1])
iso = float(sys.argv[2])

# Hartree -> eV; eV -> kcal/mol
HA_TO_EV = 27.211386245988
EV_TO_KCAL = 23.0609

def read_homo_lumo_energies(molden_path):
    """Parse [MO] section: Ene= (Hartree), Occup= . Return (E_homo, E_lumo) in Hartree."""
    text = molden_path.read_text(encoding="utf-8", errors="ignore")
    in_mo = False
    enes = []
    occs = []
    for line in text.splitlines():
        line = line.strip()
        if line == "[MO]":
            in_mo = True
            continue
        if in_mo:
            if line.startswith("Ene="):
                enes.append(float(re.search(r"Ene=\s*([-\d.Ee+]+)", line).group(1)))
            elif line.startswith("Occup="):
                occs.append(float(re.search(r"Occup=\s*([\d.]+)", line).group(1)))
    if not enes or len(enes) != len(occs):
        return None, None
    # HOMO = last occupied, LUMO = first unoccupied
    homo_i = None
    for i, o in enumerate(occs):
        if o > 0.5:
            homo_i = i
    if homo_i is None or homo_i + 1 >= len(enes):
        return None, None
    return enes[homo_i], enes[homo_i + 1]

def _font(bold=False, size=20):
    names = (
        ["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"]
        if bold else
        ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"]
    )
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

molden_path = out_dir / "TZVP.molden.input"
e_homo_ha, e_lumo_ha = None, None
if molden_path.exists():
    e_homo_ha, e_lumo_ha = read_homo_lumo_energies(molden_path)

def energy_str(e_ha):
    if e_ha is None:
        return ""
    e_ev = e_ha * HA_TO_EV
    e_kcal = e_ev * EV_TO_KCAL
    return f"{e_ev:.3f} eV   {e_kcal:.3f} kcal/mol"

homo_energy_str = energy_str(e_homo_ha)
lumo_energy_str = energy_str(e_lumo_ha)

views = ("front", "side", "top")
imgs = {}
for orb in ("homo", "lumo"):
    for v in views:
        p = out_dir / f"{orb}_view_{v}.tga"
        if p.exists():
            imgs[(orb, v)] = Image.open(p).convert("RGBA")
        else:
            sys.exit(f"Missing required render: {p}")

w1, h1 = imgs[("homo", "front")].size
w2, h2 = imgs[("lumo", "front")].size
cell_w = max(w1, w2)
cell_h = max(h1, h2)
gap = 40
label_h = 90
footer_h = 55
pw_two = cell_w + gap + cell_w
total_h_side = label_h + cell_h + footer_h
ft = _font(bold=True, size=30)
fe = _font(bold=False, size=22)
fn = _font(bold=False, size=28)
note = f"iso = \\u00b1{iso:.4g}"
_tmp = Image.new("RGBA", (1, 1))
_draw_tmp = ImageDraw.Draw(_tmp)
nb = _draw_tmp.textbbox((0, 0), note, font=fn)
note_y_side = label_h + cell_h + (footer_h - 24) / 2

def save_view_canvas(view_name, img_left, img_right):
    c = Image.new("RGBA", (int(pw_two), int(total_h_side)), (255, 255, 255, 255))
    c.paste(img_left, (0, label_h))
    c.paste(img_right, (cell_w + gap, label_h))
    d = ImageDraw.Draw(c)
    for label, x_off, energy_txt in [("HOMO", 0, homo_energy_str), ("LUMO", cell_w + gap, lumo_energy_str)]:
        bb = d.textbbox((0, 0), label, font=ft)
        y_label = (label_h - (bb[3] - bb[1])) / 2
        d.text((x_off + 20, y_label), label, fill=(30, 30, 30, 255), font=ft)
        if energy_txt:
            eb = d.textbbox((0, 0), energy_txt, font=fe)
            y_energy = (label_h - (eb[3] - eb[1])) / 2
            ex = x_off + 20 + (bb[2] - bb[0]) + 14
            d.text((ex, y_energy), energy_txt, fill=(80, 80, 80, 255), font=fe)
        d.line([(x_off + 20, label_h - 6), (x_off + cell_w - 20, label_h - 6)], fill=(180, 180, 180, 255), width=2)
    d.text(((pw_two - (nb[2] - nb[0])) / 2, note_y_side), note, fill=(50, 50, 50, 255), font=fn)
    c.save(out_dir / f"homo_lumo_{view_name}.png", format="PNG")
    print(f"  {out_dir / f'homo_lumo_{view_name}.png'}")

# Front view: HOMO front | LUMO front
save_view_canvas("front", imgs[("homo", "front")], imgs[("lumo", "front")])

# Side view: HOMO side | LUMO side
save_view_canvas("side", imgs[("homo", "side")], imgs[("lumo", "side")])

# Top view: HOMO top | LUMO top
save_view_canvas("top", imgs[("homo", "top")], imgs[("lumo", "top")])
PYMO
}

###############################################################################
# Fukui: generate cubes, render individually, compose 2x2
###############################################################################
generate_fukui_cubes() {
  local rho_n="$1" rho_np1="$2" rho_nm1="$3" out_dir="$4"
  python3 - "$rho_n" "$rho_np1" "$rho_nm1" "$out_dir" <<'PYFK'
import sys
from pathlib import Path
import numpy as np

paths = [Path(a) for a in sys.argv[1:4]]
out_dir = Path(sys.argv[4])

def read_cube(path):
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    natom = int(lines[2].split()[0])
    nx, ny, nz = (int(lines[i].split()[0]) for i in (3, 4, 5))
    data_start = 6 + abs(natom)
    header = lines[:data_start]
    vals = []
    for ln in lines[data_start:]:
        vals.extend(float(x) for x in ln.split())
    return header, np.array(vals, dtype=float).reshape((nx, ny, nz), order="C")

def write_cube(path, header, arr):
    flat = arr.reshape(-1, order="C")
    with path.open("w", encoding="utf-8") as f:
        for ln in header:
            f.write(ln + "\n")
        for i in range(0, flat.size, 6):
            f.write(" ".join(f"{v:13.5e}" for v in flat[i:i+6]) + "\n")

h_n, rho_n = read_cube(paths[0])
_, rho_np1 = read_cube(paths[1])
_, rho_nm1 = read_cube(paths[2])
assert rho_n.shape == rho_np1.shape == rho_nm1.shape, "Grid shape mismatch"

out_dir.mkdir(parents=True, exist_ok=True)
write_cube(out_dir / "fukui_fplus.cub",  h_n, rho_np1 - rho_n)
write_cube(out_dir / "fukui_fminus.cub", h_n, rho_n - rho_nm1)
write_cube(out_dir / "fukui_f0.cub",     h_n, 0.5 * (rho_np1 - rho_nm1))
write_cube(out_dir / "fukui_dual.cub",   h_n, rho_np1 + rho_nm1 - 2.0 * rho_n)
PYFK
}

render_fukui_panel() {
  local fukui_dir="$1"
  local names=("fplus" "fminus" "f0" "dual")
  for n in "${names[@]}"; do
    [[ -f "$fukui_dir/fukui_${n}.cub" ]] || { echo "Missing fukui_${n}.cub" >&2; return 1; }
    render_signed_iso_three_views "$fukui_dir/fukui_${n}.cub" "$fukui_dir/fukui_${n}_view" "$FUKUI_ISO" "fukui_${n}" "fukui"
  done

  python3 - "$fukui_dir" "$FUKUI_ISO" <<'PYFKIMG'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

fukui_dir = Path(sys.argv[1])
iso = float(sys.argv[2])

def _font(bold=False, size=20):
    names = (
        ["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf"]
        if bold else
        ["LiberationSans-Regular.ttf", "DejaVuSans.ttf"]
    )
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

tag_names = ["fplus", "fminus", "f0", "dual"]
labels = [
    "f+ (nucleophilic attack)",
    "f- (electrophilic attack)",
    "f0 (radical attack)",
    "Df (dual descriptor)",
]

views = ("front", "side", "top")
for view in views:
    images = []
    for n in tag_names:
        p = fukui_dir / f"fukui_{n}_view_{view}.tga"
        if not p.exists():
            sys.exit(f"Missing required render: {p}")
        images.append(Image.open(p).convert("RGBA"))
    w = max(img.width for img in images)
    h = max(img.height for img in images)

    gap = 30
    label_h = 60
    footer_h = 55
    total_w = 2 * w + gap
    total_h = 2 * (label_h + h) + gap + footer_h

    canvas = Image.new("RGBA", (total_w, total_h), (255, 255, 255, 255))
    positions = [
        (0, label_h), (w + gap, label_h),
        (0, label_h + h + gap + label_h), (w + gap, label_h + h + gap + label_h),
    ]
    label_positions = [
        (0, 0), (w + gap, 0),
        (0, label_h + h + gap), (w + gap, label_h + h + gap),
    ]

    for img, pos in zip(images, positions):
        canvas.paste(img, pos)
    for img in images:
        img.close()

    draw = ImageDraw.Draw(canvas)
    ft = _font(bold=True, size=58)
    fn = _font(bold=False, size=36)

    for label, (lx, ly) in zip(labels, label_positions):
        bb = draw.textbbox((0, 0), label, font=ft)
        draw.text(
            (lx + (w - (bb[2] - bb[0])) / 2, ly + (label_h - (bb[3] - bb[1])) / 2),
            label, fill=(30, 30, 30, 255), font=ft,
        )

    for lx, ly in label_positions:
        line_y = ly + label_h - 6
        draw.line([(lx + 30, line_y), (lx + w - 30, line_y)], fill=(190, 190, 190, 255), width=2)

    note = f"iso = \u00b1{iso:.4g}"
    note_y = total_h - footer_h + (footer_h - 22) / 2
    nb = draw.textbbox((0, 0), note, font=fn)
    total_note_w = nb[2] - nb[0] + 280
    start_x = (total_w - total_note_w) / 2
    draw.text((start_x, note_y), note, fill=(50, 50, 50, 255), font=fn)

    legend_items = [
        ("\u25A0", (70, 110, 210, 255), " positive"),
        ("\u25A0", (210, 70, 70, 255), " negative"),
    ]
    cx = start_x + (nb[2] - nb[0]) + 40
    for sym, color, txt in legend_items:
        draw.text((cx, note_y), sym, fill=color, font=fn)
        sb = draw.textbbox((0, 0), sym, font=fn)
        draw.text((cx + (sb[2] - sb[0]) + 2, note_y), txt, fill=(50, 50, 50, 255), font=fn)
        tb = draw.textbbox((0, 0), sym + txt, font=fn)
        cx += (tb[2] - tb[0]) + 30

    out_path = fukui_dir / f"fukui_panel_{view}.png"
    canvas.save(out_path, format="PNG")
    print(f"  {out_path}")
PYFKIMG
}

###############################################################################
# Pre-checks
###############################################################################
[[ -d "optimization" ]] || { echo "ERROR: 缺少optimization步骤。请先运行 iqcap-opt.sh。" >&2; exit 1; }
[[ -f "optimization/opt.xyz" ]] || { echo "ERROR: optimization/opt.xyz 未找到。请先运行 iqcap-opt.sh。" >&2; exit 1; }

OPT_XYZ="optimization/opt.xyz"

if [[ "$PLOT_ONLY" -eq 0 ]]; then
  ATOM_Z_SUM="$(calc_atomic_number_sum "$OPT_XYZ")"
  [[ -n "$NP1_CHARGE" ]] || NP1_CHARGE=$((N_CHARGE - 1))
  [[ -n "$NM1_CHARGE" ]] || NM1_CHARGE=$((N_CHARGE + 1))
  [[ -n "$NP1_MULT" ]] || NP1_MULT="$(infer_default_multiplicity "$NP1_CHARGE")"
  [[ -n "$NM1_MULT" ]] || NM1_MULT="$(infer_default_multiplicity "$NM1_CHARGE")"

  validate_state_parity "$N_CHARGE" "$N_MULT" "N"
  validate_state_parity "$NP1_CHARGE" "$NP1_MULT" "N+1"
  validate_state_parity "$NM1_CHARGE" "$NM1_MULT" "N-1"

  ORCA_EXE="$(resolve_bin_any "$ORCA_BIN" "orca")" || { echo "Cannot find ORCA executable (tried: orca)" >&2; exit 1; }
  ORCA_2AIM_EXE="$(resolve_bin_any "$ORCA_2AIM_BIN" "orca_2aim")" || { echo "Cannot find ORCA_2AIM executable (tried: orca_2aim)" >&2; exit 1; }
  ORCA_2MKL_EXE="$(resolve_bin_any "$ORCA_2MKL_BIN" "orca_2mkl")" || { echo "Cannot find ORCA_2MKL executable (tried: orca_2mkl)" >&2; exit 1; }
  [[ "$RUN_MULTIWFN" -eq 1 || "$RUN_CDFT" -eq 1 ]] && {
    MULTIWFN_EXE="$(resolve_bin_any "$MULTIWFN_BIN" "multiwfn" "Multiwfn" "Multiwfn_noGUI")" || {
      echo "Cannot find Multiwfn executable (tried: multiwfn, Multiwfn, Multiwfn_noGUI)" >&2
      exit 1
    }
  }
fi
if [[ "$RUN_ESP_PLOT" -eq 1 || "$RUN_MOL_VIEW" -eq 1 || "$RUN_HOMO_LUMO_PLOT" -eq 1 || "$RUN_FUKUI_PLOT" -eq 1 ]]; then
  VMD_EXE="$(resolve_bin_any "$VMD_BIN" "vmd" "VMD")" || { echo "Cannot find VMD executable (tried: vmd, VMD)" >&2; exit 1; }
  python3 -c "from PIL import Image" >/dev/null 2>&1 || {
    echo "ERROR: Python Pillow required. Install: pip install Pillow" >&2; exit 1
  }
fi
[[ "$RUN_FUKUI_PLOT" -eq 1 ]] && {
  python3 -c "import numpy" >/dev/null 2>&1 || {
    echo "ERROR: Python numpy required. Install: pip install numpy" >&2; exit 1
  }
}

BASE_NAME="$(basename "$PWD")"
ELEC_STRUCT="electronic_structure"
mkdir -p "$ELEC_STRUCT"
echo "[*] Output folder: $PWD/$ELEC_STRUCT/"
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " $IQCAP_FULLNAME"
echo " Module: $IQCAP_MODULE (Basic Electronic Structure Analysis)"
echo "========================================"
[[ "$PLOT_ONLY" -eq 0 ]] && {
  echo "  ORCA:      $ORCA_EXE"
  echo "  SP level:  $SP_LEVEL"
  echo "  orca_2aim: $ORCA_2AIM_EXE"
  echo "  orca_2mkl: $ORCA_2MKL_EXE"
  [[ "$RUN_MULTIWFN" -eq 1 || "$RUN_CDFT" -eq 1 ]] && echo "  Multiwfn:  $MULTIWFN_EXE"
}
[[ "$RUN_ESP_PLOT" -eq 1 || "$RUN_MOL_VIEW" -eq 1 || "$RUN_HOMO_LUMO_PLOT" -eq 1 || "$RUN_FUKUI_PLOT" -eq 1 ]] && echo "  VMD:       $VMD_EXE"
echo "  Working:   $PWD"
echo "  N:   charge=$N_CHARGE  mult=$N_MULT"
echo "  N+1: charge=$NP1_CHARGE  mult=$NP1_MULT"
echo "  N-1: charge=$NM1_CHARGE  mult=$NM1_MULT"
echo "========================================"

###############################################################################
# 1) Use optimization/opt.xyz from iqcap-opt.sh (no optimization here)
###############################################################################
echo "[*] Using $OPT_XYZ from iqcap-opt.sh"
if [[ "$RUN_MOL_VIEW" -eq 1 ]]; then
  echo "[*] Rendering pure molecule three views..."
  mkdir -p optimization
  render_pure_molecule_three_views "$PWD/$OPT_XYZ" "$PWD/optimization" "molecule"
fi

###############################################################################
# 2) Single point: N, N+1, N-1 (reuse optimization/ data for N when available)
###############################################################################
DIR_N="$ELEC_STRUCT/SP"
DIR_NP1="$ELEC_STRUCT/Fukui/TZVP+1"
DIR_NM1="$ELEC_STRUCT/Fukui/TZVP-1"

if [[ "$PLOT_ONLY" -eq 0 ]]; then
  mkdir -p "$ELEC_STRUCT/Fukui"
  if [[ -f "optimization/TZVP.molden.input" && -f "optimization/TZVP.wfn" ]]; then
    echo "[*] Reusing neutral-state data from optimization/ (skip redundant SP)"
    mkdir -p "$DIR_N"
    cp optimization/TZVP.molden.input "$DIR_N/"
    cp optimization/TZVP.wfn "$DIR_N/"
    cp "$OPT_XYZ" "$DIR_N/geom.xyz"
  else
    run_orca_case "$DIR_N"   "TZVP"   "$N_CHARGE"   "$N_MULT"   "$OPT_XYZ" 1
  fi
  run_orca_case "$DIR_NP1" "TZVP+1" "$NP1_CHARGE" "$NP1_MULT" "$OPT_XYZ" 0
  run_orca_case "$DIR_NM1" "TZVP-1" "$NM1_CHARGE" "$NM1_MULT" "$OPT_XYZ" 0
fi

###############################################################################
# 3) Multiwfn analyses + visualizations
###############################################################################
if [[ "$RUN_MULTIWFN" -eq 1 && "$PLOT_ONLY" -eq 0 ]]; then
  pushd "$DIR_N" >/dev/null
  echo -e "5\n12\n4\n$CUBE_STEP\n\n2\n0\nq" | "$MULTIWFN_EXE" TZVP.molden.input > outesp.txt
  echo -e "5\n1\n4\n$CUBE_STEP\n\n2\n0\nq"  | "$MULTIWFN_EXE" TZVP.molden.input > outchg.txt
  echo -e "5\n9\n3\n2\n0\nq"           | "$MULTIWFN_EXE" TZVP.molden.input > outelf.txt

  echo -e "5\n4\nh\n4\n$CUBE_STEP\n2\n0\nq\n" | "$MULTIWFN_EXE" TZVP.molden.input > HOMO.tmp
  [[ -f MOvalue.cub ]] && mv MOvalue.cub HOMO.cub

  echo -e "5\n4\nl\n4\n$CUBE_STEP\n2\n0\nq\n" | "$MULTIWFN_EXE" TZVP.molden.input > LUMO.tmp
  [[ -f MOvalue.cub ]] && mv MOvalue.cub LUMO.cub

  if [[ "$RUN_ESP_PLOT" -eq 1 ]]; then
    echo "[*] Rendering ESP three views..."
    mkdir -p "../esp"
    cube_pair="$(find_esp_cubes)" && {
      density="${cube_pair%%|*}"; esp="${cube_pair##*|}"
      cp "$density" "$esp" "../esp/"
      pushd "../esp" >/dev/null
      render_esp_three_views "$PWD"
      popd >/dev/null
    }
  fi
  if [[ "$RUN_HOMO_LUMO_PLOT" -eq 1 ]]; then
    echo "[*] Rendering HOMO/LUMO panel..."
    mkdir -p "../homo_lumo"
    cp HOMO.cub LUMO.cub TZVP.molden.input "../homo_lumo/" 2>/dev/null || true
    if [[ -f "../homo_lumo/HOMO.cub" && -f "../homo_lumo/LUMO.cub" ]]; then
      pushd "../homo_lumo" >/dev/null
      render_homo_lumo_panel "$PWD"
      popd >/dev/null
    fi
  fi
  if [[ "$RUN_CHARGES" -eq 1 ]]; then
    echo "[*] Computing Hirshfeld charges..."
    echo -e "7\n1\n1\ny\n0\nq" | "$MULTIWFN_EXE" TZVP.molden.input > hirshfeld_charges.txt
    echo "  Hirshfeld charges -> $PWD/hirshfeld_charges.txt"
  fi
  if [[ "$RUN_BONDORDER" -eq 1 ]]; then
    echo "[*] Computing Mayer bond orders..."
    echo -e "9\n1\ny\n0\nq" | "$MULTIWFN_EXE" TZVP.molden.input > mayer_bondorder.txt
    echo "  Mayer bond orders -> $PWD/mayer_bondorder.txt"
  fi
  popd >/dev/null
elif [[ "$PLOT_ONLY" -eq 1 ]]; then
  if [[ "$RUN_ESP_PLOT" -eq 1 ]]; then
    ESP_DIR="$ELEC_STRUCT/esp"
    if [[ -d "$ESP_DIR" ]]; then
      pushd "$ESP_DIR" >/dev/null
      cube_pair="$(find_esp_cubes 2>/dev/null)" && {
        echo "[*] Re-rendering ESP three views..."
        render_esp_three_views "$PWD"
      } || echo "  WARNING: No ESP cube files found in $ESP_DIR"
      popd >/dev/null
    else
      echo "  WARNING: $ESP_DIR not found, skipping ESP rendering."
    fi
  fi
  if [[ "$RUN_HOMO_LUMO_PLOT" -eq 1 ]]; then
    HL_DIR="$ELEC_STRUCT/homo_lumo"
    if [[ -f "$HL_DIR/HOMO.cub" && -f "$HL_DIR/LUMO.cub" ]]; then
      echo "[*] Re-rendering HOMO/LUMO panel..."
      pushd "$HL_DIR" >/dev/null
      render_homo_lumo_panel "$PWD"
      popd >/dev/null
    else
      echo "  WARNING: HOMO/LUMO cubes not found, skipping."
    fi
  fi
fi

###############################################################################
# 4) Fukui functions
###############################################################################
if [[ "$RUN_FUKUI_PLOT" -eq 1 ]]; then
  FUKUI_DIR="$ELEC_STRUCT/Fukui"
  if [[ "$PLOT_ONLY" -eq 0 && "$RUN_MULTIWFN" -eq 1 ]]; then
    echo "[*] Generating Fukui cubes and panel..."
    pushd "$DIR_N" >/dev/null
    export_density_cube_for_fukui "TZVP.molden.input" "density_n_fukui.cub" "out_density_fukui_n.txt"
    popd >/dev/null

    pushd "$DIR_NP1" >/dev/null
    export_density_cube_for_fukui "TZVP+1.wfn" "density_np1_fukui.cub" "out_density_fukui_np1.txt"
    popd >/dev/null

    pushd "$DIR_NM1" >/dev/null
    export_density_cube_for_fukui "TZVP-1.wfn" "density_nm1_fukui.cub" "out_density_fukui_nm1.txt"
    popd >/dev/null

    mkdir -p "$FUKUI_DIR"
    generate_fukui_cubes \
      "${DIR_N}/density_n_fukui.cub" \
      "${DIR_NP1}/density_np1_fukui.cub" \
      "${DIR_NM1}/density_nm1_fukui.cub" \
      "$FUKUI_DIR"
    render_fukui_panel "$FUKUI_DIR"
  elif [[ "$PLOT_ONLY" -eq 1 ]]; then
    if [[ -f "$FUKUI_DIR/fukui_fplus.cub" && -f "$FUKUI_DIR/fukui_fminus.cub" && -f "$FUKUI_DIR/fukui_f0.cub" && -f "$FUKUI_DIR/fukui_dual.cub" ]]; then
      echo "[*] Re-rendering Fukui panel..."
      render_fukui_panel "$FUKUI_DIR"
    else
      echo "  WARNING: Fukui cube files not found, skipping."
    fi
  fi
fi

###############################################################################
# 5) CDFT via Multiwfn
###############################################################################
if [[ "$RUN_CDFT" -eq 1 && "$PLOT_ONLY" -eq 0 ]]; then
  CDFT_DIR="$ELEC_STRUCT/CDFT"
  mkdir -p "$CDFT_DIR"
  cp "${DIR_NM1}/TZVP-1.wfn" "${CDFT_DIR}/N-1.wfn"
  cp "${DIR_N}/TZVP.wfn"     "${CDFT_DIR}/N.wfn"
  cp "${DIR_NP1}/TZVP+1.wfn" "${CDFT_DIR}/N+1.wfn"

  pushd "$CDFT_DIR" >/dev/null
  echo -e "22\n2\n3\n3\n5\n6\n7\n8\n0\n0\nq" | "$MULTIWFN_EXE" N.wfn > cdft.out
  popd >/dev/null
fi

echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION -- Basic Electronic Structure Analysis Complete"
echo "========================================"
