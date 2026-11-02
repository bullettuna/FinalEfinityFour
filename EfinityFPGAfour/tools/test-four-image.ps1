param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$PhotoOnly,[int[]]$MenuImages=@(1,2,5,7))
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/four_image';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
function Test([string]$top,[string]$snap,[string[]]$parameters=@()){
 $argv=@($top,'-s',$snap,'-mt','2');foreach($parameter in $parameters){$argv+=@('-generic_top',$parameter)}
 Run xelab $argv;Run xsim @($snap,'-runall','-log',($snap+'.log'))
 if(!(Select-String ($snap+'.log') -Pattern '^PASS ' -Quiet) -or (Select-String ($snap+'.log') -Pattern 'Fatal:|ERROR:|FAIL ' -Quiet)){throw "$snap failed"}
}
if(!$PhotoOnly){
foreach($id in $MenuImages){
 $work=Join-Path $sim ('image'+$id);New-Item -ItemType Directory -Force $work|Out-Null;Push-Location $work
 try{
  $defs=switch($id){1{@('images/image1_four_boot/image1_menu_ctrl.v','images/image1_four_boot/image1_menu_render.v','src/ui/menu_text_rom.v')}2{@('images/image2_four_boot/image2_menu_ctrl.v','images/image2_four_boot/image2_menu_render.v','images/image2_four_boot/image2_menu_rom.v')}5{@('images/image5_four_boot/image5_menu_ctrl.v','images/image5_four_boot/image5_menu_render.v','images/image5_canny/image5_menu_text_rom.v')}7{@('images/image7_four_boot/image7_usb_menu_ctrl.v','images/image7_four_boot/image7_usb_menu_render.v','images/image7_four_boot/image7_usb_menu_text_rom.v')}}
  $files=@('images/four_boot_common/flash_image_switch.v','images/four_boot_common/flash_menu_tb.sv','images/four_boot_common/flash_menu_chars_tb.sv','src/ui/menu_font_8x8.v')+$defs
  if($id -eq 1){$files+='images/four_boot_common/flash_image_switch_tb.sv'}
  $files=$files|ForEach-Object{Join-Path $root $_};Run xvlog (@('-sv','-i',$root)+$files)
  if($id -eq 1){foreach($slot in 0,1,2,3){Test 'flash_image_switch_tb' ('slot'+$slot) @('CURRENT_SLOT='+$slot)}}
  Test 'flash_menu_tb' ('keys'+$id) @('IMAGE_ID='+$id)
  Test 'flash_menu_chars_tb' ('chars'+$id) @('IMAGE_ID='+$id)
 }finally{Pop-Location}
}
}
$work=Join-Path $sim 'photo';New-Item -ItemType Directory -Force $work|Out-Null;Push-Location $work
try{
 $files=@('images/four_boot_common/flash_image_switch.v','images/image2_four_boot/image2_vision_ctrl.v','images/image2_four_boot/image2_menu_ctrl.v','images/image2_four_boot/image2_menu_control_tb.sv',
 'src/ui/menu_font_8x8.v','images/image2_four_boot/image2_menu_rom.v','images/image2_four_boot/image2_menu_render.v','images/image2_four_boot/image2_menu_render_tb.sv','images/image2_four_boot/image2_uart_regression_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$files)
 Test 'image2_menu_control_tb' 'photo_menu';Test 'image2_menu_render_tb' 'photo_render';Test 'image2_uart_regression_tb' 'photo_uart'
 & python (Join-Path $PSScriptRoot 'photo-canny-reference.py') --output .
 if($LASTEXITCODE -ne 0){throw 'Independent algorithm reference failed'}
 $files=@('src/vision/grey.v','src/photo/photo_capture_modes.v','src/storage/photo_work_memory.v','src/photo/photo_frame_process.v',
 'src/photo/photo_capture_2x_rgb565.v','src/storage/photo_async_fifo.v','src/storage/gallery_word_fifo.v','src/storage/photo_ddr_stage.v',
 'src/storage/photo_display_stream.v','src/storage/photo_ddr_dma.v','src/storage/sd4_command.v','src/storage/sd4_host.v',
 'src/storage/fat32_photo_writer.v','src/storage/photo_event_uart.v','src/storage/fat32_bmp_reader.v','src/storage/photo_uart_export.v',
 'images/image2_four_boot/image2_photo_pipeline.v','src/storage/photo_axi_mux.v','src/axi/AXI4_AWARMux.v','src/axi/axi4_ctrl.v',
 'src/storage/sd4_card_model_tb.sv','images/image2_four_boot/image2_menu_video_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$files)
 Test 'image2_menu_video_tb' 'photo_reconfig' @('PROCESS_TESTS=1','DELETE_TESTS=1','RECONFIG_TEST=1')
 Test 'image2_menu_video_tb' 'photo_video' @('PROCESS_TESTS=1','DELETE_TESTS=1')
 Write-Host 'PASS four-image menus, all 12 switch directions, defaults, photo status, concurrent SD drain and live video regression'
}finally{Pop-Location}
