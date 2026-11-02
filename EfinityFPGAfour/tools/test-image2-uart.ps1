param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$FullSize)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image2_uart'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Test-Snapshot([string]$top,[string]$name,[string[]]$generics){
 Run-Tool xelab (@($top,'-s',$name)+$generics)
 Run-Tool xsim @($name,'-runall','-log',"$name.log")
 if(!(Select-String "$name.log" -Pattern '^PASS ' -Quiet) -or
   (Select-String "$name.log" -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw "Failed $name"}
}
Push-Location $sim
try{
 & python (Join-Path $root 'tools/photo-canny-reference.py') --output .
 if($LASTEXITCODE -ne 0){throw 'reference failed'}
 $rtl=@('src/adc/adc_threshold_ctrl.v','src/storage/photo_uart_export.v','src/uart/uart_tx_arbiter.v','src/storage/photo_uart_export_tb.sv',
 'src/vision/grey.v','src/photo/photo_capture_modes.v','src/photo/photo_capture_2x_rgb565.v',
 'src/storage/photo_work_memory.v','src/photo/photo_frame_process.v','src/storage/photo_async_fifo.v',
 'src/storage/photo_ddr_dma.v','src/storage/sd4_command.v','src/storage/sd4_host.v',
 'src/storage/fat32_photo_writer.v','src/storage/fat32_bmp_reader.v','src/storage/photo_event_uart.v',
 'src/storage/photo_native_pipeline.v','src/storage/sd4_card_model_tb.sv','src/storage/photo_native_pipeline_tb.sv',
 'src/vision/uart_vision_ctrl.v','src/vision/uart_image2_canny_tb.sv',
 'src/vision/uart_photo_only_tb.v','src/vision/vision_only_uart_tb.v')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-sv')+$rtl)
 Test-Snapshot 'uart_image2_canny_tb' 'image2_uart_commands' @()
 Test-Snapshot 'photo_uart_export_tb' 'image2_uart_export' @()
 & python (Join-Path $root 'tools/check-image2-uart.py') .
 if($LASTEXITCODE -ne 0){throw 'packet/pixel checks failed'}
 if($FullSize){
  Test-Snapshot 'photo_uart_export_tb' 'image2_uart_960x540' @('-generic_top','WIDTH=960','-generic_top','HEIGHT=540')
  & python (Join-Path $root 'tools/check-image2-uart.py') .
  if($LASTEXITCODE -ne 0){throw 'full-size packet/pixel checks failed'}
 }
 Test-Snapshot 'photo_native_pipeline_tb' 'image2_uart_camera' @('-generic_top','PROCESS_TESTS=1','-generic_top','UART_TESTS=1')
 & python (Join-Path $root 'tools/check-image2-uart.py') . --integration
 if($LASTEXITCODE -ne 0){throw 'camera/processing integration pixels failed'}
 Test-Snapshot 'photo_native_pipeline_tb' 'image2_uart_adc_camera' @('-generic_top','PROCESS_TESTS=1','-generic_top','UART_TESTS=1','-generic_top','ADC_TESTS=1')
 & python (Join-Path $root 'tools/check-image2-uart.py') . --integration
 if($LASTEXITCODE -ne 0){throw 'ADC snapshot/processed pixel checks failed'}
 Test-Snapshot 'photo_native_pipeline_tb' 'image2_uart_tf_regression' @('-generic_top','PROCESS_TESTS=1')
 Test-Snapshot 'photo_native_pipeline_tb' 'image2_uart_tf_recovery' @('-generic_top','FAULT_TESTS=1')
 Test-Snapshot 'uart_photo_only_tb' 'image2_uart_legacy_commands' @()
 Test-Snapshot 'vision_only_uart_tb' 'image2_uart_vision_commands' @()
 Write-Host 'PASS image2 UART camera export, PC reconstruction, TF save/retry/delete and other-image command regressions'
}finally{Pop-Location}
