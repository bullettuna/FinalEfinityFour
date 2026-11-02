"""Refresh registered-pad constraints without inventing an external FT clock."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
image=root/'images/image6_pose_int16'
s=(image/'outflow/Ti60_Image6_Pose.pt.sdc').read_text()
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
s+='set_false_path -from [get_ports {key}] -to [get_pins {u_platform/g_key_uart.u_key_uart_reporter/key_meta~FF|D}]\n'
s+='\n# Native SD4 inputs enter only the first stage of clk_sys synchronizers.\n'
s+='set_false_path -from [get_ports {sd_cmd_i}] -to [get_pins {u_platform/u_ft_link/g_sd_boot.u_sd_boot/host/cm1~FF|D}]\n'
for lane in range(4):
    s+=f'set_false_path -from [get_ports {{sd_dat_i[{lane}]}}] -to [get_pins {{u_platform/u_ft_link/g_sd_boot.u_sd_boot/host/di1[{lane}]~FF|D}}]\n'
(image/'Ti60_Image6_Pose.pt.sdc').write_text(s)
print('PASS async image6 SDC: actual clk_sys IO-FF boundaries, retained 6ns CSI, first-stage-only TXE exception')
