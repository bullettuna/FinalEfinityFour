param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose6_debug'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 Run-Tool xvlog @((Join-Path $root 'src/pose6/pose6_debug_uart.v'))
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose6/pose6_debug_uart_tb.sv'))
 Run-Tool xelab @('pose6_debug_uart_tb','-s','debug_uart')
 Run-Tool xsim @('debug_uart','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image6 ASCII diagnostics' -Quiet) -or (Select-String -Path result.log -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'ASCII debug regression failed'}
}finally{Pop-Location}
