"""Collect torchvision native operators for the packaged bridge.

PyInstaller's torchvision hook still looks for ``_C``/``image`` while recent
torchvision wheels ship ``_C_stable``/``image_stable``. Without those binaries
torchvision imports, but every NMS call fails with
``operator torchvision::nms does not exist``.
"""
from pathlib import Path

from PyInstaller.utils.hooks import collect_dynamic_libs, get_package_paths


binaries = collect_dynamic_libs("torchvision")
_, package_dir = get_package_paths("torchvision")
for name in ("_C_stable.pyd", "image_stable.pyd"):
    path = Path(package_dir) / name
    if path.is_file():
        binaries.append((str(path), "torchvision"))

