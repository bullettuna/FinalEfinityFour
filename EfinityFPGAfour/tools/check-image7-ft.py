"""Check actual image5 pad configuration, source contracts and external budget."""
from pathlib import Path
import argparse
import json
import re
import xml.etree.ElementTree as E

root=Path(__file__).resolve().parents[1]

ns={'p':'http://www.efinixinc.com/peri_design_db'}
a=argparse.ArgumentParser();a.add_argument('--reports',action='store_true');a.add_argument('--profile',default='image7_mocap11_a');a.add_argument('--project',default='Ti60_Image7_Mocap11_A');args=a.parse_args()
image=root/'images'/args.profile
tree=E.parse(image/(args.project+'.peri.xml'))
nodes={n.get('name'):n for n in tree.findall('.//p:comp_gpio',ns)}
manifest=json.loads((image/'ft232h-hardware.json').read_text(encoding='utf-8'))
assert len(manifest['signals'])==24
assert len({p['resource'] for p in manifest['signals']})==24
for p in manifest['signals']:
    name=p['signal']
    if name.startswith('ft_d'):name=f'ft_data[{name[-1]}]'
    n=nodes.get(name)
    if not p.get("active",True):
        assert name=="ft_clk_60m" and n is None
        continue
    assert n is not None,name
    assert n.get('gpio_def')==p['resource'],name
    assert n.get('io_standard')==p['io_standard'],name
    if name.startswith('ft_data[') or name=='ft_wr_n':
        o=n.find('p:output_config',ns)
        assert o.get('register_option')=='register' and o.get('clock_name')=='clk_sys',name
        assert n.find('p:output_enable_config',ns) is not None,name
    if name=='ft_txe_n':
        i=n.find('p:input_config',ns)
        assert i.get('is_register')=='false' and not i.get('clock_name')
        assert i.get('pull_option')=='pullup'
assert nodes['ft_wr_n'].find('p:input_config',ns).get('pull_option')=='pullup'
assert not any(n.get('name')=='ft_pll' for n in tree.findall('.//p:pll',ns))
platform=(image/'image7_platform.v').read_text(encoding='utf-8')
for item in ['ft_uart_control #(.ADC_QUERY_AVAILABLE(ENABLE_ADC)) u_ft_uart',('image7_ft_link_usb' if args.profile in ['image7_usb_points','image7_four_boot'] else 'image7_ft_link_stable' if args.profile=='image7_stable_ui' else 'image7_ft_link_latest' if args.profile=='image7_latest_a' else 'image7_ft_link_fast' if args.profile=='image7_perf_a' else 'image7_ft_link')+' #(.AUTO_BOOT(1),.MENU_ENABLE(1),.MULTIBOOT_ENABLE(1)) u_ft_link','.rx_valid\t\t(w_ft_legacy_rx_valid)',
             '.gray_pixel(w_median_pixel)','.edge_pixel(w_canny_edge_pixel)']:
    assert item in platform,item
tx=(root/'src/ft232h/ft245_async_tx.v').read_text(encoding='utf-8')
for item in ['SETUP_CYCLES=10','LOW_CYCLES=10','HOLD_CYCLES=10','RECOVERY_CYCLES=10','GAP_CYCLES=96','STABLE_CYCLES=4','txe_meta<=txe_n_async;txe_sync<=txe_meta','held<=data','wr_n<=0']:
    assert item in tx,item
assert 'ft245_async_tx' in (root/'src/pose7/image7_ft_link.v').read_text(encoding='utf-8')
assert 'ft245_sync_tx' not in platform and 'ft_clk_' not in platform
assert '.resolution(w_ft_resolution)' in platform
assert platform.count('.edge_packed(w_ft_edge_packed)')==2
assert '`include "src/ft232h/ft_edge_pack.v"' in platform
assert 'kind==3?(pixels>>3)' in (root/'src/ft232h/ft_packet_source.v').read_text(encoding='utf-8')
print('PASS async FT source/pins: 23 active mappings, AC5 unused, registered clk_sys AD/WR, raw TXE + RTL synchronizer, P4 1.8V')
if not args.reports:raise SystemExit(0)
text=(image/'outflow'/(args.project+'.pt_timing.rpt')).read_text(encoding='utf-8')
def row(name,clock=None,section=None):
    part=text.split(section)[-1] if section else text
    for line in part.splitlines():
        cells=[x.strip() for x in line.split('|')[1:-1]]
        if cells and cells[0]==name and (clock is None or cells[1]==clock):return cells
    raise AssertionError(f'Missing periphery timing row {name}/{clock}')
c=row('clk_sys',section='Clock Network Delay Report (begin)')
net_max,net_min=float(c[1]),float(c[2])
outputs=[row(f'ft_data[{j}]','clk_sys') for j in range(8)]+[row('ft_wr_n','clk_sys')]
co_max=max(float(c[6]) for c in outputs);co_min=min(float(c[7]) for c in outputs)
b=json.loads((image/'ft232h-timing-budget.json').read_text(encoding='utf-8'))
period=1e9/b['clock_hz']
spread=net_max-net_min+co_max-co_min+b['data_trace_max_ns']-b['data_trace_min_ns']+b['jitter_margin_ns']
minimums={key:round(b[cycles]*period-spread,4) for key,cycles in [('setup','setup_cycles'),('low','wr_low_cycles'),('hold','hold_cycles'),('gap','min_write_gap_cycles')]}
assert minimums['setup']>=b['data_setup_min_ns'] and minimums['low']>=b['wr_low_min_ns'] and minimums['hold']>=b['data_hold_after_wr_rise_min_ns'],minimums
assert minimums['gap']>990,minimums
report=dict(transport='FT245_ASYNC_FIFO',minimum_pad_intervals_ns=minimums,assumptions=b,verified_on_board=False)
(image/'outflow/ft232h_external_budget.json').write_text(json.dumps(report,indent=2))
sdc=(image/(args.project+'.pt.sdc')).read_text(encoding='utf-8')
assert not re.search(r'(?m)^create_clock[^\n]*ft_clk',sdc)
assert 'create_clock -period 6 -name csi_rxc_i' in sdc
assert 'txe_meta~FF|D' in sdc and 'txe_sync' not in sdc
mapped=(image/'outflow'/(args.project+'.map.v')).read_text(encoding='utf-8')
assert 'u_platform/u_ft_link/u_tx/txe_meta' in mapped and 'u_platform/u_ft_link/u_tx/txe_sync' in mapped
print('PASS conditional async pad timing budget:',minimums,'ns; board trace/jitter bounds unmeasured')
