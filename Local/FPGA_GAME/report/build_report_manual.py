from __future__ import annotations

from datetime import date
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "report" / "YOLO边缘姿态识别与游戏联动验证报告手册.docx"

DEMO_ROOT = Path(r"C:\Users\Administrator\Desktop\EfinityFPGAfour(1)\edge_picture\SoulRiderDemo")
MODEL_ROOT = Path(r"D:\EfinityModels\MODEL_FULL")

INPUT_IMAGE = ROOT / "report" / "assets" / "example_input.jpg"
EDGE_IMAGE = ROOT / "report" / "assets" / "example_edge.png"
POSE_IMAGE = ROOT / "report" / "assets" / "example_pose.jpg"
GAME_IMAGE = DEMO_ROOT / "outputs" / "browser_pic_relaxed.png"
RESULTS_IMAGE = MODEL_ROOT / "runs" / "full" / "train" / "results.png"
LABEL_IMAGE = MODEL_ROOT / "runs" / "full" / "train" / "val_batch0_labels.jpg"
PRED_IMAGE = MODEL_ROOT / "runs" / "full" / "train" / "val_batch0_pred.jpg"

FONT_CN = "Microsoft YaHei"
FONT_MONO = "Consolas"
BLACK = "000000"
INK = "1D2733"
NAVY = "17324D"
PALE_BLUE = "EAF2F8"
PALE_GRAY = "F4F6F8"
MID_GRAY = "D9D9D9"
TEXT_GRAY = "555F6B"


def set_run_font(run, name: str = FONT_CN, size: float | None = None,
                 bold: bool | None = None, color: str | None = None) -> None:
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), name)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = RGBColor.from_string(color)


def set_style_font(style, name: str, size: float, bold: bool = False,
                   color: str = BLACK) -> None:
    style.font.name = name
    style._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), name)
    style._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), name)
    style._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), name)
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = RGBColor.from_string(color)


def set_cell_shading(cell, fill: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shading = tc_pr.find(qn("w:shd"))
    if shading is None:
        shading = OxmlElement("w:shd")
        tc_pr.append(shading)
    shading.set(qn("w:fill"), fill)


def set_cell_border(cell, color: str = MID_GRAY, size: str = "4") -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    borders = tc_pr.first_child_found_in("w:tcBorders")
    if borders is None:
        borders = OxmlElement("w:tcBorders")
        tc_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        element = borders.find(qn(f"w:{edge}"))
        if element is None:
            element = OxmlElement(f"w:{edge}")
            borders.append(element)
        element.set(qn("w:val"), "single")
        element.set(qn("w:sz"), size)
        element.set(qn("w:space"), "0")
        element.set(qn("w:color"), color)


def set_cell_margins(cell, top: int = 90, start: int = 110,
                     bottom: int = 90, end: int = 110) -> None:
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def repeat_table_header(row) -> None:
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


def set_table_widths(table, widths_cm: list[float]) -> None:
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    grid = table._tbl.tblGrid
    for index, width_cm in enumerate(widths_cm):
        grid.gridCol_lst[index].w = Cm(width_cm)
        for row in table.rows:
            row.cells[index].width = Cm(width_cm)


def format_body_paragraph(paragraph, space_after: float = 5.0,
                          line_spacing: float = 1.3) -> None:
    fmt = paragraph.paragraph_format
    fmt.space_after = Pt(space_after)
    fmt.space_before = Pt(0)
    fmt.line_spacing_rule = WD_LINE_SPACING.MULTIPLE
    fmt.line_spacing = line_spacing


def add_body(doc: Document, text: str, bold_lead: str | None = None) -> None:
    paragraph = doc.add_paragraph()
    format_body_paragraph(paragraph)
    if bold_lead and text.startswith(bold_lead):
        lead = paragraph.add_run(bold_lead)
        set_run_font(lead, bold=True, color=INK)
        rest = paragraph.add_run(text[len(bold_lead):])
        set_run_font(rest, color=INK)
    else:
        run = paragraph.add_run(text)
        set_run_font(run, color=INK)


def add_bullet(doc: Document, text: str, bold_lead: str | None = None) -> None:
    paragraph = doc.add_paragraph(style="List Bullet")
    format_body_paragraph(paragraph, space_after=2.5, line_spacing=1.2)
    if bold_lead and text.startswith(bold_lead):
        lead = paragraph.add_run(bold_lead)
        set_run_font(lead, bold=True, color=INK)
        rest = paragraph.add_run(text[len(bold_lead):])
        set_run_font(rest, color=INK)
    else:
        run = paragraph.add_run(text)
        set_run_font(run, color=INK)


def add_caption(doc: Document, text: str) -> None:
    paragraph = doc.add_paragraph(style="Caption")
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.space_before = Pt(3)
    paragraph.paragraph_format.space_after = Pt(9)
    paragraph.paragraph_format.keep_with_next = False
    run = paragraph.add_run(text)
    set_run_font(run, size=8.5, color=TEXT_GRAY)


def add_chapter_heading(doc: Document, text: str):
    heading = doc.add_heading(text, level=1)
    heading.paragraph_format.page_break_before = True
    return heading


def add_code_block(doc: Document, text: str) -> None:
    table = doc.add_table(rows=1, cols=1)
    repeat_table_header(table.rows[0])
    set_table_widths(table, [16.6])
    cell = table.cell(0, 0)
    set_cell_shading(cell, "F3F5F7")
    set_cell_border(cell, color=MID_GRAY, size="4")
    set_cell_margins(cell, top=130, start=150, bottom=130, end=150)
    paragraph = cell.paragraphs[0]
    format_body_paragraph(paragraph, space_after=0, line_spacing=1.12)
    run = paragraph.add_run(text)
    set_run_font(run, name=FONT_MONO, size=8.5, color=INK)
    doc.add_paragraph().paragraph_format.space_after = Pt(0)


def add_table(doc: Document, headers: list[str], rows: list[list[str]],
              widths_cm: list[float], font_size: float = 8.8,
              center_columns: set[int] | None = None) -> None:
    center_columns = center_columns or set()
    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    table.style = "Table Grid"
    header = table.rows[0]
    repeat_table_header(header)
    for index, text in enumerate(headers):
        cell = header.cells[index]
        set_cell_shading(cell, NAVY)
        set_cell_border(cell)
        set_cell_margins(cell)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        paragraph = cell.paragraphs[0]
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        format_body_paragraph(paragraph, space_after=0, line_spacing=1.05)
        run = paragraph.add_run(text)
        set_run_font(run, size=font_size, bold=True, color="FFFFFF")
    for row_index, values in enumerate(rows):
        cells = table.add_row().cells
        for column_index, text in enumerate(values):
            cell = cells[column_index]
            set_cell_shading(cell, "FFFFFF" if row_index % 2 == 0 else PALE_GRAY)
            set_cell_border(cell)
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            paragraph = cell.paragraphs[0]
            paragraph.alignment = (
                WD_ALIGN_PARAGRAPH.CENTER
                if column_index in center_columns
                else WD_ALIGN_PARAGRAPH.LEFT
            )
            format_body_paragraph(paragraph, space_after=0, line_spacing=1.12)
            run = paragraph.add_run(str(text))
            set_run_font(run, size=font_size, color=INK)
    set_table_widths(table, widths_cm)
    spacer = doc.add_paragraph()
    spacer.paragraph_format.space_after = Pt(0)
    spacer.paragraph_format.line_spacing = 0.6


def add_figure(doc: Document, image_path: Path, width_cm: float,
               caption: str, alt_text: str) -> None:
    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.keep_with_next = True
    paragraph.paragraph_format.space_before = Pt(2)
    paragraph.paragraph_format.space_after = Pt(0)
    run = paragraph.add_run()
    shape = run.add_picture(str(image_path), width=Cm(width_cm))
    shape._inline.docPr.set("descr", alt_text)
    add_caption(doc, caption)


def add_figure_trio(doc: Document, captions: list[str]) -> None:
    table = doc.add_table(rows=2, cols=3)
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    repeat_table_header(table.rows[0])
    for index, image_path in enumerate((INPUT_IMAGE, EDGE_IMAGE, POSE_IMAGE)):
        cell = table.cell(0, index)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        paragraph = cell.paragraphs[0]
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        paragraph.paragraph_format.space_after = Pt(0)
        run = paragraph.add_run()
        shape = run.add_picture(str(image_path), width=Cm(5.2))
        shape._inline.docPr.set("descr", captions[index])
        caption_cell = table.cell(1, index)
        caption_paragraph = caption_cell.paragraphs[0]
        caption_paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        caption_paragraph.paragraph_format.space_before = Pt(3)
        caption_paragraph.paragraph_format.space_after = Pt(8)
        cap_run = caption_paragraph.add_run(f"({chr(97 + index)}) {captions[index]}")
        set_run_font(cap_run, size=8.3, color=TEXT_GRAY)
    set_table_widths(table, [5.45, 5.45, 5.45])
    add_caption(doc, "图 2  单张图片的输入、image5 边缘转换与 YOLO 姿态输出")


def add_page_number_footer(section) -> None:
    footer = section.footer
    paragraph = footer.paragraphs[0]
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = paragraph.add_run("Soul Rider 图片驱动姿态验证 Demo    ")
    set_run_font(run, size=8, color=TEXT_GRAY)
    field_begin = OxmlElement("w:fldChar")
    field_begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = " PAGE "
    field_separate = OxmlElement("w:fldChar")
    field_separate.set(qn("w:fldCharType"), "separate")
    page_text = OxmlElement("w:t")
    page_text.text = "1"
    field_end = OxmlElement("w:fldChar")
    field_end.set(qn("w:fldCharType"), "end")
    page_run = paragraph.add_run()
    set_run_font(page_run, size=8, color=TEXT_GRAY)
    page_run._r.append(field_begin)
    page_run._r.append(instr)
    page_run._r.append(field_separate)
    page_run._r.append(page_text)
    page_run._r.append(field_end)


def configure_document(doc: Document) -> None:
    section = doc.sections[0]
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.top_margin = Cm(1.85)
    section.bottom_margin = Cm(1.7)
    section.left_margin = Cm(2.05)
    section.right_margin = Cm(2.05)
    section.header_distance = Cm(0.8)
    section.footer_distance = Cm(0.75)
    section.different_first_page_header_footer = True
    add_page_number_footer(section)

    styles = doc.styles
    normal = styles["Normal"]
    set_style_font(normal, FONT_CN, 10.2, color=INK)
    normal.paragraph_format.line_spacing_rule = WD_LINE_SPACING.MULTIPLE
    normal.paragraph_format.line_spacing = 1.3
    normal.paragraph_format.space_after = Pt(5)

    title = styles["Title"]
    set_style_font(title, FONT_CN, 27, bold=True, color=BLACK)
    title.paragraph_format.space_after = Pt(12)
    title_ppr = title._element.get_or_add_pPr()
    for border in title_ppr.findall(qn("w:pBdr")):
        title_ppr.remove(border)

    heading1 = styles["Heading 1"]
    set_style_font(heading1, FONT_CN, 15.5, bold=True, color=BLACK)
    heading1.paragraph_format.space_before = Pt(16)
    heading1.paragraph_format.space_after = Pt(7)
    heading1.paragraph_format.keep_with_next = True

    heading2 = styles["Heading 2"]
    set_style_font(heading2, FONT_CN, 12.2, bold=True, color=BLACK)
    heading2.paragraph_format.space_before = Pt(10)
    heading2.paragraph_format.space_after = Pt(4)
    heading2.paragraph_format.keep_with_next = True

    caption = styles["Caption"]
    set_style_font(caption, FONT_CN, 8.5, color=TEXT_GRAY)

    bullet = styles["List Bullet"]
    set_style_font(bullet, FONT_CN, 10.0, color=INK)


def add_cover(doc: Document) -> None:
    for _ in range(5):
        doc.add_paragraph()
    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.LEFT
    paragraph.paragraph_format.space_after = Pt(10)
    run = paragraph.add_run("技术验证文档")
    set_run_font(run, size=10.5, bold=True, color=TEXT_GRAY)

    title = doc.add_paragraph(style="Title")
    title.paragraph_format.space_after = Pt(12)
    run = title.add_run("YOLO 边缘姿态识别与游戏联动\n验证报告手册")
    set_run_font(run, size=28, bold=True, color=BLACK)

    subtitle = doc.add_paragraph()
    subtitle.paragraph_format.space_after = Pt(26)
    run = subtitle.add_run("图片输入、模型训练与骨架动作映射")
    set_run_font(run, size=13, color=TEXT_GRAY)

    intro = doc.add_paragraph()
    intro.paragraph_format.right_indent = Cm(1.5)
    format_body_paragraph(intro, space_after=18, line_spacing=1.45)
    run = intro.add_run(
        "本手册记录 FPGA image5 边缘图姿态模型从数据构造、训练评估到 Soul Rider "
        "游戏动作联动的完整验证路径，供项目复现、验收和后续移植使用。"
    )
    set_run_font(run, size=10.5, color=INK)

    table = doc.add_table(rows=4, cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    repeat_table_header(table.rows[0])
    metadata = [
        ("项目", "Soul Rider 图片驱动姿态验证 Demo"),
        ("核心模型", "YOLO11n Pose，FPGA image5 边缘输入"),
        ("文档版本", "V1.0"),
        ("日期", date(2026, 10, 24).strftime("%Y 年 %m 月 %d 日")),
    ]
    for row_index, (name, value) in enumerate(metadata):
        for col_index, text in enumerate((name, value)):
            cell = table.cell(row_index, col_index)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            set_cell_border(cell, color=MID_GRAY)
            set_cell_margins(cell, top=80, start=100, bottom=80, end=100)
            set_cell_shading(cell, PALE_GRAY if col_index == 0 else "FFFFFF")
            paragraph = cell.paragraphs[0]
            paragraph.paragraph_format.space_after = Pt(0)
            run = paragraph.add_run(text)
            set_run_font(run, size=9.2, bold=(col_index == 0), color=INK)
    set_table_widths(table, [3.2, 11.3])
    doc.add_page_break()


def add_contents(doc: Document) -> None:
    doc.add_heading("内容概览", level=1)
    add_body(
        doc,
        "本手册围绕三个核心问题组织：图片怎样进入系统并变成 FPGA 风格边缘图，"
        "姿态模型用什么数据和参数训练，YOLO 的关键点结果怎样转换为游戏可以执行的动作。"
        "游戏玩法仅保留验证所需的入口、状态和画面说明。",
    )
    contents = [
        ("1", "项目范围与总体链路", "明确 Demo 的边界、模块职责和数据流"),
        ("2", "图片输入与 image5 边缘处理", "文件夹循环、预处理参数、标签与运行时一致性"),
        ("3", "数据集构造与模型训练", "数据划分、训练参数、评估结果和最终权重"),
        ("4", "YOLO 骨架到游戏动作的连接", "17 点姿态、动作分类、HTTP 状态和游戏映射"),
        ("5", "验证结果与延迟", "动作回归、浏览器联动和端到端耗时"),
        ("6", "运行方法与维护要点", "启动、配置、临时目录和后续优化"),
    ]
    add_table(
        doc,
        ["章节", "内容", "读者关注点"],
        [[number, title, focus] for number, title, focus in contents],
        [2.0, 6.7, 7.9],
        center_columns={0},
    )
    add_body(
        doc,
        "结论先行：当前方案已经打通“图片文件夹输入 → FPGA image5 边缘图 → YOLO Pose "
        "关键点 → 离散动作分类 → 游戏骨架动作”的验证链路。最终模型与 Demo 使用的是同一份权重，"
        "文件 SHA256 前缀为 7bd069d4。",
        bold_lead="结论先行：",
    )


def add_project_overview(doc: Document) -> None:
    add_chapter_heading(doc, "1  项目范围与总体链路")
    doc.add_heading("1.1  验证目标", level=2)
    add_body(
        doc,
        "本 Demo 的目标不是训练最终商用识别器，而是验证四个工程条件能否同时成立："
        "电脑端能够复现 FPGA image5 的边缘输入，训练后的 YOLO Pose 能够在边缘图上稳定输出人体框和 17 个关键点，"
        "关键点能够被转换成有限的游戏动作，网页游戏能够在进入场景后自动读取图片并执行对应动作。",
    )
    add_body(
        doc,
        "原始 Soul Rider 工程保持不动。验证版本复制在 SoulRiderDemo 目录中，只增加姿态桥接、"
        "输入面板、状态 HUD 和自动开始/停止接口。",
    )

    doc.add_heading("1.2  总体数据流", level=2)
    add_table(
        doc,
        ["阶段", "主要实现", "输入", "输出"],
        [
            ["图片输入", "bridge.py", "指定文件夹中的 JPG/PNG 等图片", "按文件名排序的单帧图片"],
            ["边缘转换", "pose_engine.py + fpga_canny.py", "RGB 图片", "FPGA image5 二值边缘图"],
            ["姿态推理", "fpga_image5_best.pt", "三通道边缘图", "人体框、17 点坐标与置信度"],
            ["动作分类", "pose_engine.classify", "肩、肘、腕坐标", "stand / left / right / overhead"],
            ["游戏联动", "bridge.py + index.html", "HTTP JSON 状态", "Soul Rider 骨架动作与攻击"],
        ],
        [2.4, 4.4, 4.8, 5.0],
        center_columns={0},
    )
    add_body(
        doc,
        "图片输入装置由“文件夹扫描器 + 每秒一帧的播放器”组成。它模拟视频输入，"
        "但每一帧仍经过与训练集一致的 image5 转换，而不是把原始彩色图片直接输入 YOLO。",
    )
    doc.add_heading("1.3  验证边界", level=2)
    add_table(
        doc,
        ["范围内", "范围外"],
        [
            ["离线文件夹按 1 秒节拍模拟视频", "真实摄像头采集与视频解码"],
            ["电脑端复现 image5 边缘处理", "FPGA 板上实时 YOLO 推理"],
            ["17 点姿态到五类游戏动作", "17 点骨架的逐关节精确复刻"],
            ["复制版 Soul Rider 自动联动", "修改原始游戏工程或正式关卡系统"],
        ],
        [8.2, 8.4],
    )
    add_body(
        doc,
        "因此本手册中的“验证通过”表示接口和动作链路已经成立，不等同于 FPGA 端性能、"
        "现场光照适应性或最终动作精度已经验收。",
    )


def add_input_section(doc: Document) -> None:
    add_chapter_heading(doc, "2  图片输入与 image5 边缘处理")
    doc.add_heading("2.1  文件夹输入装置", level=2)
    add_body(
        doc,
        "输入目录固定为 C:\\Users\\Administrator\\Desktop\\SoulRider-Game(1)\\pic。"
        "服务启动时扫描该目录，支持 JPG、JPEG、PNG、BMP 和 WEBP，并按文件名排序循环读取。"
        "只有网页进入游戏场景后，前端才调用 /api/game-start，后台线程随即开始处理；"
        "返回主菜单或按 Esc 时调用 /api/game-stop，识别暂停。",
    )
    add_table(
        doc,
        ["参数", "当前值", "作用"],
        [
            ["输入目录", "SoulRider-Game(1)\\pic", "演示图片的唯一来源"],
            ["显示节拍", "1000 ms / 张", "模拟约 1 fps 的视频输入"],
            ["推理设备", "GPU 0", "RTX 5060 Laptop GPU"],
            ["人体框阈值", "0.20", "放宽小目标和弱边缘人体的检出"],
            ["关键点阈值", "0.15", "用于肩、肘、腕动作判定"],
            ["边缘支撑阈值", "0.05", "避免仅凭错误关键点硬猜动作"],
        ],
        [3.2, 6.5, 6.9],
    )
    add_body(
        doc,
        "每张图片处理前都会重新执行 image5 转换，因此输入风格的唯一来源是电脑端转换器，"
        "不会混用原始彩色图或之前缓存的不同边缘版本。",
    )

    doc.add_heading("2.2  与 FPGA 对应的处理链", level=2)
    add_table(
        doc,
        ["处理阶段", "参数或规则", "说明"],
        [
            ["白平衡", "R/G/B = 335/248/280", "Q8.8 增益，与 image5 RTL 一致"],
            ["Gamma", "启用，强度 42", "使用 RTL 导出的 256 项 LUT"],
            ["灰度", "(54R + 183G + 19B + 128) >> 8", "整数权重近似亮度"],
            ["3×3 中值", "启用", "压制边缘噪声和孤立点"],
            ["Gaussian", "[1 2 1; 2 4 2; 1 2 1] / 16", "平滑后计算梯度"],
            ["梯度与 NMS", "|Gx| + |Gy|，按 106/256 分方向", "保留局部极大值"],
            ["双阈值", "low = 30，high = 60", "强弱边缘分级"],
            ["连接与清理", "开启；两次邻域清理", "保留与强边缘连通的弱边缘"],
            ["边界保护", "顶部 12 行，左右 2 列，底部 2 行", "与 FPGA 输出一致，置黑"],
            ["光栅布局", "raster", "窗口取样存在约 7 行纵向延迟"],
        ],
        [3.2, 7.3, 6.1],
        center_columns={0},
    )
    add_figure_trio(
        doc,
        ["原始彩色输入", "FPGA image5 边缘图", "YOLO 17 点姿态结果"],
    )
    add_body(
        doc,
        "训练标签必须跟随 image5 光栅坐标：原始关键点统一向下平移 7 行，"
        "并把落在顶部 12 行、左右 2 列和底部 2 行内的点标记为不可见。"
        "运行时只转换图像，不再平移坐标，因为模型学到的已经是边缘图中的新坐标。",
        bold_lead="训练标签必须跟随 image5 光栅坐标：",
    )
    doc.add_heading("2.3  输入一致性与异常处理", level=2)
    add_body(
        doc,
        "所有输入图片统一按彩色图读取并转换到 RGB，不依据 EXIF 自动旋转，也不缩放或裁剪。"
        "这样运行时与训练集保持相同的像素布局；如果源图片方向本身不正确，应在进入文件夹前修正，"
        "不能在流水线中临时旋转，否则关键点会和图像错位。",
    )
    add_table(
        doc,
        ["情况", "系统行为", "结果"],
        [
            ["暂未进入游戏场景", "后台线程等待，不处理图片", "状态保持 waiting_game_start"],
            ["图片损坏或无法解码", "捕获异常并写入状态", "当前帧回到站立"],
            ["未检测到人体", "不生成猜测动作", "站立"],
            ["关键点或边缘支撑不足", "拒绝不可靠的手臂判定", "站立"],
            ["同图连续显示约 1 秒", "action_seq 不重复增加", "只攻击一次"],
        ],
        [4.8, 7.6, 4.2],
    )


def add_training_section(doc: Document) -> None:
    add_chapter_heading(doc, "3  数据集构造与模型训练")
    doc.add_heading("3.1  数据来源与固定划分", level=2)
    add_body(
        doc,
        "训练数据来自 COCO 2017 人体 17 点姿态标注。先按有有效关键点的图片筛选，"
        "再按人体大小和遮挡程度分层，以固定随机种子划分训练、验证和测试集。"
        "划分在原图阶段完成，避免同一张图片的不同边缘版本跨集合泄漏。",
    )
    add_table(
        doc,
        ["项目", "数量或设置", "说明"],
        [
            ["有效标注图片", "58,945", "train2017 与 val2017 合并筛选"],
            ["精确重复删除", "13", "按文件内容 SHA256 去重"],
            ["最终图片", "58,932", "image5 转换实际完成数量"],
            ["训练 / 验证 / 测试", "47,194 / 5,869 / 5,869", "约 80% / 10% / 10%"],
            ["随机种子", "20261022", "划分与试训抽样可复现"],
            ["早期 500 张冒烟图", "强制归入训练集", "避免被用作独立测试"],
            ["标注实例", "156,165", "最终写入的有效人体实例"],
        ],
        [4.2, 5.2, 7.2],
        center_columns={1},
    )

    doc.add_heading("3.2  image5 数据生成", level=2)
    add_body(
        doc,
        "58,932 张原图使用 8 进程并行转换为 image5 边缘 PNG，耗时 22.2 分钟，转换错误为 0。"
        "所有图像保持原宽高，不裁剪、不缩放；最终边缘像素值严格为 0 或 255，并复制为三通道供 YOLO 读取。",
    )
    add_table(
        doc,
        ["数据项", "训练集", "验证集", "测试集"],
        [
            ["图片", "47,194", "5,869", "5,869"],
            ["源人体实例", "124,825", "15,801", "15,483"],
            ["写入实例", "124,619", "15,775", "15,457"],
            ["边界丢失关键点", "9,375", "1,163", "1,123"],
        ],
        [4.8, 4.0, 4.0, 4.0],
        center_columns={1, 2, 3},
    )
    add_body(
        doc,
        "划分时按最大人体框面积将图片分为小于 3%、3% 至 10%、大于 10% 三档，"
        "再按最遮挡实例的可见关键点数量区分可见与遮挡组。500 张早期冒烟图被强制放入训练集，"
        "因此不会把已经参与过试训的图片重新算作独立测试样本。",
    )

    training_heading = doc.add_heading("3.3  训练参数与过程", level=2)
    training_heading.paragraph_format.page_break_before = True
    add_body(
        doc,
        "先用 5,000 张训练图、500 张验证图完成 20 轮试训，确认数据路径、标签方向、GPU 训练和验证指标均正常；"
        "随后从 yolo11n-pose.pt 预训练权重开始，使用全量数据正式训练 20 轮。",
    )
    add_table(
        doc,
        ["参数", "设置", "参数", "设置"],
        [
            ["基础模型", "YOLO11n Pose", "训练轮数", "20"],
            ["输入尺寸", "640 × 640", "Batch", "16"],
            ["设备", "GPU 0", "数据进程", "4"],
            ["优化器", "MuSGD", "AMP", "关闭"],
            ["初始学习率", "0.01", "最终学习率因子", "0.01"],
            ["动量", "0.937", "权重衰减", "0.0005"],
            ["预热", "3 epochs", "早停", "patience = 20"],
            ["随机种子", "0", "确定性训练", "开启"],
            ["Mosaic", "1.0", "水平翻转", "0.5，按 flip_idx 交换左右关键点"],
            ["平移", "0.1", "缩放", "0.5"],
        ],
        [3.0, 5.0, 3.2, 5.4],
        center_columns={1, 3},
    )
    add_body(
        doc,
        "训练输入为灰度边缘图，因此 HSV 的色相和饱和度扰动不会产生实际颜色变化；"
        "水平翻转仍是必要增强，它使用 COCO 17 点的 flip_idx 同步交换左右肩、肘、腕等关键点。",
    )

    add_figure(
        doc,
        RESULTS_IMAGE,
        16.5,
        "图 3  全量训练 20 轮的损失与评估指标曲线",
        "YOLO 全量训练结果曲线，包含 box loss、pose loss、分类损失、mAP 和学习率",
    )
    add_body(
        doc,
        "全量训练耗时 10,323.2 秒，约 2 小时 52 分钟。最佳权重大小为 6,034,888 字节，"
        "SHA256 为 7bd069d4b6940adcf46cd5e6d85d1a423b0b7d298056537a756bdc4902e85f15，"
        "与 SoulRiderDemo/models/fpga_image5_best.pt 完全一致。",
        bold_lead="全量训练耗时",
    )
    add_figure(
        doc,
        LABEL_IMAGE,
        16.4,
        "图 4  验证集真值标签（image5 边缘图与 17 点关键点）",
        "image5 验证集批量标签示例",
    )
    add_figure(
        doc,
        PRED_IMAGE,
        16.4,
        "图 5  同一批验证图的 YOLO 姿态预测结果",
        "image5 验证集批量姿态预测示例",
    )

    doc.add_heading("3.4  训练与测试指标", level=2)
    add_table(
        doc,
        ["阶段", "Box mAP50", "Box mAP50-95", "Pose mAP50", "Pose mAP50-95"],
        [
            ["5,000 张试训", "0.722", "0.441", "0.420", "0.157"],
            ["全量训练（验证集）", "0.808", "0.548", "0.588", "0.284"],
            ["全量训练（独立测试集）", "0.811", "0.555", "0.586", "0.285"],
        ],
        [5.0, 2.8, 3.2, 2.8, 3.2],
        center_columns={1, 2, 3, 4},
    )
    add_table(
        doc,
        ["最终指标", "Precision", "Recall", "mAP50", "mAP50-95"],
        [
            ["人体框", "0.837", "0.702", "0.811", "0.555"],
            ["17 点姿态", "0.761", "0.567", "0.586", "0.285"],
        ],
        [4.8, 3.0, 3.0, 3.0, 3.0],
        center_columns={1, 2, 3, 4},
    )


def add_connection_section(doc: Document) -> None:
    add_chapter_heading(doc, "4  YOLO 骨架到游戏动作的连接")
    doc.add_heading("4.1  YOLO 输出内容", level=2)
    add_body(
        doc,
        "模型对每张边缘图输出一个或多个人体实例。Demo 只选择人体框置信度最高的一个实例，"
        "保留其 bbox 置信度、边界框、17 个关键点的图像坐标和每个关键点的独立置信度。"
        "这组数据既用于动作判断，也写入状态接口供调试面板和 YOLO 骨架预览使用。",
    )
    add_table(
        doc,
        ["字段", "维度", "用途"],
        [
            ["bbox_xyxy", "4", "人体边界框，用于归一化和体型比例判断"],
            ["bbox_confidence", "1", "最高人体实例筛选与人体是否存在"],
            ["keypoints_xy", "17 × 2", "COCO 17 点图像坐标"],
            ["keypoint_confidence", "17", "过滤不可靠关节，避免用错误点硬判动作"],
            ["edges", "H × W", "检查肩肘、肘腕连线上是否有真实边缘支撑"],
        ],
        [4.1, 3.0, 9.5],
        center_columns={1},
    )

    doc.add_heading("4.2  从 17 点坐标到游戏动作", level=2)
    add_body(
        doc,
        "游戏骨架只有 15 个控制点，不能把 COCO 17 点按数组位置直接塞入，否则腕、膝和脚踝的语义会错位。"
        "当前 Demo 采用更稳健的动作抽象：利用左/右肩、肘、腕六点判断哪一侧手臂抬起，"
        "再调用游戏已有的五个模板姿势。",
    )
    add_table(
        doc,
        ["动作", "判定条件", "游戏 pose_id", "游戏表现"],
        [
            ["站立", "无人体、低置信度、手臂未抬起或动作不明确", "1", "默认站姿"],
            ["右平举", "右腕高于肩或与肩近似同高，并向右外侧伸展", "2", "右手平举攻击"],
            ["左平举", "左腕高于肩或与肩近似同高，并向左外侧伸展", "3", "左手平举攻击"],
            ["右上举", "右腕高于右肩至少 6% 人体框高", "4", "右手上举攻击"],
            ["左上举", "左腕高于左肩至少 6% 人体框高", "5", "左手上举攻击"],
        ],
        [2.5, 8.4, 2.5, 4.1],
        center_columns={0, 2},
    )
    add_body(
        doc,
        "关键点必须同时满足最低置信度和手臂边缘支撑。平举允许手腕与肩的高度差在人体框高的 25% 内，"
        "并要求手腕在水平方向上有足够横向位移。只要单侧手臂满足条件，就触发该侧动作；"
        "两侧都可靠抬起、方向不明或证据不足时保持站立，不硬凑动作。",
    )

    doc.add_heading("4.3  状态接口与动作去重", level=2)
    add_body(
        doc,
        "Python 桥接服务在本机 8765 端口提供 HTTP 接口。游戏每 33 ms 请求 /state，"
        "动作数据以单调递增的 action_seq 标识。前端只有在 action_seq 变大时才执行一次动作，"
        "所以同一张图片显示约 1 秒期间不会重复触发攻击。",
    )
    add_code_block(
        doc,
        '{\n'
        '  "action": "right",\n'
        '  "pose_id": 2,\n'
        '  "action_seq": 7,\n'
        '  "bbox_confidence": 0.899,\n'
        '  "keypoints_xy": [[x0, y0], "... 共 17 点"],\n'
        '  "keypoint_confidence": [c0, "..."],\n'
        '  "frame_seq": 7\n'
        '}'
    )
    add_body(
        doc,
        "游戏收到 left、right、left_overhead 或 right_overhead 后调用 playerAttack，"
        "设置 420 ms 的攻击姿势保持时间，再通过 setSkelPose 调整 15 点骨架。"
        "若 action 为 stand，则回到姿势 1。",
    )
    add_figure(
        doc,
        GAME_IMAGE,
        16.2,
        "图 6  YOLO 识别为“右平举”后，游戏骑士执行右手攻击",
        "Soul Rider 游戏截图，右上角显示 YOLO 输入预览，左侧 HUD 显示右平举动作",
    )


def add_game_section(doc: Document) -> None:
    doc.add_heading("5  游戏部分简要说明", level=1)
    add_body(
        doc,
        "游戏沿用原 Soul Rider 的主菜单、场景、怪物和攻击机制。进入场景后自动开始图片识别，"
        "Esc 返回主菜单后自动暂停。左上 HUD 显示当前图片序号、动作名称和姿势，右上小窗显示当前 "
        "YOLO 骨架结果，便于同时检查输入与动作是否一致。",
    )
    add_bullet(doc, "游戏入口：http://127.0.0.1:8765/game/")
    add_bullet(doc, "控制面板：http://127.0.0.1:8765/panel")
    add_bullet(doc, "输入目录可在控制面板中修改，并同步写入 config.json")
    add_body(
        doc,
        "游戏本体的玩法不在本手册展开。验证关注点是：动作是否由模型结果触发，"
        "左右方向是否正确，以及同一图片是否会重复攻击。",
    )


def add_validation_section(doc: Document) -> None:
    doc.add_heading("6  验证结果与延迟", level=1)
    doc.add_heading("6.1  动作回归", level=2)
    add_body(
        doc,
        "使用 pic 目录中的 12 张图片回归，7 张明确单臂动作成功触发：左平举 2 张、右平举 1 张、"
        "左上举 2 张、右上举 2 张。5 张保持站立，包括双臂上举、双臂平举以及无可靠姿势的图片。"
        "浏览器实测 HUD 能显示“右平举”，骑士同步抬臂，页面无 JavaScript 错误。",
    )
    add_table(
        doc,
        ["检查项", "结果", "判定"],
        [
            ["图片扫描与循环", "12 张按序读取", "通过"],
            ["image5 边缘转换", "每张都重新生成边缘图", "通过"],
            ["人体框与 17 点输出", "最高置信度实例稳定输出", "通过"],
            ["单侧左右动作", "7 张正确触发", "通过"],
            ["双臂和无效姿势", "5 张保持站立", "通过"],
            ["同图重复攻击", "action_seq 去重", "通过"],
            ["游戏进入/退出联动", "自动开始、Esc 自动暂停", "通过"],
        ],
        [4.5, 8.2, 3.9],
        center_columns={2},
    )

    doc.add_heading("6.2  端到端延迟", level=2)
    add_body(
        doc,
        "在 RTX 5060 Laptop GPU 上对 12 张 1280×960 图片测量稳定状态耗时。"
        "后端平均约 384 ms，网页轮询和渲染叠加后，从开始处理图片到游戏开始执行动作约 420～450 ms。",
    )
    add_table(
        doc,
        ["环节", "平均耗时", "占比或说明"],
        [
            ["图片读取与 RGB 转换", "8 ms", "磁盘图片解码"],
            ["FPGA image5 边缘转换", "343 ms", "当前主要瓶颈"],
            ["YOLO Pose GPU 推理", "19 ms", "RTX 5060 Laptop GPU"],
            ["动作分类", "2.5 ms", "肩肘腕几何与边缘支撑"],
            ["预览绘制和写盘", "12 ms", "三张调试图写入 outputs/live"],
            ["网页轮询", "0～33 ms", "每 33 ms 请求一次 /state"],
            ["浏览器绘制", "约 0～17 ms", "下一绘制帧执行动作"],
        ],
        [5.3, 3.0, 8.2],
        center_columns={1},
    )
    add_body(
        doc,
        "首次推理包含 CUDA 内核初始化，实测首帧后端约 1.96 秒。模型完成预热后进入上述稳定速度。"
        "骨架采用每帧 24% 的缓动，动作从触发到视觉上明显抬臂还需约 100～150 ms。",
    )


def add_operations_section(doc: Document) -> None:
    doc.add_heading("7  运行方法与维护要点", level=1)
    doc.add_heading("7.1  启动", level=2)
    add_code_block(
        doc,
        'cd "C:\\Users\\Administrator\\Desktop\\EfinityFPGAfour(1)\\edge_picture\\SoulRiderDemo"\n'
        '.\\run_demo.ps1'
    )
    add_body(
        doc,
        "浏览器打开游戏后进入场景即开始自动识别。输入目录可在面板中改为其他绝对路径；"
        "保存后 config.json 会同步更新。",
    )

    doc.add_heading("7.2  文件与临时数据", level=2)
    add_table(
        doc,
        ["路径", "用途", "维护建议"],
        [
            ["bridge.py", "HTTP 服务、目录循环和开始/停止控制", "保留"],
            ["pose_engine.py", "image5 转换、YOLO 推理、动作分类", "保留"],
            ["models/fpga_image5_best.pt", "最终姿态权重", "按 SHA256 校验"],
            ["game/", "复制后的 Soul Rider 游戏", "保留，不改原工程"],
            ["outputs/live/", "当前原图、边缘图和骨架预览", "可定期清理"],
            ["outputs/history.csv", "最近识别历史", "可定期清理"],
        ],
        [5.4, 7.8, 3.6],
    )
    add_body(
        doc,
        "训练素材和完整训练记录位于 D:\\EfinityModels\\MODEL_FULL。Demo 目录只放推理所需的最终权重，"
        "因此可以单独复制到另一台装有 Python、Ultralytics 和 CUDA 的电脑运行。",
    )

    doc.add_heading("7.3  已知限制与优化方向", level=2)
    add_bullet(
        doc,
        "image5 转换占后端耗时约 89%。静态图片 Demo 可预生成并缓存边缘图，运行时直接读取，预计把端到端延迟降到约 100 ms。",
        bold_lead="主要性能瓶颈：",
    )
    add_bullet(
        doc,
        "当前动作是五类模板，不直接复现 17 点细节。若后续要表现更细的手臂角度，需要设计 17 点与游戏 15 点的坐标映射、尺度归一化和异常点抑制。",
        bold_lead="动作粒度：",
    )
    add_bullet(
        doc,
        "COCO 数据与 FPGA 实拍仍可能存在线宽、噪声和曝光差异。正式部署前应增加 FPGA 实拍图片集，并单独评估漏检、左右混淆和遮挡场景。",
        bold_lead="域差异：",
    )
    add_bullet(
        doc,
        "当前已将 state、关键点坐标和置信度分开输出，可继续接入平滑、阈值迟滞和短暂丢帧保持，减少视频输入下的动作抖动。",
        bold_lead="视频化：",
    )

    doc.add_heading("7.4  验收结论", level=2)
    add_body(
        doc,
        "图片输入、image5 风格一致性、YOLO 姿态推理、动作分类、HTTP 传输和游戏骨架执行均已跑通。"
        "最终模型在独立测试集上的 Pose mAP50 为 0.586，满足验证性 Demo 的动作映射要求；"
        "后续工作需要围绕真实 FPGA 图片采集、动作平滑和边缘转换性能展开。",
    )


def build_document() -> None:
    doc = Document()
    configure_document(doc)
    props = doc.core_properties
    props.title = "YOLO 边缘姿态识别与游戏联动验证报告手册"
    props.subject = "FPGA image5 边缘输入、YOLO Pose 训练与 Soul Rider 动作连接"
    props.author = "EfinityFPGAfour 项目组"
    props.keywords = "YOLO Pose, FPGA, image5, Soul Rider, 姿态识别, 游戏联动"
    props.comments = "根据 SoulRiderDemo 与 MODEL_FULL 的实际实现和验证结果生成。"

    add_cover(doc)
    add_contents(doc)
    add_project_overview(doc)
    add_input_section(doc)
    add_training_section(doc)
    add_connection_section(doc)
    add_game_section(doc)
    add_validation_section(doc)
    add_operations_section(doc)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build_document()
