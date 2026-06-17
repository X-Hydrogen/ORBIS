#!/usr/bin/env bash
###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-amigm  (Averaged mIGM Weak Interaction Analysis)
#
#  Version:    1.0.0
#  Author:     Hengyue Xu (ORCiD: 0000-0003-4438-9647)
#  Date:       2026-06-17
#  Copyright:  (C) 2024-2026 Hengyue Xu. All rights reserved.
#
#  Description:
#    Standalone averaged mIGM (amIGM) weak interaction analysis for MD
#    trajectories.  Computes the time-averaged independent gradient model
#    over every frame of an XYZ trajectory, producing avgsl2r.cub and
#    avgdg_inter.cub.  Renders three-view VMD isosurface images + scatter
#    plot with BWR colour bar via Pillow.
#
#    Unlike mIGM, amIGM requires frag1 to be the *fixed* (already aligned)
#    fragment so the averaging over frames is meaningful.  Frag2 is usually
#    the complementary mobile part (--frag2 'c').
#
#    Reference: http://sobereva.com/759
#    Multiwfn menu: 20 → -12 (amIGM)
#
#  Prerequisites:
#    Multiwfn ≥ 2025-Nov-23 (amIGM needs mIGM support)
#    VMD (TachyonInternal renderer)
#    Python 3 + Pillow + numpy + matplotlib
#
#    NONE of ORCA, molden, or any QM output is required —
#    the only input is a multi-frame XYZ trajectory.
#
#  Usage:
#    bash iqcap-amigm.sh --traj trajectory.xyz --frag1 "1-13" [options]
#    bash iqcap-amigm.sh --traj md.xyz --frag1 "1-20" --frag2 "21-40"
#    bash iqcap-amigm.sh --traj md.xyz --frag1 "1-13" --grid 0.15
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_FULLNAME="Intelligent Quantum Chemistry Analysis Platform"
IQCAP_MODULE="iqcap-amigm"
IQCAP_VERSION="1.0.0"
IQCAP_AUTHOR="Hengyue Xu (ORCiD: 0000-0003-4438-9647)"
IQCAP_COPYRIGHT="(C) 2024-2026 Hengyue Xu. All rights reserved."

###############################################################################
# User configuration — override via CLI flags
###############################################################################
MULTIWFN_BIN=""
VMD_BIN=""

OUTPUT_DIR="amIGM"
TRAJ_XYZ=""           # path to multi-frame XYZ trajectory
FRAG1_ATOMS=""        # frag1: fixed/aligned part (REQUIRED)
FRAG2_DEF="c"         # frag2: 'c' = complement (all others), or explicit range
AMIGM_GRID=0.2        # Bohr, Multiwfn default
AMIGM_EXTEND=3.0      # Å, grid extension beyond frag1
AMIGM_ISO=0.01        # isosurface threshold
AMIGM_COLOR_MIN=-0.04
AMIGM_COLOR_MAX=0.02
MOL_ZOOM=1.00
SKIP_RENDER=0
SKIP_SCATTER=0

###############################################################################
# Help
###############################################################################
help() {
  cat <<EOF
Usage:  bash iqcap-amigm.sh --traj <XYZ> --frag1 <ATOMS> [options]

  REQUIRED:
    --traj PATH        Multi-frame XYZ trajectory file
    --frag1 ATOMS      Fragment 1 atoms (the fixed / pre-aligned part)
                       e.g. "1-13" or "1,3,5-8"

  OPTIONAL:
    --frag2 ATOMS      Fragment 2 atoms (default: c = all others)
    --grid N           Grid spacing in Bohr (default: 0.2)
    --extend N         Grid extension beyond frag1 in Å (default: 3.0)
    --iso N            Isosurface threshold (default: 0.01)
    --color-min N      BWR colour bar minimum (default: -0.04)
    --color-max N      BWR colour bar maximum (default: 0.02)
    --zoom N           Molecular zoom factor (default: 1.0)
    --multiwfn PATH    Path to Multiwfn executable
    --vmd PATH         Path to VMD executable
    --out-dir NAME     Output directory name (default: amIGM)
    --skip-render      Only run Multiwfn, skip VMD rendering
    --skip-scatter     Skip scatter plot generation
    -h, --help         Show this help

  Notes:
    - frag1 MUST be the fixed/aligned fragment.
      If you haven't aligned the trajectory to frag1, do it first, e.g.:
        Multiwfn traj.xyz → 100 → 22 → 1-13 → 11 → ...
    - No molden / ORCA / QM output is needed — only the XYZ trajectory.
    - Multiwfn ≥ 2025-Nov-23 required.

  Example:
    bash iqcap-amigm.sh --traj md_align.xyz --frag1 "1-13"
EOF
}

###############################################################################
# Argument parsing
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --traj)        TRAJ_XYZ="$2";       shift 2 ;;
    --frag1)       FRAG1_ATOMS="$2";     shift 2 ;;
    --frag2)       FRAG2_DEF="$2";       shift 2 ;;
    --grid)        AMIGM_GRID="$2";      shift 2 ;;
    --extend)      AMIGM_EXTEND="$2";    shift 2 ;;
    --iso)         AMIGM_ISO="$2";       shift 2 ;;
    --color-min)   AMIGM_COLOR_MIN="$2"; shift 2 ;;
    --color-max)   AMIGM_COLOR_MAX="$2"; shift 2 ;;
    --zoom)        MOL_ZOOM="$2";        shift 2 ;;
    --multiwfn)    MULTIWFN_BIN="$2";    shift 2 ;;
    --vmd)         VMD_BIN="$2";         shift 2 ;;
    --out-dir)     OUTPUT_DIR="$2";      shift 2 ;;
    --skip-render) SKIP_RENDER=1;        shift 1 ;;
    --skip-scatter) SKIP_SCATTER=1;      shift 1 ;;
    -h|--help)     help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; help >&2; exit 1 ;;
  esac
done

###############################################################################
# Validation
###############################################################################
if [[ -z "$TRAJ_XYZ" ]]; then
  echo "ERROR: --traj is required." >&2; help >&2; exit 1
fi
if [[ -z "$FRAG1_ATOMS" ]]; then
  echo "ERROR: --frag1 is required (the fixed/aligned fragment)." >&2; help >&2; exit 1
fi
if [[ ! -f "$TRAJ_XYZ" ]]; then
  echo "ERROR: Trajectory file not found: $TRAJ_XYZ" >&2; exit 1
fi

# Resolve absolute path
TRAJ_XYZ="$(realpath "$TRAJ_XYZ")"

###############################################################################
# Tool resolution
###############################################################################
expand_path() {
  local p="$1"
  [[ -z "$p" ]] && { echo "$p"; return; }
  [[ "$p" = /* ]] && { echo "$p"; return; }
  [[ "$p" = \~/* ]] && { echo "$HOME/${p#\~/}"; return; }
  echo "$PWD/$p"
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

MULTIWFN_EXE="$(resolve_bin_any "$MULTIWFN_BIN" "multiwfn" "Multiwfn" "Multiwfn_noGUI")" || {
  echo "ERROR: Cannot find Multiwfn executable. Use --multiwfn to specify path." >&2
  exit 1
}

VMD_EXE=""
if [[ "$SKIP_RENDER" -ne 1 ]]; then
  VMD_EXE="$(resolve_bin_any "$VMD_BIN" "vmd" "VMD")" || {
    echo "WARNING: VMD not found. Set --skip-render or install VMD." >&2
    SKIP_RENDER=1
  }
  python3 -c "from PIL import Image" >/dev/null 2>&1 || {
    echo "ERROR: Python Pillow required. Install: pip install Pillow" >&2; exit 1
  }
  python3 -c "import numpy" >/dev/null 2>&1 || {
    echo "ERROR: Python numpy required." >&2; exit 1
  }
fi

if [[ "$SKIP_SCATTER" -ne 1 ]]; then
  python3 -c "import matplotlib" >/dev/null 2>&1 || {
    echo "WARNING: matplotlib not found; scatter plot skipped." >&2
    SKIP_SCATTER=1
  }
fi

###############################################################################
# VMD TCL helper functions (same as elect_interaction.sh)
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

vmd_add_li_s_bonds_tcl() {
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

###############################################################################
# amIGM Multiwfn computation
###############################################################################
run_amigm_multiwfn() {
  echo "[*] Running Multiwfn amIGM (menu 20 → -12)..."

  # amIGM input sequence (ref: http://sobereva.com/759)
  # 20    → weak interaction visualization
  # -12   → amIGM (averaged mIGM)
  # 2     → two fragments
  # frag1 → user-defined fixed fragment
  # frag2 → complement or user-defined
  # [Enter] → consider all frames
  # 11    → define grid around fragment
  # frag1 → use frag1 atoms for grid centre
  # N Å   → extension beyond frag1
  # [Enter] → default 0.2 Bohr grid spacing
  # 3     → export cube files
  # 0     → (back)
  # q     → quit

  local input
  input="20\n-12\n2\n${FRAG1_ATOMS}\n${FRAG2_DEF}\n\n11\n${FRAG1_ATOMS}\n${AMIGM_EXTEND} A\n\n3\n0\nq"

  echo -e "$input" | "$MULTIWFN_EXE" "$TRAJ_XYZ" > amigm.out 2>&1
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "  WARNING: Multiwfn exited with code $rc (check amigm.out)" >&2
    return 1
  fi

  # Check for expected output
  if [[ -f avgsl2r.cub && -f avgdg_inter.cub ]]; then
    echo "  amIGM cubes: avgsl2r.cub, avgdg_inter.cub"
    return 0
  elif [[ -f sl2r.cub && -f dg_inter.cub ]]; then
    # Some Multiwfn versions use unprefixed names even for amIGM
    ln -sf sl2r.cub avgsl2r.cub
    ln -sf dg_inter.cub avgdg_inter.cub
    echo "  amIGM cubes (legacy names): sl2r.cub → avgsl2r.cub, dg_inter.cub → avgdg_inter.cub"
    return 0
  else
    echo "  ERROR: amIGM cube files not generated." >&2
    echo "  Check amigm.out for Multiwfn errors." >&2
    return 1
  fi
}

###############################################################################
# VMD rendering: three views (front / side / top)
###############################################################################
render_amigm_views() {
  local out_dir="$1"
  local avgsl2r="$out_dir/avgsl2r.cub"
  local avgdg_inter="$out_dir/avgdg_inter.cub"

  [[ -f "$avgsl2r" && -f "$avgdg_inter" ]] || {
    echo "  WARNING: amIGM cubes missing, skipping render." >&2
    return 1
  }

  echo "[*] Rendering amIGM three views..."

  {
    vmd_quality_preamble
    vmd_add_li_s_bonds_tcl
    cat <<EOF

mol new "$avgdg_inter" type cube waitfor all
mol addfile "$avgsl2r" type cube waitfor all
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

mol representation Isosurface $AMIGM_ISO 0 0 0 1 1
mol color Volume 1
mol selection all
material change opacity Transparent 0.75
mol material Transparent
mol addrep top

color scale method BGR
mol scaleminmax top 1 $AMIGM_COLOR_MIN $AMIGM_COLOR_MAX

display resetview
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/amigm_front.tga"

display resetview
rotate y by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/amigm_side.tga"

display resetview
rotate x by 90
scale by $MOL_ZOOM
render TachyonInternal "$out_dir/amigm_top.tga"

quit
EOF
  } > "$out_dir/render_amigm.tcl"

  "$VMD_EXE" -dispdev text -e "$out_dir/render_amigm.tcl" > "$out_dir/amigm_render.out" 2>&1

  for v in front side top; do
    if [[ ! -f "$out_dir/amigm_${v}.tga" ]]; then
      echo "  ERROR: Missing amigm_${v}.tga" >&2
      return 1
    fi
  done
  return 0
}

###############################################################################
# TGA → PNG conversion with BWR colour bar
###############################################################################
convert_tga_to_png() {
  local out_dir="$1"

  echo "[*] Converting TGA → PNG with colour bar..."

  python3 - "$out_dir" "$AMIGM_ISO" "$AMIGM_COLOR_MIN" "$AMIGM_COLOR_MAX" <<'PYAMIGM'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

out_dir = Path(sys.argv[1])
iso_val = float(sys.argv[2])
cmin = float(sys.argv[3])
cmax = float(sys.argv[4])

def _font(bold=False, size=20):
    for n in (["LiberationSans-Bold.ttf","DejaVuSans-Bold.ttf"] if bold
              else ["LiberationSans-Regular.ttf","DejaVuSans.ttf"]):
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()

def bgr_color(v):
    """BWR colour: blue(0) → white(0.5) → red(1)"""
    v = max(0.0, min(1.0, v))
    if v < 0.5:
        t = v / 0.5
        return 0, int(255*t), int(255*(1-t))
    t = (v - 0.5) / 0.5
    return int(255*t), int(255*(1-t)), 0

for view in ("front", "side", "top"):
    tga = out_dir / f"amigm_{view}.tga"
    png = out_dir / f"amigm_{view}.png"
    if not tga.exists():
        print(f"  SKIP: {tga} not found")
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
        draw.text((x1+16, y0-2), f"+{cmax:.3f}", fill=(28,28,28,255), font=fv)
        bb = draw.textbbox((0,0), f"{cmin:.3f}", font=fv)
        draw.text((x1+16, y1-(bb[3]-bb[1])+2), f"{cmin:.3f}", fill=(28,28,28,255), font=fv)

        fn = _font(bold=False, size=max(32, int(0.024*w)))
        footer = (f"amIGM  δg_inter avg  iso = {iso_val:.4g}      "
                  "blue = attractive      green = vdW      red = repulsive")
        fb = draw.textbbox((0,0), footer, font=fn)
        draw.text(((canvas.width-(fb[2]-fb[0]))/2, h+(footer_h-(fb[3]-fb[1]))/2),
                  footer, fill=(30,30,30,255), font=fn)
        canvas.save(png, format="PNG")
    print(f"  {png}")
PYAMIGM
}

###############################################################################
# Scatter plot (if output.txt generated)
###############################################################################
render_scatter() {
  local out_dir="$1"
  local scatter_data="$out_dir/output.txt"

  if [[ ! -f "$scatter_data" ]]; then
    echo "  No scatter data (output.txt), skipping scatter plot."
    return 1
  fi

  echo "[*] Generating amIGM scatter plot..."

  python3 - "$scatter_data" "$out_dir/amigm_scatter.png" <<'PYSCT'
import sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['Arial', 'Liberation Sans', 'DejaVu Sans']

raw = np.loadtxt(sys.argv[1], comments='#')
if raw.ndim == 1:
    raw = raw.reshape(1, -1)

if raw.shape[1] >= 2:
    x = raw[:, 0]   # sign(λ₂)ρ
    y = raw[:, 1]   # δg_inter
else:
    print("  WARNING: scatter data has < 2 columns, cannot plot.")
    sys.exit(1)

colors_bwr = [(0.0, '#0000FF'), (0.5, '#FFFFFF'), (1.0, '#FF0000')]
cmap = LinearSegmentedColormap.from_list('BWR', colors_bwr)

fig, ax = plt.subplots(figsize=(8, 6))
vals = np.linspace(0, 1, 256)
ax.imshow([vals], cmap=cmap, aspect='auto', extent=[x.min(), x.max(), 0, 1], alpha=0)

sc = ax.scatter(x, y, c=x, cmap=cmap, s=2, alpha=0.8, edgecolors='none',
                vmin=-0.04, vmax=0.02)

ax.set_xlabel('sign(λ₂)ρ  (a.u.)', fontsize=12)
ax.set_ylabel('δg_inter  (a.u.)', fontsize=12)
ax.set_title('amIGM Scatter Plot', fontsize=14, weight='bold')
ax.axhline(y=0, color='gray', linewidth=0.5, linestyle='--')
ax.axvline(x=0, color='gray', linewidth=0.5, linestyle='--')
fig.tight_layout()
fig.savefig(sys.argv[2], dpi=150)
plt.close()
print(f"  {sys.argv[2]}")
PYSCT
}

###############################################################################
# Main
###############################################################################
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION"
echo " $IQCAP_FULLNAME"
echo " Module: $IQCAP_MODULE (Averaged mIGM)"
echo "========================================"
echo "  Trajectory:  $TRAJ_XYZ"
echo "  Frag 1:      $FRAG1_ATOMS (fixed)"
echo "  Frag 2:      $FRAG2_DEF"
echo "  Grid:        $AMIGM_GRID Bohr  (extend ${AMIGM_EXTEND} Å around frag1)"
echo "  Isosurface:  $AMIGM_ISO"
echo "  Colour:      $AMIGM_COLOR_MIN  –  $AMIGM_COLOR_MAX"
echo "  Multiwfn:    $MULTIWFN_EXE"
echo "  VMD:         ${VMD_EXE:-N/A}"
echo "  Output:      $PWD/$OUTPUT_DIR/"
echo "========================================"

mkdir -p "$OUTPUT_DIR"
pushd "$OUTPUT_DIR" >/dev/null

# Step 1: Multiwfn amIGM computation
run_amigm_multiwfn || {
  echo "ERROR: Multiwfn amIGM failed." >&2
  popd >/dev/null; exit 1
}

# Step 2: VMD rendering
RENDER_OK=0
if [[ "$SKIP_RENDER" -ne 1 && -n "$VMD_EXE" ]]; then
  render_amigm_views "$PWD" && RENDER_OK=1
  if [[ "$RENDER_OK" -eq 1 ]]; then
    convert_tga_to_png "$PWD"
  fi
fi

# Step 3: Scatter plot
if [[ "$SKIP_SCATTER" -ne 1 ]]; then
  render_scatter "$PWD" || true
fi

popd >/dev/null

###############################################################################
# Summary
###############################################################################
echo ""
echo "========================================"
echo " $IQCAP_NAME v$IQCAP_VERSION -- amIGM Complete"
echo "========================================"
echo "  Output:  $PWD/$OUTPUT_DIR/"
if [[ -f "$OUTPUT_DIR/avgsl2r.cub" ]]; then
  echo "  Cubes:   avgsl2r.cub, avgdg_inter.cub"
  echo "  Log:     $OUTPUT_DIR/amigm.out"
fi
if [[ "$RENDER_OK" -eq 1 ]]; then
  echo "  Views:   amigm_front.png, amigm_side.png, amigm_top.png"
fi
if [[ -f "$OUTPUT_DIR/amigm_scatter.png" ]]; then
  echo "  Scatter: amigm_scatter.png"
fi
echo "========================================"
