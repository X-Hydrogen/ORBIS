"""
Orbis Agent Package — Lazy imports to avoid loading heavy deps.
"""
# Don't eagerly import orbis_agent (pulls in openai SDK)
# Import config and tools only (lightweight)
from .orbis_config import *
from .orbis_tools import TOOL_REGISTRY, TOOL_DEFINITIONS

# Lazy access to OrbisAgent
def get_agent(**kwargs):
    from .orbis_agent import OrbisAgent
    return OrbisAgent(**kwargs)

__all__ = ["TOOL_REGISTRY", "TOOL_DEFINITIONS", "get_agent"]
