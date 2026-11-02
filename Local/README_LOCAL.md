# Local Source Version

This version runs directly from Python. Install Python 3.10 or newer, then
install dependencies:

```powershell
cd .\FPGA_GAME
py -3 -m pip install -r .\requirements.txt
```

If `py` is not available, use the actual `python.exe` installed by Python
instead. The Microsoft Store `python.exe` shortcut is not a working interpreter
and is rejected by the launcher.

The launcher waits for `http://127.0.0.1:8765/state` to become available before
opening the game page.

Start with:

```text
START_SOULRIDER_LOCAL.cmd
```

Or run manually:

```powershell
py -3 .\bridge.py --no-browser --detection-mode eleven_point
```

Open the game at `http://127.0.0.1:8765/game/` and the diagnostic page at
`http://127.0.0.1:8765/game/debug.html`.

## Tests

```powershell
py -3 -m unittest discover -s .\tests -v
```

## Retraining

```powershell
python .\train_pose_model.py --data-root ..\TrainingData\11点骨架训练数据
```

The final configuration disables the left/right arm model and keeps only the
human-presence model gate.

