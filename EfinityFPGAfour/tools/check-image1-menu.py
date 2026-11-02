"""Verify that the image1 menu is isolated, wired to the real control path,
and that the overlay keeps one fixed sync phase."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
top = (root / 'example_top.v').read_text(encoding='utf-8-sig')
wrapper = (root / 'images/image1_vision/image1_top.v').read_text(encoding='utf-8-sig')
uart = (root / 'src/vision/uart_vision_ctrl.v').read_text(encoding='utf-8-sig')
adc = (root / 'src/adc/adc_threshold_ctrl.v').read_text(encoding='utf-8-sig')
render = (root / 'src/ui/menu_text_render.v').read_text(encoding='utf-8-sig')
ctrl = (root / 'src/ui/menu_ctrl.v').read_text(encoding='utf-8-sig')

# 1. Only image1 turns the menu hardware on.
assert re.search(r"\.MENU_BUILD\(1'b1\)", wrapper), 'image1 menu gate disabled'
assert re.search(r"parameter\s+MENU_BUILD\s*=\s*1'b0", top), 'other profiles must keep MENU_BUILD=0'
# Image1 defaults requested for the final profile; image2 keeps its old values.
for pattern, label in (
    (r"DEFAULT_EDGE_THRESHOLD\s*=\s*PHOTO_TF_BUILD\?11'd60:11'd25", 'Canny H default'),
    (r"DEFAULT_CANNY_LOW_THRESHOLD\s*=\s*PHOTO_TF_BUILD\?11'd30:11'd8", 'Canny L default'),
    (r"DEFAULT_WB_RED_GAIN\s*=\s*PHOTO_TF_BUILD\?11'd335:11'd496", 'WB R default'),
    (r"DEFAULT_WB_GREEN_GAIN\s*=\s*PHOTO_TF_BUILD\?11'd248:11'd416", 'WB G default'),
    (r"DEFAULT_WB_BLUE_GAIN\s*=\s*PHOTO_TF_BUILD\?11'd280:11'd313", 'WB B default'),
    (r"DEFAULT_GAMMA_STRENGTH\s*=\s*PHOTO_TF_BUILD\?9'd42:9'd255", 'Gamma strength default'),
):
    assert re.search(pattern, top), f'{label} mismatch'
for other in (root / 'images').glob('*/*_top.v'):
    if other.parent.name == 'image1_vision':
        continue
    text = other.read_text(encoding='utf-8-sig', errors='ignore')
    assert not re.search(r"\.MENU_BUILD\(1'b1\)", text), f'{other} unexpectedly enables the menu'

# 2. The controller runs in the ADC clock domain and owns no video timing.
assert re.search(r'generate if \(MENU_BUILD\) begin : g_menu', top), 'menu generate block missing'
assert 'u_menu_ctrl' in top and 'key_press_debounce' in top, 'menu controller/debouncer missing'
assert re.search(r"\.KNOB_DIRECT\(MENU_BUILD \? 1'b0 : 1'b1\)", top), \
    'image1 must disable the direct knob threshold path'
assert re.search(r'parameter\s+KNOB_DIRECT\s*=\s*1', adc), 'KNOB_DIRECT parameter missing'
assert re.search(r'KNOB_DIRECT\s*&&\s*knob_ready', adc), 'knob branch is not gated by KNOB_DIRECT'
assert '.key_n(key)' in top, 'KEY1 (P4-37) not connected to the menu debouncer'
# knob_ready is a level in this platform; the menu must consume the one-cycle
# averaged-sample pulse instead, or the settle window would last 8 clocks.
adc_input = (root / 'src/adc/adc_input_ctrl.v').read_text(encoding='utf-8-sig')
assert re.search(r'output reg knob_sample', adc_input), 'adc_input_ctrl has no sample pulse'
assert re.search(r'knob_sample\s*<=\s*1', adc_input) and re.search(r'knob_sample\s*<=\s*0', adc_input), \
    'knob_sample is not a one-cycle pulse'
assert top.count('.knob_sample(knob_sample)') >= 2, 'knob_sample is not connected to the menu'

# 3. Menu writes enter the same register set as the serial commands.
for port in ('menu_write_valid', 'menu_write_addr', 'menu_write_value'):
    assert re.search(r'\.' + port + r'\(w_' + port + r'\)', top), f'{port} not wired'
    assert re.search(r'input\s+[^;]*' + port, uart), f'uart_vision_ctrl missing {port}'
for item in ('VIEW', 'SPLIT', 'SHAPE', 'FREEZE', 'TEST', 'CANNY', 'CANNY_H', 'CANNY_L',
             'CANNY_RST', 'MEDIAN', 'WB_R', 'WB_G', 'WB_B', 'WB_RST', 'GAMMA', 'GAMMA_P',
             'BLACK'):
    assert '`MENU_ITEM_' + item + ':' in uart, f'uart_vision_ctrl missing menu write {item}'
assert 'threshold_update        <= 1' in uart or 'threshold_update <= 1' in uart, \
    'menu threshold writes do not retrigger adc_threshold_ctrl'

# 4. The overlay is the last stage before TMDS and is a fixed three-clock path.
assert top.index('u_video_diagnostic_mux') < top.index('u_menu_text_render') < top.index('u_rgb2dvi'), \
    'overlay must sit between the diagnostic mux and rgb2dvi'
for port in ('vid_pVSync', 'vid_pHSync', 'vid_pVDE', 'vid_pData'):
    assert re.search(r'\.' + port + r'\s*\(w_ui_', top), f'rgb2dvi still bypasses the overlay ({port})'
for signal in ('r_menu_disp_meta', 'r_menu_disp_sync', 'r_menu_disp_active'):
    assert signal in top, f'missing display CDC register {signal}'
assert re.search(r'if\s*\(!w_hdmi_vsync\)\s*\n\s*r_menu_disp_active\s*<=', top), \
    'menu state must only commit in vertical blanking'

# 5. Three identical register stages carry VS, HS, DE and RGB.
for stage in (r's0_region\s*<=\s*in_region', r's1_region\s*<=\s*s0_region',
              r'out_rgb\s*<=\s*s1_region', r'out_vsync\s*<=\s*s1_vs',
              r's0_rgb\s*<=\s*in_rgb', r's1_rgb\s*<=\s*s0_rgb'):
    assert re.search(stage, render), f'overlay pipeline missing: {stage}'
assert re.search(r'font_bits\[3\'d7\s*-\s*font_col\]', render), '3x font pixel selection changed'
assert re.search(r'function\s+\[2:0\]\s+scale3', render), '3x glyph scaler missing'
assert re.search(r'CELL_W\s*=\s*18', render) and re.search(r'CELL_H\s*=\s*24', render), \
    'menu must use the enlarged 18x24 cell'

# 6. Controller behaviour required by the agreed interaction.
for feature in ('key1_long', 'key1_short', 'item_type', 'cursor_forward', 'cursor_backward',
                'KNOB_SCROLL_STEP', 'edit_value', '`MENU_STATE_EDIT', 'input knob_sample'):
    assert feature in ctrl, f'menu controller missing {feature}'
assert re.search(r'KNOB_DEADBAND\s*=\s*16', ctrl), 'knob edit deadband missing'
assert re.search(r'edit_settle', ctrl), 'EDIT settle window missing'
assert re.search(r'knob_delta\s*>=\s*KNOB_DEADBAND', ctrl), 'EDIT path does not apply the deadband'
assert re.search(r'KEY2 is the "up" key', ctrl), 'KEY2/KEY3 minimum-step comment missing'
assert re.search(r'cursor_forward\(cursor, 5\'d1\)', ctrl), 'KEY3 navigation missing'
assert re.search(r'cursor_backward\(cursor, 5\'d1\)', ctrl), 'KEY2 navigation missing'

# 7. The font and static text ROM are generated and present.
for generated in ('src/ui/menu_font_8x8.v', 'src/ui/menu_text_rom.v'):
    assert (root / generated).stat().st_size > 1000, f'{generated} missing or empty'
assert (root / 'tools/generate-menu-font.py').exists(), 'font generator missing'

# 8. The display record layout is self-consistent.
defs = (root / 'src/ui/menu_defs.vh').read_text(encoding='utf-8-sig')
width = int(re.search(r'`define\s+MENU_DISP_WIDTH\s+(\d+)', defs).group(1))
last = re.search(r'`define\s+MD_BOOT_STATUS_OFF\s+(\d+)', defs)
assert last and int(last.group(1)) + 4 == width, 'display record width does not match fields'
assert re.search(r'`define\s+MENU_ITEM_COUNT\s+19', defs), 'menu must have 19 selectable items including BOOT/LOAD'

# 9. The build graph actually includes the new modules.
for inc in ('key_press_debounce.v', 'menu_font_8x8.v', 'menu_text_rom.v',
            'menu_ctrl.v', 'menu_text_render.v'):
    assert f'`include "src/ui/{inc}"' in top, f'example_top does not include {inc}'

# 10. image1 removes the direct knob->Canny path; the menu is the only knob path.
assert 'knob_enable' in adc and 'KNOB_DIRECT' in adc, \
    'adc_threshold_ctrl lost the direct-knob gate'

print('PASS image1 menu isolation, control writes, three-clock overlay, CDC and build graph')
