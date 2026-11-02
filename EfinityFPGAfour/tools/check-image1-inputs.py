"""Validate image1's actual P4 pads, levels and enabled ADC/menu path."""
from pathlib import Path
import json
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "images/image1_vision"
manifest = json.loads((PROFILE / "p4-inputs.json").read_text(encoding="utf-8"))
tree = ET.parse(PROFILE / "Ti60_Image1_Vision.peri.xml")
gpio = {e.get("name"): e for e in tree.iter() if e.tag.endswith("comp_gpio")}
assert len(manifest["signals"]) == 13
used = [e.get("gpio_def") for e in gpio.values()]
assert len(used) == len(set(used)), "GPIO resource assigned more than once"
for signal in manifest["signals"]:
    name = signal["signal"]
    actual = gpio[name]
    assert signal["connector"] == "P4"
    expected = (signal["resource"], signal["direction_from_fpga"], "1.8 V LVCMOS")
    assert tuple(actual.get(k) for k in ("gpio_def", "mode", "io_standard")) == expected, name
    if name in ("key", "spi_miso"):
        config = next(e for e in actual if e.tag.endswith("input_config"))
        assert config.get("is_register") == "false", name
        assert config.get("pull_option") == "none", name

top = (ROOT / "example_top.v").read_text(encoding="utf-8-sig")
wrapper = (PROFILE / "image1_top.v").read_text(encoding="utf-8-sig")
for setting in (".ENABLE_ADC(1'b1)", ".ENABLE_KEY_UART(1'b1)", ".MENU_BUILD(1'b1)"):
    assert setting in wrapper, setting
assert ".ENABLE_PHOTO_TF(1'b0)" in wrapper
assert ".key_n(key)" in top and ".spi_miso(spi_miso)" in top
assert ".knob_sample(knob_sample)" in top
for pattern in (r"assign\s+cs_oled\s*=\s*1'b1", r"assign\s+sd_clk\s*=\s*1'b0",
                r"assign\s+sd_cmd_oe\s*=\s*1'b0", r"assign\s+sd_dat_oe\s*=\s*4'h0"):
    assert re.search(pattern, top), pattern
adc = (ROOT / "src/adc/mcp3202_spi.v").read_text()
assert "miso_meta <= spi_miso" in adc and "miso_sync <= miso_meta" in adc

if "--reports" in sys.argv:
    report = (PROFILE / "outflow/Ti60_Image1_Vision.pt.rpt").read_text(encoding="utf-8-sig")
    rows = [[cell.strip() for cell in line.split("|")[1:-1]] for line in report.splitlines() if line.startswith("|")]
    for signal in manifest["signals"]:
        assert any(len(cells) >= 9 and cells[0] == signal["signal"] and
                   cells[1] == signal["resource"] and cells[2] == signal["direction_from_fpga"] and
                   cells[-1] == signal["ball"] and "1.8 V LVCMOS" in cells
                   for cells in rows), "Generated pin/ball mismatch: " + signal["signal"]
    mapped = (PROFILE / "outflow/Ti60_Image1_Vision.map.v").read_text(encoding="utf-8-sig")
    assert "u_mcp3202_spi/miso_meta" in mapped and "u_mcp3202_spi/miso_sync" in mapped
    assert "u_key1_debounce" in mapped, "Menu GPIO debounce removed"
    assert "u_menu_ctrl" in mapped, "Menu control removed"
    print("PASS mapped image1 MISO synchronizer, menu GPIO debounce and controller")
print("PASS image1 final P4: 13 unique 1.8V GPIOs; MCP3202, resistor keys and menu enabled")
