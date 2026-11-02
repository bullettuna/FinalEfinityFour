param(
    [string]$VivadoRoot = 'F:\vivado\Vivado\2024.2',
    [switch]$GalleryOnly,
    [switch]$DeleteOnly,
    [switch]$ProcessedVideoOnly,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$SimulationName = 'sd4_init'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$simDirectory = Join-Path $projectRoot "work_sim/$SimulationName"
if (!(Test-Path (Join-Path $VivadoRoot 'settings64.bat'))) {
    throw "Vivado settings64.bat not found in $VivadoRoot"
}
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null

function Invoke-VivadoTool([string]$toolName, [string[]]$toolArguments) {
    $quotedArguments = ($toolArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $command = 'call "' + $VivadoRoot + '\settings64.bat" >nul && call "' +
        $VivadoRoot + '\bin\' + $toolName + '.bat" ' + $quotedArguments
    & cmd.exe /d /c $command
    if ($LASTEXITCODE -ne 0) { throw "$toolName failed with exit code $LASTEXITCODE" }
}
function Test-Snapshot([string]$top, [string]$snapshot, [string[]]$parameters) {
    $elaborateArguments = @($top, '-s', $snapshot)
    foreach ($parameter in $parameters) { $elaborateArguments += @('-generic_top', $parameter) }
    Invoke-VivadoTool 'xelab' $elaborateArguments
    $logName = "$snapshot.log"
    Invoke-VivadoTool 'xsim' @($snapshot, '-runall', '-log', $logName)
    # XSim can exit 0 after $fatal; require a PASS marker and reject errors.
    if (!(Select-String -LiteralPath $logName -Pattern '^PASS ' -Quiet) -or
        (Select-String -LiteralPath $logName -Pattern 'Fatal:|Error:|ERROR:' -Quiet)) {
        throw "Regression failed; inspect $simDirectory/$logName"
    }
}

$sourceFiles = @(
    'src/vision/grey.v',
    'src/photo/photo_capture_modes.v',
    'src/storage/photo_work_memory.v',
    'src/photo/photo_frame_process.v',
    'src/photo/photo_capture_2x_rgb565.v',
    'src/storage/photo_async_fifo.v',
    'src/storage/gallery_word_fifo.v',
    'src/storage/photo_ddr_stage.v',
    'src/storage/photo_display_stream.v',
    'src/storage/photo_ddr_dma.v',
    'src/storage/sd4_command.v',
    'src/storage/sd4_host.v',
    'src/storage/fat32_photo_writer.v',
    'src/storage/photo_event_uart.v',
    'src/storage/fat32_bmp_reader.v',
    'src/storage/photo_uart_export.v','src/storage/photo_native_pipeline.v',
    'src/storage/photo_axi_mux.v',
    'src/axi/AXI4_AWARMux.v',
    'src/axi/axi4_ctrl.v',
    'src/storage/sd4_card_model_tb.sv',
    'src/storage/photo_native_pipeline_tb.sv',
    'src/storage/photo_sd4_init_tb.sv',
    'src/storage/photo_axi_mux_tb.sv',
    'src/storage/photo_ddr_recovery_tb.sv',
    'src/storage/fat32_wait_timeout_tb.sv',
    'src/storage/photo_event_queue_tb.sv',
    'src/storage/photo_video_save_tb.sv',
    'src/storage/photo_gallery_display_tb.sv',
    'src/storage/photo_gallery_stage_tb.sv'
) | ForEach-Object { Join-Path $projectRoot $_ }
Push-Location $simDirectory
try {
    Invoke-VivadoTool 'xvlog' (@('-sv') + $sourceFiles)
    if($ProcessedVideoOnly){
        & python (Join-Path $PSScriptRoot 'photo-canny-reference.py') --output .
        if($LASTEXITCODE -ne 0){throw 'Photo reference failed'}
        Test-Snapshot 'photo_video_save_tb' 'sd4_processed_video' @('PROCESS_TESTS=1')
        return
    }
    if($DeleteOnly) {
        Test-Snapshot 'photo_video_save_tb' 'sd4_delete_full' @('GALLERY_TESTS=1','DELETE_TESTS=1')
        Write-Host 'PASS native SD4 delete integration'
        return
    }
    Test-Snapshot 'photo_gallery_display_tb' 'gallery_display' @()
    Test-Snapshot 'photo_gallery_display_tb' 'gallery_display_1080p' @('DWIDTH=1920','DHEIGHT=1080')
    Test-Snapshot 'photo_gallery_stage_tb' 'gallery_stage' @()
    if ($GalleryOnly) {
        Test-Snapshot 'photo_video_save_tb' 'sd4_gallery_full' @('GALLERY_TESTS=1')
        Write-Host 'PASS all gallery regressions'
        return
    }
    Test-Snapshot 'photo_sd4_init_tb' 'sd4_init_errors' @()
    Test-Snapshot 'sd4_poll_timeout_tb' 'sd4_poll_timeout' @()
    Invoke-VivadoTool 'xelab' @('photo_sd4_gap_negative_tb', '-s', 'sd4_gap_negative')
    Invoke-VivadoTool 'xsim' @('sd4_gap_negative', '-runall', '-log', 'sd4_gap_negative.log')
    if (!(Select-String -LiteralPath 'sd4_gap_negative.log' -Pattern 'Fatal: N_(RC|CC) gap shorter than 8 clocks' -Quiet)) {
        throw 'Card timing checker failed to reject a deliberately short command gap'
    }
    Write-Host 'PASS negative test: card model rejects a short command gap'
    Test-Snapshot 'photo_native_pipeline_tb' 'sd4_photo_sdhc' @()
    Test-Snapshot 'photo_native_pipeline_tb' 'sd4_photo_sdsc_v2' @('SDSC=1')
    Test-Snapshot 'photo_native_pipeline_tb' 'sd4_photo_sdsc_legacy' @('SDSC=1', 'LEGACY_CMD8=1')
    Test-Snapshot 'photo_axi_mux_tb' 'sd4_axi_mux' @()
    Test-Snapshot 'photo_ddr_recovery_tb' 'sd4_ddr_recovery' @()
    Test-Snapshot 'fat32_wait_timeout_tb' 'sd4_writer_timeout' @()
    Test-Snapshot 'photo_native_pipeline_tb' 'sd4_pipeline_recovery' @('FAULT_TESTS=1')
    Test-Snapshot 'photo_video_save_tb' 'sd4_video_save' @()
    Test-Snapshot 'photo_video_save_tb' 'sd4_gallery_full' @('GALLERY_TESTS=1')
    Test-Snapshot 'photo_event_queue_tb' 'sd4_event_queue' @()
    Write-Host 'PASS all SD4 initialization and photo-save regressions'
} finally {
    Pop-Location
}
