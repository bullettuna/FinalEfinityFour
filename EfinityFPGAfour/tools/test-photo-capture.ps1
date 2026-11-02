param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/photo_capture_full_hd'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-Tool([string]$name,[string[]]$arguments) {
    $quoted=($arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
    & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
    if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $simDirectory
try {
    $rtl=@('src/vision/gamma_correction.v','src/vision/grey.v','src/photo/photo_capture_2x_rgb565.v',
           'src/storage/photo_async_fifo.v','src/storage/photo_ddr_dma.v') | ForEach-Object {Join-Path $projectRoot $_}
    Invoke-Tool 'xvlog' $rtl
    Invoke-Tool 'xvlog' @('-sv',(Join-Path $projectRoot 'src/storage/photo_capture_full_hd_tb.sv'))
    Invoke-Tool 'xelab' @('photo_capture_full_hd_tb','-s','photo_capture_full_hd')
    Invoke-Tool 'xsim' @('photo_capture_full_hd','-runall','-log','photo_capture_full_hd.log')
    if(!(Select-String -LiteralPath 'photo_capture_full_hd.log' -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath 'photo_capture_full_hd.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw 'Full-HD capture regression failed'}
} finally {Pop-Location}
