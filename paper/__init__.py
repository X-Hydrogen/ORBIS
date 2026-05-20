"""
Orbis Paper Generator — Automatic Research Paper Generation

Generates complete publication-ready papers from quantum chemistry
computational results. Outputs both LaTeX (ACS-style) and Word (DOCX) formats.
"""

from .generator import PaperGenerator, generate_paper

__all__ = ["PaperGenerator", "generate_paper"]
