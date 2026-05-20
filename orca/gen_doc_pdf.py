#!/usr/bin/env python3
"""Generate documentation PDF for IQCAP copyright registration.
   Tables use smart column widths; long text always wraps, never truncates."""
import re
from pathlib import Path
from fpdf import FPDF

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
SANS_FONT = f"{FONT_DIR}/DejaVuSans.ttf"
SANS_BOLD = f"{FONT_DIR}/DejaVuSans-Bold.ttf"
MONO_FONT = f"{FONT_DIR}/DejaVuSansMono.ttf"
CJK_FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
CJK_BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"

PAGE_W = 210
MARGIN_L = 12
MARGIN_R = 12
CONTENT_W = PAGE_W - MARGIN_L - MARGIN_R
TABLE_FONT_SZ = 7
TABLE_LINE_H = 3.8
TABLE_PAD = 1.2
IQCAP_VERSION = "1.5.0"
IQCAP_DATE = "2026-03-02"


class DocPDF(FPDF):
    def __init__(self):
        super().__init__(orientation="P", unit="mm", format="A4")
        self.add_font("DSans", "", SANS_FONT)
        self.add_font("DSans", "B", SANS_BOLD)
        self.add_font("DMono", "", MONO_FONT)
        self.add_font("CJK", "", CJK_FONT)
        self.add_font("CJK", "B", CJK_BOLD)
        self.set_fallback_fonts(["CJK"])
        self.set_left_margin(MARGIN_L)
        self.set_right_margin(MARGIN_R)
        self.alias_nb_pages()
        self.set_auto_page_break(auto=True, margin=18)

    def header(self):
        if self.page_no() <= 1:
            return
        self.set_font("DSans", "B", 7.5)
        self.set_text_color(130, 130, 130)
        self.cell(0, 5,
                  f"IQCAP v{IQCAP_VERSION} - Intelligent Quantum Chemistry Analysis Platform"
                  " - Software Documentation", align="C")
        self.ln(3)
        self.set_draw_color(190, 190, 190)
        self.line(MARGIN_L, self.get_y(), PAGE_W - MARGIN_R, self.get_y())
        self.ln(3)

    def footer(self):
        self.set_y(-13)
        self.set_font("DSans", "", 7)
        self.set_text_color(150, 150, 150)
        self.cell(0, 8,
                  f"(C) 2024-2026 Hengyue Xu. All rights reserved."
                  f"        Page {self.page_no()}/{{nb}}", align="C")


# ---------------------------------------------------------------------------
# Table helpers
# ---------------------------------------------------------------------------
def _parse_table(lines, start):
    """Parse a markdown table, returning (rows, header_flags, end_index)."""
    rows, hdrs = [], []
    i = start
    while i < len(lines) and lines[i].strip().startswith("|"):
        cells = [c.strip() for c in lines[i].split("|")[1:-1]]
        if all(set(c) <= {"-", ":", " "} for c in cells):
            i += 1
            continue
        is_hdr = (
            i + 1 < len(lines)
            and lines[i + 1].strip().startswith("|")
            and all(set(c.strip()) <= {"-", ":", " "}
                    for c in lines[i + 1].split("|")[1:-1])
        )
        rows.append(cells)
        hdrs.append(is_hdr)
        i += 1
    return rows, hdrs, i


def _col_widths(pdf, rows, total_w):
    """Give non-last columns their header width, last column gets the rest."""
    if not rows:
        return []
    ncols = max(len(r) for r in rows)
    if ncols <= 1:
        return [total_w]

    pdf.set_font("DSans", "B", TABLE_FONT_SZ)
    hdr_widths = []
    for ci in range(ncols):
        max_w = 0
        for r in rows:
            txt = r[ci] if ci < len(r) else ""
            w = pdf.get_string_width(txt.replace("`", ""))
            max_w = max(max_w, w)
        hdr_widths.append(max_w + 2 * TABLE_PAD + 3)

    short_cols_w = sum(hdr_widths[:-1])
    min_last = total_w * 0.3
    if short_cols_w + min_last > total_w:
        cap = (total_w - min_last) / max(ncols - 1, 1)
        for ci in range(ncols - 1):
            hdr_widths[ci] = min(hdr_widths[ci], cap)
        short_cols_w = sum(hdr_widths[:-1])

    hdr_widths[-1] = total_w - short_cols_w
    return hdr_widths


def _count_wrap_lines(pdf, txt, cell_w):
    usable = cell_w - 2 * TABLE_PAD
    if usable <= 1:
        return 1
    words = txt.split()
    if not words:
        return 1
    lines, cur = 1, 0
    for w in words:
        ww = pdf.get_string_width(w + " ")
        if cur + ww > usable and cur > 0:
            lines += 1
            cur = ww
        else:
            cur += ww
    return lines


def _render_table(pdf, rows, hdrs, col_ws):
    ncols = len(col_ws)
    for ri, (row, is_hdr) in enumerate(zip(rows, hdrs)):
        style = "B" if is_hdr else ""
        pdf.set_font("DSans", style, TABLE_FONT_SZ)

        max_lines = 1
        for ci in range(ncols):
            txt = row[ci] if ci < len(row) else ""
            nl = _count_wrap_lines(pdf, txt, col_ws[ci])
            max_lines = max(max_lines, nl)
        row_h = max_lines * TABLE_LINE_H + 1.5

        if pdf.get_y() + row_h > 272:
            pdf.add_page()

        y0 = pdf.get_y()
        x = MARGIN_L
        saved_margin = pdf.l_margin
        for ci in range(ncols):
            txt = row[ci] if ci < len(row) else ""
            w = col_ws[ci]

            if is_hdr:
                pdf.set_fill_color(220, 232, 245)
            else:
                pdf.set_fill_color(252, 252, 252) if ri % 2 == 0 else pdf.set_fill_color(255, 255, 255)

            pdf.set_draw_color(180, 180, 180)
            pdf.rect(x, y0, w, row_h, style="DF")

            pdf.l_margin = x + TABLE_PAD
            pdf.set_xy(x + TABLE_PAD, y0 + 0.7)
            pdf.set_font("DSans", style, TABLE_FONT_SZ)
            pdf.set_text_color(25, 25, 25)
            pdf.multi_cell(w - 2 * TABLE_PAD, TABLE_LINE_H, _strip_md_links(txt))

            x += w
        pdf.l_margin = saved_margin

        pdf.set_y(y0 + row_h)


# ---------------------------------------------------------------------------
# Inline rich text
# ---------------------------------------------------------------------------
def _strip_md_links(text):
    """Convert [text](url) to just text."""
    return re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)


def _rich(pdf, text, sz=10):
    lh = sz * 0.55 + 1
    text = _strip_md_links(text)
    parts = re.split(r'(\*\*.*?\*\*|`[^`]+`)', text)
    for p in parts:
        if p.startswith("**") and p.endswith("**"):
            pdf.set_font("DSans", "B", sz)
            pdf.write(lh, p[2:-2])
        elif p.startswith("`") and p.endswith("`"):
            pdf.set_font("DMono", "", sz - 1)
            pdf.write(lh, p[1:-1])
        else:
            pdf.set_font("DSans", "", sz)
            pdf.write(lh, p)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def build_pdf(md_path, out_path):
    lines = Path(md_path).read_text(encoding="utf-8").splitlines()
    pdf = DocPDF()

    # ==================== Title page ====================
    pdf.add_page()
    pdf.ln(35)
    pdf.set_font("DSans", "B", 32)
    pdf.set_text_color(25, 25, 25)
    pdf.cell(0, 14, "IQCAP", align="C")
    pdf.ln(18)
    pdf.set_font("DSans", "", 13)
    pdf.set_text_color(70, 70, 70)
    pdf.cell(0, 8, "Intelligent Quantum Chemistry Analysis Platform", align="C")
    pdf.ln(24)
    pdf.set_draw_color(0, 80, 160)
    pdf.set_line_width(0.8)
    pdf.line(55, pdf.get_y(), PAGE_W - 55, pdf.get_y())
    pdf.set_line_width(0.2)
    pdf.ln(20)
    pdf.set_font("DSans", "B", 22)
    pdf.set_text_color(0, 70, 140)
    pdf.cell(0, 10, "Software Documentation", align="C")
    pdf.ln(14)
    pdf.set_font("DSans", "", 14)
    pdf.set_text_color(110, 110, 110)
    pdf.cell(0, 8, f"Version {IQCAP_VERSION}", align="C")
    pdf.ln(32)

    info = [
        ("Software Name", "IQCAP"),
        ("Full Name", "Intelligent Quantum Chemistry Analysis Platform"),
        ("Version", f"v{IQCAP_VERSION}"),
        ("Author", "Hengyue Xu"),
        ("ORCiD", "0000-0003-4438-9647"),
        ("Date", IQCAP_DATE),
        ("Copyright", "(C) 2024-2026 Hengyue Xu. All rights reserved."),
        ("Language", "Bash / Python 3"),
    ]
    pdf.set_text_color(40, 40, 40)
    for label, value in info:
        pdf.set_x(30)
        pdf.set_font("DSans", "B", 10.5)
        pdf.cell(45, 7.5, f"{label}:", align="R")
        pdf.set_font("DSans", "", 10.5)
        pdf.cell(4, 7.5, "")
        pdf.cell(0, 7.5, value)
        pdf.ln(8)

    pdf.ln(12)
    pdf.set_font("DSans", "", 8.5)
    pdf.set_text_color(110, 110, 110)
    pdf.set_x(30)
    pdf.multi_cell(PAGE_W - 60, 4.5,
        "Disclaimer: This software is a workflow orchestration and analysis "
        "platform. It does NOT include ORCA, Multiwfn, or VMD. Users must "
        "obtain those programs independently under their respective licenses.",
        align="C")

    # ==================== Content pages ====================
    pdf.add_page()
    in_code = False
    i = 0

    while i < len(lines):
        line = lines[i]

        # --- code block ---
        if line.strip().startswith("```"):
            in_code = not in_code
            pdf.ln(1.5)
            i += 1
            continue
        if in_code:
            pdf.set_font("DMono", "", 7.2)
            pdf.set_text_color(35, 35, 35)
            pdf.set_fill_color(244, 244, 244)
            pdf.set_x(MARGIN_L + 4)
            pdf.cell(CONTENT_W - 8, 3.8, f"  {line.replace(chr(9), '    ')}", fill=True)
            pdf.ln(3.8)
            i += 1
            continue

        # --- table ---
        if line.strip().startswith("|"):
            rows, hdrs, end = _parse_table(lines, i)
            if rows:
                ws = _col_widths(pdf, rows, CONTENT_W)
                _render_table(pdf, rows, hdrs, ws)
                pdf.ln(3)
            i = end
            continue

        # --- H1 ---
        if line.startswith("# ") and not line.startswith("## "):
            pdf.ln(3)
            pdf.set_font("DSans", "B", 14)
            pdf.set_text_color(20, 20, 20)
            pdf.multi_cell(CONTENT_W, 8, _strip_md_links(line[2:].strip()))
            pdf.ln(2)
            i += 1
            continue

        # --- H2 ---
        if line.startswith("## "):
            if pdf.get_y() > 248:
                pdf.add_page()
            pdf.ln(5)
            pdf.set_font("DSans", "B", 13)
            pdf.set_text_color(0, 70, 140)
            pdf.multi_cell(CONTENT_W, 7.5, line[3:].strip())
            pdf.set_draw_color(0, 70, 140)
            pdf.set_line_width(0.35)
            pdf.line(MARGIN_L, pdf.get_y() + 1, PAGE_W - MARGIN_R, pdf.get_y() + 1)
            pdf.ln(4)
            pdf.set_line_width(0.2)
            i += 1
            continue

        # --- H3 ---
        if line.startswith("### "):
            if pdf.get_y() > 250:
                pdf.add_page()
            pdf.ln(3)
            pdf.set_font("DSans", "B", 11.5)
            pdf.set_text_color(35, 35, 35)
            pdf.multi_cell(CONTENT_W, 6.5, line[4:].strip())
            pdf.ln(1.5)
            i += 1
            continue

        # --- H4 ---
        if line.startswith("#### "):
            if pdf.get_y() > 255:
                pdf.add_page()
            pdf.ln(2)
            pdf.set_font("DSans", "B", 10)
            pdf.set_text_color(50, 50, 50)
            pdf.multi_cell(CONTENT_W, 5.5, line[5:].strip())
            pdf.ln(1)
            i += 1
            continue

        # --- horizontal rule ---
        if line.strip() == "---":
            pdf.ln(3)
            pdf.set_draw_color(195, 195, 195)
            pdf.line(MARGIN_L, pdf.get_y(), PAGE_W - MARGIN_R, pdf.get_y())
            pdf.ln(4)
            i += 1
            continue

        # --- numbered list ---
        m = re.match(r'^(\d+)\.\s+(.*)', line.strip())
        if m:
            pdf.set_x(MARGIN_L + 2)
            pdf.set_font("DSans", "B", 10)
            pdf.set_text_color(0, 70, 140)
            pdf.write(6, f"{m.group(1)}. ")
            pdf.set_text_color(30, 30, 30)
            _rich(pdf, m.group(2), 10)
            pdf.ln(7)
            i += 1
            continue

        # --- bullet ---
        if line.strip().startswith("- ") or line.strip().startswith("* "):
            indent = len(line) - len(line.lstrip())
            pdf.set_x(MARGIN_L + 3 + indent * 2)
            pdf.set_font("DSans", "", 10)
            pdf.set_text_color(30, 30, 30)
            pdf.write(6, "\u2022 ")
            _rich(pdf, line.strip()[2:], 10)
            pdf.ln(6.5)
            i += 1
            continue

        # --- blank ---
        if not line.strip():
            pdf.ln(2.5)
            i += 1
            continue

        # --- bold-only line ---
        s = line.strip()
        if s.startswith("**") and s.endswith("**") and s.count("**") == 2:
            if pdf.get_y() > 260:
                pdf.add_page()
            pdf.set_font("DSans", "B", 10)
            pdf.set_text_color(30, 30, 30)
            pdf.multi_cell(CONTENT_W, 5.5, s[2:-2])
            pdf.ln(1)
            i += 1
            continue

        # --- paragraph ---
        pdf.set_font("DSans", "", 10)
        pdf.set_text_color(30, 30, 30)
        _rich(pdf, line, 10)
        pdf.ln(6)
        i += 1

    pdf.output(str(out_path))
    print(f"Documentation PDF: {out_path}")
    print(f"  Pages: {pdf.page_no()},  Size: {out_path.stat().st_size / 1024:.0f} KB")


base = Path(__file__).parent
build_pdf(base / "README.md", base / f"IQCAP_v{IQCAP_VERSION}_Documentation.pdf")
