param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[int[]]$Images=@(1,5,7))
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
foreach($imageId in $Images){
 $sim=Join-Path $root ('work_sim/stable_ui_'+$imageId);New-Item -ItemType Directory -Force $sim|Out-Null
 Push-Location $sim
 try{
  $files=@('src/ui/menu_font_8x8.v','src/ui/menu_text_rom.v','images/image5_canny/image5_menu_text_rom.v','src/pose7/ui/image7_menu_text_rom.v','src/stable_ui/stable_menu_render1.v','src/stable_ui/stable_menu_render5.v','src/stable_ui/stable_menu_render7.v','src/stable_ui/stable_ui_render_tb.sv')|ForEach-Object{Join-Path $root $_}
  Run xvlog (@('-sv','-i',$root)+$files)
  Run xelab @('stable_ui_render_tb','-generic_top',('IMAGE='+$imageId),'-s','ui','-mt','2');Run xsim @('ui','-runall','-log','result.log')
  if(!(Select-String result.log -Pattern '^PASS stable UI' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw "UI image$imageId failed"}
 }finally{Pop-Location}
}
