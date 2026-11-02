"""Check actual EFX_RAM10 INIT bits/ports before accepting an init-only ROM warning.

Efinity's local efx_ram10.v model defines mem[256*n+i]=INIT_n[i] and
rdata[i]=mem[addr*READ_WIDTH+i]. We verify all 4096x10 bits and five read ports.
"""
import argparse
import re
from pathlib import Path


def check(mapped, source):
    words = re.findall(r"template_rom\[(\d+)\]\s*=\s*10'h([0-9a-fA-F]+);", source)
    assert [int(a) for a, _ in words] == list(range(4096)), "Incomplete source ROM"
    expected = [int(value, 16) for _, value in words]
    actual, covered = [0] * 4096, set()
    blocks = list(re.finditer(r"EFX_RAM10\s+\\(\S*?/g_pose_match\.u_matcher/template_rom\S*)\s+\((.*?)/\*", mapped, re.S))
    assert len(blocks) == 5, f"Expected five mapped pose ROM RAM10s, got {len(blocks)}"
    for block in blocks:
        name, ports = block[1], block[2]
        prefix = re.escape(name.split("/template_rom", 1)[0])
        assert re.search(r"\.RADDR\(\{\\" + prefix + r"/index\s*\}\)", ports), "ROM address not matcher index"
        connection = re.search(r"\.RDATA\(\{\\" + prefix + r"/reference\s*\[(\d+):(\d+)\]\}\)", ports)
        assert connection, "ROM output not matcher reference"
        high, low = map(int, connection.groups())
        assert high == low + 1 and not ({high, low} & covered), "Overlapping ROM outputs"
        covered.update((high, low))
        for pin, value in {"RCLK": "clk_pixel_2x", "RE": "1'b1", "RST": "1'b0", "RADDREN": "1'b1",
                           "WCLK": "1'b0", "WCLKE": "1'b0", "WE": "{2'b00}"}.items():
            assert f".{pin}({value})" in ports, f"Unexpected ROM {pin}"
        params = dict(re.findall(r"defparam\s+\\" + re.escape(name) + r"\s+\.([A-Za-z0-9_]+)\s*=\s*([^;]+);", mapped))
        assert params.get("READ_WIDTH") == "2" and params.get("WRITE_WIDTH") == "2", "ROM width changed"
        assert params.get("OUTPUT_REG") == "1'b0", "ROM latency changed"
        bits = 0
        for n in range(40):
            value = params.get(f"INIT_{n:X}", "")
            assert re.fullmatch(r"256'h[0-9a-fA-F]{64}", value), "Missing/unknown ROM INIT"
            bits |= int(value[5:], 16) << (256*n)
        for address in range(4096):
            actual[address] |= ((bits >> (address*2)) & 3) << low
    assert covered == set(range(10)), "ROM bits missing"
    assert actual == expected, "Mapped pose ROM INIT differs from source templates"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("map_path", type=Path)
    parser.add_argument("--negative-controls", action="store_true")
    args = parser.parse_args()
    mapped = args.map_path.read_text()
    source = (Path(__file__).resolve().parent.parent / "src/vision/pose_templates.vh").read_text()
    check(mapped, source)
    print("PASS mapped pose ROM: all 40960 INIT bits, index/output ports, read clock/latency and disabled writes verified")
    if args.negative_controls:
        # Mutate an effective INIT defparam, not just a comment attribute.
        pattern = r"(defparam\s+\\\S*template_rom\S*\s+\.INIT_0\s*=\s*256'h)([0-9A-Fa-f]{64})"
        corrupt, count = re.subn(pattern, lambda m: m[1]+f"{int(m[2],16)^1:064x}", mapped, count=1)
        assert count == 1
        for description, bad in [("corrupt INIT bit", corrupt),
                                 ("missing ROM", re.sub(r"EFX_RAM10(\s+\\\S*template_rom)", r"REMOVED\1", mapped, count=1))]:
            try:
                check(bad, source)
            except AssertionError:
                print(f"PASS rejects {description}")
            else:
                raise AssertionError(f"Accepted {description}")


if __name__ == "__main__":
    main()
