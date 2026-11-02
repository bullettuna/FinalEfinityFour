param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose6_uart_wire'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/uart/integer_divider.v','src/uart/uart_receiver.v','src/pose6/pose6_uart_loader.v')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog $files
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose6/pose6_uart_wire_tb.sv'))
 Run-Tool xelab @('pose6_uart_wire_tb','-s','pose6_uart_wire')
 Run-Tool xsim @('pose6_uart_wire','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image6 real UART wire' -Quiet) -or
    (Select-String -Path result.log -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'UART wire regression failed'}
}finally{Pop-Location}
