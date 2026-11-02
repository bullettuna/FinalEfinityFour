param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/key_uart'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-Tool([string]$name,[string[]]$toolArguments) {
    $quoted=($toolArguments | ForEach-Object {'"'+$_+'"'}) -join ' '
    & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
    if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $simDirectory
try {
    $sources=@('src/uart/key_uart_reporter.v','src/uart/uart_tx_arbiter.v',
        'src/uart/uart_transfer.v','src/uart/key_uart_reporter_tb.sv') |
        ForEach-Object {Join-Path $projectRoot $_}
    Invoke-Tool 'xvlog' (@('-sv')+$sources)
    Invoke-Tool 'xelab' @('key_uart_reporter_tb','-s','key_uart')
    Invoke-Tool 'xsim' @('key_uart','-runall','-log','key_uart.log')
    if(!(Select-String -LiteralPath 'key_uart.log' -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath 'key_uart.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)) {
        throw 'Key UART regression failed'
    }
} finally {Pop-Location}
