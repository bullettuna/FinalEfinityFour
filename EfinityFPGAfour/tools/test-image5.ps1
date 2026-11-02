param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$FullSize)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image5'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Run-Test([string]$top,[string]$snapshot,[string[]]$generics=@()){
 Run-Tool xelab (@($top,'-s',$snapshot)+$generics)
 Run-Tool xsim @($snapshot,'-runall','-log',"$snapshot.log")
 if(!(Select-String -LiteralPath "$snapshot.log" -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath "$snapshot.log" -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw "image5 simulation failed: $snapshot.log"}
}
$rtl=@('src/isp/Line_Shift_RAM_8Bit.v','src/isp/VIP_Matrix_Generate_3X3_8Bit.v',
 'src/vision/median3x3_sort3.v','src/vision/median3x3_kernel.v','src/vision/gaussian3x3_filter.v',
 'src/vision/canny_gradient.v','src/vision/canny_nms.v','src/vision/canny_double_threshold.v',
 'src/vision/canny_hysteresis.v','src/vision/canny_edge.v','src/vision/image5_canny_pipeline.v',
 'images/image5_canny/uart_vision_ctrl.v')|ForEach-Object{Join-Path $root $_}
$tb=@('src/vision/image5_pipeline_tb.sv','src/vision/uart_image5_tb.sv')|ForEach-Object{Join-Path $root $_}
& (Join-Path $PSScriptRoot 'check-image5-wiring.ps1')
Push-Location $sim
try{
 Run-Tool xvlog $rtl
 Run-Tool xvlog (@('-sv')+$tb)
 Run-Test uart_image5_tb uart_image5
 Run-Test image5_pipeline_tb image5_pipeline
 if($FullSize){Run-Test image5_pipeline_tb image5_1080p @('-generic_top','WIDTH=1920','-generic_top','HEIGHT=1080')}
 Write-Host 'PASS image5 selected regressions'
}finally{Pop-Location}
