"""
Orbis Agent Configuration
"""
import os
from pathlib import Path

# ── API Configuration ──
API_KEY = os.environ.get("ORBIS_API_KEY", "sk-7ef90b3694c74295a551154a441fb078")
API_BASE = os.environ.get("ORBIS_API_BASE", "https://api.deepseek.com")
MODEL = os.environ.get("ORBIS_MODEL", "deepseek-chat")

# ── Paths ──
ORBIS_HOME = Path(__file__).resolve().parent.parent  # orbis/
ORCA_DIR = ORBIS_HOME / "orca"
AGENT_DIR = ORBIS_HOME / "agent"
WORKSPACE = Path(os.environ.get("ORBIS_WORKSPACE", str(ORBIS_HOME / "workspace")))

# ── ORCA Binary Paths ──
ORCA_BIN = os.environ.get("ORCA_BIN", "/home/quantum/tools/orca_6_1_0_avx2/orca")
ORCA_2AIM_BIN = os.environ.get("ORCA_2AIM_BIN", "/home/quantum/tools/orca_6_1_0_avx2/orca_2aim")
ORCA_2MKL_BIN = os.environ.get("ORCA_2MKL_BIN", "/home/quantum/tools/orca_6_1_0_avx2/orca_2mkl")

# ── Compute Resources ──
NPROCS = int(os.environ.get("ORBIS_NPROCS", "16"))
MAXCORE = int(os.environ.get("ORBIS_MAXCORE", "4096"))

# ── Agent Settings ──
MAX_ITERATIONS = int(os.environ.get("ORBIS_MAX_ITERATIONS", "30"))
TOOL_TIMEOUT = int(os.environ.get("ORBIS_TOOL_TIMEOUT", "3600"))  # 1 hour for ORCA jobs
TEMPERATURE = float(os.environ.get("ORBIS_TEMPERATURE", "0.3"))


def ensure_workspace():
    """Ensure workspace directory exists."""
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    return WORKSPACE
