param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_protocol'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 Run-Tool xvlog @((Join-Path $root 'src/pose7/pose7_uart_loader.v'),(Join-Path $root 'src/pose7/pose7_packet.v'))
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose7/pose7_protocol_tb.sv'))
 Run-Tool xelab @('pose7_protocol_tb','-s','pose7_protocol')
 Run-Tool xsim @('pose7_protocol','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image7 UART' -Quiet)){throw 'No protocol PASS marker'}
 & 'E:\Efinity_Project\FPGA_GAME\.venv-fourpoint\Scripts\python.exe' (Join-Path $PSScriptRoot 'check-image7-packet.py') --capture (Join-Path $sim 'points.bin')
 if($LASTEXITCODE -ne 0){throw 'PC point parser oracle failed'}
}finally{Pop-Location}
