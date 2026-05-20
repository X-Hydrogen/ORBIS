#!/usr/bin/env python3
"""Generate source code PDF for IQCAP copyright registration.
   Handles long code lines by soft-wrapping with continuation indent."""
from pathlib import Path
from fpdf import FPDF

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
MONO_FONT = f"{FONT_DIR}/DejaVuSansMono.ttf"
SANS_FONT = f"{FONT_DIR}/DejaVuSans.ttf"
SANS_BOLD = f"{FONT_DIR}/DejaVuSans-Bold.ttf"
CJK_FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
CJK_BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"

PAGE_W = 210
MARGIN = 10
NUM_W = 12
CODE_X = MARGIN + NUM_W + 1.5
CODE_W = PAGE_W - MARGIN - CODE_X
LINE_H = 3.3
FONT_SIZE = 6.2
WRAP_INDENT = 8
IQCAP_VERSION = "1.5.0"
IQCAP_DATE = "2026-03-02"


class SourceCodePDF(FPDF):
    def __init__(self):
        super().__init__(orientation="P", unit="mm", format="A4")
        self.add_font("DSans", "", SANS_FONT)
        self.add_font("DSans", "B", SANS_BOLD)
        self.add_font("DMono", "", MONO_FONT)
        self.add_font("CJK", "", CJK_FONT)
        self.add_font("CJK", "B", CJK_BOLD)
        self.set_fallback_fonts(["CJK"])
        self.alias_nb_pages()
        self.set_auto_page_break(auto=False)
        self._char_w = None

    def header(self):
        self.set_font("DSans", "B", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 5,
                  f"IQCAP v{IQCAP_VERSION} - Intelligent Quantum Chemistry Analysis Platform"
                  " - Source Code", align="C")
        self.ln(3)
        self.set_draw_color(180, 180, 180)
        self.line(MARGIN, self.get_y(), PAGE_W - MARGIN, self.get_y())
        self.ln(3)

    def footer(self):
        self.set_y(-12)
        self.set_font("DSans", "", 7.5)
        self.set_text_color(140, 140, 140)
        self.cell(0, 8,
                  f"(C) 2024-2026 Hengyue Xu. All rights reserved."
                  f"        Page {self.page_no()}/{{nb}}", align="C")

    def _get_char_w(self):
        if self._char_w is None:
            self.set_font("DMono", "", FONT_SIZE)
            self._char_w = self.get_string_width("M")
        return self._char_w

    def _max_chars_per_line(self, first_line=True):
        w = CODE_W if first_line else CODE_W - WRAP_INDENT
        return max(20, int(w / self._get_char_w()))

    def _check_page(self, lines_needed=1):
        if self.get_y() + LINE_H * lines_needed > 282:
            self.add_page()

    def add_title_page(self, total_lines):
        self.add_page()
        self.ln(45)
        self.set_font("DSans", "B", 32)
        self.set_text_color(25, 25, 25)
        self.cell(0, 14, "IQCAP", align="C")
        self.ln(18)
        self.set_font("DSans", "", 14)
        self.set_text_color(60, 60, 60)
        self.cell(0, 8, "Intelligent Quantum Chemistry Analysis Platform", align="C")
        self.ln(22)
        self.set_draw_color(0, 80, 160)
        self.set_line_width(0.8)
        self.line(60, self.get_y(), PAGE_W - 60, self.get_y())
        self.set_line_width(0.2)
        self.ln(18)
        self.set_font("DSans", "B", 22)
        self.set_text_color(0, 70, 140)
        self.cell(0, 10, "Source Code", align="C")
        self.ln(14)
        self.set_font("DSans", "", 14)
        self.set_text_color(100, 100, 100)
        self.cell(0, 8, f"Version {IQCAP_VERSION}", align="C")
        self.ln(30)

        info = [
            ("Software Name", "IQCAP (Intelligent Quantum Chemistry Analysis Platform)"),
            ("Version", f"v{IQCAP_VERSION}"),
            ("Author", "Hengyue Xu"),
            ("ORCiD", "0000-0003-4438-9647"),
            ("Date", IQCAP_DATE),
            ("Copyright", "(C) 2024-2026 Hengyue Xu. All rights reserved."),
            ("Language", "Bash / Python 3"),
            ("Total Lines", f"{total_lines:,}"),
        ]
        self.set_text_color(40, 40, 40)
        for label, value in info:
            self.set_x(28)
            self.set_font("DSans", "B", 11)
            self.cell(50, 8, f"{label}:", align="R")
            self.set_font("DSans", "", 11)
            self.cell(5, 8, "")
            self.cell(0, 8, value)
            self.ln(9)

        self.ln(16)
        self.set_font("DSans", "", 9)
        self.set_text_color(100, 100, 100)
        self.set_x(28)
        self.multi_cell(PAGE_W - 56, 5,
            "Disclaimer: This software is a workflow orchestration and analysis "
            "platform. It does NOT include ORCA, Multiwfn, or VMD. Users must "
            "obtain those programs independently under their respective licenses.",
            align="C")

    def add_source_file(self, filepath, display_name):
        self.add_page()
        self.set_font("DSans", "B", 13)
        self.set_text_color(0, 70, 140)
        self.cell(0, 9, display_name, align="L")
        self.ln(5)
        self.set_draw_color(0, 80, 160)
        self.set_line_width(0.5)
        self.line(MARGIN, self.get_y(), PAGE_W - MARGIN, self.get_y())
        self.ln(4)
        self.set_line_width(0.2)

        src_lines = Path(filepath).read_text(encoding="utf-8").splitlines()
        max_chars = self._max_chars_per_line(True)
        max_chars_cont = self._max_chars_per_line(False)

        for line_no, raw_line in enumerate(src_lines, 1):
            safe = raw_line.replace("\t", "    ")

            if len(safe) <= max_chars:
                visual_lines = [safe]
            else:
                visual_lines = []
                remaining = safe
                first = True
                while remaining:
                    limit = max_chars if first else max_chars_cont
                    visual_lines.append(remaining[:limit])
                    remaining = remaining[limit:]
                    first = False

            self._check_page(len(visual_lines))

            for vi, vline in enumerate(visual_lines):
                y = self.get_y()

                # Line number (only on first visual line)
                self.set_font("DMono", "", FONT_SIZE)
                self.set_text_color(150, 150, 150)
                self.set_x(MARGIN)
                if vi == 0:
                    self.cell(NUM_W, LINE_H, f"{line_no:>5}", align="R")
                else:
                    self.cell(NUM_W, LINE_H, "", align="R")

                # Separator line
                sep_x = MARGIN + NUM_W + 0.3
                self.set_draw_color(210, 210, 210)
                self.line(sep_x, y, sep_x, y + LINE_H)

                # Code text
                self.set_font("DMono", "", FONT_SIZE)
                self.set_text_color(20, 20, 20)
                x_start = CODE_X + (WRAP_INDENT if vi > 0 else 0)
                self.set_x(x_start)
                self.cell(0, LINE_H, f" {vline}")
                self.ln(LINE_H)


pdf = SourceCodePDF()

base = Path(__file__).parent
source_files = [
    (base / "bin" / "iqcap-opt.sh",
     "Module 1: iqcap-opt.sh  (Geometry Optimization)"),
    (base / "bin" / "iqcap-basic_elect_analysis.sh",
     "Module 2: iqcap-basic_elect_analysis.sh  (Basic Electronic Structure Analysis)"),
    (base / "bin" / "iqcap-elect_interaction.sh",
     "Module 3: iqcap-elect_interaction.sh  (Weak Interaction Analysis)"),
    (base / "bin" / "iqcap-ts.sh",
     "Module 4: iqcap-ts.sh  (Transition State & Reaction Path Analysis)"),
]
total_lines = sum(len(path.read_text(encoding="utf-8").splitlines()) for path, _ in source_files)

pdf.add_title_page(total_lines)

for path, title in source_files:
    pdf.add_source_file(path, title)

out = base / f"IQCAP_v{IQCAP_VERSION}_SourceCode.pdf"
pdf.output(str(out))
print(f"Source code PDF generated: {out}")
print(f"  Pages: {pdf.page_no()}")
print(f"  Size:  {out.stat().st_size / 1024:.0f} KB")
