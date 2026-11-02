param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/stable_menu_control';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
Push-Location $sim
try{
 $files=@('src/stable_ui/stable_menu_ctrl7.v','src/pose7/ui/image7_menu_cdc.v','src/stable_ui/stable_menu_control_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv','-i',$root)+$files);Run xelab @('stable_menu_control_tb','-s','control','-mt','2');Run xsim @('control','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS stable menu control:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Stable menu control/CDC failed'}
}finally{Pop-Location}
