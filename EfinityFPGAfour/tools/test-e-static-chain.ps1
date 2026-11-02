param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$NativeFifo,[switch]$ResetOnly,[int]$ResetDelay=0)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/e_static_chain'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
# Native IP contains an IEEE-1735 block requiring an Efinix-supported simulator.
# Vivado can still qualify the actual Canny/AXI RTL with the existing FIFO model.
$stub=Get-Content (Join-Path $root 'src/axi/axi4_background_tb.sv') -Raw
$stubEnd=if($NativeFifo){$stub.IndexOf('module R0_FIFO_8')}else{$stub.IndexOf('module axi4_background_tb')}
[IO.File]::WriteAllText((Join-Path $sim 'fifo_stub.sv'),$stub.Substring(0,$stubEnd))
function Tool([string]$name,[string[]]$arguments){
 $quoted=($arguments|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Simulate([string]$top,[string]$snapshot,[string[]]$generic=@()){
 $args=@($top,'-s',$snapshot)
 foreach($g in $generic){$args+=@('-generic_top',$g)}
 Tool 'xelab' $args
 Tool 'xsim' @($snapshot,'-runall','-log',($snapshot+'.log'))
 $log=Get-Content ($snapshot+'.log') -Raw
 if($log -notmatch '(?m)^PASS ' -or $log -match 'Fatal:|ERROR:|FAIL '){throw "$snapshot failed"}
}
Push-Location $sim
try{
 $rtl=@('src/isp/Line_Shift_RAM_8Bit.v','src/isp/VIP_Matrix_Generate_3X3_8Bit.v',
 'src/storage/photo_async_fifo.v','src/storage/gallery_word_fifo.v','src/axi/axi4_ctrl.v','src/storage/photo_axi_mux.v',
 'src/vision/edge_background_expand.v','src/vision/edge_background_capture.v',
 'src/vision/gaussian3x3_filter.v','src/vision/canny_gradient.v','src/vision/canny_nms.v',
 'src/vision/canny_double_threshold.v','src/vision/canny_hysteresis.v','src/vision/canny_edge.v')|ForEach-Object{Join-Path $root $_}
 Tool 'xvlog' $rtl
 $tb=@('-sv','fifo_stub.sv')
 if($NativeFifo){$tb+=Join-Path $root 'ip/R0_FIFO_8/R0_FIFO_8.sv'}
 Tool 'xvlog' ($tb+@(
  (Join-Path $root 'src/axi/axi4_edge_background_tb.sv'),
  (Join-Path $root 'src/vision/e_static_chain_tb.sv'),
  (Join-Path $root 'src/axi/axi4_edge_reset_tb.sv')))
 if($NativeFifo){Simulate 'axi4_edge_background_tb' 'native_fifo_edge' @('TOLERANCE=1')}
 if(!$ResetOnly){
 Simulate 'e_static_chain_tb' 'e_static_chain'
 Simulate 'e_static_chain_tb' 'e_static_chain_burst128' @('BURST=128')
 }
 $delays=if($ResetDelay){@($ResetDelay)}else{@(32,60,100)}
 foreach($delay in $delays){Simulate 'axi4_edge_reset_tb' "axi4_edge_reset_$delay" @("RESET_DELAY=$delay")}
 'PASS selected static Canny / E reset regressions; FIFO model selected explicitly'
}finally{Pop-Location}
