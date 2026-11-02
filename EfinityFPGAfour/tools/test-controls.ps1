param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/controls'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-VivadoTool([string]$name,[string[]]$toolArguments) {
    $quotedArguments=($toolArguments | ForEach-Object { '"'+$_+'"' }) -join ' '
    & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quotedArguments)
    if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Test-Snapshot([string]$top,[string]$snapshot) {
    Invoke-VivadoTool 'xelab' @($top,'-s',$snapshot)
    Invoke-VivadoTool 'xsim' @($snapshot,'-runall','-log',"$snapshot.log")
    if(!(Select-String -LiteralPath "$snapshot.log" -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath "$snapshot.log" -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)) {throw "Regression failed: $simDirectory/$snapshot.log"}
}
$sourceFiles=@(
 'src/vision/uart_vision_ctrl.v',
 'src/vision/uart_vision_ctrl_tb.v',
 'src/vision/uart_canny_only_tb.v',
 'src/vision/vision_only_uart_tb.v',
 'src/vision/uart_photo_only_tb.v',
 'src/vision/uart_image3_baseline_tb.v',
 'src/vision/video_diagnostic_mux.v',
 'src/vision/video_diagnostic_mux_tb.v',
 'src/vision/gray_edge_split.v',
 'src/vision/gray_edge_split_tb.v',
 'src/storage/photo_async_fifo.v',
 'src/storage/gallery_word_fifo.v',
 'src/axi/axi4_ctrl.v',
 'src/axi/axi4_ctrl_freeze_tb.v'
) | ForEach-Object {Join-Path $projectRoot $_}
Push-Location $simDirectory
try {
    Invoke-VivadoTool 'xvlog' (@('-sv')+$sourceFiles)
    Test-Snapshot 'uart_vision_ctrl_tb' 'uart_controls'
    Test-Snapshot 'uart_canny_only_tb' 'uart_canny_only'
    Test-Snapshot 'vision_only_uart_tb' 'vision_only_uart'
    Test-Snapshot 'uart_photo_only_tb' 'uart_photo_only'
    Test-Snapshot 'uart_image3_baseline_tb' 'uart_image3_baseline'
    Test-Snapshot 'gray_edge_split_tb' 'gray_edge_split'
    Invoke-VivadoTool 'xelab' @('gray_edge_split_tb','-generic_top','FULL_HD=1','-s','gray_edge_split_full_hd')
    Invoke-VivadoTool 'xsim' @('gray_edge_split_full_hd','-runall','-log','gray_edge_split_full_hd.log')
    if(!(Select-String -LiteralPath 'gray_edge_split_full_hd.log' -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath 'gray_edge_split_full_hd.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)) {throw 'Full-HD split regression failed'}
    Test-Snapshot 'video_diagnostic_mux_tb' 'video_diagnostic_mux'
    Invoke-VivadoTool 'xelab' @('video_diagnostic_mux_tb','-generic_top','FULL_HD=1','-s','video_diagnostic_full_hd')
    Invoke-VivadoTool 'xsim' @('video_diagnostic_full_hd','-runall','-log','video_diagnostic_full_hd.log')
    if(!(Select-String -LiteralPath 'video_diagnostic_full_hd.log' -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath 'video_diagnostic_full_hd.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)) {throw 'Full-HD diagnostic regression failed'}
    Test-Snapshot 'axi4_ctrl_freeze_tb' 'axi_freeze'
    Write-Host 'PASS all remaining UART and freeze controls'
} finally {Pop-Location}
