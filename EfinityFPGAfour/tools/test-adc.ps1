param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[string[]]$Tests=@())
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/adc'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-Tool([string]$name,[string[]]$toolArguments) {
    $quoted=($toolArguments|ForEach-Object{'"'+$_+'"'}) -join ' '
    & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
    if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $simDirectory
try {
    $sources=@('src/adc/mcp3202_spi.v','src/adc/adc_input_ctrl.v','src/adc/adc_uart_reporter.v',
        'src/adc/adc_threshold_ctrl.v','src/vision/edge_threshold_cdc.v','src/vision/uart_vision_ctrl.v',
        'src/uart/uart_tx_arbiter.v','src/uart/uart_transfer.v','src/uart/key_uart_reporter.v',
        'src/adc/mcp3202_spi_tb.sv','src/adc/adc_input_ctrl_tb.sv','src/adc/adc_uart_reporter_tb.sv',
        'src/adc/adc_threshold_ctrl_tb.sv','src/vision/uart_vision_ctrl_tb.v') |
        ForEach-Object {Join-Path $projectRoot $_}
    Invoke-Tool 'xvlog' (@('-sv','-i',$projectRoot)+$sources)
    foreach($test in @('mcp3202_spi','adc_input_ctrl','adc_uart_reporter','adc_threshold_ctrl','uart_vision_ctrl')) {
        if($Tests.Count -gt 0 -and $Tests -notcontains $test){continue}
        Invoke-Tool 'xelab' @("${test}_tb",'-s',$test)
        Invoke-Tool 'xsim' @($test,'-runall','-log',"$test.log")
        if(!(Select-String -LiteralPath "$test.log" -Pattern '^PASS ' -Quiet) -or
           (Select-String -LiteralPath "$test.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)) {
            throw "ADC regression failed: $test"
        }
    }
    if($Tests.Count -eq 0 -or $Tests -contains 'adc_threshold_image1') {
        Invoke-Tool 'xelab' @('adc_threshold_ctrl_tb','-generic_top','MENU_PROFILE=1','-s','adc_threshold_image1')
        Invoke-Tool 'xsim' @('adc_threshold_image1','-runall','-log','adc_threshold_image1.log')
        if(!(Select-String -LiteralPath 'adc_threshold_image1.log' -Pattern '^PASS ' -Quiet) -or
           (Select-String -LiteralPath 'adc_threshold_image1.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)) {
            throw 'Image1 menu-only Canny threshold regression failed'
        }
    }
    if($Tests.Count -eq 0 -or $Tests -contains 'adc_threshold_image3') {
        Invoke-Tool 'xelab' @('adc_threshold_ctrl_tb','-generic_top','PERSON_PROFILE=1','-s','adc_threshold_image3')
        Invoke-Tool 'xsim' @('adc_threshold_image3','-runall','-log','adc_threshold_image3.log')
        if(!(Select-String -LiteralPath 'adc_threshold_image3.log' -Pattern '^PASS ' -Quiet) -or
           (Select-String -LiteralPath 'adc_threshold_image3.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)) {
            throw 'Image3 ADC/Canny/N/U6 control regression failed'
        }
    }
    if($Tests.Count -eq 0 -or $Tests -contains 'adc_threshold_image2') {
        Invoke-Tool 'xelab' @('adc_threshold_ctrl_tb','-generic_top','PHOTO_PROFILE=1','-s','adc_threshold_image2')
        Invoke-Tool 'xsim' @('adc_threshold_image2','-runall','-log','adc_threshold_image2.log')
        if(!(Select-String -LiteralPath 'adc_threshold_image2.log' -Pattern '^PASS ' -Quiet) -or
           (Select-String -LiteralPath 'adc_threshold_image2.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)) {
            throw 'Image2 ADC/Canny/UART threshold regression failed'
        }
    }
    if($Tests.Count -eq 0 -or $Tests -contains 'mcp3202_production') {
    Invoke-Tool 'xelab' @('mcp3202_spi_tb','-generic_top','PRODUCTION=1','-s','mcp3202_production')
    Invoke-Tool 'xsim' @('mcp3202_production','-runall','-log','mcp3202_production.log')
    if(!(Select-String -LiteralPath 'mcp3202_production.log' -Pattern '^PASS ' -Quiet) -or
       (Select-String -LiteralPath 'mcp3202_production.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)) {
        throw 'Production ADC clock/timing regression failed'
    }
    }
    Write-Host 'PASS selected ADC regressions'
} finally {Pop-Location}
