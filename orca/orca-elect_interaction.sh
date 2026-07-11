#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-elect_interaction  (Weak Interaction Analysis)
#
#  Version:    1.5.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-03-02
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Standalone weak interaction analysis module. Includes NCI (Noncovalent
#    Interaction / RDG), IGMH (Independent Gradient Model based on Hirshfeld),
#    IRI (Interaction Region Indicator), HS (Hirshfeld Surface analysis),
#    differential charge density (chgdiff), and CDA (Charge Decomposition
#    Analysis). Fragment definition (--frag1-atoms, --frag2-atoms) required
#    for IGMH, HS, chgdiff, and CDA; not needed for NCI and IRI.
#    Results written to electronic_structure/ with subfolders:
#      electronic_structure/NCI/     - NCI/RDG analysis
#      electronic_structure/IGMH/    - IGMH weak-interaction visualization
#      electronic_structure/IRI/     - IRI analysis
#      electronic_structure/HS/      - Hirshfeld Surface analysis
#      electronic_structure/chgdiff/ - Differential charge density Δρ
#      electronic_structure/CDA/     - Charge decomposition analysis
#
#  Prerequisite:
#    iqcap-opt.sh must have been executed first (optimization/opt.xyz).
#    iqcap-basic_elect_analysis.sh should have been run (electronic_structure/SP/TZVP.molden.input).
#    Alternatively, iqcap-opt.sh with orca_2aim/orca_2mkl produces optimization/TZVP.molden.input.
#    For chgdiff/CDA: ORCA also required for fragment single-points.
#
#  External dependencies:
#    Multiwfn  - Wavefunction analysis toolkit
#    VMD       - Molecular visualization (TachyonInternal renderer)
#    ORCA      - For chgdiff and CDA (fragment single-points)
#    Python 3  - With packages: numpy, scipy, Pillow, matplotlib
#
#  Usage:
#    bash iqcap-elect_interaction.sh --frag1-atoms "1-3" --frag2-atoms "4-6" [options]
#    bash iqcap-elect_interaction.sh --only-CDA --frag1-atoms "1-3" --frag2-atoms "4-6"
#    bash iqcap-elect_interaction.sh --only-chgdiff --frag1-atoms "1-3" --frag2-atoms "4-6"
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-elect_interaction"
IQCAP_VERSION="1.5.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration
###############################################################################
MULTIWFN_BIN=""
VMD_BIN=""
ORCA_BIN=""
ORCA_2AIM_BIN=""
ORCA_2MKL_BIN=""

OUTPUT_DIR="electronic_structure"
NPROCS=16
MAXCORE=4096
SP_LEVEL=""
SP_LEVEL_CLI=0

# Module switches
RUN_NCI=1
RUN_IGMH=1
RUN_MIGM=1
RUN_IRI=1
RUN_HS=1
RUN_CHGDIFF=1
RUN_CDA=1

# NCI parameters
NCI_ISO=0.5
NCI_MIN=-0.04
NCI_MAX=0.02
CUBE_STEP=0.15
MOL_ZOOM=1.00

# IGMH parameters
FRAG1_ATOMS=""
FRAG2_ATOMS=""
IGMH_GRID=0.15
IGMH_VDW_SCL=2.0
IGMH_SCATTER_MODE="both"    # "inter", "intra", or "both"
IGMH_SCATTER_YSCALE="log"   # "log" or "linear"

# mIGM parameters (geometry-only, no wavefunction needed)
MIGM_GRID=0.2
IGMH_ISO=0.01
IGMH_COLOR_MIN=-0.04
IGMH_COLOR_MAX=0.02

# IRI parameters
IRI_ISO=1.0
IRI_COLOR_MIN=-0.035
IRI_COLOR_MAX=0.02

# Hirshfeld Surface parameters
HS_COLOR_MIN=0.0
HS_COLOR_MAX=0.015

# Chgdiff parameters (Δρ = ρ(AB) - ρ(A) - ρ(B))
CHGDIFF_ISO=0.001
CHGDIFF_ZOOM=0.80

# CDA parameters
FRAG1_CHARGE=0
FRAG1_MULT=1
FRAG2_CHARGE=0
FRAG2_MULT=1
CDA_PLOT=1
CDA_SKIP_ORCA=0
CDA_EMIN=-30.0
CDA_EMAX=10.0
CDA_PLOT_MARGIN=0.2
CDA_PUB_ORBITALS=1
CDA_ALL_ORBITALS=0
MO_ZOOM=0.9
MO_ZOOM_FRAG=0.3
PLOT_ONLY=0
CDA_TOTAL_CHARGE="auto"
ELEMENT_COLOR_OVERRIDES=()

###############################################################################
# CLI
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)     OUTPUT_DIR="$2";     shift 2 ;;
    --no-nci)         RUN_NCI=0;          shift 1 ;;
    --no-igmh)        RUN_IGMH=0;         shift 1 ;;
    --no-migm)        RUN_MIGM=0;         shift 1 ;;
    --no-iri)         RUN_IRI=0;          shift 1 ;;
    --no-hs)          RUN_HS=0;           shift 1 ;;
    --no-chgdiff)     RUN_CHGDIFF=0;      shift 1 ;;
    --no-cda)         RUN_CDA=0;          shift 1 ;;
    --only-NCI)       RUN_NCI=1 RUN_IGMH=0 RUN_MIGM=0 RUN_IRI=0 RUN_HS=0 RUN_CHGDIFF=0 RUN_CDA=0; shift 1 ;;
    --only-IGMH)      RUN_NCI=0 RUN_IGMH=1 RUN_MIGM=0 RUN_IRI=0 RUN_HS=0 RUN_CHGDIFF=0 RUN_CDA=0; shift 1 ;;
    --only-mIGM)      RUN_NCI=0 RUN_IGMH=0 RUN_MIGM=1 RUN_IRI=0 RUN_HS=0 RUN_CHGDIFF=0 RUN_CDA=0; shift 1 ;;
    --only-IRI)       RUN_NCI=0 RUN_IGMH=0 RUN_MIGM=0 RUN_IRI=1 RUN_HS=0 RUN_CHGDIFF=0 RUN_CDA=0; shift 1 ;;
    --only-HS)        RUN_NCI=0 RUN_IGMH=0 RUN_MIGM=0 RUN_IRI=0 RUN_HS=1 RUN_CHGDIFF=0 RUN_CDA=0; shift 1 ;;
    --only-chgdiff)   RUN_NCI=0 RUN_IGMH=0 RUN_MIGM=0 RUN_IRI=0 RUN_HS=0 RUN_CHGDIFF=1 RUN_CDA=0; shift 1 ;;
    --only-CDA)       RUN_NCI=0 RUN_IGMH=0 RUN_MIGM=0 RUN_IRI=0 RUN_HS=0 RUN_CHGDIFF=0 RUN_CDA=1; shift 1 ;;
    --skip-CDA)       RUN_CDA=0;          shift 1 ;;
    --skip-chgdiff)   RUN_CHGDIFF=0;      shift 1 ;;
    --skip-hs)        RUN_HS=0;           shift 1 ;;
    --frag1-atoms)    FRAG1_ATOMS="$2";   shift 2 ;;
    --frag2-atoms)    FRAG2_ATOMS="$2";   shift 2 ;;
    --frag1-charge)   FRAG1_CHARGE="$2";  shift 2 ;;
    --frag1-mult)     FRAG1_MULT="$2";    shift 2 ;;
    --frag2-charge)   FRAG2_CHARGE="$2";  shift 2 ;;
    --frag2-mult)     FRAG2_MULT="$2";    shift 2 ;;
    --nprocs)         NPROCS="$2";        shift 2 ;;
    --maxcore)        MAXCORE="$2";       shift 2 ;;
    --sp-level)       SP_LEVEL="$2"; SP_LEVEL_CLI=1; shift 2 ;;
    --nci-iso)        NCI_ISO="$2";       shift 2 ;;
    --nci-min)        NCI_MIN="$2";       shift 2 ;;
    --nci-max)        NCI_MAX="$2";       shift 2 ;;
    --igmh-iso)       IGMH_ISO="$2";      shift 2 ;;
    --igmh-color-min) IGMH_COLOR_MIN="$2"; shift 2 ;;
    --igmh-color-max) IGMH_COLOR_MAX="$2"; shift 2 ;;
    --igmh-grid)      IGMH_GRID="$2";      shift 2 ;;
    --igmh-vdw-scl)   IGMH_VDW_SCL="$2";   shift 2 ;;
    --igmh-scatter)   IGMH_SCATTER_MODE="$2"; shift 2 ;;
    --igmh-yscale)    IGMH_SCATTER_YSCALE="$2"; shift 2 ;;
    --iri-iso)        IRI_ISO="$2";       shift 2 ;;
    --hs-color-min)   HS_COLOR_MIN="$2";  shift 2 ;;
    --hs-color-max)   HS_COLOR_MAX="$2";  shift 2 ;;
    --chgdiff-iso)    CHGDIFF_ISO="$2";   shift 2 ;;
    --chgdiff-zoom)   CHGDIFF_ZOOM="$2";  shift 2 ;;
    --no-cda-plot)    CDA_PLOT=0;         shift 1 ;;
    --cda-skip-orca)  CDA_SKIP_ORCA=1;    shift 1 ;;
    --CDA-all-orbitals) CDA_ALL_ORBITALS=1; shift 1 ;;
    --no-cda-pub-orbitals) CDA_PUB_ORBITALS=0; shift 1 ;;
    --cda-emin)       CDA_EMIN="$2";      shift 2 ;;
    --cda-emax)       CDA_EMAX="$2";      shift 2 ;;
    --cda-plot-margin) CDA_PLOT_MARGIN="$2";   shift 2 ;;
    --cda-total-charge) CDA_TOTAL_CHARGE="$2"; shift 2 ;;
    --cube-step)      CUBE_STEP="$2";     shift 2 ;;
    --migm-grid)      MIGM_GRID="$2";     shift 2 ;;
    --mol-zoom)       MOL_ZOOM="$2";      shift 2 ;;
    --mo-zoom)        MO_ZOOM="$2";      shift 2 ;;
    --mo-zoom-frag)   MO_ZOOM_FRAG="$2";  shift 2 ;;
    --vmd-bin)        VMD_BIN="$2";       shift 2 ;;
    --plot-only)        PLOT_ONLY=1;          shift 1 ;;
    --element-color)  ELEMENT_COLOR_OVERRIDES+=("$2"); shift 2 ;;
    -V|--version)
      echo "$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME"
      echo "Module:    $IQCAP_MODULE (Weak Interaction Analysis)"
      echo "Author:    $IQCAP_AUTHOR"
      echo "Copyright: $IQCAP_COPYRIGHT"
      exit 0
      ;;
    -h|--help)
      cat <<EOF
$IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_FULLNAME
Module: $IQCAP_MODULE (Weak Interaction Analysis)

Usage: bash iqcap-elect_interaction.sh [options]

  Prerequisite: iqcap-opt.sh (and optionally iqcap-basic_elect_analysis.sh) must have been run first.
  Fragment definition (--frag1-atoms, --frag2-atoms) is required for IGMH, chgdiff, and CDA.

  All results are written to $OUTPUT_DIR/ with subfolders:
    $OUTPUT_DIR/NCI/     - NCI/RDG analysis
    $OUTPUT_DIR/IGMH/    - IGMH weak-interaction
    $OUTPUT_DIR/IRI/     - IRI analysis
    $OUTPUT_DIR/HS/      - Hirshfeld Surface analysis
    $OUTPUT_DIR/chgdiff/ - Differential charge density Δρ
    $OUTPUT_DIR/CDA/     - Charge decomposition analysis

Output directory:
  --output-dir DIR     Output folder (default: electronic_structure)

Module switches:
  --no-nci             Skip NCI/RDG analysis
  --no-igmh            Skip IGMH analysis
  --no-migm            Skip mIGM analysis (geometry-only, no wavefunction needed)
  --no-iri             Skip IRI analysis
  --no-hs              Skip Hirshfeld Surface analysis
  --no-chgdiff         Skip differential charge density
  --no-cda             Skip CDA charge decomposition analysis
  --skip-CDA           Same as --no-cda
  --skip-chgdiff       Same as --no-chgdiff
  --skip-hs            Same as --no-hs
  --only-NCI           Run only NCI (skip all others)
  --only-IGMH          Run only IGMH
  --only-mIGM          Run only mIGM (geometry-only, fastest)
  --only-IRI           Run only IRI
  --only-HS            Run only Hirshfeld Surface
  --only-chgdiff       Run only chgdiff
  --only-CDA           Run only CDA charge decomposition analysis
  --plot-only           Skip all computation; re-render/re-plot from existing data

Fragment definition (required for IGMH, HS, chgdiff, CDA):
  --frag1-atoms STR    Fragment 1 atom indices (1-based, e.g. "1-3" or "1,2,3")
  --frag2-atoms STR    Fragment 2 atom indices (e.g. "4-6")
  --frag1-charge INT   Fragment 1 charge for CDA (default: 0)
  --frag1-mult INT     Fragment 1 multiplicity (default: 1)
  --frag2-charge INT   Fragment 2 charge (default: 0)
  --frag2-mult INT     Fragment 2 multiplicity (default: 1)

NCI parameters:
  --nci-iso FLOAT      RDG isosurface value (default: 0.5)
  --nci-min FLOAT      sign(lambda2)*rho color min (default: -0.04)
  --nci-max FLOAT      sign(lambda2)*rho color max (default: 0.02)

IGMH parameters:
  --igmh-iso FLOAT     delta-g_inter isosurface value (default: 0.01)
  --igmh-color-min F   sign(lambda2)*rho color min (default: -0.04)
  --igmh-color-max F   sign(lambda2)*rho color max (default: 0.02)
  --igmh-grid FLOAT    grid spacing in Bohr (default: 0.15)
  --igmh-vdw-scl FLOAT IGMvdwscl acceleration factor (default: 2.0, 0=off)
  --igmh-scatter MODE  scatter channels: inter, intra, both (default: both)
  --igmh-yscale MODE   y-axis scale: log or linear (default: log)

IRI parameters:
  --iri-iso FLOAT      IRI isosurface value (default: 1.0)

Hirshfeld Surface parameters:
  --hs-color-min FLOAT HS color scale min for promol. density (default: 0.0)
  --hs-color-max FLOAT HS color scale max for promol. density (default: 0.015)

Chgdiff parameters:
  --chgdiff-iso FLOAT  Isovalue for ±Δρ isosurfaces (default: 0.001)
  --chgdiff-zoom FLOAT VMD zoom factor (default: 0.80)

CDA parameters:
  --cda-total-charge INT  Override total complex charge (default: auto from optimization/opt.out)
  --cda-emin FLOAT     Orbital diagram energy min in eV (default: -30)
  --cda-emax FLOAT     Orbital diagram energy max in eV (default: 10)
  --cda-plot-margin FLOAT  Y-axis margin coefficient: y_min = min - range*M, y_max = max + range*M (default: 0.3)
  --no-cda-plot        Skip orbital interaction diagram
  --cda-skip-orca      Skip fragment ORCA runs (reuse existing)
  --CDA-all-orbitals   Output ALL orbitals as three-view images; default OFF
  --no-cda-pub-orbitals Skip orbitals for pub diagram (HOMO-2..LUMO+2); default ON

Compute resources (for chgdiff, CDA):
  --nprocs INT         Number of parallel processes (default: 16)
  --maxcore INT        Memory per process in MB (default: 4096)
  --sp-level STR       ORCA SP level (default: from optimization/iqcap_orca.env if present, else PBE0 TZVP tightSCF)

Visualization:
  --cube-step FLOAT    Grid spacing in Bohr (default: 0.15)
  --mol-zoom FLOAT     VMD zoom for NCI/IGMH/IRI/HS/chgdiff (default: 1.00)
  --chgdiff-zoom FLOAT VMD zoom for chgdiff three-view (default: 0.80)
  --mo-zoom FLOAT      VMD zoom for CDA complex orbital images (default: 0.9)
  --mo-zoom-frag FLOAT VMD zoom for CDA fragment orbital images (default: 0.3)
  --element-color SPEC Override element color (repeatable). SPEC formats:
                       "Na=#1f77b4" or "S=#ffcc00" or "Na=0.12/0.34/0.56" (RGB 0..1)
                       Multiple entries can be separated by ',' or ';'

Path overrides:
  --vmd-bin PATH       VMD executable path (auto-detected)

Info:
  -h, --help           Show this help message
  -V, --version        Show version information
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
# Helper functions: path resolution
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
all_idx = sorted(f1 + f2)
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

# Check if CDA needs atom reordering (frag1 and frag2 interleaved in xyz).
# Multiwfn CDA expects frag1 atoms first, frag2 second. When interleaved,
# we create a reordered xyz and run ORCA SP to obtain correctly-ordered molden.
fragments_need_reorder_for_cda() {
  python3 - "$1" "$2" "$3" <<'PYCDA'
import sys, re
def expand_indices(s):
    idx = []
    for p in re.split(r'[,\s]+', s.strip()):
        if not p: continue
        if '-' in p:
            a,b = p.split('-',1)
            idx.extend(range(int(a), int(b)+1))
        else:
            idx.append(int(p))
    return sorted(set(idx))
f1 = expand_indices(sys.argv[2])
f2 = expand_indices(sys.argv[3])
if f1 and f2 and max(f1) > min(f2):
    print("1")
else:
    print("0")
PYCDA
}

reorder_xyz_for_cda() {
  local xyz_in="$1" frag1="$2" frag2="$3" xyz_out="$4"
  python3 - "$xyz_in" "$frag1" "$frag2" "$xyz_out" <<'PYREORD'
import sys, re
from pathlib import Path
def expand_indices(s):
    idx = []
    for p in re.split(r'[,\s]+', s.strip()):
        if not p: continue
        if '-' in p:
            a,b = p.split('-',1)
            idx.extend(range(int(a), int(b)+1))
        else:
            idx.append(int(p))
    return sorted(set(idx))
path_in, frag1_spec, frag2_spec, path_out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = Path(path_in).read_text().splitlines()
natom = int(lines[0].strip())
comment = lines[1].strip() if len(lines) > 1 else ""
atoms = lines[2:2+natom]
f1_idx = expand_indices(frag1_spec)
f2_idx = expand_indices(frag2_spec)
ordered = [atoms[i-1] for i in f1_idx] + [atoms[i-1] for i in f2_idx]
with open(path_out, 'w') as f:
    f.write(f"{natom}\n")
    f.write(f"{comment} (reordered for CDA: frag1 then frag2)\n")
    for line in ordered:
        f.write(line.rstrip() + "\n")
PYREORD
}

# Extract first n1 atoms to out1, next n2 atoms to out2 from xyz (for reordered CDA).
extract_fragments_from_reordered_xyz() {
  local xyz_file="$1" n1="$2" out1="$3" out2="$4"
  python3 - "$xyz_file" "$n1" "$out1" "$out2" <<'PYEXT'
import sys
from pathlib import Path
path, n1, out1, out2 = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
lines = Path(path).read_text().splitlines()
natom = int(lines[0].strip())
atoms = lines[2:2+natom]
n2 = natom - n1
with open(out1, 'w') as f:
    f.write(f"{n1}\nFragment 1 (from reordered xyz)\n")
    for line in atoms[:n1]:
        f.write(line.rstrip() + "\n")
with open(out2, 'w') as f:
    f.write(f"{n2}\nFragment 2 (from reordered xyz)\n")
    for line in atoms[n1:]:
        f.write(line.rstrip() + "\n")
PYEXT
}

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

# Read total charge from optimization output (optimization/opt.out or opt.out)
read_charge_from_optimization() {
  local chg=""
  for f in "optimization/opt.out" "opt.out"; do
    [[ -f "$f" ]] || continue
    chg=$(grep -m1 "Total Charge" "$f" 2>/dev/null | awk '{print $NF}')
    [[ -n "$chg" && "$chg" =~ ^-?[0-9]+$ ]] && { echo "$chg"; return 0; }
  done
  echo "0"
}

# Infer fragment charges for closed-shell fragments. Output: "Q1 Q2"
# If hirshfeld_file exists, picks (Q1,Q2) closest to Hirshfeld fragment sums; else minimizes |Q1|+|Q2|.
# Args: frag1_xyz frag2_xyz q_total [hirshfeld_file frag1_atoms frag2_atoms]
infer_closed_shell_charges() {
  local frag1_xyz="$1" frag2_xyz="$2" q_total="$3" hirshfeld="$4" frag1_atoms="$5" frag2_atoms="$6"
  python3 - "$frag1_xyz" "$frag2_xyz" "$q_total" "$hirshfeld" "$frag1_atoms" "$frag2_atoms" <<'PYINFER'
import sys, re
from pathlib import Path
zmap = {'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Ne':10,'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'Ar':18}
def expand_atoms(s):
    if not s: return set()
    idx = []
    for p in re.split(r'[,\s]+', s.strip()):
        if not p: continue
        if '-' in p:
            a, b = p.split('-', 1)
            idx.extend(range(int(a), int(b) + 1))
        else:
            idx.append(int(p))
    return set(idx)
def z_sum(path):
    lines = Path(path).read_text().splitlines()
    n = int(lines[0].strip())
    return sum(zmap.get(ln.split()[0][0].upper()+(ln.split()[0][1:].lower() if len(ln.split()[0])>1 else ''), 0)
          for ln in lines[2:2+n] if ln.strip())
Z1 = z_sum(sys.argv[1])
Z2 = z_sum(sys.argv[2])
Q_total = int(sys.argv[3])
hirshfeld_path = sys.argv[4] if len(sys.argv) > 4 else ""
frag1_atoms = expand_atoms(sys.argv[5]) if len(sys.argv) > 5 else set()
frag2_atoms = expand_atoms(sys.argv[6]) if len(sys.argv) > 6 else set()
h_sum1, h_sum2 = None, None
if hirshfeld_path and Path(hirshfeld_path).exists() and frag1_atoms and frag2_atoms:
    text = Path(hirshfeld_path).read_text(encoding='utf-8', errors='ignore')
    charges = {}
    for m in re.finditer(r'Hirshfeld charge of atom\s+(\d+)\s+\([^)]*\)\s+is\s+([-\d.]+)', text):
        charges[int(m.group(1))] = float(m.group(2))
    if charges:
        h_sum1 = sum(charges.get(i, 0) for i in frag1_atoms)
        h_sum2 = sum(charges.get(i, 0) for i in frag2_atoms)
best = None
best_score = 1e9
for q1 in range(-10, 11):
    q2 = Q_total - q1
    n1, n2 = Z1 - q1, Z2 - q2
    if n1 < 0 or n2 < 0:
        continue
    if n1 % 2 != 0 or n2 % 2 != 0:
        continue
    if h_sum1 is not None and h_sum2 is not None:
        score = abs(q1 - h_sum1) + abs(q2 - h_sum2)
    else:
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
# Chgdiff helpers: run ORCA, density cube, Δρ
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

run_orca_sp() {
  local workdir="$1" prefix="$2" charge="$3" mult="$4" xyz_source="$5"
  mkdir -p "$workdir"
  cp "$xyz_source" "$workdir/geom.xyz"
  pushd "$workdir" >/dev/null
  write_orca_input "${prefix}.inp" "$SP_LEVEL" "$charge" "$mult" "geom.xyz"
  "$ORCA_EXE" "${prefix}.inp" > s.out
  "$ORCA_2AIM_EXE" "$prefix" 2>/dev/null || true
  "$ORCA_2MKL_EXE" "$prefix" -emolden
  popd >/dev/null
}

export_density_cube() {
  local workdir="$1" molden_name="$2" log_name="$3"
  pushd "$workdir" >/dev/null
  echo -e "5\n1\n4\n$CUBE_STEP\n\n2\n0\nq" | "$MULTIWFN_EXE" "$molden_name" > "$log_name"
  popd >/dev/null
}

find_density_cube() {
  local f
  shopt -s nullglob
  for f in *.cub *.cube; do
    [[ "$(echo "$f" | tr '[:upper:]' '[:lower:]')" =~ dens|density ]] && { shopt -u nullglob; echo "$f"; return 0; }
  done
  for f in *.cub *.cube; do
    [[ -n "$f" ]] && { shopt -u nullglob; echo "$f"; return 0; }
  done
  shopt -u nullglob
  return 1
}

compute_chgdiff_cube() {
  python3 - "$1" "$2" "$3" "$4" <<'PYCHG'
import sys
from pathlib import Path
import numpy as np
try:
    from scipy.interpolate import RegularGridInterpolator
except ImportError:
    raise SystemExit("ERROR: scipy required for chgdiff. pip install scipy")
rho_ab_path, rho_a_path, rho_b_path, out_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
def read_cube_full(path):
    lines = path.read_text().splitlines()
    natom = int(lines[2].split()[0])
    origin = np.array([float(lines[2].split()[1]), float(lines[2].split()[2]), float(lines[2].split()[3])])
    nx,ny,nz = int(lines[3].split()[0]), int(lines[4].split()[0]), int(lines[5].split()[0])
    v1 = np.array([float(x) for x in lines[3].split()[1:4]])
    v2 = np.array([float(x) for x in lines[4].split()[1:4]])
    v3 = np.array([float(x) for x in lines[5].split()[1:4]])
    data_start = 6 + abs(natom)
    vals = []
    for ln in lines[data_start:]:
        vals.extend(float(x) for x in ln.split())
    arr = np.array(vals, dtype=float).reshape((nx,ny,nz), order="C")
    x_1d = origin[0] + np.arange(nx) * v1[0]
    y_1d = origin[1] + np.arange(ny) * v2[1]
    z_1d = origin[2] + np.arange(nz) * v3[2]
    return lines[:data_start], arr, (x_1d, y_1d, z_1d)
def write_cube(path, header, arr):
    with path.open("w") as f:
        for ln in header:
            f.write(ln + "\n")
        flat = arr.reshape(-1, order="C")
        for i in range(0, flat.size, 6):
            f.write(" ".join(f"{v:13.5e}" for v in flat[i:i+6]) + "\n")
def interp_to_ref(path, x_ref, y_ref, z_ref):
    h, arr, (x1,y1,z1) = read_cube_full(path)
    rgi = RegularGridInterpolator((x1,y1,z1), arr, bounds_error=False, fill_value=0.0)
    pts = np.stack(np.meshgrid(x_ref, y_ref, z_ref, indexing="ij"), axis=-1)
    return rgi(pts)
h_ab, rho_ab, grid_ab = read_cube_full(rho_ab_path)
x_ab, y_ab, z_ab = grid_ab
rho_a = interp_to_ref(rho_a_path, x_ab, y_ab, z_ab)
rho_b = interp_to_ref(rho_b_path, x_ab, y_ab, z_ab)
delta_rho = rho_ab - rho_a - rho_b
write_cube(out_path, h_ab, delta_rho)
print(f"  Δρ computed: min={delta_rho.min():.5e}, max={delta_rho.max():.5e} a.u.")
PYCHG
}

vmd_add_li_s_bonds_tcl() {
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
}

render_chgdiff_three_views() {
  local out_dir="$1" cube_file="$2" iso="$3" zoom="$4"
  {
    vmd_quality_preamble
    echo 'color change rgb 30 0.38 0.75 0.98'
    echo 'color change rgb 31 0.98 0.80 0.20'
    vmd_add_li_s_bonds_tcl
    cat <<EOF

mol new "$out_dir/$cube_file" type cube waitfor all
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
mol color ColorID 31
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top

mol representation Isosurface -$iso 0 0 0 1 1
mol color ColorID 30
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top

display resetview
scale by $zoom
render TachyonInternal "$out_dir/chgdiff_front.tga"

display resetview
rotate y by 90
scale by $zoom
render TachyonInternal "$out_dir/chgdiff_side.tga"

display resetview
rotate x by 90
scale by $zoom
render TachyonInternal "$out_dir/chgdiff_top.tga"

quit
EOF
  } > "$out_dir/render_chgdiff.tcl"
  "$VMD_EXE" -dispdev text -e "$out_dir/render_chgdiff.tcl" > "$out_dir/chgdiff_render.out" 2>&1
  for v in front side top; do
    [[ -f "$out_dir/chgdiff_${v}.tga" ]] || { echo "Missing chgdiff_${v}.tga" >&2; return 1; }
  done
}

annotate_chgdiff_images() {
  python3 - "$1" "$2" "${3:-}" "${4:-}" <<'PYANN'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
out_dir, iso_value = Path(sys.argv[1]), float(sys.argv[2])
frag1_q = sys.argv[3].strip() if len(sys.argv) > 3 and sys.argv[3] is not None else ""
frag2_q = sys.argv[4].strip() if len(sys.argv) > 4 and sys.argv[4] is not None else ""
def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try: return ImageFont.truetype(n, size)
        except: continue
    return ImageFont.load_default()
footer = f"Δρ iso = ±{iso_value:.4g} a.u.      blue = depletion      yellow = accumulation"
charge_line = ""
if frag1_q or frag2_q:
    # Keep wording stable and short for figure captions.
    charge_line = f"frag1 charge = {frag1_q} e      frag2 charge = {frag2_q} e"
for view in ("front","side","top"):
    tga_path = out_dir / f"chgdiff_{view}.tga"
    png_path = out_dir / f"chgdiff_{view}.png"
    with Image.open(tga_path) as src:
        src = src.convert("RGBA")
        w, h = src.size
        footer_h = max(55, int(0.06*h))
        if charge_line:
            footer_h = max(95, int(0.10*h))
        canvas = Image.new("RGBA", (w, h+footer_h), (255,255,255,255))
        canvas.paste(src, (0,0))
        draw = ImageDraw.Draw(canvas, "RGBA")
        fn = _font(bold=False, size=max(28, int(0.022*w)))
        fb = draw.textbbox((0,0), footer, font=fn)
        footer_w = (fb[2]-fb[0])
        footer_h_txt = (fb[3]-fb[1])
        if not charge_line:
            y0 = h + (footer_h - footer_h_txt)/2
            draw.text(((w-footer_w)/2, y0), footer, fill=(30,30,30,255), font=fn)
        else:
            # Two-line footer: iso info + fragment charges
            fn2 = _font(bold=False, size=max(28, int(0.020*w)))
            cb = draw.textbbox((0,0), charge_line, font=fn2)
            charge_w = (cb[2]-cb[0])
            charge_h_txt = (cb[3]-cb[1])
            total_txt_h = footer_h_txt + charge_h_txt + max(10, int(0.01*h))
            y0 = h + (footer_h - total_txt_h)/2
            draw.text(((w-footer_w)/2, y0), footer, fill=(30,30,30,255), font=fn)
            draw.text(((w-charge_w)/2, y0 + footer_h_txt + max(10, int(0.01*h))), charge_line, fill=(30,30,30,255), font=fn2)
        canvas.save(png_path, format="PNG")
    print(f"  {png_path}")
PYANN
}

###############################################################################
# VMD preamble for publication-quality rendering
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
TCLPRE
}

###############################################################################
# NCI / RDG: isosurface + scatter plot
###############################################################################
render_nci_views() {
  local out_dir="$1"
  local cube_a="$out_dir/func1.cub"
  local cube_b="$out_dir/func2.cub"
  [[ -f "$cube_a" && -f "$cube_b" ]] || {
    echo "Missing NCI cubes (func1.cub / func2.cub), skipping NCI render." >&2
    return 1
  }

  {
    vmd_quality_preamble
    vmd_add_li_s_bonds_tcl
    cat <<EOF

mol new "$cube_b" type cube waitfor all
mol addfile "$cube_a" type cube waitfor all
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

mol representation Isosurface $NCI_ISO 0 0 0 1 1
mol color Volume 1
mol selection all
material change opacity Transparent 0.75
mol material Transparent
mol addrep top

color scale method BGR
mol scaleminmax top 1 $NCI_MIN $NCI_MAX

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/nci_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/nci_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/nci_top.tga"

quit
EOF
  } > "$out_dir/render_nci.tcl"

  "$VMD_EXE" -dispdev text -e "$out_dir/render_nci.tcl" > "$out_dir/nci_render.out" 2>&1

  for v in front side top; do
    [[ -f "$out_dir/nci_${v}.tga" ]] || { echo "Missing nci_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" "$NCI_ISO" "$NCI_MIN" "$NCI_MAX" <<'PYNCI'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

out_dir = Path(sys.argv[1])
nci_iso = float(sys.argv[2])
nci_min = float(sys.argv[3])
nci_max = float(sys.argv[4])

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

def bgr_color(v):
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return 0, int(255*t), int(255*(1-t))
    t = (v - 0.5) / 0.5
    return int(255*t), int(255*(1-t)), 0

for view in ("front", "side", "top"):
    tga = out_dir / f"nci_{view}.tga"
    png = out_dir / f"nci_{view}.png"
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        legend_w = max(200, int(0.16 * w))
        footer_h = max(85, int(0.07 * h))
        canvas = Image.new("RGBA", (w + legend_w, h + footer_h), (255,255,255,255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas, "RGBA")

        arr = np.array(src.convert("RGB"))
        non_white = np.any(arr < 245, axis=2)
        ys, _ = np.where(non_white)
        obj_y0 = int(ys.min()) if ys.size > 0 else int(0.2*h)
        obj_y1 = int(ys.max()) if ys.size > 0 else int(0.8*h)
        obj_h = max(1, obj_y1 - obj_y0 + 1)
        obj_cy = (obj_y0 + obj_y1) // 2

        pad = 18
        bar_w = max(30, int(0.026*w))
        bar_h = min(max(int(obj_h*1.04), int(0.42*h)), h - 2*pad)
        x0 = w + int(legend_w * 0.28)
        y0 = max(pad, min(obj_cy - bar_h//2, h - pad - bar_h))
        x1 = x0 + bar_w
        y1 = y0 + bar_h

        for yy in range(y0, y1+1):
            t = 1.0 - (yy - y0) / max(1, y1 - y0)
            c = bgr_color(t)
            draw.line([(x0, yy), (x1, yy)], fill=(*c, 255))
        draw.rectangle([x0-1, y0-1, x1+1, y1+1], outline=(35,35,35,255), width=2)

        fv = _font(bold=True, size=max(26, int(0.020*w)))
        fn = _font(bold=False, size=max(32, int(0.024*w)))
        draw.text((x1+16, y0-2), f"+{nci_max:.3f}", fill=(28,28,28,255), font=fv)
        bb = draw.textbbox((0,0), f"{nci_min:.3f}", font=fv)
        draw.text((x1+16, y1-(bb[3]-bb[1])+2), f"{nci_min:.3f}", fill=(28,28,28,255), font=fv)
        uf = _font(False, max(19, int(0.015*w)))
        draw.text((x1+20, y1+(bb[3]-bb[1])+8), "sign(\u03bb\u2082)\u03c1", fill=(85,85,85,255), font=uf)

        footer = f"RDG iso = {nci_iso:.2g}      blue = attractive      green = vdW      red = repulsive"
        fb = draw.textbbox((0,0), footer, font=fn)
        draw.text(((canvas.width-(fb[2]-fb[0]))/2, h+(footer_h-(fb[3]-fb[1]))/2),
                  footer, fill=(30,30,30,255), font=fn)
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYNCI
}

render_nci_scatter() {
  local out_dir="$1"
  local scatter_data="$out_dir/output.txt"
  [[ -f "$scatter_data" ]] || { echo "No NCI scatter data (output.txt), skipping." >&2; return 1; }

  python3 - "$scatter_data" "$out_dir/nci_scatter.png" <<'PYSCT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

data_file = sys.argv[1]
out_png = sys.argv[2]

raw = np.loadtxt(data_file, comments='#')
if raw.ndim == 1:
    raw = raw.reshape(1, -1)

ncol = raw.shape[1]
if ncol >= 5:
    x = raw[:, 3]  # sign(lambda2)*rho
    y = raw[:, 4]  # RDG
elif ncol >= 2:
    x = raw[:, 0]
    y = raw[:, 1]
else:
    print("  Warning: unexpected output.txt format, skipping scatter.")
    sys.exit(0)

mask = y < 2.0
x = x[mask]
y = y[mask]

if x.size > 80000:
    idx = np.random.default_rng(42).choice(x.size, 80000, replace=False)
    x, y = x[idx], y[idx]

cmap = LinearSegmentedColormap.from_list('bgr', [
    (0.0, (0.0, 0.0, 1.0)),
    (0.33, (0.0, 0.75, 0.75)),
    (0.5, (0.0, 0.85, 0.0)),
    (0.67, (0.85, 0.85, 0.0)),
    (1.0, (1.0, 0.0, 0.0)),
])
xmin, xmax = -0.05, 0.05
norm_x = np.clip((x - xmin) / (xmax - xmin), 0, 1)
colors = cmap(norm_x)

fig, ax = plt.subplots(figsize=(8, 6), dpi=300)
ax.scatter(x, y, c=colors, s=4.0, alpha=0.75, edgecolors='none', rasterized=True)
ax.set_xlim(xmin, xmax)
ax.set_ylim(0, 2.0)
ax.set_xlabel('sign($\\lambda_2$)$\\rho$ (a.u.)', fontsize=20)
ax.set_ylabel('RDG', fontsize=20)
ax.tick_params(labelsize=16)
ax.set_title('NCI Scatter Plot', fontsize=26, fontweight='bold')
ax.axhline(y=0.5, color='gray', ls='--', lw=0.8, alpha=0.5)

sm = plt.cm.ScalarMappable(cmap=cmap, norm=plt.Normalize(vmin=xmin, vmax=xmax))
sm.set_array([])
cbar = fig.colorbar(sm, ax=ax, pad=0.02)
cbar.set_label('sign($\\lambda_2$)$\\rho$', fontsize=16)
cbar.ax.tick_params(labelsize=14)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  {out_png}")
PYSCT
}

###############################################################################
# IGMH three-view rendering
###############################################################################
render_igmh_views() {
  local out_dir="$1"
  local cube_a="$out_dir/sl2r.cub"
  local cube_b="$out_dir/dg_inter.cub"
  [[ -f "$cube_a" && -f "$cube_b" ]] || {
    echo "Missing IGMH cubes (sl2r.cub / dg_inter.cub), skipping render." >&2
    return 1
  }

  {
    vmd_quality_preamble
    vmd_add_li_s_bonds_tcl
    cat <<EOF

mol new "$cube_b" type cube waitfor all
mol addfile "$cube_a" type cube waitfor all
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

mol representation Isosurface $IGMH_ISO 0 0 0 1 1
mol color Volume 1
mol selection all
material change opacity Transparent 0.75
mol material Transparent
mol addrep top

# If atmdg.pdb exists, color atoms by δG_atom contribution
set atmpdb [file join [file dirname [molinfo top get filename]] "atmdg.pdb"]
if {[file exists \$atmpdb]} {
  mol new \$atmpdb type pdb waitfor all
  mol representation CPK 0.8 0.3 30.0 30.0
  mol color Occupancy
  mol selection all
  mol material Glossy
  mol addrep top
  mol scaleminmax top 0 0.0 50.0
}

color scale method BGR
mol scaleminmax top 1 $IGMH_COLOR_MIN $IGMH_COLOR_MAX

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/igmh_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/igmh_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/igmh_top.tga"

quit
EOF
  } > "$out_dir/render_igmh.tcl"

  if [[ -z "${VMD_EXE:-}" ]]; then
    echo "  WARNING: VMD not found, skipping IGMH/mIGM rendering." >&2
    return 1
  fi
  "$VMD_EXE" -dispdev text -e "$out_dir/render_igmh.tcl" > "$out_dir/igmh_render.out" 2>&1

  for v in front side top; do
    [[ -f "$out_dir/igmh_${v}.tga" ]] || { echo "Missing igmh_${v}.tga" >&2; return 1; }
  done

  python3 - "$out_dir" "$IGMH_ISO" "$IGMH_COLOR_MIN" "$IGMH_COLOR_MAX" <<'PYIGMH'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

out_dir = Path(sys.argv[1])
igmh_iso = float(sys.argv[2])
igmh_min = float(sys.argv[3])
igmh_max = float(sys.argv[4])

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

def bgr_color(v):
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return 0, int(255*t), int(255*(1-t))
    t = (v - 0.5) / 0.5
    return int(255*t), int(255*(1-t)), 0

for view in ("front", "side", "top"):
    tga = out_dir / f"igmh_{view}.tga"
    png = out_dir / f"igmh_{view}.png"
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        legend_w = max(200, int(0.16 * w))
        footer_h = max(85, int(0.07 * h))
        canvas = Image.new("RGBA", (w + legend_w, h + footer_h), (255,255,255,255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas, "RGBA")

        arr = np.array(src.convert("RGB"))
        non_white = np.any(arr < 245, axis=2)
        ys, _ = np.where(non_white)
        obj_y0 = int(ys.min()) if ys.size > 0 else int(0.2*h)
        obj_y1 = int(ys.max()) if ys.size > 0 else int(0.8*h)
        obj_h = max(1, obj_y1 - obj_y0 + 1)
        obj_cy = (obj_y0 + obj_y1) // 2

        pad = 18
        bar_w = max(30, int(0.026*w))
        bar_h = min(max(int(obj_h*1.04), int(0.42*h)), h - 2*pad)
        x0 = w + int(legend_w * 0.28)
        y0 = max(pad, min(obj_cy - bar_h//2, h - pad - bar_h))
        x1 = x0 + bar_w
        y1 = y0 + bar_h

        for yy in range(y0, y1+1):
            t = 1.0 - (yy - y0) / max(1, y1 - y0)
            c = bgr_color(t)
            draw.line([(x0, yy), (x1, yy)], fill=(*c, 255))
        draw.rectangle([x0-1, y0-1, x1+1, y1+1], outline=(35,35,35,255), width=2)

        fv = _font(bold=True, size=max(26, int(0.020*w)))
        fn = _font(bold=False, size=max(32, int(0.024*w)))
        draw.text((x1+16, y0-2), f"+{igmh_max:.3f}", fill=(28,28,28,255), font=fv)
        bb = draw.textbbox((0,0), f"{igmh_min:.3f}", font=fv)
        draw.text((x1+16, y1-(bb[3]-bb[1])+2), f"{igmh_min:.3f}", fill=(28,28,28,255), font=fv)
        uf = _font(False, max(19, int(0.015*w)))
        draw.text((x1+20, y1+(bb[3]-bb[1])+8), "sign(\\u03bb\\u2082)\\u03c1", fill=(85,85,85,255), font=uf)

        footer = (f"IGMH  \\u03b4g_inter iso = {igmh_iso:.4g}      "
                  "blue = attractive      green = vdW      red = repulsive")
        fb = draw.textbbox((0,0), footer, font=fn)
        draw.text(((canvas.width-(fb[2]-fb[0]))/2, h+(footer_h-(fb[3]-fb[1]))/2),
                  footer, fill=(30,30,30,255), font=fn)
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYIGMH
}

render_igmh_scatter() {
  local out_dir="$1"
  local scatter_mode="${2:-both}"   # inter, intra, both
  local yscale="${3:-log}"          # log or linear
  local scatter_data="$out_dir/output.txt"
  [[ -f "$scatter_data" ]] || { echo "No IGMH scatter data (output.txt), skipping." >&2; return 1; }

  # Build list of (mode, scale, suffix) to generate.
  # "both" default → all three variants; specific mode → single variant.
  local specs=""
  if [[ "$scatter_mode" == "both" ]]; then
    specs="both:log:both_log inter:log:inter_log both:linear:both_linear"
  elif [[ "$scatter_mode" == "inter" ]]; then
    specs="inter:${yscale}:inter_${yscale}"
  else
    specs="intra:${yscale}:intra_${yscale}"
  fi

  python3 - "$scatter_data" "$out_dir" "$specs" <<'PYSCT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

fname = sys.argv[1]
out_dir = sys.argv[2]
specs_str = sys.argv[3]    # e.g. "both:log:both_log inter:log:inter_log both:linear:both_linear"

# Parse specs into list of (mode, yscale, suffix)
specs = []
for tok in specs_str.split():
    parts = tok.split(':')
    if len(parts) == 3:
        specs.append((parts[0], parts[1], parts[2]))

raw = np.loadtxt(fname, comments='#')
if raw.ndim == 1:
    raw = raw.reshape(1, -1)

ncol = raw.shape[1]
# Multiwfn output.txt format (option 2 in post-process menu):
#   col 0 = delta_g_inter  col 1 = delta_g_intra
#   col 2 = delta_g         col 3 = sign(lambda2)*rho
sl2r_full  = raw[:, 3]
dg_inter_full = raw[:, 0]
dg_intra_full = raw[:, 1] if ncol >= 2 else np.zeros_like(dg_inter_full)

# Shared BGR colormap
cmap = LinearSegmentedColormap.from_list('bgr', [
    (0.0, (0.0, 0.0, 1.0)), (0.33, (0.0, 0.75, 0.75)),
    (0.5, (0.0, 0.85, 0.0)), (0.67, (0.85, 0.85, 0.0)),
    (1.0, (1.0, 0.0, 0.0)),
])
xmin, xmax = -0.05, 0.05

for scatter_mode, yscale, suffix in specs:
    out_png = f"{out_dir}/igmh_scatter_{suffix}.png"

    # Filter per this spec's needs
    mask = (sl2r_full > -0.2) & (sl2r_full < 0.2)
    if yscale == 'log':
        mask &= (dg_inter_full > 1e-10)
        if scatter_mode in ('intra', 'both'):
            mask &= (dg_intra_full > 1e-10)
    sl2r = sl2r_full[mask].copy()
    dg_inter = dg_inter_full[mask].copy()
    dg_intra = dg_intra_full[mask].copy()

    # Subsample for performance
    if sl2r.size > 80000:
        rng = np.random.default_rng(42)
        idx = rng.choice(sl2r.size, 80000, replace=False)
        sl2r = sl2r[idx]
        dg_inter = dg_inter[idx]
        dg_intra = dg_intra[idx]

    colors = cmap(np.clip((sl2r - xmin) / (xmax - xmin), 0, 1))

    fig, ax = plt.subplots(figsize=(8, 6), dpi=300)
    plot_inter = scatter_mode in ('inter', 'both')
    plot_intra = scatter_mode in ('intra', 'both')

    if plot_inter and dg_inter.size > 0:
        ax.scatter(sl2r, dg_inter, c=colors, s=4.0, alpha=0.75,
                   edgecolors='none', rasterized=True, label=r'$\delta g_{inter}$')
    if plot_intra and dg_intra.size > 0:
        ax.scatter(sl2r, dg_intra, s=2.5, alpha=0.35,
                   facecolors='#888888', edgecolors='none', rasterized=True,
                   label=r'$\delta g_{intra}$')

    ax.set_xlim(xmin, xmax)

    if yscale == 'log':
        ax.set_yscale('log')
        all_y = []
        if plot_inter and dg_inter.size > 0:
            all_y.append(dg_inter[dg_inter > 0])
        if plot_intra and dg_intra.size > 0:
            all_y.append(dg_intra[dg_intra > 0])
        if all_y:
            combined = np.concatenate(all_y)
            ylo = max(np.percentile(combined[combined > 0], 1) * 0.5, 1e-6)
            yhi = min(max(np.percentile(combined, 99), 0.1), 1.0)
            ax.set_ylim(ylo, yhi)
    else:
        yhi = 0
        if plot_inter and dg_inter.size > 0:
            yhi = max(yhi, np.percentile(dg_inter, 99.9))
        if plot_intra and dg_intra.size > 0:
            yhi = max(yhi, np.percentile(dg_intra, 99.9))
        ax.set_ylim(0, min(yhi * 1.05, 0.25))

    ax.set_xlabel(r'sign($\lambda_2$)$\rho$ (a.u.)', fontsize=20)
    ylabel = r'$\delta g$ (a.u.)'
    if yscale == 'log':
        ylabel += '  [log scale]'
    ax.set_ylabel(ylabel, fontsize=20)
    ax.tick_params(labelsize=16)

    title_parts = ['IGMH Scatter']
    if scatter_mode == 'both':
        title_parts.append(r'$\delta g_{inter}$ + $\delta g_{intra}$')
    elif scatter_mode == 'inter':
        title_parts.append(r'$\delta g_{inter}$ only')
    else:
        title_parts.append(r'$\delta g_{intra}$ only')
    ax.set_title(' — '.join(title_parts), fontsize=22, fontweight='bold')

    if plot_inter and plot_intra:
        ax.legend(fontsize=14, loc='upper right', framealpha=0.8)

    sm = plt.cm.ScalarMappable(cmap=cmap, norm=plt.Normalize(vmin=xmin, vmax=xmax))
    sm.set_array([])
    cbar = fig.colorbar(sm, ax=ax, pad=0.02)
    cbar.set_label(r'sign($\lambda_2$)$\rho$', fontsize=16)
    cbar.ax.tick_params(labelsize=14)

    fig.tight_layout()
    fig.savefig(out_png, dpi=300, bbox_inches='tight')
    plt.close(fig)
    print(f"  {out_png}")
PYSCT
}

###############################################################################
# Pre-checks
###############################################################################
if [[ "$PLOT_ONLY" -eq 0 ]]; then
  if [[ -d "electronic_structure/SP" ]]; then
    DIR_N="electronic_structure/SP"
  elif [[ -d "optimization" ]]; then
    DIR_N="optimization"
  else
    echo "Neither electronic_structure/SP nor optimization/ found. Run iqcap-opt.sh first." >&2; exit 1
  fi

  [[ -f "opt.xyz" ]] || { echo "opt.xyz not found. Run iqcap-opt.sh first." >&2; exit 1; }
  [[ -d "$DIR_N" ]] || { echo "Directory $DIR_N not found. Run iqcap-opt.sh first." >&2; exit 1; }
  [[ -f "$DIR_N/TZVP.molden.input" ]] || {
    if [[ "$RUN_NCI" -eq 1 || "$RUN_IGMH" -eq 1 || "$RUN_IRI" -eq 1 || "$RUN_CHGDIFF" -eq 1 || "$RUN_CDA" -eq 1 ]]; then
      echo "$DIR_N/TZVP.molden.input not found. Run iqcap-basic_elect_analysis.sh or iqcap-opt.sh with orca_2aim/orca_2mkl." >&2; exit 1
    else
      echo "  Note: $DIR_N/TZVP.molden.input not found, but no molden-dependent modules are enabled (mIGM/HS only need XYZ)."
    fi
  }

  MULTIWFN_EXE="$(resolve_bin_any "$MULTIWFN_BIN" "multiwfn" "Multiwfn" "Multiwfn_noGUI")" || {
    echo "Cannot find Multiwfn executable" >&2; exit 1
  }
else
  MULTIWFN_EXE=""
  if [[ -d "electronic_structure/SP" ]]; then
    DIR_N="electronic_structure/SP"
  elif [[ -d "optimization" ]]; then
    DIR_N="optimization"
  else
    DIR_N=""
  fi
  # CDA orbital images (orbitals/*.png) need Multiwfn to export MO cube from molden
  if [[ "$RUN_CDA" -eq 1 && ( "$CDA_PUB_ORBITALS" -eq 1 || "$CDA_ALL_ORBITALS" -eq 1 ) ]]; then
    MULTIWFN_EXE="$(resolve_bin_any "$MULTIWFN_BIN" "multiwfn" "Multiwfn" "Multiwfn_noGUI")" || {
      echo "WARNING: Multiwfn not found; CDA orbital images (orbitals/*.png) will be skipped in plot-only mode." >&2
    }
  fi
fi

if [[ "$RUN_NCI" -eq 1 || "$RUN_MIGM" -eq 1 || "$RUN_IGMH" -eq 1 || "$RUN_IRI" -eq 1 || "$RUN_HS" -eq 1 || "$RUN_CHGDIFF" -eq 1 || ( "$RUN_CDA" -eq 1 && "$CDA_PLOT" -eq 1 ) ]]; then
  VMD_EXE="$(resolve_bin_any "$VMD_BIN" "vmd" "VMD")" || { echo "Cannot find VMD executable" >&2; exit 1; }
  python3 -c "from PIL import Image" >/dev/null 2>&1 || {
    echo "ERROR: Python Pillow required. Install: pip install Pillow" >&2; exit 1
  }
  python3 -c "import numpy" >/dev/null 2>&1 || {
    echo "ERROR: Python numpy required. Install: pip install numpy" >&2; exit 1
  }
  python3 -c "import matplotlib" >/dev/null 2>&1 || {
    echo "ERROR: Python matplotlib required. Install: pip install matplotlib" >&2; exit 1
  }
fi

if [[ "$PLOT_ONLY" -eq 0 ]]; then
  NEED_FRAG=0
  [[ "$RUN_IGMH" -eq 1 || "$RUN_HS" -eq 1 || "$RUN_CHGDIFF" -eq 1 || "$RUN_CDA" -eq 1 ]] && NEED_FRAG=1
  if [[ "$NEED_FRAG" -eq 1 ]]; then
    if [[ -z "$FRAG1_ATOMS" || -z "$FRAG2_ATOMS" ]]; then
      echo "WARNING: No fragments provided (--frag1-atoms, --frag2-atoms)."
      echo "  IGMH, HS, chgdiff, and CDA require fragments. Running only NCI and IRI."
      RUN_IGMH=0
      RUN_HS=0
      RUN_CHGDIFF=0
      RUN_CDA=0
    else
      validate_fragment_partition "opt.xyz" "$FRAG1_ATOMS" "$FRAG2_ATOMS"
    fi
  fi

  if [[ "$RUN_CHGDIFF" -eq 1 || ( "$RUN_CDA" -eq 1 && "$CDA_SKIP_ORCA" -ne 1 ) ]]; then
    ORCA_EXE="$(resolve_bin_any "$ORCA_BIN" "orca")" || { echo "Cannot find ORCA executable" >&2; exit 1; }
    ORCA_2AIM_EXE="$(resolve_bin_any "$ORCA_2AIM_BIN" "orca_2aim")" || true
    ORCA_2MKL_EXE="$(resolve_bin_any "$ORCA_2MKL_BIN" "orca_2mkl")" || { echo "Cannot find orca_2mkl" >&2; exit 1; }
  fi
  if [[ "$RUN_CHGDIFF" -eq 1 ]]; then
    python3 -c "import scipy" >/dev/null 2>&1 || {
      echo "ERROR: Python scipy required for chgdiff. Install: pip install scipy" >&2; exit 1
    }
  fi
fi

mkdir -p "$OUTPUT_DIR"
PROJECT_ROOT="$PWD"

echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " $IQCAP_FULLNAME"
echo " Module: $IQCAP_MODULE (Weak Interaction Analysis)"
echo "========================================"
echo "  Output:   $PWD/$OUTPUT_DIR/"
echo "  Multiwfn: ${MULTIWFN_EXE:-(plot-only mode)}"
echo "  VMD:      ${VMD_EXE:-N/A}"
[[ "$PLOT_ONLY" -eq 1 ]] && echo "  Mode:     PLOT-ONLY (skip computation, re-render only)"
echo "  NCI:      $( [[ "$RUN_NCI" -eq 1 ]] && echo ON || echo OFF )"
echo "  IGMH:     $( [[ "$RUN_IGMH" -eq 1 ]] && echo ON || echo OFF )"
echo "  mIGM:     $( [[ "$RUN_MIGM" -eq 1 ]] && echo ON || echo OFF )"
echo "  IRI:      $( [[ "$RUN_IRI" -eq 1 ]] && echo ON || echo OFF )"
echo "  HS:       $( [[ "$RUN_HS" -eq 1 ]] && echo ON || echo OFF )"
echo "  Chgdiff:  $( [[ "$RUN_CHGDIFF" -eq 1 ]] && echo ON || echo OFF )"
echo "  CDA:      $( [[ "$RUN_CDA" -eq 1 ]] && echo ON || echo OFF )"
[[ -n "$FRAG1_ATOMS" ]] && echo "  Frag 1:   $FRAG1_ATOMS"
[[ -n "$FRAG2_ATOMS" ]] && echo "  Frag 2:   $FRAG2_ATOMS"
echo "========================================"

###############################################################################
# Module 1: NCI
###############################################################################
if [[ "$RUN_NCI" -eq 1 ]]; then
  echo ""
  echo "[*] ===== NCI / RDG Analysis ====="

  NCI_DIR="$OUTPUT_DIR/NCI"
  mkdir -p "$NCI_DIR"

  pushd "$NCI_DIR" >/dev/null

  if [[ "$PLOT_ONLY" -eq 0 ]]; then
    MOLDEN_ABS="$PROJECT_ROOT/$DIR_N/TZVP.molden.input"
    echo "[*] Running NCI / RDG analysis..."
    echo -e "20\n1\n3\n2\n3\n0\n0\nq" | "$MULTIWFN_EXE" "$MOLDEN_ABS" > out_nci.txt

    if [[ -f func1.cub && -f func2.cub ]]; then
      python3 - "$PWD" <<'PYNCIFILL'
import sys, numpy as np
from pathlib import Path
d = Path(sys.argv[1])
nci_lo, nci_hi = -0.05, 0.05

def read_cube(p):
    lines = p.read_text(encoding="utf-8", errors="ignore").splitlines()
    natom = int(lines[2].split()[0])
    nx,ny,nz = (int(lines[i].split()[0]) for i in (3,4,5))
    start = 6 + abs(natom)
    header = lines[:start]
    vals = []
    for ln in lines[start:]:
        vals.extend(float(x) for x in ln.split())
    return header, np.array(vals, dtype=float).reshape((nx,ny,nz), order="C")

def write_cube(p, header, arr):
    flat = arr.reshape(-1, order="C")
    with p.open("w") as f:
        for ln in header:
            f.write(ln + "\n")
        for i in range(0, flat.size, 6):
            f.write(" ".join(f"{v:13.5e}" for v in flat[i:i+6]) + "\n")

h1, srho = read_cube(d / "func1.cub")
h2, rdg = read_cube(d / "func2.cub")
mask = (srho < nci_lo) | (srho > nci_hi)
rdg[mask] = 100.0
write_cube(d / "func2.cub", h2, rdg)
print(f"  NCI fill: masked {mask.sum()} voxels outside [{nci_lo},{nci_hi}]")
PYNCIFILL
    fi
  fi

  if [[ -f func1.cub && -f func2.cub ]]; then
    echo "[*] Rendering NCI three views..."
    render_nci_views "$PWD"
    [[ -f output.txt ]] && { echo "[*] Generating NCI scatter plot..."; render_nci_scatter "$PWD"; }
  else
    echo "  WARNING: NCI cube files not found. Cannot render."
  fi

  popd >/dev/null
fi

###############################################################################
# Module 2: IGMH
###############################################################################
# Helper: temporarily set IGMvdwscl in Multiwfn's settings.ini, returns backup path
_igmh_enable_vdw_scl() {
  local mwfn_dir
  mwfn_dir="$(dirname "$MULTIWFN_EXE")"
  local ini="$mwfn_dir/settings.ini"
  [[ -f "$ini" ]] || return 1
  local bak="${ini}.igmh_bak_$$"
  cp "$ini" "$bak"
  if [[ "$IGMH_VDW_SCL" != "0" ]]; then
    sed -i "s/^  IGMvdwscl=.*/  IGMvdwscl= ${IGMH_VDW_SCL}/" "$ini"
    echo "  IGMvdwscl = ${IGMH_VDW_SCL} (was backed up)"
  fi
  echo "$bak"
}

_igmh_restore_vdw_scl() {
  local bak="$1"
  local mwfn_dir
  mwfn_dir="$(dirname "$MULTIWFN_EXE")"
  local ini="$mwfn_dir/settings.ini"
  [[ -f "$bak" && -f "$ini" ]] && mv "$bak" "$ini"
}

# Parse atmdg.txt → report top δG_pair and δG_atom
_igmh_parse_atmdg() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  echo ""
  echo "  ── IGMH δG index summary ──"

  # Fragment-level δG_atom: use simple field splitting
  awk '
    /^Atomic delta-g indices of fragment/ { frag=1; print ""; print "  "$0; next }
    frag && /^ Atom/ {
      # Format: " Atom    2 :    0.123846  (  64.98 % )"
      gsub(/[():]/, " ")
      printf "    Atom %3s  δG_atom=%-10s (%5s%%)\n", $2, $3, $4
      next
    }
    frag && /^$/ { frag=0 }
  ' "$f"

  # δG_pair: top entries
  echo ""
  awk '
    /^ Atomic pair delta-g indices/ { in_pair=1; next }
    in_pair && /^ *[0-9]+[[:space:]]+[0-9]+[[:space:]]*:/ {
      gsub(/[():]/, " ")
      printf "    Pair %s-%-3s  δG_pair=%-10s (%5s%%)\n", $1, $2, $3, $4
      count++
      if (count >= 6) exit
      next
    }
  ' "$f"

  # Total
  awk '/^ Sum of all atomic pair/ { print ""; print "  "$0; }' "$f"
  echo ""
}
if [[ "$RUN_IGMH" -eq 1 ]]; then
  echo ""
  echo "[*] ===== IGMH Analysis ====="

  IGMH_DIR="$OUTPUT_DIR/IGMH"
  mkdir -p "$IGMH_DIR"

  pushd "$IGMH_DIR" >/dev/null

  if [[ "$PLOT_ONLY" -eq 0 ]]; then
    MOLDEN_ABS="$PROJECT_ROOT/$DIR_N/TZVP.molden.input"

    # Temporarily enable IGMvdwscl acceleration
    VDW_BAK="$(_igmh_enable_vdw_scl)"
    trap '[[ -n "${VDW_BAK:-}" ]] && _igmh_restore_vdw_scl "$VDW_BAK"' EXIT

    # New Multiwfn sequence:
    #   20  → Visual study of weak interaction
    #   11  → IGMH analysis
    #   2   → Two fragments
    #   FRAG1_ATOMS / FRAG2_ATOMS
    #   4   → Grid: spacing + cover whole system
    #   IGMH_GRID (0.15)
    #   --- IGMH computes grid data ---
    #   2   → Output scatter points FIRST (unfiltered, full range)
    #   8   → Filter δg_inter outside sign(λ2)ρ range (for isosurface)
    #   COLOR_MIN,COLOR_MAX  → 0 (set to zero outside range)
    #   3   → Output .cub files (filtered, for VMD isosurface)
    #   6   → δG_atom / δG_pair evaluation
    #   2   → High quality
    #   y   → Export atmdg.pdb
    #   0   → Exit post-processing
    #   0   → Exit to main menu
    #   q   → Quit
    IGMH_INPUT="20\\n11\\n2\\n${FRAG1_ATOMS}\\n${FRAG2_ATOMS}\\n4\\n${IGMH_GRID}\\n2\\n8\\n${IGMH_COLOR_MIN},${IGMH_COLOR_MAX}\\n0\\n3\\n6\\n2\\ny\\n0\\n0\\nq"

    echo "[*] IGMH: frag1=$FRAG1_ATOMS  frag2=$FRAG2_ATOMS  grid=${IGMH_GRID}  vdwscl=${IGMH_VDW_SCL}"
    echo -e "$IGMH_INPUT" | "$MULTIWFN_EXE" "$MOLDEN_ABS" > igmh.out 2>&1

    # Restore settings.ini immediately (don't wait for EXIT trap)
    [[ -n "${VDW_BAK:-}" ]] && _igmh_restore_vdw_scl "$VDW_BAK" && VDW_BAK=""
    trap - EXIT

    # Parse atmdg.txt if it was generated
    if [[ -f atmdg.txt ]]; then
      _igmh_parse_atmdg "atmdg.txt"
    else
      echo "  NOTE: atmdg.txt not generated (δG indices unavailable)"
    fi
  fi

  if [[ -f sl2r.cub && -f dg_inter.cub ]]; then
    echo "  IGMH cubes: sl2r.cub, dg_inter.cub"
    [[ -f dg_intra.cub ]] && echo "  IGMH cubes: dg_intra.cub, dg.cub"
    echo "[*] Rendering IGMH three views..."
    render_igmh_views "$PWD"
    [[ -f output.txt ]] && { echo "[*] Generating IGMH scatter plot..."; render_igmh_scatter "$PWD" "$IGMH_SCATTER_MODE" "$IGMH_SCATTER_YSCALE"; }
  elif [[ -f func1.cub && -f func2.cub ]]; then
    ln -sf func1.cub sl2r.cub
    ln -sf func2.cub dg_inter.cub
    echo "  IGMH cubes (legacy names): func1.cub -> sl2r.cub, func2.cub -> dg_inter.cub"
    render_igmh_views "$PWD"
    [[ -f output.txt ]] && render_igmh_scatter "$PWD" "$IGMH_SCATTER_MODE" "$IGMH_SCATTER_YSCALE"
  else
    echo "  WARNING: IGMH cubes not found. Cannot render."
  fi

  popd >/dev/null
fi

###############################################################################
# Module 2.5: mIGM (geometry-only, no wavefunction needed)
###############################################################################
if [[ "$RUN_MIGM" -eq 1 ]]; then
  echo ""
  echo "[*] ===== mIGM Analysis (geometry-only) ====="

  MIGM_DIR="$OUTPUT_DIR/mIGM"
  mkdir -p "$MIGM_DIR"

  pushd "$MIGM_DIR" >/dev/null

  if [[ "$PLOT_ONLY" -eq 0 ]]; then
    # mIGM only needs XYZ — no molden/wfn required
    xyz_src=""
    if [[ -f "$PROJECT_ROOT/optimization/opt.xyz" ]]; then
      xyz_src="$PROJECT_ROOT/optimization/opt.xyz"
    elif [[ -f "$PROJECT_ROOT/0.xyz" ]]; then
      xyz_src="$PROJECT_ROOT/0.xyz"
    else
      # Search for any XYZ in project root
      xyz_src=$(ls "$PROJECT_ROOT"/*.xyz 2>/dev/null | head -1)
    fi
    if [[ -z "$xyz_src" ]]; then
      echo "  ERROR: No XYZ file found. mIGM requires a geometry file." >&2
    else
      # Build fragment definitions
      # frag1 = user-specified atoms, frag2 = complementary (all others)
      frag2_def="c"
      if [[ -n "$FRAG2_ATOMS" ]]; then
        frag2_def="$FRAG2_ATOMS"
      fi

      echo "  Input XYZ: $xyz_src"
      echo "  mIGM: frag1=$FRAG1_ATOMS  frag2=$frag2_def  grid=$MIGM_GRID Bohr"
      MIGM_INPUT="20\\n-10\\n2\\n${FRAG1_ATOMS}\\n${frag2_def}\\n4\\n${MIGM_GRID}\\n3\\n0\\n0\\nq"
      echo -e "$MIGM_INPUT" | "$MULTIWFN_EXE" "$xyz_src" > migm.out 2>&1
    fi
  fi

  if [[ -f sl2r.cub && -f dg_inter.cub ]]; then
    echo "  mIGM cubes: sl2r.cub, dg_inter.cub"
    echo "[*] Rendering mIGM three views..."
    render_igmh_views "$PWD"
    [[ -f output.txt ]] && { echo "[*] Generating mIGM scatter plot..."; render_igmh_scatter "$PWD" "$IGMH_SCATTER_MODE" "$IGMH_SCATTER_YSCALE"; }
  elif [[ -f func1.cub && -f func2.cub ]]; then
    ln -sf func1.cub sl2r.cub
    ln -sf func2.cub dg_inter.cub
    echo "  mIGM cubes (legacy names): func1.cub -> sl2r.cub, func2.cub -> dg_inter.cub"
    render_igmh_views "$PWD"
    [[ -f output.txt ]] && render_igmh_scatter "$PWD" "$IGMH_SCATTER_MODE" "$IGMH_SCATTER_YSCALE"
  else
    echo "  WARNING: mIGM cubes not found. Cannot render."
  fi

  popd >/dev/null
fi

###############################################################################
# Module 3: IRI
###############################################################################
if [[ "$RUN_IRI" -eq 1 ]]; then
  echo ""
  echo "[*] ===== IRI Analysis ====="

  IRI_DIR="$OUTPUT_DIR/IRI"
  mkdir -p "$IRI_DIR"

  pushd "$IRI_DIR" >/dev/null

  if [[ "$PLOT_ONLY" -eq 0 ]]; then
    MOLDEN_ABS="$PROJECT_ROOT/$DIR_N/TZVP.molden.input"
    echo "[*] Computing IRI grid data..."
    echo -e "20\n4\n-10\n6\n4\n0.08\n2\n3\n0\n0\nq" | "$MULTIWFN_EXE" "$MOLDEN_ABS" > iri.out 2>&1
  fi

  if [[ -f func1.cub && -f func2.cub ]]; then
    echo "  IRI cubes: func1.cub (sign(l2)*rho), func2.cub (IRI)"

    {
      vmd_quality_preamble
      vmd_add_li_s_bonds_tcl
      cat <<EOF

mol new "$PWD/func2.cub" type cube waitfor all
mol addfile "$PWD/func1.cub" type cube waitfor all
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

mol representation Isosurface $IRI_ISO 0 0 0 1 1
mol color Volume 1
mol selection all
mol material Opaque
mol addrep top

color scale method BGR
mol scaleminmax top 1 $IRI_COLOR_MIN $IRI_COLOR_MAX

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$PWD/iri_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$PWD/iri_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$PWD/iri_top.tga"

quit
EOF
    } > "$PWD/render_iri.tcl"

    echo "[*] Rendering IRI three views..."
    "$VMD_EXE" -dispdev text -e "$PWD/render_iri.tcl" > "$PWD/iri_render.out" 2>&1

    python3 - "$PWD" "$IRI_ISO" "$IRI_COLOR_MIN" "$IRI_COLOR_MAX" <<'PYIRI'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

out_dir = Path(sys.argv[1])
iri_iso = float(sys.argv[2])
iri_min = float(sys.argv[3])
iri_max = float(sys.argv[4])

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try: return ImageFont.truetype(n, size)
        except Exception: continue
    return ImageFont.load_default()

def bgr_color(v):
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return 0, int(255*t), int(255*(1-t))
    t = (v - 0.5) / 0.5
    return int(255*t), int(255*(1-t)), 0

for view in ("front", "side", "top"):
    tga = out_dir / f"iri_{view}.tga"
    png = out_dir / f"iri_{view}.png"
    if not tga.exists():
        continue
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        legend_w = max(200, int(0.16 * w))
        footer_h = max(85, int(0.07 * h))
        canvas = Image.new("RGBA", (w + legend_w, h + footer_h), (255,255,255,255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas, "RGBA")

        arr = np.array(src.convert("RGB"))
        non_white = np.any(arr < 245, axis=2)
        ys, _ = np.where(non_white)
        obj_y0 = int(ys.min()) if ys.size > 0 else int(0.2*h)
        obj_y1 = int(ys.max()) if ys.size > 0 else int(0.8*h)
        obj_cy = (obj_y0 + obj_y1) // 2

        pad = 18
        bar_w = max(30, int(0.026*w))
        bar_h = min(max(int((obj_y1-obj_y0)*1.04), int(0.42*h)), h - 2*pad)
        x0 = w + int(legend_w * 0.28)
        y0 = max(pad, min(obj_cy - bar_h//2, h - pad - bar_h))
        x1 = x0 + bar_w; y1 = y0 + bar_h

        for yy in range(y0, y1+1):
            t = 1.0 - (yy - y0) / max(1, y1 - y0)
            c = bgr_color(t)
            draw.line([(x0, yy), (x1, yy)], fill=(*c, 255))
        draw.rectangle([x0-1, y0-1, x1+1, y1+1], outline=(35,35,35,255), width=2)

        fv = _font(bold=True, size=max(26, int(0.020*w)))
        fn = _font(bold=False, size=max(32, int(0.024*w)))
        draw.text((x1+16, y0-2), f"+{iri_max:.3f}", fill=(28,28,28,255), font=fv)
        bb = draw.textbbox((0,0), f"{iri_min:.3f}", font=fv)
        draw.text((x1+16, y1-(bb[3]-bb[1])+2), f"{iri_min:.3f}", fill=(28,28,28,255), font=fv)
        uf = _font(False, max(19, int(0.015*w)))
        draw.text((x1+20, y1+(bb[3]-bb[1])+8), "sign(\u03bb\u2082)\u03c1", fill=(85,85,85,255), font=uf)

        footer = (f"IRI iso = {iri_iso:.2g}      "
                  "blue = covalent/strong      green = vdW      red = steric")
        fb = draw.textbbox((0,0), footer, font=fn)
        draw.text(((canvas.width-(fb[2]-fb[0]))/2, h+(footer_h-(fb[3]-fb[1]))/2),
                  footer, fill=(30,30,30,255), font=fn)
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYIRI

    if [[ -f output.txt ]]; then
      echo "[*] Generating IRI scatter plot..."
      python3 - "$PWD/output.txt" "$PWD/iri_scatter.png" <<'PYIRISCT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

raw = np.loadtxt(sys.argv[1], comments='#', usecols=(3, 4))
x = raw[:, 0]   # sign(lambda2)*rho
y = raw[:, 1]   # IRI

mask = y < 2.5
x, y = x[mask], y[mask]
if x.size > 80000:
    idx = np.random.default_rng(42).choice(x.size, 80000, replace=False)
    x, y = x[idx], y[idx]

cmap = LinearSegmentedColormap.from_list('bgr', [
    (0.0, (0.0, 0.0, 1.0)), (0.33, (0.0, 0.75, 0.75)),
    (0.5, (0.0, 0.85, 0.0)), (0.67, (0.85, 0.85, 0.0)),
    (1.0, (1.0, 0.0, 0.0)),
])
xmin, xmax = -0.4, 0.1
colors = cmap(np.clip((x - xmin) / (xmax - xmin), 0, 1))

fig, ax = plt.subplots(figsize=(8, 6), dpi=300)
ax.scatter(x, y, c=colors, s=2.0, alpha=0.6, edgecolors='none', rasterized=True)
ax.set_xlim(xmin, xmax)
ax.set_ylim(0, 2.5)
ax.set_xlabel('sign($\\lambda_2$)$\\rho$ (a.u.)', fontsize=20)
ax.set_ylabel('IRI', fontsize=20)
ax.tick_params(labelsize=16)
ax.set_title('IRI Scatter Plot', fontsize=26, fontweight='bold')
ax.axhline(y=1.0, color='gray', ls='--', lw=0.8, alpha=0.5)

sm = plt.cm.ScalarMappable(cmap=cmap, norm=plt.Normalize(vmin=xmin, vmax=xmax))
sm.set_array([])
cbar = fig.colorbar(sm, ax=ax, pad=0.02)
cbar.set_label('sign($\\lambda_2$)$\\rho$', fontsize=16)
cbar.ax.tick_params(labelsize=14)

fig.tight_layout()
fig.savefig(sys.argv[2], dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  {sys.argv[2]}")
PYIRISCT
    fi
  else
    echo "  WARNING: IRI cubes not found. Cannot render."
  fi

  popd >/dev/null
fi

###############################################################################
# Module 3.5: Hirshfeld Surface (HS) Analysis
###############################################################################
if [[ "$RUN_HS" -eq 1 ]]; then
  echo ""
  echo "[*] ===== Hirshfeld Surface Analysis ====="

  HS_DIR="$OUTPUT_DIR/HS"
  mkdir -p "$HS_DIR"

  pushd "$HS_DIR" >/dev/null

  if [[ "$PLOT_ONLY" -eq 0 ]]; then
    XYZ_ABS="$PROJECT_ROOT/opt.xyz"
    echo "[*] Computing Hirshfeld surface (interior fragment: $FRAG1_ATOMS)..."
    HS_INPUT="12\n1\n5\n${FRAG1_ATOMS}\n0\n-2\n13\n8\n20\n3\n0\n1\n5\n-1\n-1\n-1\n-1\nq"
    echo -e "$HS_INPUT" | "$MULTIWFN_EXE" "$XYZ_ABS" > hs.out 2>&1
  fi

  if [[ -f surf.cub && -f mapfunc.cub ]]; then
    echo "  HS cubes: surf.cub (Hirshfeld weight), mapfunc.cub (promolecular density)"

    python3 - "$PWD/hs.out" <<'PYHSINFO'
import sys, re
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
m_vol = re.search(r'Volume:\s+[\d.]+\s+Bohr\^3\s+\(\s*([\d.]+)\s+Angstrom\^3\)', text)
m_area = re.search(r'Overall surface area:\s+[\d.]+\s+Bohr\^2\s+\(\s*([\d.]+)\s+Angstrom\^2\)', text)
if m_vol:
    print(f"  HS volume:  {m_vol.group(1)} Ang^3")
if m_area:
    print(f"  HS area:    {m_area.group(1)} Ang^2")
PYHSINFO

    python3 - "$PWD/hs.out" "$PWD/contact_areas.txt" <<'PYHSCONTACT'
import sys, re
from pathlib import Path
hs_out = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
out_path = Path(sys.argv[2])

m = re.search(r'Inside element, outside element.*?\n((?:\s+\w+-\w+\s+[\d.]+\s+[\d.]+\n)+)', hs_out)
m2 = re.search(r'The same as above.*?\n((?:\s+\S+\s+[\d.]+\s+[\d.]+\n)+)', hs_out)
m_area = re.search(r'Area of total contact surface is\s+([\d.]+)', hs_out)

lines = []
lines.append("Element Contact Area Analysis (Hirshfeld Surface)")
lines.append("=" * 60)
if m:
    lines.append("")
    lines.append(f"{'Inside-Outside':<16s}  {'Area(Ang^2)':>12s}  {'Pct(%)':>8s}")
    lines.append("-" * 45)
    for line in m.group(1).strip().split('\n'):
        parts = line.split()
        if len(parts) >= 3:
            lines.append(f"  {parts[0]:<16s} {parts[1]:>12s}  {parts[2]:>8s}")
if m2:
    lines.append("")
    lines.append(f"{'Combined':<16s}  {'Area(Ang^2)':>12s}  {'Pct(%)':>8s}")
    lines.append("-" * 45)
    for line in m2.group(1).strip().split('\n'):
        parts = line.split()
        if len(parts) >= 3:
            lines.append(f"  {parts[0]:<16s} {parts[1]:>12s}  {parts[2]:>8s}")
if m_area:
    lines.append("")
    lines.append(f"Total contact surface area: {m_area.group(1)} Ang^2")

out_path.write_text('\n'.join(lines) + '\n')
print(f"  Contact areas saved: {out_path}")
PYHSCONTACT

    python3 - "$PWD/hs.out" "$PWD/contact_pie.png" <<'PYHSPIE'
import sys, re
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

hs_out = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
out_png = sys.argv[2]

m = re.search(r'The same as above.*?\n((?:\s+\S+\s+[\d.]+\s+[\d.]+\n)+)', hs_out)
if not m:
    m = re.search(r'Inside element.*?\n((?:\s+\w+-\w+\s+[\d.]+\s+[\d.]+\n)+)', hs_out)
if not m:
    print("  No contact data found for pie chart")
    sys.exit(0)

labels, sizes = [], []
for line in m.group(1).strip().split('\n'):
    parts = line.split()
    if len(parts) >= 3:
        labels.append(parts[0])
        sizes.append(float(parts[2]))

if not labels:
    sys.exit(0)

threshold = 2.0
other_pct = sum(s for s in sizes if s < threshold)
main_labels = [l for l, s in zip(labels, sizes) if s >= threshold]
main_sizes = [s for s in sizes if s >= threshold]
if other_pct > 0:
    main_labels.append('Other')
    main_sizes.append(other_pct)

colors = plt.cm.Set3(range(len(main_labels)))
fig, ax = plt.subplots(figsize=(8, 6), dpi=300)
wedges, texts, autotexts = ax.pie(
    main_sizes, labels=main_labels, autopct='%1.1f%%',
    colors=colors, pctdistance=0.82, startangle=90,
    textprops={'fontsize': 12})
for t in autotexts:
    t.set_fontsize(10)
ax.set_title('Hirshfeld Surface Contact Area Distribution',
             fontsize=16, fontweight='bold', pad=20)
fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  {out_png}")
PYHSPIE

    {
      vmd_quality_preamble
      vmd_add_li_s_bonds_tcl
      cat <<EOF

mol new "$PWD/surf.cub" type cube waitfor all
mol addfile "$PWD/mapfunc.cub" type cube waitfor all
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

mol representation Isosurface 0.5 0 0 0 1 1
mol color Volume 1
mol selection all
material change opacity Transparent 0.70
mol material Transparent
mol addrep top

color scale method BWR
mol scaleminmax top 1 $HS_COLOR_MIN $HS_COLOR_MAX

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$PWD/hs_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$PWD/hs_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$PWD/hs_top.tga"

quit
EOF
    } > "$PWD/render_hs.tcl"

    echo "[*] Rendering Hirshfeld surface three views..."
    "$VMD_EXE" -dispdev text -e "$PWD/render_hs.tcl" > "$PWD/hs_render.out" 2>&1

    python3 - "$PWD" "$HS_COLOR_MIN" "$HS_COLOR_MAX" <<'PYHSANN'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

out_dir = Path(sys.argv[1])
hs_min = float(sys.argv[2])
hs_max = float(sys.argv[3])

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try: return ImageFont.truetype(n, size)
        except Exception: continue
    return ImageFont.load_default()

def bwr_color(v):
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return (int(255*t), int(255*t), 255)
    t = (v - 0.5) / 0.5
    return (255, int(255*(1-t)), int(255*(1-t)))

for view in ("front", "side", "top"):
    tga = out_dir / f"hs_{view}.tga"
    png = out_dir / f"hs_{view}.png"
    if not tga.exists():
        continue
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        legend_w = max(200, int(0.16 * w))
        footer_h = max(85, int(0.07 * h))
        canvas = Image.new("RGBA", (w + legend_w, h + footer_h), (255,255,255,255))
        canvas.paste(src, (0, 0))
        draw = ImageDraw.Draw(canvas, "RGBA")

        arr = np.array(src.convert("RGB"))
        non_white = np.any(arr < 245, axis=2)
        ys, _ = np.where(non_white)
        obj_y0 = int(ys.min()) if ys.size > 0 else int(0.2*h)
        obj_y1 = int(ys.max()) if ys.size > 0 else int(0.8*h)
        obj_cy = (obj_y0 + obj_y1) // 2

        pad = 18
        bar_w = max(30, int(0.026*w))
        bar_h = min(max(int((obj_y1-obj_y0)*1.04), int(0.42*h)), h - 2*pad)
        x0 = w + int(legend_w * 0.28)
        y0 = max(pad, min(obj_cy - bar_h//2, h - pad - bar_h))
        x1 = x0 + bar_w; y1 = y0 + bar_h

        for yy in range(y0, y1+1):
            t = 1.0 - (yy - y0) / max(1, y1 - y0)
            c = bwr_color(t)
            draw.line([(x0, yy), (x1, yy)], fill=(*c, 255))
        draw.rectangle([x0-1, y0-1, x1+1, y1+1], outline=(35,35,35,255), width=2)

        fv = _font(bold=True, size=max(26, int(0.020*w)))
        fn = _font(bold=False, size=max(32, int(0.024*w)))
        draw.text((x1+16, y0-2), f"{hs_max:.4g}", fill=(28,28,28,255), font=fv)
        bb = draw.textbbox((0,0), f"{hs_min:.4g}", font=fv)
        draw.text((x1+16, y1-(bb[3]-bb[1])+2), f"{hs_min:.4g}", fill=(28,28,28,255), font=fv)
        uf = _font(False, max(19, int(0.015*w)))
        draw.text((x1+20, y1+(bb[3]-bb[1])+8), "\u03c1(promol) / a.u.", fill=(85,85,85,255), font=uf)

        footer = ("Hirshfeld Surface (\u03c1 colored)      "
                  "blue = weak      white = moderate      red = strong interaction")
        fb = draw.textbbox((0,0), footer, font=fn)
        draw.text(((canvas.width-(fb[2]-fb[0]))/2, h+(footer_h-(fb[3]-fb[1]))/2),
                  footer, fill=(30,30,30,255), font=fn)
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYHSANN

    HS_DIDE=""
    shopt -s nullglob
    for _f in dide.txt di_de.txt *.txt; do
      [[ "$_f" == "contact_areas.txt" ]] && continue
      if head -3 "$_f" 2>/dev/null | grep -qE '^\s*[0-9.]+\s+[0-9.]+'; then
        HS_DIDE="$_f"; break
      fi
    done
    shopt -u nullglob
    if [[ -n "$HS_DIDE" ]]; then
      echo "[*] Generating HS fingerprint scatter plot..."
      python3 - "$PWD/$HS_DIDE" "$PWD/hs_fingerprint.png" <<'PYHSFP'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

data_file = sys.argv[1]
out_png = sys.argv[2]

raw = np.loadtxt(data_file, comments='#')
if raw.ndim == 1:
    raw = raw.reshape(1, -1)

di = raw[:, 0]
de = raw[:, 1]

xmin, xmax = 0.6, 2.6
bins = 150
hist, xedges, yedges = np.histogram2d(di, de, bins=bins,
                                       range=[[xmin, xmax], [xmin, xmax]])
xi = np.clip(np.searchsorted(xedges[:-1], di) - 1, 0, bins - 1)
yi = np.clip(np.searchsorted(yedges[:-1], de) - 1, 0, bins - 1)
density = hist[xi, yi]

if di.size > 80000:
    idx = np.random.default_rng(42).choice(di.size, 80000, replace=False)
    di, de, density = di[idx], de[idx], density[idx]

fig, ax = plt.subplots(figsize=(7, 6.5), dpi=300)
sc = ax.scatter(di, de, c=density, cmap='viridis', s=15.0, alpha=0.75,
                edgecolors='none', rasterized=True)
ax.plot([xmin, xmax], [xmin, xmax], color='gray', ls='--', lw=0.8, alpha=0.5)
ax.set_xlim(xmin, xmax)
ax.set_ylim(xmin, xmax)
ax.set_xlabel('$d_i$ (Angstrom)', fontsize=20)
ax.set_ylabel('$d_e$ (Angstrom)', fontsize=20)
ax.tick_params(labelsize=16)
ax.set_title('Hirshfeld Surface Fingerprint', fontsize=22, fontweight='bold')
ax.set_aspect('equal')
ax.grid(True, color='gray', alpha=0.3, linestyle='-', linewidth=0.5)

cbar = fig.colorbar(sc, ax=ax, pad=0.02, shrink=0.9)
cbar.set_label('Count', fontsize=16)
cbar.ax.tick_params(labelsize=14)

fig.tight_layout()
fig.savefig(out_png, dpi=300, bbox_inches='tight')
plt.close(fig)
print(f"  {out_png}")
PYHSFP
    else
      echo "  No d_i/d_e data file found, skipping fingerprint plot."
    fi

  else
    echo "  WARNING: HS cubes not found. Cannot render."
  fi

  popd >/dev/null
fi

###############################################################################
# Module 4: Chgdiff (Differential charge density Δρ = ρ(AB) - ρ(A) - ρ(B))
###############################################################################
if [[ "$RUN_CHGDIFF" -eq 1 ]]; then
  echo ""
  echo "[*] ===== Chgdiff (Differential Charge Density) ====="

  CHGDIFF_DIR="$OUTPUT_DIR/chgdiff"
  ROOT_ABS="$PWD"

  if [[ "$PLOT_ONLY" -eq 0 ]]; then
  WORKDIR="$CHGDIFF_DIR/chgdiff-work"
  mkdir -p "$WORKDIR"
  pushd "$WORKDIR" >/dev/null

  echo "[*] Extracting fragments..."
  extract_fragment_xyz "$ROOT_ABS/opt.xyz" "$FRAG1_ATOMS" "fragA.xyz"
  extract_fragment_xyz "$ROOT_ABS/opt.xyz" "$FRAG2_ATOMS" "fragB.xyz"

  CHG_FULL=0 CHG_A=0 CHG_B=0
  NEL_FULL=$(python3 - "$ROOT_ABS/opt.xyz" <<'PYNEL'
import sys
from pathlib import Path
zmap={'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'K':19,'Ca':20,'Br':35,'I':53}
lines=Path(sys.argv[1]).read_text().splitlines()
n=int(lines[0])
total=sum(zmap.get(ln.split()[0][0].upper()+(ln.split()[0][1:].lower() if len(ln.split()[0])>1 else ''),0) for ln in lines[2:2+n] if ln.strip())
print(total)
PYNEL
  ) || echo 10
  NEL_A=$(python3 -c "
from pathlib import Path
zmap={'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'K':19,'Ca':20,'Br':35,'I':53}
lines=Path('fragA.xyz').read_text().splitlines()
print(sum(zmap.get(ln.split()[0][0].upper()+(ln.split()[0][1:].lower() if len(ln.split()[0])>1 else ''),0) for ln in lines[2:] if ln.strip()))
" 2>/dev/null || echo 9)
  NEL_B=$(python3 -c "
from pathlib import Path
zmap={'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'K':19,'Ca':20,'Br':35,'I':53}
lines=Path('fragB.xyz').read_text().splitlines()
print(sum(zmap.get(ln.split()[0][0].upper()+(ln.split()[0][1:].lower() if len(ln.split()[0])>1 else ''),0) for ln in lines[2:] if ln.strip()))
" 2>/dev/null || echo 1)
  MULT_FULL=1; [[ $((NEL_FULL % 2)) -eq 1 ]] && MULT_FULL=2
  MULT_A=1;    [[ $((NEL_A % 2)) -eq 1 ]] && MULT_A=2
  MULT_B=1;    [[ $((NEL_B % 2)) -eq 1 ]] && MULT_B=2

  echo "[*] Running ORCA single-point (full, frag A, frag B)..."
  run_orca_sp "full" "full" "$CHG_FULL" "$MULT_FULL" "$ROOT_ABS/opt.xyz"
  run_orca_sp "fragA" "fragA" "$CHG_A" "$MULT_A" "fragA.xyz"
  run_orca_sp "fragB" "fragB" "$CHG_B" "$MULT_B" "fragB.xyz"

  echo "[*] Exporting density cubes via Multiwfn..."
  export_density_cube "full" "full.molden.input" "out_rho.txt"
  export_density_cube "fragA" "fragA.molden.input" "out_rho.txt"
  export_density_cube "fragB" "fragB.molden.input" "out_rho.txt"

  RHO_AB=$(cd full && find_density_cube) || { echo "No density cube in full/" >&2; popd >/dev/null; exit 1; }
  RHO_A=$(cd fragA && find_density_cube) || { echo "No density cube in fragA/" >&2; popd >/dev/null; exit 1; }
  RHO_B=$(cd fragB && find_density_cube) || { echo "No density cube in fragB/" >&2; popd >/dev/null; exit 1; }

  echo "[*] Computing Δρ = ρ(AB) - ρ(A) - ρ(B)..."
  compute_chgdiff_cube "full/$RHO_AB" "fragA/$RHO_A" "fragB/$RHO_B" "chgdiff.cub"

  echo "[*] Rendering chgdiff three-view images..."
  render_chgdiff_three_views "$PWD" "chgdiff.cub" "$CHGDIFF_ISO" "$CHGDIFF_ZOOM"
  echo "[*] Annotating PNG..."
  CHGDIFF_F1F2_CHARGES=$(python3 - "$FRAG1_ATOMS" "$FRAG2_ATOMS" "full/full.property.txt" <<'PYFQ' || true
import sys, re
from pathlib import Path
frag1_spec, frag2_spec, prop_path = sys.argv[1], sys.argv[2], Path(sys.argv[3])

def expand_atoms(spec: str):
    out = set()
    for p in re.split(r'[,\s]+', spec.strip()):
        if not p:
            continue
        if '-' in p:
            a, b = p.split('-', 1)
            out.update(range(int(a), int(b) + 1))
        else:
            out.add(int(p))
    return out

def parse_loewdin_charges(text: str):
    # ORCA property file block: $SCF_Loewdin_Population_Analysis ... &AtomicCharges ... index value
    m = re.search(r'\$SCF_Loewdin_Population_Analysis[\s\S]*?&AtomicCharges[\s\S]*?\n([\s\S]*?)\n\s*&Method\b', text)
    if not m:
        return {}
    block = m.group(1)
    charges = {}
    for line in block.splitlines():
        s = line.strip()
        if not s or s == '0':
            continue
        parts = s.split()
        if len(parts) >= 2 and parts[0].lstrip('+-').isdigit():
            try:
                charges[int(parts[0])] = float(parts[1])
            except Exception:
                pass
    return charges

if not prop_path.exists():
    raise SystemExit(0)
text = prop_path.read_text(errors='ignore')
q = parse_loewdin_charges(text)
if not q:
    raise SystemExit(0)

f1 = expand_atoms(frag1_spec)
f2 = expand_atoms(frag2_spec)
# FRAG specs are 1-based, property indices are 0-based.
f1_sum = sum(q.get(i-1, 0.0) for i in f1)
f2_sum = sum(q.get(i-1, 0.0) for i in f2)
print(f"{f1_sum:.4f} {f2_sum:.4f}")
PYFQ
  )
  CHGDIFF_F1_Q=$(awk '{print $1}' <<<"$CHGDIFF_F1F2_CHARGES")
  CHGDIFF_F2_Q=$(awk '{print $2}' <<<"$CHGDIFF_F1F2_CHARGES")
  annotate_chgdiff_images "$PWD" "$CHGDIFF_ISO" "${CHGDIFF_F1_Q:-}" "${CHGDIFF_F2_Q:-}"

  mkdir -p "$ROOT_ABS/$CHGDIFF_DIR"
  cp chgdiff.cub chgdiff_front.png chgdiff_side.png chgdiff_top.png "$ROOT_ABS/$CHGDIFF_DIR/"
  popd >/dev/null

  else
    if [[ -f "$CHGDIFF_DIR/chgdiff.cub" ]]; then
      pushd "$CHGDIFF_DIR" >/dev/null
      echo "[*] Rendering chgdiff three-view images..."
      render_chgdiff_three_views "$PWD" "chgdiff.cub" "$CHGDIFF_ISO" "$CHGDIFF_ZOOM"
      echo "[*] Annotating PNG..."
      CHGDIFF_PROP_PATH="full/full.property.txt"
      [[ -f "$CHGDIFF_PROP_PATH" ]] || CHGDIFF_PROP_PATH="chgdiff-work/full/full.property.txt"
      CHGDIFF_F1F2_CHARGES=$(python3 - "$FRAG1_ATOMS" "$FRAG2_ATOMS" "$CHGDIFF_PROP_PATH" <<'PYFQ' || true
import sys, re
from pathlib import Path
frag1_spec, frag2_spec, prop_path = sys.argv[1], sys.argv[2], Path(sys.argv[3])

def expand_atoms(spec: str):
    out = set()
    for p in re.split(r'[,\s]+', spec.strip()):
        if not p:
            continue
        if '-' in p:
            a, b = p.split('-', 1)
            out.update(range(int(a), int(b) + 1))
        else:
            out.add(int(p))
    return out

def parse_loewdin_charges(text: str):
    m = re.search(r'\$SCF_Loewdin_Population_Analysis[\s\S]*?&AtomicCharges[\s\S]*?\n([\s\S]*?)\n\s*&Method\b', text)
    if not m:
        return {}
    block = m.group(1)
    charges = {}
    for line in block.splitlines():
        s = line.strip()
        if not s or s == '0':
            continue
        parts = s.split()
        if len(parts) >= 2 and parts[0].lstrip('+-').isdigit():
            try:
                charges[int(parts[0])] = float(parts[1])
            except Exception:
                pass
    return charges

if not prop_path.exists():
    raise SystemExit(0)
text = prop_path.read_text(errors='ignore')
q = parse_loewdin_charges(text)
if not q:
    raise SystemExit(0)

f1 = expand_atoms(frag1_spec)
f2 = expand_atoms(frag2_spec)
f1_sum = sum(q.get(i-1, 0.0) for i in f1)
f2_sum = sum(q.get(i-1, 0.0) for i in f2)
print(f"{f1_sum:.4f} {f2_sum:.4f}")
PYFQ
      )
      CHGDIFF_F1_Q=$(awk '{print $1}' <<<"$CHGDIFF_F1F2_CHARGES")
      CHGDIFF_F2_Q=$(awk '{print $2}' <<<"$CHGDIFF_F1F2_CHARGES")
      annotate_chgdiff_images "$PWD" "$CHGDIFF_ISO" "${CHGDIFF_F1_Q:-}" "${CHGDIFF_F2_Q:-}"
      popd >/dev/null
    elif [[ -f "$CHGDIFF_DIR/chgdiff-work/chgdiff.cub" ]]; then
      pushd "$CHGDIFF_DIR/chgdiff-work" >/dev/null
      echo "[*] Rendering chgdiff three-view images..."
      render_chgdiff_three_views "$PWD" "chgdiff.cub" "$CHGDIFF_ISO" "$CHGDIFF_ZOOM"
      echo "[*] Annotating PNG..."
      CHGDIFF_F1F2_CHARGES=$(python3 - "$FRAG1_ATOMS" "$FRAG2_ATOMS" "full/full.property.txt" <<'PYFQ' || true
import sys, re
from pathlib import Path
frag1_spec, frag2_spec, prop_path = sys.argv[1], sys.argv[2], Path(sys.argv[3])

def expand_atoms(spec: str):
    out = set()
    for p in re.split(r'[,\s]+', spec.strip()):
        if not p:
            continue
        if '-' in p:
            a, b = p.split('-', 1)
            out.update(range(int(a), int(b) + 1))
        else:
            out.add(int(p))
    return out

def parse_loewdin_charges(text: str):
    m = re.search(r'\$SCF_Loewdin_Population_Analysis[\s\S]*?&AtomicCharges[\s\S]*?\n([\s\S]*?)\n\s*&Method\b', text)
    if not m:
        return {}
    block = m.group(1)
    charges = {}
    for line in block.splitlines():
        s = line.strip()
        if not s or s == '0':
            continue
        parts = s.split()
        if len(parts) >= 2 and parts[0].lstrip('+-').isdigit():
            try:
                charges[int(parts[0])] = float(parts[1])
            except Exception:
                pass
    return charges

if not prop_path.exists():
    raise SystemExit(0)
text = prop_path.read_text(errors='ignore')
q = parse_loewdin_charges(text)
if not q:
    raise SystemExit(0)

f1 = expand_atoms(frag1_spec)
f2 = expand_atoms(frag2_spec)
f1_sum = sum(q.get(i-1, 0.0) for i in f1)
f2_sum = sum(q.get(i-1, 0.0) for i in f2)
print(f"{f1_sum:.4f} {f2_sum:.4f}")
PYFQ
      )
      CHGDIFF_F1_Q=$(awk '{print $1}' <<<"$CHGDIFF_F1F2_CHARGES")
      CHGDIFF_F2_Q=$(awk '{print $2}' <<<"$CHGDIFF_F1F2_CHARGES")
      annotate_chgdiff_images "$PWD" "$CHGDIFF_ISO" "${CHGDIFF_F1_Q:-}" "${CHGDIFF_F2_Q:-}"
      mkdir -p "$ROOT_ABS/$CHGDIFF_DIR"
      cp chgdiff_front.png chgdiff_side.png chgdiff_top.png "$ROOT_ABS/$CHGDIFF_DIR/" 2>/dev/null || true
      popd >/dev/null
    else
      echo "  WARNING: chgdiff.cub not found. Cannot render."
    fi
  fi
fi

###############################################################################
# Module 5: CDA (Charge Decomposition Analysis)
###############################################################################
if [[ "$RUN_CDA" -eq 1 ]]; then
  echo ""
  echo "[*] ===== CDA Analysis ====="

  CDA_DIR="$OUTPUT_DIR/CDA"
  mkdir -p "$CDA_DIR"

  if [[ "$PLOT_ONLY" -eq 0 ]]; then

  if [[ "$CDA_TOTAL_CHARGE" = "auto" ]]; then
    CDA_TOTAL_CHARGE=$(read_charge_from_optimization)
    echo "[*] Total charge from optimization: $CDA_TOTAL_CHARGE"
  fi

  CDA_NEED_REORDER=$(fragments_need_reorder_for_cda "opt.xyz" "$FRAG1_ATOMS" "$FRAG2_ATOMS")
  N_FRAG1=$(python3 - "$FRAG1_ATOMS" <<'PYN'
import sys, re
def expand(s):
    idx = []
    for p in re.split(r'[,\s]+', s.strip()):
        if not p: continue
        if '-' in p:
            a, b = p.split('-', 1)
            idx.extend(range(int(a), int(b) + 1))
        else:
            idx.append(int(p))
    return len(set(idx))
print(expand(sys.argv[1]))
PYN
  )

  if [[ "$CDA_NEED_REORDER" = "1" ]]; then
    echo "[*] Fragments interleaved in xyz (frag1 not before frag2); reordering for CDA..."
    reorder_xyz_for_cda "opt.xyz" "$FRAG1_ATOMS" "$FRAG2_ATOMS" "$CDA_DIR/opt_cda.xyz"
    extract_fragments_from_reordered_xyz "$CDA_DIR/opt_cda.xyz" "$N_FRAG1" "$CDA_DIR/frag1.xyz" "$CDA_DIR/frag2.xyz"
    echo "  Fragment 1: $N_FRAG1 atoms (first in reordered xyz)"
    echo "  Fragment 2: $(($(head -1 "$CDA_DIR/opt_cda.xyz") - N_FRAG1)) atoms"

    echo "[*] Running ORCA SP on reordered complex (frag1 first, frag2 second)..."
    mkdir -p "$CDA_DIR/complex_cda"
    pushd "$CDA_DIR/complex_cda" >/dev/null
    cp "../opt_cda.xyz" geom.xyz
    CHG_FULL="$CDA_TOTAL_CHARGE"
    Z_FULL=$(python3 - "$PWD/geom.xyz" <<'PYNEL'
import sys
from pathlib import Path
zmap={'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'K':19,'Ca':20,'Br':35,'I':53}
lines=Path(sys.argv[1]).read_text().splitlines()
n=int(lines[0])
print(sum(zmap.get(ln.split()[0][0].upper()+(ln.split()[0][1:].lower() if len(ln.split()[0])>1 else ''),0) for ln in lines[2:2+n] if ln.strip()))
PYNEL
    ) || 10
    NEL_FULL=$((Z_FULL - CHG_FULL))
    MULT_FULL=1
    [[ $((NEL_FULL % 2)) -eq 1 ]] && MULT_FULL=2
    write_orca_input "complex.inp" "$SP_LEVEL" "$CHG_FULL" "$MULT_FULL" "geom.xyz"
    "$ORCA_EXE" "complex.inp" > s.out 2>&1 || true
    "$ORCA_2MKL_EXE" "complex" -emolden 2>&1 || true
    [[ -f "complex.molden.input" ]] || { echo "Failed complex molden for CDA. Check $CDA_DIR/complex_cda/s.out" >&2; popd >/dev/null; exit 1; }
    popd >/dev/null
    COMPLEX_MOLDEN="$PWD/$CDA_DIR/complex_cda/complex.molden.input"
  else
    echo "[*] Extracting fragment geometries..."
    extract_fragment_xyz "opt.xyz" "$FRAG1_ATOMS" "$CDA_DIR/frag1.xyz"
    extract_fragment_xyz "opt.xyz" "$FRAG2_ATOMS" "$CDA_DIR/frag2.xyz"
    echo "  Fragment 1: $(head -1 "$CDA_DIR/frag1.xyz") atoms"
    echo "  Fragment 2: $(head -1 "$CDA_DIR/frag2.xyz") atoms"
    COMPLEX_MOLDEN="$PWD/$DIR_N/TZVP.molden.input"
  fi

  HIRSHFELD_FILE=""
  for f in "$DIR_N/hirshfeld_charges.txt" "electronic_structure/SP/hirshfeld_charges.txt"; do
    [[ -f "$f" ]] && { HIRSHFELD_FILE="$f"; break; }
  done
  if [[ -n "$HIRSHFELD_FILE" ]]; then
    echo "[*] Using Hirshfeld charges from $HIRSHFELD_FILE to infer fragment charges"
  fi
  CDA_Q1_Q2=$(infer_closed_shell_charges "$CDA_DIR/frag1.xyz" "$CDA_DIR/frag2.xyz" "$CDA_TOTAL_CHARGE" "$HIRSHFELD_FILE" "$FRAG1_ATOMS" "$FRAG2_ATOMS")
  CDA_Q1=$(echo "$CDA_Q1_Q2" | awk '{print $1}')
  CDA_Q2=$(echo "$CDA_Q1_Q2" | awk '{print $2}')
  echo "[*] Inferred fragment charges for closed shell (total charge $CDA_TOTAL_CHARGE): frag1=$CDA_Q1, frag2=$CDA_Q2"
  {
    echo "# CDA fragment charges (auto-inferred for closed shell)"
    echo "# Total complex charge: $CDA_TOTAL_CHARGE"
    [[ -n "$HIRSHFELD_FILE" ]] && echo "# Guided by Hirshfeld charges from $HIRSHFELD_FILE"
    echo "frag1_charge=$CDA_Q1"
    echo "frag2_charge=$CDA_Q2"
  } > "$CDA_DIR/fragment_charges.txt"

  if [[ "$CDA_SKIP_ORCA" -ne 1 ]]; then
    for fidx in 1 2; do
      fdir="$CDA_DIR/frag${fidx}"
      mkdir -p "$fdir"
      cp "$CDA_DIR/frag${fidx}.xyz" "$fdir/geom.xyz"
      charge=$([ "$fidx" -eq 1 ] && echo "$CDA_Q1" || echo "$CDA_Q2")
      NEL_F=$(python3 - "$CDA_DIR/frag${fidx}.xyz" "$charge" <<'PYNEL'
import sys
from pathlib import Path
zmap={'H':1,'He':2,'Li':3,'Be':4,'B':5,'C':6,'N':7,'O':8,'F':9,'Na':11,'Mg':12,'Al':13,'Si':14,'P':15,'S':16,'Cl':17,'K':19,'Ca':20,'Br':35,'I':53}
lines=Path(sys.argv[1]).read_text().splitlines()
n=int(lines[0])
charge=int(sys.argv[2])
total=sum(zmap.get(ln.split()[0][0].upper()+(ln.split()[0][1:].lower() if len(ln.split()[0])>1 else ''),0) for ln in lines[2:2+n] if ln.strip())
print(total - charge)
PYNEL
      ) || 2
      mult=$([ $((NEL_F % 2)) -eq 1 ] && echo 2 || echo 1)
      pushd "$fdir" >/dev/null
      write_orca_input "frag${fidx}.inp" "$SP_LEVEL" "$charge" "$mult" "geom.xyz"
      echo "[*] Running ORCA SP for fragment $fidx (charge=$charge mult=$mult)..."
      "$ORCA_EXE" "frag${fidx}.inp" > s.out 2>&1 || true
      "$ORCA_2MKL_EXE" "frag${fidx}" -emolden 2>&1 || true
      [[ -f "frag${fidx}.molden.input" ]] || { echo "Failed molden for fragment $fidx. Check $fdir/s.out" >&2; popd >/dev/null; exit 1; }
      popd >/dev/null
    done
  else
    echo "[*] Skipping fragment ORCA (--cda-skip-orca)"
    for fidx in 1 2; do
      [[ -f "$CDA_DIR/frag${fidx}/frag${fidx}.molden.input" ]] || {
        echo "Missing $CDA_DIR/frag${fidx}/frag${fidx}.molden.input" >&2; exit 1
      }
    done
  fi

  FRAG1_MOLDEN="$PWD/$CDA_DIR/frag1/frag1.molden.input"
  FRAG2_MOLDEN="$PWD/$CDA_DIR/frag2/frag2.molden.input"

  pushd "$CDA_DIR" >/dev/null

  CDA_N_OCC=$(grep -c 'Occup=\s*2\.0' "$COMPLEX_MOLDEN" 2>/dev/null || echo 0)
  CDA_HOMO=$CDA_N_OCC
  CDA_LUMO=$((CDA_N_OCC + 1))
  CDA_Q_LO=$((CDA_HOMO - 5))
  CDA_Q_HI=$((CDA_LUMO + 5))
  [[ "$CDA_Q_LO" -lt 1 ]] && CDA_Q_LO=1

  COMP_QUERY="2"
  declare -A _cda_seen=()
  for oi in $(seq 1 25); do
    COMP_QUERY="${COMP_QUERY}\n${oi}"; _cda_seen[$oi]=1
  done
  for oi in $(seq "$CDA_Q_LO" "$CDA_Q_HI"); do
    [[ -z "${_cda_seen[$oi]:-}" ]] && COMP_QUERY="${COMP_QUERY}\n${oi}"
  done
  COMP_QUERY="${COMP_QUERY}\n0"
  unset _cda_seen

  echo "  CDA orbital query: 1-25 + ${CDA_Q_LO}-${CDA_Q_HI} (HOMO=$CDA_HOMO, LUMO=$CDA_LUMO)"
  CDA_INPUT="16\n2\n${FRAG1_MOLDEN}\n${FRAG2_MOLDEN}\n5\n10\n0\n${COMP_QUERY}\n-1\nq"
  echo "[*] Running Multiwfn CDA..."
  echo -e "$CDA_INPUT" | "$MULTIWFN_EXE" "$COMPLEX_MOLDEN" > cda.out 2>&1
  if grep -q "Sum:" cda.out 2>/dev/null; then
    echo "  CDA analysis completed."
    grep "Sum:" cda.out || true
  else
    echo "  WARNING: CDA may not have completed. Check cda.out"
  fi

  else
    # plot-only: set molden paths from existing run (no ORCA/Multiwfn above)
    if [[ -f "$CDA_DIR/complex_cda/complex.molden.input" ]]; then
      COMPLEX_MOLDEN="$PWD/$CDA_DIR/complex_cda/complex.molden.input"
    else
      COMPLEX_MOLDEN="$PWD/$DIR_N/TZVP.molden.input"
    fi
    FRAG1_MOLDEN="$PWD/$CDA_DIR/frag1/frag1.molden.input"
    FRAG2_MOLDEN="$PWD/$CDA_DIR/frag2/frag2.molden.input"
    pushd "$CDA_DIR" >/dev/null
  fi

  if [[ "$CDA_PLOT" -eq 1 ]]; then
   if [[ -f cda.out ]]; then
    echo "[*] Generating orbital interaction diagram..."
    python3 - "$PWD/cda.out" "$PWD/orbinteract.png" "$CDA_EMIN" "$CDA_EMAX" "$CDA_PLOT_MARGIN" <<'PYORB'
import sys, re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

cda_file, out_png = sys.argv[1], sys.argv[2]
e_lo, e_hi = float(sys.argv[3]), float(sys.argv[4])
plot_margin = float(sys.argv[5])
text = open(cda_file, encoding='utf-8', errors='ignore').read()

n_occ = 0
for m in re.finditer(r'Sum:\s+(\d+\.\d+)', text):
    n_occ = int(float(m.group(1))) // 2
    break

energy_blocks = {}
for m in re.finditer(
    r'Energy of molecular orbitals of (the complex|fragment\s+\d+),\s+in eV:\s*\n(.*?)(?=Energy of molecular|-----|\Z)',
    text, re.DOTALL
):
    label = m.group(1).strip().lower().replace('the ', '')
    vals = [float(x) for x in m.group(2).split()]
    energies = {}
    for i, ev in enumerate(vals, 1):
        occ = 2.0 if i <= n_occ else 0.0
        energies[i] = (ev, occ)
    energy_blocks[label] = energies

comp_data = {}
for m in re.finditer(
    r'Occupation number of orbital\s+(\d+) of the complex:\s*([\d.]+)(.*?)(?=Occupation number of orbital|Input the index|\Z)',
    text, re.DOTALL
):
    orb_idx, occ = int(m.group(1)), float(m.group(2))
    block = m.group(3)
    contribs = []
    for cm in re.finditer(r'Orbital\s+(\d+)\s+of fragment\s+(\d+).*?Contribution:\s*([\d.]+)\s*%', block):
        f_orb, f_id, pct = int(cm.group(1)), int(cm.group(2)), float(cm.group(3))
        if pct >= 1.0:
            contribs.append((f_id, f_orb, pct))
    if contribs:
        comp_data[orb_idx] = (occ, contribs)

complex_e = energy_blocks.get('complex', {})
frag1_e, frag2_e = {}, {}
for k, v in energy_blocks.items():
    if 'fragment' in k:
        if '1' in k: frag1_e = v
        elif '2' in k: frag2_e = v

frag_occ_lines = re.findall(r'Alpha electrons:\s+(\d+)', text)
for fi, fe in enumerate([frag1_e, frag2_e]):
    if fi < len(frag_occ_lines):
        n_f_occ = int(frag_occ_lines[fi + 1]) if fi + 1 < len(frag_occ_lines) else n_occ
        for idx in fe:
            ev, _ = fe[idx]
            fe[idx] = (ev, 2.0 if idx <= n_f_occ else 0.0)

if not complex_e:
    print("  WARNING: Could not parse orbital energies. Diagram not generated.")
    sys.exit(0)

def filt(edict):
    return {i: (ev, occ) for i, (ev, occ) in edict.items() if e_lo <= ev <= e_hi}

c_orbs, f1_orbs, f2_orbs = filt(complex_e), filt(frag1_e), filt(frag2_e)
if not c_orbs:
    print(f"  WARNING: No orbitals in [{e_lo}, {e_hi}] eV range")
    sys.exit(0)

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

all_ev_plot = [ev for ev, _ in list(c_orbs.values()) + list(f1_orbs.values()) + list(f2_orbs.values())]
e_min_plot = min(all_ev_plot)
e_max_plot = max(all_ev_plot)
e_range_plot = e_max_plot - e_min_plot
y_lim_lo = e_min_plot - e_range_plot * plot_margin
y_lim_hi = e_max_plot + e_range_plot * plot_margin
e_range = e_range_plot
min_gap = max(1.2, e_range * 0.04)

n_total = len(c_orbs) + len(f1_orbs) + len(f2_orbs)
fig_h = max(14, 10 + n_total * 0.25)
fig_w = max(12, fig_h * 0.8)
S = fig_h / 14.0

fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=200)
x_f1, x_c, x_f2 = 1.0, 3.5, 6.0
bw = 0.75
COL_F1, COL_C, COL_F2 = '#2244AA', '#333333', '#228B22'

def draw_orbs(orbs, xc, color, side='right'):
    pos = {}
    sorted_items = sorted(orbs.items(), key=lambda kv: kv[1][0])
    prev_label_y = -999
    for idx, (ev, occ) in sorted_items:
        ls, lw = ('-', 3.5*S) if occ > 0.5 else ('--', 2.0*S)
        ax.plot([xc-bw/2, xc+bw/2], [ev, ev], color=color, lw=lw, ls=ls, solid_capstyle='round')
        off = bw/2 + 0.15
        ha = 'right' if side == 'left' else 'left'
        tx = xc - off if side == 'left' else xc + off
        label_y = ev
        if abs(label_y - prev_label_y) < min_gap:
            label_y = prev_label_y + min_gap
        ax.text(tx, label_y, str(idx), fontsize=20*S, fontweight='bold', color=color, ha=ha, va='center')
        prev_label_y = label_y
        pos[idx] = ev
    return pos

pos_f1 = draw_orbs(f1_orbs, x_f1, COL_F1, 'left')
pos_c  = draw_orbs(c_orbs,  x_c,  COL_C,  'right')
pos_f2 = draw_orbs(f2_orbs, x_f2, COL_F2, 'right')

label_positions = []
def find_label_pos(mx, my):
    gap = max(1.0, e_range * 0.035)
    for lx, ly in label_positions:
        if abs(mx - lx) < 0.35 and abs(my - ly) < gap:
            my = ly + gap
    label_positions.append((mx, my))
    return mx, my

for c_idx, (occ, contribs) in comp_data.items():
    if c_idx not in pos_c: continue
    c_ev = pos_c[c_idx]
    for f_id, f_orb, pct in contribs:
        src = pos_f1 if f_id == 1 else pos_f2
        if f_orb not in src: continue
        f_ev = src[f_orb]
        alpha = min(1.0, max(0.35, pct / 50.0))
        lw = max(1.0*S, min(3.5*S, pct / 10.0 * S))
        if f_id == 1:
            ax.plot([x_f1+bw/2, x_c-bw/2], [f_ev, c_ev], color='#CC4444', alpha=alpha, lw=lw)
            mx = (x_f1+bw/2+x_c-bw/2) * 0.42
            my = f_ev * 0.55 + c_ev * 0.45
        else:
            ax.plot([x_c+bw/2, x_f2-bw/2], [c_ev, f_ev], color='#CC4444', alpha=alpha, lw=lw)
            mx = (x_c+bw/2+x_f2-bw/2) * 0.58
            my = c_ev * 0.55 + f_ev * 0.45
        mx, my = find_label_pos(mx, my)
        ax.text(mx, my, f'{pct:.0f}%', fontsize=17*S, fontweight='bold', color='#CC4444',
                ha='center', va='center',
                bbox=dict(boxstyle='round,pad=0.15', fc='white', ec='none', alpha=0.88))

ax.set_ylim(y_lim_lo, y_lim_hi)
ax.set_xlim(-0.3, 7.3)
ax.set_ylabel('Orbital energy (eV)', fontsize=28*S, fontweight='bold')
ax.set_xticks([x_f1, x_c, x_f2])
ax.set_xticklabels(['Frag. 1', 'Complex', 'Frag. 2'], fontsize=24*S, fontweight='bold')
ax.tick_params(axis='y', labelsize=22*S)
ax.tick_params(axis='both', width=2.5, length=7)
for spine in ax.spines.values():
    spine.set_linewidth(2.5)
ax.set_title('Orbital Interaction Diagram (CDA)', fontsize=30*S, fontweight='bold', pad=24)
occ_l = plt.Line2D([], [], color='gray', lw=3.5*S, ls='-', label='Occupied')
vir_l = plt.Line2D([], [], color='gray', lw=2.0*S, ls='--', label='Virtual')
ax.legend(handles=[occ_l, vir_l], loc='upper right', fontsize=18*S, framealpha=0.9)
ax.grid(axis='y', alpha=0.2, ls=':', lw=0.8)
fig.tight_layout()
fig.savefig(out_png, dpi=200, bbox_inches='tight')
plt.close(fig)
print(f"  Orbital interaction diagram: {out_png}")
PYORB

    echo "[*] Generating publication diagram (HOMO-2..LUMO+2)..."
    python3 - "$PWD/cda.out" "$PWD/orbinteract-pub.png" "$CDA_PLOT_MARGIN" "$PWD/orbinteract-pub-nomark.png" <<'PYORBPUB'
import sys, re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize
from matplotlib.cm import ScalarMappable

cda_file, out_png = sys.argv[1], sys.argv[2]
plot_margin = float(sys.argv[3])
out_png_nomark = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
text = open(cda_file, encoding='utf-8', errors='ignore').read()

n_occ_complex = 0
for m in re.finditer(r'Sum:\s+(\d+\.\d+)', text):
    n_occ_complex = int(float(m.group(1))) // 2; break

HOMO = n_occ_complex
LUMO = n_occ_complex + 1
show_complex = set(range(HOMO - 2, LUMO + 3))

energy_blocks = {}
for m in re.finditer(
    r'Energy of molecular orbitals of (the complex|fragment\s+\d+),\s+in eV:\s*\n(.*?)(?=Energy of molecular|-----|\Z)',
    text, re.DOTALL):
    label = m.group(1).strip().lower().replace('the ', '')
    vals = [float(x) for x in m.group(2).split()]
    energy_blocks[label] = {i+1: v for i, v in enumerate(vals)}

complex_e = energy_blocks.get('complex', {})
frag_e = {}
for k, v in energy_blocks.items():
    if 'fragment' in k:
        fid = '1' if '1' in k else '2'
        frag_e[fid] = v

frag_occ = {}
occ_lines = re.findall(r'Alpha electrons:\s+(\d+)', text)
if len(occ_lines) >= 3:
    frag_occ['1'] = int(occ_lines[1])
    frag_occ['2'] = int(occ_lines[2])

comp_data = {}
for m in re.finditer(
    r'Occupation number of orbital\s+(\d+) of the complex:\s*([\d.]+)(.*?)(?=Occupation number of orbital|Input the index|\Z)',
    text, re.DOTALL):
    orb_idx, occ = int(m.group(1)), float(m.group(2))
    block = m.group(3)
    contribs = []
    for cm in re.finditer(r'Orbital\s+(\d+)\s+of fragment\s+(\d+).*?Contribution:\s*([\d.]+)\s*%', block):
        f_orb, f_id, pct = int(cm.group(1)), cm.group(2), float(cm.group(3))
        if pct >= 1.0:
            contribs.append((f_id, f_orb, pct))
    if contribs:
        comp_data[orb_idx] = (occ, contribs)

show_f1, show_f2 = set(), set()
for c_idx in show_complex:
    if c_idx in comp_data:
        for f_id, f_orb, pct in comp_data[c_idx][1]:
            if f_id == '1': show_f1.add(f_orb)
            else: show_f2.add(f_orb)

c_orbs = {i: (complex_e[i], 2.0 if i <= HOMO else 0.0) for i in show_complex if i in complex_e}
f1_orbs = {i: (frag_e.get('1',{}).get(i,0), 2.0 if i <= frag_occ.get('1', HOMO) else 0.0)
           for i in show_f1 if i in frag_e.get('1',{})}
f2_orbs = {i: (frag_e.get('2',{}).get(i,0), 2.0 if i <= frag_occ.get('2', HOMO) else 0.0)
           for i in show_f2 if i in frag_e.get('2',{})}

all_ev = [ev for ev, _ in list(c_orbs.values()) + list(f1_orbs.values()) + list(f2_orbs.values())]
if not all_ev:
    print("  WARNING: No orbitals to show in pub diagram"); sys.exit(0)

e_min_data = min(all_ev)
e_max_data = max(all_ev)
e_range_data = e_max_data - e_min_data
e_lo = e_min_data - e_range_data * plot_margin
e_hi = e_max_data + e_range_data * plot_margin
e_range = e_hi - e_lo
min_gap = 0.1

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']
fig, ax = plt.subplots(figsize=(13, 10), dpi=200)
x_f1, x_c, x_f2 = 1.0, 3.5, 6.0
bw = 0.75
COL_F1, COL_C, COL_F2 = '#2244AA', '#333333', '#228B22'

homo_lumo_labels = {}
for i in show_complex:
    if i == HOMO: homo_lumo_labels[i] = 'HOMO'
    elif i == HOMO - 1: homo_lumo_labels[i] = 'HOMO-1'
    elif i == HOMO - 2: homo_lumo_labels[i] = 'HOMO-2'
    elif i == LUMO: homo_lumo_labels[i] = 'LUMO'
    elif i == LUMO + 1: homo_lumo_labels[i] = 'LUMO+1'
    elif i == LUMO + 2: homo_lumo_labels[i] = 'LUMO+2'

S = 1.0

def draw_orbs(orbs, xc, color, side='right', special_labels=None):
    pos = {}
    sorted_items = sorted(orbs.items(), key=lambda kv: kv[1][0])
    off = bw/2 + 0.15
    ha = 'right' if side == 'left' else 'left'
    tx = xc - off if side == 'left' else xc + off
    groups = []
    cur_grp = [sorted_items[0]] if sorted_items else []
    for item in sorted_items[1:] if sorted_items else []:
        prev_ev = cur_grp[-1][1][0]
        if abs(item[1][0] - prev_ev) < min_gap:
            cur_grp.append(item)
        else:
            groups.append(cur_grp)
            cur_grp = [item]
    if cur_grp:
        groups.append(cur_grp)
    for grp in groups:
        for idx, (ev, occ) in grp:
            ls, lw = ('-', 3.5) if occ > 0.5 else ('--', 2.0)
            ax.plot([xc-bw/2, xc+bw/2], [ev, ev], color=color, lw=lw, ls=ls, solid_capstyle='round')
            pos[idx] = ev
        lbls = []
        for idx, _ in grp:
            lbl = str(idx)
            if special_labels and idx in special_labels:
                lbl = f"{idx} ({special_labels[idx]})"
            lbls.append(lbl)
        label_y = sum(it[1][0] for it in grp) / len(grp)
        ax.text(tx, label_y, ', '.join(lbls), fontsize=18, fontweight='bold', color=color, ha=ha, va='center')
    return pos

pos_f1 = draw_orbs(f1_orbs, x_f1, COL_F1, 'left')
pos_c  = draw_orbs(c_orbs,  x_c,  COL_C,  'right', homo_lumo_labels)
pos_f2 = draw_orbs(f2_orbs, x_f2, COL_F2, 'right')

# 连线颜色按贡献百分含量映射到色阶 (0–100%)
pct_norm = Normalize(vmin=0, vmax=100)
cmap = plt.cm.get_cmap('YlOrRd')
lw_base = 2.0
for c_idx in show_complex:
    if c_idx not in comp_data or c_idx not in pos_c: continue
    occ, contribs = comp_data[c_idx]
    c_ev = pos_c[c_idx]
    for f_id, f_orb, pct in contribs:
        src = pos_f1 if f_id == '1' else pos_f2
        if f_orb not in src: continue
        f_ev = src[f_orb]
        line_color = cmap(pct_norm(pct))
        lw = max(1.0, min(3.5, lw_base * (0.5 + pct / 50.0)))
        if f_id == '1':
            ax.plot([x_f1+bw/2, x_c-bw/2], [f_ev, c_ev], color=line_color, lw=lw, solid_capstyle='round')
        else:
            ax.plot([x_c+bw/2, x_f2-bw/2], [c_ev, f_ev], color=line_color, lw=lw, solid_capstyle='round')
sm = ScalarMappable(cmap=cmap, norm=pct_norm)
sm.set_array([])
cbar = fig.colorbar(sm, ax=ax, shrink=0.55, aspect=28, pad=0.02)
cbar.set_label('Contribution (%)', fontsize=18, fontweight='bold')
cbar.ax.tick_params(labelsize=14)

ax.set_ylim(e_lo, e_hi)
ax.set_xlim(-0.3, 7.3)
ax.set_ylabel('Orbital energy (eV)', fontsize=26, fontweight='bold')
ax.set_xticks([x_f1, x_c, x_f2])
ax.set_xticklabels(['Frag. 1', 'Complex', 'Frag. 2'], fontsize=22, fontweight='bold')
ax.tick_params(axis='y', labelsize=20)
ax.tick_params(axis='both', width=2.5, length=7)
for spine in ax.spines.values():
    spine.set_linewidth(2.5)
ax.set_title('Orbital Interaction Diagram (CDA)', fontsize=28, fontweight='bold', pad=22)
occ_l = plt.Line2D([], [], color='gray', lw=3.5, ls='-', label='Occupied')
vir_l = plt.Line2D([], [], color='gray', lw=2.0, ls='--', label='Virtual')
ax.legend(handles=[occ_l, vir_l], loc='upper right', fontsize=16, framealpha=0.9)
ax.grid(axis='y', alpha=0.2, ls=':', lw=0.8)
fig.tight_layout()
fig.savefig(out_png, dpi=200, bbox_inches='tight')
print(f"  Publication diagram: {out_png}")
if out_png_nomark:
    for t in list(ax.texts):
        t.remove()
    fig.savefig(out_png_nomark, dpi=200, bbox_inches='tight')
    print(f"  Publication diagram (no labels): {out_png_nomark}")
plt.close(fig)
PYORBPUB

  python3 - "$PWD/cda.out" "$PWD/orbinteract-pub.md" "$PWD/fragment_charges.txt" <<'PYCDAMD'
import re
import sys
from pathlib import Path

cda_path = Path(sys.argv[1])
md_path = Path(sys.argv[2])
frag_charge_path = Path(sys.argv[3])

text = cda_path.read_text(encoding='utf-8', errors='ignore')

def parse_charge_file(path):
  charges = {}
  if not path.exists():
    return charges
  for match in re.finditer(r'frag(\d+)_charge=([-\d]+)', path.read_text(encoding='utf-8', errors='ignore')):
    charges[match.group(1)] = int(match.group(2))
  return charges

charges = parse_charge_file(frag_charge_path)

sum_match = re.search(r'Sum:\s+(\d+\.\d+)', text)
if not sum_match:
  raise SystemExit('Could not find CDA total electron count in cda.out')

n_occ_complex = int(float(sum_match.group(1))) // 2
homo = n_occ_complex
lumo = homo + 1
show_complex = list(range(homo - 2, lumo + 3))

alpha_matches = [tuple(int(x) for x in m.groups()) for m in re.finditer(r'Alpha electrons:\s+(\d+)\s+Beta electrons:\s+(\d+)\s+Multiplicity:\s+(\d+)', text)]
frag_occ = {'1': alpha_matches[1][0] if len(alpha_matches) > 1 else 0, '2': alpha_matches[2][0] if len(alpha_matches) > 2 else 0}

energy_blocks = {}
for match in re.finditer(
  r'Energy of molecular orbitals of (the complex|fragment\s+\d+),\s+in eV:\s*\n(.*?)(?=Energy of molecular|-----|\Z)',
  text,
  re.DOTALL,
):
  label = match.group(1).strip().lower().replace('the ', '')
  values = [float(x) for x in match.group(2).split()]
  energy_blocks[label] = {i + 1: value for i, value in enumerate(values)}

complex_e = energy_blocks.get('complex', {})
frag_e = {}
for key, value in energy_blocks.items():
  if 'fragment' in key:
    frag_e['1' if '1' in key else '2'] = value

comp_data = {}
for match in re.finditer(
  r'Occupation number of orbital\s+(\d+) of the complex:\s*([\d.]+)(.*?)(?=Occupation number of orbital|Input the index|\Z)',
  text,
  re.DOTALL,
):
  orb_idx = int(match.group(1))
  occ = float(match.group(2))
  block = match.group(3)
  contribs = []
  for cmatch in re.finditer(r'Orbital\s+(\d+)\s+of fragment\s+(\d+).*?Contribution:\s*([\d.]+)\s*%', block):
    f_orb = int(cmatch.group(1))
    f_id = cmatch.group(2)
    pct = float(cmatch.group(3))
    if pct >= 1.0:
      contribs.append((f_id, f_orb, pct))
  comp_data[orb_idx] = (occ, contribs)

def label_for(idx):
  if idx == homo - 2:
    return 'HOMO-2'
  if idx == homo - 1:
    return 'HOMO-1'
  if idx == homo:
    return 'HOMO'
  if idx == lumo:
    return 'LUMO'
  if idx == lumo + 1:
    return 'LUMO+1'
  if idx == lumo + 2:
    return 'LUMO+2'
  return f'MO {idx}'

def fmt_frag_orbital(f_id, f_orb, pct):
  f_energy = frag_e.get(f_id, {}).get(f_orb)
  occ_tag = 'occ' if f_orb <= frag_occ.get(f_id, 0) else 'vir'
  if f_energy is None:
    return f'Frag. {f_id} MO {f_orb}: {pct:.2f}%'
  return f'Frag. {f_id} MO {f_orb} ({f_energy:.4f} eV, {occ_tag}): {pct:.2f}%'

lines = []
lines.append('# CDA publication-orbital summary')
lines.append('')
lines.append('![Orbital interaction diagram](orbinteract-pub.png)')
lines.append('')
lines.append('## Metadata')
lines.append(f'- Source CDA output: {cda_path.name}')
lines.append(f'- Publication figure: orbinteract-pub.png')
if (cda_path.parent / 'orbinteract-pub-nomark.png').exists():
  lines.append(f'- Publication figure without labels: orbinteract-pub-nomark.png')
lines.append(f'- Complex HOMO index: {homo}')
lines.append(f'- Complex LUMO index: {lumo}')
lines.append(f'- Publication window: HOMO-2 .. LUMO+2, i.e. complex orbitals {show_complex[0]} .. {show_complex[-1]}')
if charges:
  lines.append(f'- Fragment charges: frag1 = {charges.get("1", 0)} e, frag2 = {charges.get("2", 0)} e')
lines.append('- Multiwfn only prints fragment-orbital contributions above 1.0%, so smaller terms are omitted here.')
lines.append('')
lines.append('## Publication orbital table')
lines.append('| Complex MO | Label | Energy (eV) | Occupation | Dominant fragment contributions |')
lines.append('| --- | --- | ---: | ---: | --- |')
for idx in show_complex:
  if idx not in complex_e:
    continue
  energy = complex_e[idx]
  occ, contribs = comp_data.get(idx, (2.0 if idx <= homo else 0.0, []))
  if contribs:
    contrib_text = '<br>'.join(fmt_frag_orbital(f_id, f_orb, pct) for f_id, f_orb, pct in sorted(contribs, key=lambda item: (-item[2], item[0], item[1])))
  else:
    contrib_text = 'No fragment contribution above the printing threshold.'
  lines.append(f'| {idx} | {label_for(idx)} | {energy:.4f} | {occ:.4f} | {contrib_text} |')

lines.append('')
lines.append('## Orbital details')
for idx in show_complex:
  if idx not in complex_e:
    continue
  energy = complex_e[idx]
  occ, contribs = comp_data.get(idx, (2.0 if idx <= homo else 0.0, []))
  lines.append(f'### Complex MO {idx} ({label_for(idx)})')
  lines.append(f'- Energy: {energy:.4f} eV')
  lines.append(f'- Occupation: {occ:.4f}')
  if contribs:
    lines.append(f'- Printed contribution sum: {sum(pct for _, _, pct in contribs):.2f}%')
    lines.append('- Fragment-orbital composition:')
    for f_id, f_orb, pct in sorted(contribs, key=lambda item: (-item[2], item[0], item[1])):
      lines.append(f'  - {fmt_frag_orbital(f_id, f_orb, pct)}')
  else:
    lines.append('- Fragment-orbital composition: not available in the parsed Multiwfn output.')
  lines.append('')

lines.append('## Notes for downstream language-model analysis')
lines.append('- The orbital window is centered on the frontier orbitals shown in the publication diagram.')
lines.append('- Fragment contributions are Mulliken-style CDA percentages from Multiwfn.')
lines.append('- Contributions below 1% are not listed by the upstream Multiwfn query.')

md_path.write_text('\n'.join(lines).rstrip() + '\n', encoding='utf-8')
print(f'  Publication summary markdown: {md_path}')
PYCDAMD

   else
    echo "  WARNING: cda.out not found. Cannot generate CDA plots."
   fi

    if [[ "$CDA_ALL_ORBITALS" -eq 1 || "$CDA_PUB_ORBITALS" -eq 1 ]]; then
    if [[ -z "$MULTIWFN_EXE" ]]; then
      echo "  Skipping CDA orbital images (Multiwfn not available in plot-only mode)."
    else
    if [[ "$CDA_ALL_ORBITALS" -eq 1 ]]; then
      echo "[*] Rendering ALL orbital images (front/side/top) for CDA diagram..."
    else
      echo "[*] Rendering pub-diagram orbital images (HOMO-2..LUMO+2, front/side/top)..."
    fi
    mkdir -p orbitals
    if [[ "$CDA_ALL_ORBITALS" -eq 1 ]]; then
    ORB_JSON=$(python3 - "$PWD/cda.out" "$CDA_EMIN" "$CDA_EMAX" "$PWD/orbitals" <<'PYORBLIST'
import sys, re, json
cda_file, e_lo, e_hi, out_dir = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
text = open(cda_file, encoding='utf-8', errors='ignore').read()

n_occ = 0
for m in re.finditer(r'Sum:\s+(\d+\.\d+)', text):
    n_occ = int(float(m.group(1))) // 2; break

energy_blocks = {}
for m in re.finditer(
    r'Energy of molecular orbitals of (the complex|fragment\s+\d+),\s+in eV:\s*\n(.*?)(?=Energy of molecular|-----|\Z)',
    text, re.DOTALL
):
    label = m.group(1).strip().lower().replace('the ', '')
    vals = [float(x) for x in m.group(2).split()]
    energy_blocks[label] = {i+1: v for i, v in enumerate(vals)}

complex_e = energy_blocks.get('complex', {})
frag_e = {}
for k, v in energy_blocks.items():
    if 'fragment' in k:
        fid = '1' if '1' in k else '2'
        frag_e[fid] = v

needed = {'complex': set(), 'frag1': set(), 'frag2': set()}
for m in re.finditer(
    r'Occupation number of orbital\s+(\d+) of the complex:\s*([\d.]+)(.*?)(?=Occupation number of orbital|Input the index|\Z)',
    text, re.DOTALL
):
    c_idx = int(m.group(1))
    c_ev = complex_e.get(c_idx, 999)
    if not (e_lo <= c_ev <= e_hi): continue
    block = m.group(3)
    for cm in re.finditer(r'Orbital\s+(\d+)\s+of fragment\s+(\d+).*?Contribution:\s*([\d.]+)\s*%', block):
        f_orb, f_id, pct = int(cm.group(1)), cm.group(2), float(cm.group(3))
        f_ev = frag_e.get(f_id, {}).get(f_orb, 999)
        if pct >= 10.0 and e_lo <= f_ev <= e_hi:
            needed['complex'].add(c_idx)
            needed[f'frag{f_id}'].add(f_orb)

result = {k: sorted(v) for k, v in needed.items()}
print(json.dumps(result))
PYORBLIST
    )
    else
    ORB_JSON=$(python3 - "$PWD/cda.out" <<'PYORBLIST_PUB'
import sys, re, json
cda_file = sys.argv[1]
text = open(cda_file, encoding='utf-8', errors='ignore').read()

n_occ_complex = 0
for m in re.finditer(r'Sum:\s+(\d+\.\d+)', text):
    n_occ_complex = int(float(m.group(1))) // 2
    break

HOMO = n_occ_complex
LUMO = n_occ_complex + 1
show_complex = set(range(HOMO - 2, LUMO + 3))

comp_data = {}
for m in re.finditer(
    r'Occupation number of orbital\s+(\d+) of the complex:\s*([\d.]+)(.*?)(?=Occupation number of orbital|Input the index|\Z)',
    text, re.DOTALL):
    orb_idx, occ = int(m.group(1)), float(m.group(2))
    block = m.group(3)
    contribs = []
    for cm in re.finditer(r'Orbital\s+(\d+)\s+of fragment\s+(\d+).*?Contribution:\s*([\d.]+)\s*%', block):
        f_orb, f_id, pct = int(cm.group(1)), cm.group(2), float(cm.group(3))
        if pct >= 1.0:
            contribs.append((f_id, f_orb, pct))
    if contribs:
        comp_data[orb_idx] = (occ, contribs)

show_f1, show_f2 = set(), set()
for c_idx in show_complex:
    if c_idx in comp_data:
        for f_id, f_orb, pct in comp_data[c_idx][1]:
            if f_id == '1':
                show_f1.add(f_orb)
            else:
                show_f2.add(f_orb)

needed = {
    'complex': sorted(show_complex),
    'frag1': sorted(show_f1),
    'frag2': sorted(show_f2)
}
print(json.dumps(needed))
PYORBLIST_PUB
    )
    fi

    MO_ISO=0.03
    generate_and_render_orbital() {
      local molden="$1" orb_idx="$2" out_prefix="$3" label="$4" zoom="${5:-$MO_ZOOM}"
      local tmpdir; tmpdir="$(mktemp -d)"
      echo -e "5\n4\n${orb_idx}\n4\n${CUBE_STEP}\n\n2\n0\nq" \
        | "$MULTIWFN_EXE" "$molden" > "$tmpdir/mo.log" 2>&1
      [[ -f MOvalue.cub ]] || return 1
      mv MOvalue.cub "$tmpdir/mo.cub"
      {
        vmd_quality_preamble
        vmd_add_li_s_bonds_tcl
        cat <<EOFMO
mol new "$tmpdir/mo.cub" type cube waitfor all
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
mol representation Isosurface ${MO_ISO} 0 0 0 1 1
mol color ColorID 0
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top
mol representation Isosurface -${MO_ISO} 0 0 0 1 1
mol color ColorID 1
mol selection all
material change opacity Transparent 0.40
mol material Transparent
mol addrep top
display resetview
scale by ${zoom}
render TachyonInternal "$tmpdir/mo_front.tga"
display resetview
rotate y by 90
scale by ${zoom}
render TachyonInternal "$tmpdir/mo_side.tga"
display resetview
rotate x by 90
scale by ${zoom}
render TachyonInternal "$tmpdir/mo_top.tga"
quit
EOFMO
      } > "$tmpdir/render.tcl"
      "$VMD_EXE" -dispdev text -e "$tmpdir/render.tcl" > /dev/null 2>&1
      python3 - "$tmpdir" "$out_prefix" "$label" <<'PYMOPNG'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try: return ImageFont.truetype(n, size)
        except: continue
    return ImageFont.load_default()

tmpdir, out_prefix, label = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
for view in ("front", "side", "top"):
    tga = tmpdir / f"mo_{view}.tga"
    png = out_prefix + f"_{view}.png"
    if not tga.exists():
        continue
    with Image.open(tga) as src:
        src = src.convert("RGBA")
        w, h = src.size
        lbl_h = 60
        canvas = Image.new("RGBA", (w, h + lbl_h), (255,255,255,255))
        canvas.paste(src, (0, lbl_h))
        draw = ImageDraw.Draw(canvas)
        ft = _font(bold=True, size=48)
        bb = draw.textbbox((0,0), label, font=ft)
        draw.text(((w-(bb[2]-bb[0]))/2, (lbl_h-(bb[3]-bb[1]))/2),
                  label, fill=(30,30,30,255), font=ft)
        canvas.save(png, format="PNG")
    print(png)
PYMOPNG
      rm -rf "$tmpdir"
    }

    echo "$ORB_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for orb in data.get('complex', []):
    print('complex', orb)
for orb in data.get('frag1', []):
    print('frag1', orb)
for orb in data.get('frag2', []):
    print('frag2', orb)
" > "$PWD/orbitals/_orblist.txt"

    while read -u 3 kind idx; do
      case "$kind" in
        complex)
          out_prefix="$PWD/orbitals/complex_MO${idx}"
          generate_and_render_orbital "$COMPLEX_MOLDEN" "$idx" "$out_prefix" "Complex MO $idx" "$MO_ZOOM" || true
          echo "    ${out_prefix}_{front,side,top}.png"
          ;;
        frag1)
          out_prefix="$PWD/orbitals/frag1_MO${idx}"
          generate_and_render_orbital "$FRAG1_MOLDEN" "$idx" "$out_prefix" "Frag.1 MO $idx" "$MO_ZOOM_FRAG" || true
          echo "    ${out_prefix}_{front,side,top}.png"
          ;;
        frag2)
          out_prefix="$PWD/orbitals/frag2_MO${idx}"
          generate_and_render_orbital "$FRAG2_MOLDEN" "$idx" "$out_prefix" "Frag.2 MO $idx" "$MO_ZOOM_FRAG" || true
          echo "    ${out_prefix}_{front,side,top}.png"
          ;;
      esac
    done 3< "$PWD/orbitals/_orblist.txt"
    echo "  Individual orbital images (front/side/top) saved to: $PWD/orbitals/"
    fi
    fi
  fi
  popd >/dev/null
fi

###############################################################################
# Summary
###############################################################################
echo ""
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION -- Weak Interaction Analysis Complete"
echo "========================================"
echo "  Output: $PWD/$OUTPUT_DIR/"
[[ "$RUN_NCI" -eq 1 ]] && echo "    NCI:     $OUTPUT_DIR/NCI/"
[[ "$RUN_MIGM" -eq 1 ]] && echo "    mIGM:    $OUTPUT_DIR/mIGM/"
[[ "$RUN_IGMH" -eq 1 ]] && echo "    IGMH:    $OUTPUT_DIR/IGMH/"
[[ "$RUN_IRI" -eq 1 ]] && echo "    IRI:     $OUTPUT_DIR/IRI/"
[[ "$RUN_HS" -eq 1 ]] && echo "    HS:      $OUTPUT_DIR/HS/"
[[ "$RUN_CHGDIFF" -eq 1 ]] && echo "    Chgdiff: $OUTPUT_DIR/chgdiff/"
[[ "$RUN_CDA" -eq 1 ]] && echo "    CDA:     $OUTPUT_DIR/CDA/"
echo "========================================"
