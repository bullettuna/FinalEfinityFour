"""Guard image2's old P3 ADC pins, effective thresholds and TF UART ownership."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def check(top, wrapper, peripheral):
    assert ".ENABLE_ADC(1'b1)" in wrapper, "image2 ADC disabled"
    assert re.search(r"localparam\s+ADC_UART_REPORT\s*=\s*ENABLE_ADC\s*&&\s*!PHOTO_TF_BUILD", top), "ADC steals photo status UART"
    for field, adc, tf in (("valid", "w_adc_tx_valid", "w_uart_sd_tx_valid"),
                           ("data", "w_adc_tx_data", "w_uart_sd_tx_data"),
                           ("last", "w_adc_tx_last", "w_uart_sd_tx_last")):
        assert re.search(rf"\.msg4_tx_{field}\s*\(ADC_UART_REPORT\s*\?\s*{adc}\s*:\s*{tf}\)", top), "TF UART mux incorrect"
    assert "assign w_uart_sd_tx_accept = ADC_UART_REPORT ? 1'b0 : w_uart_aux_accept;" in top
    assert "assign w_uart_sd_tx_done = ADC_UART_REPORT ? 1'b0 : w_uart_aux_done;" in top
    pipeline = top.split(" u_photo_native_pipeline (", 1)[1].split("\n\t);", 1)[0]
    assert ".high_threshold(w_edge_threshold_effective_request)" in pipeline, "Photo ignores ADC high threshold"
    assert ".low_threshold(w_canny_low_threshold_effective_request)" in pipeline, "Photo ignores ADC low threshold"
    assert ".high_request(w_edge_threshold_effective_request)" in top, "Preview high threshold disconnected"
    assert ".low_request(w_canny_low_threshold_effective_request)" in top, "Preview low threshold disconnected"
    expected = dict(spi_sclk=("GPIOL_09", "output"), spi_mosi=("GPIOL_03", "output"),
                    spi_miso=("GPIOR_12", "input"), cs_adc=("GPIOL_06", "output"))
    gpio = {e.attrib["name"]: e.attrib for e in ET.fromstring(peripheral).iter() if e.tag.endswith("comp_gpio")}
    for signal, (pad, direction) in expected.items():
        actual = gpio[signal]
        assert (actual["gpio_def"], actual["mode"], actual["io_standard"]) == (pad, direction, "3.3 V LVCMOS"), f"Not old P3 wiring: {signal}"


if __name__ == "__main__":
    top = (ROOT / "example_top.v").read_text(encoding="utf-8")
    wrapper = (ROOT / "images/image2_photo/image2_top.v").read_text(encoding="utf-8")
    peripheral = (ROOT / "images/image2_photo/Ti60_Image2_Photo.peri.xml").read_text(encoding="utf-8")
    check(top, wrapper, peripheral)
    # Both common integration mistakes must be rejected by this guard.
    for bad in (top.replace(".high_threshold(w_edge_threshold_effective_request)", ".high_threshold(w_edge_threshold_request)"),
                top.replace("ADC_UART_REPORT = ENABLE_ADC && !PHOTO_TF_BUILD", "ADC_UART_REPORT = ENABLE_ADC")):
        try:
            check(bad, wrapper, peripheral)
        except AssertionError:
            continue
        raise AssertionError("Negative wiring case accepted")
    print("PASS image2 old P3 MCP3202, common preview/photo thresholds, TF UART ownership and negative wiring guards")
