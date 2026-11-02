"""Qualify image5's actual mapped asynchronous transport and image path."""
from pathlib import Path
import re,json
image=Path(__file__).resolve().parents[1]/'images/image5_canny'
h=(image/'outflow/Ti60_Image5_Canny-hierarchical_stats.rpt').read_text()
for block in ['u_ft_link','u_snapshot','u_capture_fifo','u_packet','u_pack','u_tx','u_ft_uart','u_image5_pipeline','u_photo_axi_mux','u_mcp3202_spi','u_adc_input_ctrl','u_adc_uart_reporter','u_key_uart_reporter']:
    assert re.search(r'\+(?:[\w]+\.)?'+block+r'\s+\|',h),f'Missing mapped block {block}'
for absent in ['u_adc_threshold_ctrl','u_person_roi','u_person_pose','g_photo_tf.u_photo_native','u_tf_gallery','ft245_sync_tx']:
    assert absent not in h,absent
row=next(line for line in h.splitlines() if '+image5_top' in line)
cells=row.split('|');xlr=float(re.search(r'[\d.]+',cells[2])[0]);ram=int(re.search(r'\d+',cells[3])[0]);dsp=int(re.search(r'\d+',cells[4])[0])
assert ram<=256 and xlr<=60800 and dsp<=160
s=(image/'outflow/Ti60_Image5_Canny.map.v').read_text()
assert 'u_platform/u_ft_link/u_tx/txe_meta~FF' in s and 'u_platform/u_ft_link/u_tx/txe_sync~FF' in s
assert not re.search(r'(?m)^\s*input.*ft_clk',s)
for pin,level in [('cs_oled',1),('oled_dc',0),('sd_clk',0),('sd_cmd_oe',0)]+[(f'sd_dat_oe[{i}]',0) for i in range(4)]:
    assert re.search(r'assign\s+'+re.escape(pin)+r'\s*=\s*1\x27b'+str(level),s),f'Inactive pin driver {pin}'
for name in ['g_adc.u_mcp3202_spi/miso_meta','g_adc.u_mcp3202_spi/miso_sync',
             'g_key_uart.u_key_uart_reporter/key_meta','g_key_uart.u_key_uart_reporter/key_sync']:
    assert 'u_platform/'+name+'~FF' in s,f'Missing input synchronizer {name}'
w=(image/'outflow/Ti60_Image5_Canny.warn.log').read_text()
w=w[w.rfind('// Efinity Synthesis Started'):]
for line in w.splitlines():
    if re.search(r"net 'i_dqs_n_(?:hi|lo)\[\d+\]'",line): continue
    if 'does not have a driver' in line or 'non-driven net' in line:
        if re.search(r'(src[\\/](ft232h|vision|storage|photo|adc|uart)|image5_platform|image5_canny[\\/](uart_vision|image5_adc))',line):
            raise AssertionError('Undriven application signal: '+line)
report=dict(xlr=xlr,ram10=ram,dsp=dsp)
(image/'outflow/image5_resources.json').write_text(json.dumps(report,indent=2))
print('PASS mapped image5 Canny + async DDR transport + ADC/key, no knob threshold path or OLED/SD:',report)
