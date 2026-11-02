param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$DisplayOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/multiboot'
New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$name,[string[]]$toolArgs){
 $q=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/ui/flash_image_switch.v','src/ui/menu_ctrl.v','src/pose7/ui/image7_menu_ctrl.v',
 'images/image5_canny/image5_menu_ctrl.v','src/ui/flash_image_switch_tb.sv','src/ui/flash_menu_tb.sv','src/ui/flash_menu_chars_tb.sv','src/ui/menu_font_8x8.v',
 'src/ui/menu_text_rom.v','src/ui/menu_text_render.v','src/pose7/ui/image7_menu_text_rom.v','src/pose7/ui/image7_menu_text_render.v',
 'images/image5_canny/image5_menu_text_rom.v','images/image5_canny/image5_menu_render.v')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$files)
 if(!$DisplayOnly){
 foreach($slot in 0,1,2){
  $snap='switch'+$slot
  Run xelab @('flash_image_switch_tb','-generic_top',("CURRENT_SLOT="+$slot),'-s',$snap)
  Run xsim @($snap,'-runall','-log',($snap+'.log'))
  if(!(Select-String -Path ($snap+'.log') -Pattern '^PASS flash_image_switch' -Quiet) -or
     (Select-String -Path ($snap+'.log') -Pattern '^Fatal:|^ERROR:' -Quiet)){throw "Switch slot $slot failed"}
 }
 foreach($id in 1,5,7){
  $snap='menu'+$id
  Run xelab @('flash_menu_tb','-generic_top',("IMAGE_ID="+$id),'-s',$snap)
  Run xsim @($snap,'-runall','-log',($snap+'.log'))
  if(!(Select-String -Path ($snap+'.log') -Pattern '^PASS flash_menu' -Quiet) -or
     (Select-String -Path ($snap+'.log') -Pattern '^Fatal:|^ERROR:' -Quiet)){throw "Menu image$id failed"}
 }
 }
 foreach($id in 1,5,7){
  $snap='chars'+$id
  Run xelab @('flash_menu_chars_tb','-generic_top',("IMAGE_ID="+$id),'-s',$snap,'-mt','2')
  Run xsim @($snap,'-runall','-log',($snap+'.log'))
  if(!(Select-String -Path ($snap+'.log') -Pattern '^PASS flash_menu_chars' -Quiet) -or
     (Select-String -Path ($snap+'.log') -Pattern '^Fatal:|^ERROR:' -Quiet)){throw "Display image$id failed"}
 }
 Write-Host 'PASS multiboot all source/destination slots and three real HDMI menus'
}finally{Pop-Location}
