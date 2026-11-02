"""Generate the image1 on-screen menu font and static text ROM.

The font is a hand-drawn 5x7 ASCII set, padded to an 8x8 cell and enlarged 2x
in RTL (10x14 visible glyph inside a 16x16 character cell). Only the printable
range 0x20..0x5F is stored; menu text is upper-case by design.

Run from the repository root:
    python tools/generate-menu-font.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# 5 columns x 7 rows, '#' = ink.  Every glyph is left-aligned in the 8x8 cell.
GLYPHS = {
    " ": ("     ", "     ", "     ", "     ", "     ", "     ", "     "),
    "!": ("  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "),
    "?": (" ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  "),
    ":": ("     ", "  #  ", "  #  ", "     ", "  #  ", "  #  ", "     "),
    "-": ("     ", "     ", "     ", "#####", "     ", "     ", "     "),
    ".": ("     ", "     ", "     ", "     ", "     ", " ##  ", " ##  "),
    "/": ("    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    "),
    "+": ("     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "),
    "=": ("     ", "     ", "#####", "     ", "#####", "     ", "     "),
    "<": ("    #", "   # ", "  #  ", " #   ", "  #  ", "   # ", "    #"),
    ">": ("#    ", " #   ", "  #  ", "   # ", "  #  ", " #   ", "#    "),
    "[": (" ### ", " #   ", " #   ", " #   ", " #   ", " #   ", " ### "),
    "]": (" ### ", "   # ", "   # ", "   # ", "   # ", "   # ", " ### "),
    "0": (" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "),
    "1": ("  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "),
    "2": (" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"),
    "3": ("#### ", "    #", "    #", " ### ", "    #", "    #", "#### "),
    "4": ("   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "),
    "5": ("#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "),
    "6": (" ### ", "#    ", "#    ", "#### ", "#   #", "#   #", " ### "),
    "7": ("#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "),
    "8": (" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "),
    "9": (" ### ", "#   #", "#   #", " ####", "    #", "    #", " ### "),
    "A": (" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"),
    "B": ("#### ", "#   #", "#### ", "#   #", "#   #", "#   #", "#### "),
    "C": (" ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####"),
    "D": ("#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "),
    "E": ("#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"),
    "F": ("#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "),
    "G": (" ####", "#    ", "#    ", "# ###", "#   #", "#   #", " ### "),
    "H": ("#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"),
    "I": ("#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"),
    "J": ("  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "),
    "K": ("#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"),
    "L": ("#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"),
    "M": ("#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"),
    "N": ("#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"),
    "O": (" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "),
    "P": ("#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "),
    "Q": (" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"),
    "R": ("#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"),
    "S": (" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "),
    "T": ("#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "),
    "U": ("#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "),
    "V": ("#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "),
    "W": ("#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"),
    "X": ("#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"),
    "Y": ("#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "),
    "Z": ("#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"),
}

for ch, rows in GLYPHS.items():
    assert len(rows) == 7, (ch, len(rows))
    assert all(len(r) == 5 for r in rows), ch

# Static menu rows.  Column 0 is the selection marker (filled by RTL); labels
# start at column 1 and dynamic values start at column 10.
ITEM_TEXTS = {
    0: " VIEW",
    1: " SPLIT",
    2: " SHAPE",
    3: " FREEZE",
    4: " TEST",
    5: " CANNY",
    6: " CANNY H",
    7: " CANNY L",
    8: " CANNY RST PRESS K1",
    9: " MEDIAN",
    10: " WB R",
    11: " WB G",
    12: " WB B",
    13: " WB RST PRESS K1",
    14: " GAMMA",
    15: " GAMMA P",
    16: " BLACK",
    17: " BOOT IMAGE",
    18: " LOAD IMAGE",
    # Footer rows 19/20 are BROWSE; 21/22 are EDIT.
    19: "K2/K3/KNOB:SCROLL  K1:ENTER",
    20: "HOLD K1:EXIT",
    21: "K2:+1 K3:-1 KNOB:FAST",
    22: "K1:OK  HOLD K1:EXIT",
}
COLS = 30
assert set(ITEM_TEXTS) == set(range(23))


def preview():
    """Print the static labels so the table can be eyeballed before use."""
    for item in sorted(ITEM_TEXTS):
        line = ITEM_TEXTS[item].ljust(COLS)
        print(f"{item:2d} |{line}|")


def generate_font():
    lines = [
        "`timescale 1ns/1ps",
        "",
        "// Generated by tools/generate-menu-font.py. Do not edit by hand.",
        "// 5x7 ASCII glyphs, 0x20..0x5F, left-aligned in an 8-pixel cell.",
        "// Output bits [7:3] are the five columns; bits [2:0] are always zero.",
        "module menu_font_8x8(input [5:0] glyph, input [2:0] row,",
        "                    output reg [7:0] pixels);",
        "always @* begin",
        "    pixels = 8'h00;",
        "    case ({glyph,row})",
    ]
    for code in range(0x20, 0x60):
        ch = chr(code)
        rows = GLYPHS.get(ch)
        if rows is None:
            continue
        for y in range(7):
            bits = 0
            for x, pixel in enumerate(rows[y]):
                if pixel == "#":
                    bits |= 1 << (7 - x)
            if bits:
                index = (code - 0x20) * 8 + y
                lines.append(f"        10'h{index:03x}: pixels = 8'h{bits:02x}; // {ch!r} row {y}")
    lines += [
        "        default: pixels = 8'h00;",
        "    endcase",
        "end",
        "endmodule",
        "",
    ]
    (ROOT / "src/ui/menu_font_8x8.v").write_text("\n".join(lines), encoding="utf-8")


def generate_text_rom():
    lines = [
        "`timescale 1ns/1ps",
        "",
        "// Generated by tools/generate-menu-font.py. Do not edit by hand.",
        "// Static part of the 19 selectable menu rows.  The RTL overlays the",
        "// current value, selection marker and EDIT brackets.",
        "module menu_text_rom(input [4:0] item, input [4:0] col,",
        "                     output reg [7:0] ch);",
        "always @* begin",
        "    ch = 8'h20;",
        "    case ({item,col})",
    ]
    for item in range(21):
        text = ITEM_TEXTS[item].ljust(COLS)
        for col, ch in enumerate(text):
            if ch == " ":
                continue
            index = item * 32 + col
            lines.append(f"        10'h{index:03x}: ch = 8'h{ord(ch):02x}; // {ch!r} item {item} col {col}")
    lines += [
        "        default: ch = 8'h20;",
        "    endcase",
        "end",
        "endmodule",
        "",
    ]
    (ROOT / "src/ui/menu_text_rom.v").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    preview()
    generate_font()
    generate_text_rom()
    print("Generated src/ui/menu_font_8x8.v and src/ui/menu_text_rom.v")
