param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image2_p4_menu';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
function Test([string]$top,[string[]]$parameters=@()){
 $args_=@($top,'-s',$top,'-mt','2');foreach($parameter in $parameters){$args_+=@('-generic_top',$parameter)}
 Run xelab $args_;Run xsim @($top,'-runall','-log',($top+'.log'))
 if(!(Select-String ($top+'.log') -Pattern '^PASS ' -Quiet) -or (Select-String ($top+'.log') -Pattern 'Fatal:|ERROR:|FAIL ' -Quiet)){throw "$top failed"}
}
Push-Location $sim
try{
 $files=@('images/image2_p4_menu/image2_vision_ctrl.v','images/image2_p4_menu/image2_menu_ctrl.v','images/image2_p4_menu/image2_menu_control_tb.sv',
 'src/ui/menu_font_8x8.v','images/image2_p4_menu/image2_menu_rom.v','images/image2_p4_menu/image2_menu_render.v','images/image2_p4_menu/image2_menu_render_tb.sv',
 'images/image2_p4_menu/image2_uart_regression_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$files)
 Test 'image2_menu_control_tb';Test 'image2_menu_render_tb';Test 'image2_uart_regression_tb'
 & python (Join-Path $PSScriptRoot 'photo-canny-reference.py') --output .
 if($LASTEXITCODE -ne 0){throw 'Independent algorithm reference failed'}
 $storage=@('src/vision/grey.v','src/photo/photo_capture_modes.v','src/storage/photo_work_memory.v','src/photo/photo_frame_process.v',
 'src/photo/photo_capture_2x_rgb565.v','src/storage/photo_async_fifo.v','src/storage/gallery_word_fifo.v','src/storage/photo_ddr_stage.v',
 'src/storage/photo_display_stream.v','src/storage/photo_ddr_dma.v','src/storage/sd4_command.v','src/storage/sd4_host.v',
 'src/storage/fat32_photo_writer.v','src/storage/photo_event_uart.v','src/storage/fat32_bmp_reader.v','src/storage/photo_uart_export.v',
 'images/image2_p4_menu/image2_photo_pipeline.v','src/storage/photo_axi_mux.v','src/axi/AXI4_AWARMux.v','src/axi/axi4_ctrl.v',
 'src/storage/sd4_card_model_tb.sv','images/image2_p4_menu/image2_menu_video_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$storage)
 Test 'image2_menu_video_tb' @('PROCESS_TESTS=1','DELETE_TESTS=1')
 Write-Host 'PASS image2 P4 menu, rendering, UART compatibility, real native SD4 capture and HDMI contention'
}finally{Pop-Location}
