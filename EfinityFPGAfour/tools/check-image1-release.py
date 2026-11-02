"""Verify the prebuilt image1 files and their portable source fingerprint."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
release = root / "releases/image1"
manifest = json.loads((release / "manifest.json").read_text(encoding="utf-8"))
errors = []

for name, expected in manifest["artifacts"].items():
    path = release / name
    if not path.is_file():
        errors.append(f"Missing artifact: {path}")
        continue
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != expected["bytes"] or digest != expected["sha256"]:
        errors.append(f"Artifact differs from qualified build: {path}")
    else:
        print(f"PASS {name}: {len(data)} bytes, SHA256 {digest}")

for name, expected in manifest["source_files"].items():
    path = root / name
    if not path.is_file():
        errors.append(f"Missing source/config: {name}")
        continue
    data = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").encode("utf-8")
    if name == "images/image1_vision/Ti60_Image1_Vision.xml" and manifest.get("project_xml_ignored_attributes"):
        element = ET.fromstring(data)
        for attribute in manifest["project_xml_ignored_attributes"]:
            element.attrib.pop(attribute, None)
        data = ET.tostring(element, encoding="utf-8")
    if hashlib.sha256(data).hexdigest() != expected:
        errors.append(f"Source/config differs from prebuilt image: {name}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"PASS image1 release: {len(manifest['source_files'])} source/config files match")
