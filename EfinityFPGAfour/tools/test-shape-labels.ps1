param([string]$VivadoRoot='F:\vivado\Vivado\2024.2', [switch]$FullHD)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$width=640; $height=240
if($FullHD){$width=1920; $height=1080}
$simDirectory=Join-Path $projectRoot "work_sim/shape_labels_${width}x${height}"
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
& python (Join-Path $PSScriptRoot 'shape-label-vectors.py') $simDirectory --width $width --height $height
if($LASTEXITCODE -ne 0){throw 'Oracle generation failed'}
function Invoke-VivadoTool([string]$name,[string[]]$toolArguments) {
    $quotedArguments=($toolArguments | ForEach-Object { '"'+$_+'"' }) -join ' '
    & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quotedArguments)
    if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $simDirectory
try {
    $sources=@('shape_overlay.v','shape_chinese_font.v','shape_label_overlay.v','shape_label_overlay_tb.v') |
        ForEach-Object{Join-Path $projectRoot "src/vision/$_"}
    Invoke-VivadoTool 'xvlog' $sources
    Invoke-VivadoTool 'xelab' @('shape_label_overlay_tb','-generic_top',"WIDTH=$width",'-generic_top',"HEIGHT=$height",'-s','shape_labels')
    Invoke-VivadoTool 'xsim' @('shape_labels','-runall','-log','shape_labels.log')
    if(!(Select-String -LiteralPath 'shape_labels.log' -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath 'shape_labels.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {throw 'Chinese label regression failed'}
    & python (Join-Path $PSScriptRoot 'shape-label-vectors.py') $simDirectory --preview
    if($LASTEXITCODE -ne 0){throw 'Simulation preview conversion failed'}
    Write-Host "PASS: $simDirectory/shape_labels_actual.png"
} finally {Pop-Location}
