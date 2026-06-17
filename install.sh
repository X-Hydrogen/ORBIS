#!/usr/bin/env bash
###############################################################################
# Orbis — Lightweight Environment Setup
#
# Detects existing installations of ORCA, Multiwfn, VMD, and other tools.
# Configures Python environment. Does NOT download or bundle anything.
#
# Usage:
#   bash install.sh              # Interactive setup
#   bash install.sh --yes        # Non-interactive, auto-detect only
#   bash install.sh --check      # Check only, no changes
###############################################################################

set -euo pipefail

ORBIS_HOME="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$ORBIS_HOME/agent/orbis_config.py"
YES_MODE=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)   YES_MODE=true; shift ;;
        --check)    CHECK_ONLY=true; shift ;;
        --help|-h)
            echo "Orbis Environment Setup"
            echo "Usage: bash install.sh [--yes] [--check]"
            echo "  --yes     Non-interactive, auto-detect only"
            echo "  --check   Dry-run: report what's found, make no changes"
            exit 0
            ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

# ── Helpers ────────────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';    YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';     BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[✓]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[!]${NC}    $*"; }
err()     { echo -e "${RED}[✗]${NC}    $*"; }
header()  { echo -e "\n${BOLD}${CYAN}══ $*${NC}"; }

confirm() {
    local prompt="$1"; local default="${2:-Y}"
    $YES_MODE && { echo "y"; return; }
    [ "$default" = "Y" ] && read -rp "$prompt [Y/n]: " ans || read -rp "$prompt [y/N]: " ans
    echo "${ans:-$default}"
}

# ── Detection functions ────────────────────────────────────────────

detect_orca() {
    ORCA_BIN=""; ORCA_DIR_PATH=""
    local search=(
        "/home/quantum/tools/orca_6_1_0_avx2/orca"
        "/home/quantum/tools/orca_6_0_0_avx2/orca"
        "/home/quantum/tools/orca_5_0_4_avx2/orca"
        "/usr/local/bin/orca"
        "$ORBIS_HOME/tools/orca/orca"
    )
    for c in "${search[@]}"; do
        [ -x "$c" ] && { ORCA_BIN="$c"; ORCA_DIR_PATH="$(dirname "$c")"; break; }
    done
    [ -z "$ORCA_BIN" ] && [ -x "$(command -v orca 2>/dev/null)" ] && {
        ORCA_BIN="$(command -v orca)"; ORCA_DIR_PATH="$(dirname "$ORCA_BIN")"
    }
    [ -n "$ORCA_BIN" ] && {
        local ver=$(timeout 3 "$ORCA_BIN" 2>&1 | grep -oP 'Program Version \K[0-9.]+' | head -1 || echo "?")
        ok "ORCA $ver → $ORCA_BIN"
        [ -x "$ORCA_DIR_PATH/orca_2aim" ] && ok "  orca_2aim ✓" || warn "  orca_2aim ✗"
        [ -x "$ORCA_DIR_PATH/orca_2mkl" ] && ok "  orca_2mkl ✓" || warn "  orca_2mkl ✗"
        return 0
    }
    warn "ORCA  — NOT FOUND"
    echo "       Download: https://orcaforum.kofo.mpg.de/ (license required)"
    return 1
}

detect_multiwfn() {
    MULTIWFN_BIN=""
    local search=(
        "/home/quantum/tools/Multiwfn/multiwfn"
        "/usr/local/bin/multiwfn"
        "$ORBIS_HOME/tools/Multiwfn/multiwfn"
    )
    for c in "${search[@]}"; do
        [ -x "$c" ] && { MULTIWFN_BIN="$c"; break; }
    done
    [ -z "$MULTIWFN_BIN" ] && [ -x "$(command -v multiwfn 2>/dev/null)" ] && MULTIWFN_BIN="$(command -v multiwfn)"
    [ -n "$MULTIWFN_BIN" ] && { ok "Multiwfn → $MULTIWFN_BIN"; return 0; }
    warn "Multiwfn — NOT FOUND"
    install_multiwfn && return 0
    return 1
}

install_multiwfn() {
    local MW_VER="3.8"
    local MW_URL="http://sobereva.com/multiwfn/misc/Multiwfn_${MW_VER}_bin_Linux_noGUI.zip"
    local MW_ZIP="/tmp/Multiwfn_${MW_VER}.zip"
    local MW_DIR="/home/quantum/tools/Multiwfn"

    echo ""
    echo "  Multiwfn is free and open-source (~18MB)."
    ans=$(confirm "Auto-download and install Multiwfn $MW_VER?" "Y")
    [ "$ans" != "y" ] && [ "$ans" != "Y" ] && {
        echo "       Download manually: http://sobereva.com/multiwfn/download.html"
        return 1
    }

    [ -f "$MW_ZIP" ] && info "Using existing download" || {
        info "Downloading Multiwfn $MW_VER (18MB)..."
        curl -L --progress-bar -o "$MW_ZIP" "$MW_URL" || { err "Download failed"; return 1; }
    }

    info "Extracting to $MW_DIR..."
    mkdir -p "$MW_DIR"
    unzip -qo "$MW_ZIP" -d "$MW_DIR" || { err "Extraction failed"; return 1; }
    chmod +x "$MW_DIR"/multiwfn 2>/dev/null || true
    rm -f "$MW_ZIP"

    if [ -x "$MW_DIR/multiwfn" ]; then
        ok "Multiwfn installed → $MW_DIR/multiwfn"
        MULTIWFN_BIN="$MW_DIR/multiwfn"
        return 0
    fi
    err "Installation failed"
    return 1
}

detect_vmd() {
    VMD_EXE=""
    local search=(
        "/home/quantum/tools/vmd-2.0.0/bin/vmd.sh"
        "/home/quantum/tools/vmd-1.9.4/bin/vmd.sh"
        "/usr/local/bin/vmd"
        "/usr/bin/vmd"
        "$ORBIS_HOME/tools/vmd/vmd.sh"
    )
    for c in "${search[@]}"; do
        # Expand wildcards
        for f in $c; do
            [ -x "$f" ] && { VMD_EXE="$f"; break 2; }
        done
    done
    # Also check PATH
    [ -z "$VMD_EXE" ] && [ -x "$(command -v vmd 2>/dev/null)" ] && VMD_EXE="$(command -v vmd)"
    [ -n "$VMD_EXE" ] && {
        local ver=$("$VMD_EXE" -dispdev text -e /dev/null 2>&1 | grep -oP 'version \K[0-9.]+' | head -1 || echo "?")
        ok "VMD $ver → $VMD_EXE"
        # ABI check
        if "$VMD_EXE" -dispdev text -e /dev/null 2>&1 | grep -q "Rejecting.*orcaplugin"; then
            warn "  ORCA plugin ABI mismatch — upgrade VMD to ≥1.9.4 for cube generation"
        fi
        return 0
    }
    warn "VMD     — NOT FOUND"
    install_vmd && return 0
    return 1
}

install_vmd() {
    local VMD_VER="2.0.0"
    local VMD_URL="https://www.ks.uiuc.edu/Research/vmd/vmd-${VMD_VER}/files/final/vmd-${VMD_VER}.bin.LINUXAMD64.tar.gz"
    local VMD_TGZ="/tmp/vmd-${VMD_VER}.tar.gz"
    local VMD_DIR="/home/quantum/tools/vmd-${VMD_VER}"

    echo ""
    echo "  VMD is free for academic use. The installer can auto-download"
    echo "  VMD $VMD_VER (~81MB) from the official UIUC server."
    echo ""
    ans=$(confirm "Auto-download and install VMD $VMD_VER?" "Y")
    [ "$ans" != "y" ] && [ "$ans" != "Y" ] && {
        echo "       Download manually: https://www.ks.uiuc.edu/Research/vmd/"
        return 1
    }

    # Reuse existing download
    [ -f "$VMD_TGZ" ] && info "Using existing download" || {
        info "Downloading VMD $VMD_VER (81MB)..."
        curl -L --progress-bar -o "$VMD_TGZ" "$VMD_URL" || { err "Download failed"; return 1; }
    }

    info "Extracting to $VMD_DIR..."
    mkdir -p "$VMD_DIR"
    tar xzf "$VMD_TGZ" -C "$VMD_DIR" --strip-components=1 || { err "Extraction failed"; return 1; }
    rm -f "$VMD_TGZ"

    # Configure vmd.sh
    local VMD_SH="$VMD_DIR/bin/vmd.sh"
    sed -i "s|^#defaultvmddir=.*|defaultvmddir=$VMD_DIR|" "$VMD_SH"
    sed -i "s|^#vmdbasename=.*|vmdbasename=vmd|" "$VMD_SH"
    sed -i "5a VMD_LIBDIR=$VMD_DIR/lib/redistrib/lib_LINUXAMD64\nexport LD_LIBRARY_PATH=\${VMD_LIBDIR}:\${LD_LIBRARY_PATH}" "$VMD_SH"
    ln -sf "$VMD_DIR/LINUXAMD64/vmd_LINUXAMD64" "$VMD_DIR/vmd_LINUXAMD64"
    chmod +x "$VMD_SH"

    if "$VMD_SH" -dispdev text -e /dev/null 2>&1 | grep -q "version"; then
        local ver=$("$VMD_SH" -dispdev text -e /dev/null 2>&1 | grep -oP 'version \K[0-9.]+' | head -1)
        ok "VMD $ver installed → $VMD_SH"
        VMD_EXE="$VMD_SH"
        return 0
    fi
    err "Installation failed — VMD won't run"
    return 1
}

detect_latex() {
    if command -v pdflatex &>/dev/null; then
        ok "pdflatex → $(command -v pdflatex)"; HAS_PDFLATEX=true; return 0
    fi
    warn "pdflatex — NOT FOUND (PDF will use plain-text fpdf2 fallback)"
    echo ""
    echo "  texlive provides pdflatex for publication-quality PDFs"
    echo "  with proper formatting, references, and chemical formulas."
    echo "  Install: sudo apt install texlive-latex-base (~200MB)"
    echo ""
    ans=$(confirm "Install texlive now? (requires sudo)" "N")
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] && {
        info "Installing texlive..."
        sudo apt-get update -qq && sudo apt-get install -y -qq texlive-latex-base texlive-latex-recommended 2>&1 | tail -2
        command -v pdflatex &>/dev/null && { ok "pdflatex installed ✓"; HAS_PDFLATEX=true; return 0; }
        warn "Installation may have failed — PDF will use fpdf2 fallback"
    }
    HAS_PDFLATEX=false; return 1
}

detect_pandoc() {
    if command -v pandoc &>/dev/null; then
        ok "pandoc → $(command -v pandoc)"; HAS_PANDOC=true; return 0
    fi
    warn "pandoc   — NOT FOUND (Word will use python-docx fallback)"
    echo "       Install: sudo apt install pandoc (~20MB)"
    ans=$(confirm "Install pandoc now? (requires sudo)" "N")
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] && {
        sudo apt-get install -y -qq pandoc 2>&1 | tail -1
        command -v pandoc &>/dev/null && { ok "pandoc installed ✓"; HAS_PANDOC=true; return 0; }
    }
    HAS_PANDOC=false; return 1
}

detect_python() {
    local ver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0")
    local maj=$(echo "$ver" | cut -d. -f1); local min=$(echo "$ver" | cut -d. -f2)
    [ "$maj" -ge 3 ] && [ "$min" -ge 10 ] && { ok "Python $ver → $(command -v python3)"; return 0; }
    err "Python 3.10+ required, found $ver"; return 1
}

# ══════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${CYAN}  🔬  Orbis — Quantum Chemistry AI Scientist${NC}"
echo -e "${CYAN}  Environment Detection & Setup${NC}"
echo ""

# ── 1. OS check ────────────────────────────────────────────────────
header "System"
[ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ] || {
    err "Only Linux x86_64 is supported. Detected: $(uname -s) / $(uname -m)"; exit 1
}
ok "Linux x86_64 ✓"

# ── 2. Tool detection ──────────────────────────────────────────────
header "External Tools"
OK_COUNT=0; WARN_COUNT=0

detect_orca      && OK_COUNT=$((OK_COUNT+1)) || WARN_COUNT=$((WARN_COUNT+1))
detect_multiwfn  && OK_COUNT=$((OK_COUNT+1)) || WARN_COUNT=$((WARN_COUNT+1))
detect_vmd       && OK_COUNT=$((OK_COUNT+1)) || WARN_COUNT=$((WARN_COUNT+1))
detect_latex     && OK_COUNT=$((OK_COUNT+1)) || WARN_COUNT=$((WARN_COUNT+1))
detect_pandoc    && OK_COUNT=$((OK_COUNT+1)) || WARN_COUNT=$((WARN_COUNT+1))

header "Python"
detect_python    && OK_COUNT=$((OK_COUNT+1)) || { err "Cannot proceed without Python 3.10+"; exit 1; }

echo ""
echo -e "  ${GREEN}$OK_COUNT ready${NC}, ${YELLOW}$WARN_COUNT missing${NC}"
echo ""

if $CHECK_ONLY; then
    echo "Dry-run complete. No changes made."
    exit $WARN_COUNT
fi

# ── 3. Python venv + packages ─────────────────────────────────────
header "Python Environment"

VENV_DIR="$ORBIS_HOME/venv"
if [ -d "$VENV_DIR" ]; then
    ans=$(confirm "Recreate venv?" "N")
    [ "$ans" = "y" ] && { rm -rf "$VENV_DIR"; info "Removed old venv"; }
fi

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    ok "venv created: $VENV_DIR"
fi

set +euo pipefail; source "$VENV_DIR/bin/activate"; set -euo pipefail
pip install --upgrade pip -q 2>/dev/null

if [ -f "$ORBIS_HOME/requirements.txt" ]; then
    info "Installing Python packages..."
    pip install -r "$ORBIS_HOME/requirements.txt" -q 2>&1 | tail -1
    ok "Python packages installed"
else
    warn "No requirements.txt found, installing core packages..."
    pip install openai numpy scipy matplotlib python-docx fpdf2 flask -q
    ok "Core packages installed"
fi

# ── 4. Write config ───────────────────────────────────────────────
header "Configuration"

# Preserve existing API key
EXISTING_KEY=""
[ -f "$CONFIG_FILE" ] && {
    EXISTING_KEY=$(grep -oP 'ORBIS_API_KEY",\s*"\K[^"]*' "$CONFIG_FILE" 2>/dev/null || true)
    [ "$EXISTING_KEY" = "sk-7ef...b078" ] && EXISTING_KEY=""
}
API_KEY_VAL="${EXISTING_KEY:-${ORBIS_API_KEY:-}}"

cat > "$CONFIG_FILE" << PYEOF
"""
Orbis Agent Configuration — Auto-generated by install.sh
Edit paths below or re-run: bash install.sh
"""
import os
from pathlib import Path

# ── API ──
API_KEY = os.environ.get("ORBIS_API_KEY", "${API_KEY_VAL}")
API_BASE = os.environ.get("ORBIS_API_BASE", "https://api.deepseek.com")
MODEL = os.environ.get("ORBIS_MODEL", "deepseek-chat")

# ── Paths ──
ORBIS_HOME = Path(__file__).resolve().parent.parent
ORCA_DIR = ORBIS_HOME / "orca"
AGENT_DIR = ORBIS_HOME / "agent"
WORKSPACE = Path(os.environ.get("ORBIS_WORKSPACE", str(ORBIS_HOME / "workspace")))

# ── ORCA ──
ORCA_BIN = os.environ.get("ORCA_BIN", "${ORCA_BIN}")
ORCA_2AIM_BIN = os.environ.get("ORCA_2AIM_BIN", "${ORCA_DIR_PATH:-}/orca_2aim")
ORCA_2MKL_BIN = os.environ.get("ORCA_2MKL_BIN", "${ORCA_DIR_PATH:-}/orca_2mkl")

# ── External Tools ──
MULTIWFN_BIN = os.environ.get("MULTIWFN_BIN", "${MULTIWFN_BIN}")
VMD_BIN = os.environ.get("VMD_BIN", "${VMD_EXE}")

# ── Resources ──
NPROCS = int(os.environ.get("ORBIS_NPROCS", "$(nproc 2>/dev/null || echo 4)"))
MAXCORE = int(os.environ.get("ORBIS_MAXCORE", "4096"))

# ── Agent ──
MAX_ITERATIONS = int(os.environ.get("ORBIS_MAX_ITERATIONS", "30"))
TOOL_TIMEOUT = int(os.environ.get("ORBIS_TOOL_TIMEOUT", "3600"))
TEMPERATURE = float(os.environ.get("ORBIS_TEMPERATURE", "0.3"))


def ensure_workspace():
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    return WORKSPACE
PYEOF

ok "Config written: $CONFIG_FILE"

# ── 5. Verify ──────────────────────────────────────────────────────
header "Verification"

set +euo pipefail; source "$VENV_DIR/bin/activate"; set -euo pipefail
if python3 -c "import sys; sys.path.insert(0,'$ORBIS_HOME'); from agent.orbis_tools import TOOL_REGISTRY; print(f'{len(TOOL_REGISTRY)} tools OK')" 2>/dev/null; then
    ok "Agent imports OK"
else
    err "Agent import failed — check error above"
fi

# ── Done ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}  ✓  Setup complete${NC}"
echo ""
echo "  Set your API key:"
echo "    export ORBIS_API_KEY='sk-...'"
echo ""
echo "  Run Orbis:"
echo "    bash run_orbis.sh 'Your scientific goal'"
echo "    bash start_web.sh"
echo ""
