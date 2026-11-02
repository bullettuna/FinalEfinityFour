param(
    [string]$InputDir = "",
    [ValidateSet("yolo", "four_point", "eleven_point")]
    [string]$DetectionMode = "",
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'

# Every candidate is verified by actually importing the runtime dependencies.
# A bare "python" on PATH is often the Microsoft Store stub or a clean
# interpreter without opencv/ultralytics, which used to fail deep inside
# bridge.py with a confusing traceback.
$required = 'cv2, numpy, scipy, PIL, ultralytics'

$candidates = New-Object System.Collections.Generic.List[string]
if ($env:YOLO_PYTHON) { $candidates.Add($env:YOLO_PYTHON) }
$candidates.Add((Join-Path $PSScriptRoot '..\..\..\FPGA_GAME\.venv-fourpoint\Scripts\python.exe'))
$candidates.Add('D:\python\python.exe')
$candidates.Add('py -3')
$candidates.Add('python')

$Python = $null
foreach ($candidate in $candidates) {
    $exe = $candidate
    if ($candidate -eq 'py -3') {
        $exe = (Get-Command py -ErrorAction SilentlyContinue).Source
        if (-not $exe) { continue }
        $script = '-3'
    } else {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $script = $null
    }
    try {
        $probeArgs = @()
        if ($script) { $probeArgs += $script }
        $probeArgs += @('-c', "import $required")
        & $exe @probeArgs 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        $argList = @()
        if ($script) { $argList += $script }
        $argList += @('-c', 'import sys;print(sys.executable)')
        $resolved = (& $exe @argList 2>$null | Select-Object -Last 1)
        if ($resolved) { $Python = $resolved.Trim() }
        break
    } catch {
        continue
    }
}

if (-not $Python) {
    throw "No Python with $required was found. Install it with: py -3 -m pip install opencv-python ultralytics"
}

Write-Host "Using Python: $Python"

$ArgsList = @((Join-Path $PSScriptRoot 'bridge.py'), '--port', $Port)
if ($InputDir) {
    $ArgsList += @('--input-dir', $InputDir)
}
if ($DetectionMode) {
    $ArgsList += @('--detection-mode', $DetectionMode)
}
& $Python @ArgsList
exit $LASTEXITCODE
