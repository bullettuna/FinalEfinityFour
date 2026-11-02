param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_overlay'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 Run-Tool xvlog @((Join-Path $root 'src/pose7/pose7_hdmi_overlay.v'))
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose7/pose7_overlay_tb.sv'))
 Run-Tool xelab @('pose7_overlay_tb','-s','overlay')
 Run-Tool xsim @('overlay','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS HDMI eleven-point overlay' -Quiet) -or (Select-String -Path result.log -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'Overlay regression failed'}
}finally{Pop-Location}
