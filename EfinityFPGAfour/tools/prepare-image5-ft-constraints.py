"""Refresh registered-pad constraints without inventing an external FT clock."""
from pathlib import Path
import re,argparse
root=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--profile',default='image5_canny');a.add_argument('--project',default='Ti60_Image5_Canny');args=a.parse_args()
image=root/'images'/args.profile
s=(image/'outflow'/(args.project+'.pt.sdc')).read_text()
assert not re.search(r'(?m)^create_clock[^\n]*ft_clk',s)
assert s.count('set_output_delay -clock clk_sys')>=18
assert not re.search(r'(?m)^[^#\n]*<USER_',s)
board=(image/'board-domains.sdc').read_text()
csi='create_clock -period 6 -name csi_rxc_i [get_ports {csi_rxc_i}]'
assert board.count(csi)==1
s=csi+'\n'+s+'\n'+board.replace(csi,'')
# The raw asynchronous TXE input only feeds txe_meta; stage 2 and all state
# logic remain timed. async_reg prevents merging and guides placement.
s+='\n# Only the first TXE synchronizer D is asynchronous.\n'
s+='set_false_path -from [get_ports {ft_txe_n}] -to [get_pins {u_platform/u_ft_link/u_tx/txe_meta~FF|D}]\n'
s+='\n# ADC MISO and GPIO key enter two-stage clk_sys synchronizers.\n'
s+='set_false_path -from [get_ports {spi_miso}] -to [get_pins {u_platform/g_adc.u_mcp3202_spi/miso_meta~FF|D}]\n'
s+='set_false_path -from [get_ports {key}] -to [get_pins {u_platform/r_key_meta~FF|D}]\n'
(image/(args.project+'.pt.sdc')).write_text(s)
print('PASS async image5 SDC: actual clk_sys IO-FF boundaries, retained 6ns CSI, first-stage-only TXE exception')
