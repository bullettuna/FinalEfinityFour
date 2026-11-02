param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image7_usb_render';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
Push-Location $sim
try{
 $files=@('src/ui/menu_font_8x8.v','images/image7_usb_points/image7_usb_menu_text_rom.v','images/image7_usb_points/image7_usb_menu_render.v','images/image7_usb_points/image7_usb_render_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$files);Run xelab @('image7_usb_render_tb','-s','control','-mt','2');Run xsim @('control','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS USB UI' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Stable menu control/CDC failed'}
}finally{Pop-Location}
