param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$FullSize)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image2_canny'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 & python (Join-Path $root 'tools/photo-canny-reference.py') --output .
 if($LASTEXITCODE -ne 0){throw 'reference failed'}
 $rtl=@('src/storage/photo_work_memory.v','src/photo/photo_frame_process.v','src/vision/grey.v',
 'src/photo/photo_capture_modes.v','src/vision/uart_vision_ctrl.v','src/photo/photo_frame_process_tb.sv',
 'src/photo/photo_capture_modes_tb.sv','src/vision/uart_image2_canny_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-sv')+$rtl)
 foreach($top in @('photo_frame_process_tb','photo_capture_modes_tb','uart_image2_canny_tb')){
  Run-Tool xelab @($top,'-s',$top)
  Run-Tool xsim @($top,'-runall','-log',"$top.log")
  if(!(Select-String "$top.log" -Pattern '^PASS ' -Quiet) -or (Select-String "$top.log" -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw "Failed $top"}
 }
 if($FullSize){
  Run-Tool xelab @('photo_capture_modes_tb','-generic_top','WIDTH=1920','-generic_top','HEIGHT=1080','-s','capture_modes_full_hd')
  Run-Tool xsim @('capture_modes_full_hd','-runall','-log','capture_modes_full_hd.log')
  if(!(Select-String 'capture_modes_full_hd.log' -Pattern '^PASS ' -Quiet) -or (Select-String 'capture_modes_full_hd.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw 'Full-HD mode sampler failed'}
 }
 $storage=@('src/photo/photo_capture_2x_rgb565.v','src/storage/photo_async_fifo.v','src/storage/photo_ddr_dma.v',
 'src/storage/sd4_command.v','src/storage/sd4_host.v','src/storage/fat32_photo_writer.v','src/storage/fat32_bmp_reader.v',
 'src/storage/photo_event_uart.v','src/storage/photo_uart_export.v','src/storage/photo_native_pipeline.v','src/storage/sd4_card_model_tb.sv',
 'src/storage/photo_native_pipeline_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-sv')+$storage)
 Run-Tool xelab @('photo_native_pipeline_tb','-generic_top','PROCESS_TESTS=1','-s','image2_processed_save')
 Run-Tool xsim @('image2_processed_save','-runall','-log','image2_processed_save.log')
 if(!(Select-String 'image2_processed_save.log' -Pattern '^PASS ' -Quiet) -or (Select-String 'image2_processed_save.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw 'Processed TF/save integration failed'}
 Run-Tool xelab @('photo_native_pipeline_tb','-generic_top','PROCESS_TESTS=1','-generic_top','AUTO_OPEN_RACE=1','-s','image2_auto_open_race')
 Run-Tool xsim @('image2_auto_open_race','-runall','-log','image2_auto_open_race.log')
 if(!(Select-String 'image2_auto_open_race.log' -Pattern '^PASS ' -Quiet) -or (Select-String 'image2_auto_open_race.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw 'Automatic preview/query race regression failed'}
}finally{Pop-Location}
