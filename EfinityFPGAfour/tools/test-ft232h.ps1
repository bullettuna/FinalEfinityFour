param([switch]$FullSize,[switch]$UartOnly,[string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/ft_packed'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Run-Test([string]$top,[string]$snap,[string[]]$generics=@()){
 Run-Tool xelab (@($top,'-s',$snap)+$generics)
 Run-Tool xsim @($snap,'-runall','-log',"$snap.log")
 if(!(Select-String -LiteralPath "$snap.log" -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath "$snap.log" -Pattern 'Fatal:|ERROR:|FAIL |invalid file' -Quiet)){throw "FT regression failed: $snap.log"}
}
Push-Location $sim
try{
 $rtl=@('ft245_async_tx.v','ft_edge_pack.v','ft_ddr_snapshot.v','ft_packet_source.v','ft_uart_control.v','image5_ft_link.v')|ForEach-Object{Join-Path $root ('src/ft232h/'+$_)}
 $rtl+=Join-Path $root 'src/storage/photo_async_fifo.v'
 $rtl+=Join-Path $root 'images/image5_canny/uart_vision_ctrl.v'
 $tb=@('ft_uart_tb.sv','ft_uart_vision_tb.sv','ft_async_tx_tb.sv','ft_async_link_tb.sv','ft_edge_pack_tb.sv')|ForEach-Object{Join-Path $root ('src/ft232h/'+$_)}
 Run-Tool xvlog $rtl
 Run-Tool xvlog (@('-sv')+$tb)
 Run-Test ft_uart_tb ft_uart
 Run-Test ft_uart_vision_tb ft_uart_vision
 if($UartOnly){Write-Host 'PASS FT UART isolated and integrated ownership regressions';return}
 Run-Test ft_edge_pack_tb ft_edge_pack
 Run-Test ft_async_tx_tb ft_async_tx
 Run-Test ft_async_tx_tb ft_async_tx_corner @('-generic_top','DATA_DELAY=2.5','-generic_top','WR_DELAY=4.8')
 Run-Test ft_async_link_tb ft_async_link
 & python (Join-Path $root 'tools/test-ft232h.py') --captures $sim
 if($LASTEXITCODE -ne 0){throw 'Async RTL pixel/protocol oracle failed'}
 if($FullSize){
  Run-Test ft_async_link_tb ft_async_full @('-generic_top','WIDTH=1920','-generic_top','HEIGHT=1080','-generic_top','FAST=1','-generic_top','FRAMES=1')
  & python (Join-Path $root 'tools/test-ft232h.py') --captures $sim
  if($LASTEXITCODE -ne 0){throw 'Full-resolution DDR/packet pixel oracle failed'}
 }
 Write-Host 'PASS FT232H RTL, PC parser and snapshot regressions'
}finally{Pop-Location}
