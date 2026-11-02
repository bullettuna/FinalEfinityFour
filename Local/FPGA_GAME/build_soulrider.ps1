param(
    [string]$OutputRoot = "",
    [string]$Python = "D:\python\python.exe"
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $Root "build\soulrider"
}
if (-not (Test-Path -LiteralPath $Python)) {
    throw "Python was not found: $Python"
}

$ArgsList = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--clean",
    "--onedir",
    "--console",
    "--contents-directory", ".",
    "--name", "SoulRiderBridge",
    "--distpath", (Join-Path $OutputRoot "dist"),
    "--workpath", (Join-Path $OutputRoot "build"),
    "--specpath", (Join-Path $OutputRoot "spec"),
    "--additional-hooks-dir", (Join-Path $Root "hooks"),
    "--add-data", "$(Join-Path $Root 'game');game",
    "--add-data", "$(Join-Path $Root 'models');models",
    "--add-data", "$(Join-Path $Root 'tools\fpga');tools/fpga",
    "--add-data", "$(Join-Path $Root 'panel.html');.",
    "--add-data", "$(Join-Path $Root 'config.json');.",
    "--add-data", "$(Join-Path $Root 'README.md');.",
    (Join-Path $Root "bridge.py")
)

& $Python @ArgsList
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller failed with exit code $LASTEXITCODE"
}

$Dist = Join-Path $OutputRoot "dist\SoulRiderBridge"
$Required = @(
    "torchvision\_C_stable.pyd",
    "torchvision\image_stable.pyd",
    "torchvision\jpeg8.dll",
    "torchvision\libpng16.dll",
    "torchvision\libwebp.dll",
    "torchvision\zlib.dll"
)
foreach ($Relative in $Required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dist $Relative))) {
        throw "Build is missing required torchvision runtime file: $Relative"
    }
}

Write-Host "Build ready: $Dist"
