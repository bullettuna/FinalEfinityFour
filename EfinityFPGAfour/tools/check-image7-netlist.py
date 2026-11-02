"""Qualify image5's actual mapped asynchronous transport and image path."""
from pathlib import Path
import re,json
image=Path(__file__).resolve().parents[1]/'images/image7_mocap11_a'
h=(image/'outflow/Ti60_Image7_Mocap11_A-hierarchical_stats.rpt').read_text(encoding='utf-8')
for block in ['u_network','u_conv','u_mac','u_requant','u_pool','u_decode','u_loader','u_master','u_pose_axi_mux','u_ft_link','u_snapshot','u_capture_fifo','u_packet','u_pack','u_tx','u_ft_uart','u_image5_pipeline','u_photo_axi_mux','u_mcp3202_spi','u_adc_input_ctrl','u_adc_uart_reporter','u_key_uart_reporter']:
    assert re.search(r'\+(?:[\w]+\.)?'+block+r'\s+\|',h),f'Missing mapped block {block}'
for absent in ['u_adc_threshold_ctrl','u_person_roi','u_person_pose','g_photo_tf.u_photo_native','u_tf_gallery','ft245_sync_tx']:
    assert absent not in h,absent
row=next(line for line in h.splitlines() if '+image7_top' in line)
cells=row.split('|');xlr=float(re.search(r'[\d.]+',cells[2])[0]);ram=int(re.search(r'\d+',cells[3])[0]);dsp=int(re.search(r'\d+',cells[4])[0])
assert ram<=256 and xlr<=60800 and dsp<=160
s=(image/'outflow/Ti60_Image7_Mocap11_A.map.v').read_text(encoding='utf-8')
assert 'u_platform/u_ft_link/u_tx/txe_meta~FF' in s and 'u_platform/u_ft_link/u_tx/txe_sync~FF' in s
assert not re.search(r'(?m)^\s*input.*ft_clk',s)
for pin,level in [('cs_oled',1),('oled_dc',0)]:
    assert re.search(r'assign\s+'+re.escape(pin)+r'\s*=\s*1\x27b'+str(level),s),f'Inactive pin driver {pin}'
for name in ['g_adc.u_mcp3202_spi/miso_meta','g_adc.u_mcp3202_spi/miso_sync',
             'g_adc.u_key1_debounce/key_meta','g_adc.u_key1_debounce/key_sync']:
    assert 'u_platform/'+name+'~FF' in s,f'Missing input synchronizer {name}'
# Identical GPIO-key synchronizers are merged into the menu debounce chain.
# Check the surviving two physical stages, rather than requiring duplicate FFs.
w=(image/'outflow/Ti60_Image7_Mocap11_A.warn.log').read_text(encoding='utf-8')
w=w[w.rfind('// Efinity Synthesis Started'):]
for line in w.splitlines():
    if re.search(r"net 'i_dqs_n_(?:hi|lo)\[\d+\]'",line): continue
    if 'does not have a driver' in line or 'non-driven net' in line:
        if re.search(r'(src[\\/](pose7|ft232h|vision|storage|photo|adc|uart)|image7_platform|image5_canny[\\/](uart_vision|image5_adc))',line):
            raise AssertionError('Undriven application signal: '+line)
report=dict(xlr=xlr,ram10=ram,dsp=dsp)
(image/'outflow/image7_resources.json').write_text(json.dumps(report,indent=2))
for block in ['u_menu_ctrl','u_menu_cdc','u_menu_text_render','u_key1_debounce','u_sd_boot','reader','host','u_pose7_hdmi_overlay','u_debug']:
    assert re.search(r'\+(?:[\w]+\.)?'+block+r'\s+\|',h),f'Missing standalone block {block}'
print('PASS mapped image7 Canny + integer pose + native SD4 startup + async DDR transport + ADC/key:',report)
