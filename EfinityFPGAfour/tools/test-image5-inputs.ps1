param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image5_inputs'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $sources=@('src/adc/adc_input_ctrl.v','src/adc/adc_uart_reporter.v',
  'images/image5_canny/image5_adc_uart.v','src/ft232h/ft_uart_control.v',
  'images/image5_canny/uart_vision_ctrl.v','src/uart/key_uart_reporter.v',
  'src/uart/uart_tx_arbiter.v','src/uart/uart_transfer.v','src/adc/image5_inputs_tb.sv')|
  ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-sv')+$sources)
 Run-Tool xelab @('image5_inputs_tb','-s','image5_inputs')
 Run-Tool xsim @('image5_inputs','-runall','-log','image5_inputs.log')
 if(!(Select-String -LiteralPath 'image5_inputs.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'image5_inputs.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){
  throw 'Image5 input integration regression failed'
 }
}finally{Pop-Location}
