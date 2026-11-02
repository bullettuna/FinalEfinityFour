param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$WithVideo,[switch]$PerfCandidate,[switch]$LatestCandidate,[switch]$StableCandidate,[switch]$UsbCandidate,[switch]$PerfOnly,[ValidateRange(4,64)][int]$LiveSamples=4,[ValidatePattern('^[A-Za-z0-9_-]+$')][string]$SimulationName='pose7_standalone')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root "work_sim/$SimulationName"
New-Item -ItemType Directory -Path $sim -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $root 'tmp/image7_mocap11_a/sdcard/MODEL7.BIN') -Destination (Join-Path $sim 'MODEL7.BIN')
foreach($n in @('capture640.bin','expected.vec')){Copy-Item -LiteralPath (Join-Path $root "work_sim/pose7_pipeline/$n") -Destination (Join-Path $sim $n)}
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/storage/photo_async_fifo.v','src/storage/photo_axi_mux.v','src/storage/sd4_command.v','src/storage/sd4_host.v',
 'src/ft232h/ft_ddr_snapshot.v','src/ft232h/ft_edge_pack.v','src/ft232h/ft_packet_source.v','src/ft232h/ft245_async_tx.v')|ForEach-Object{Join-Path $root $_}
 $files+=Get-ChildItem (Join-Path $root 'src/pose7') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}
 if($UsbCandidate){$StableCandidate=$true}
 if($LatestCandidate){$PerfCandidate=$true}
 if($LatestCandidate){$files+=Get-ChildItem (Join-Path $root 'src/pose7_latest') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}}
 if($PerfCandidate){$files+=Get-ChildItem (Join-Path $root 'src/pose7_perf') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}}
 if($StableCandidate){$files+=(Join-Path $root 'src/stable_ui/image7_ft_link_stable.v')}
 if($UsbCandidate){foreach($f in 'image7_ft_link_usb.v','pose7_usb_sender.v','pose7_usb_packet.v'){$files+=(Join-Path $root ('images/image7_usb_points/'+$f))}}
 Run-Tool xvlog (@('-i',$root)+$files)
 $tb=@('-sv');if($UsbCandidate){$tb+=@('-d','POSE7_USB_CANDIDATE')};if($StableCandidate){$tb+=@('-d','POSE7_STABLE_CANDIDATE')};if($LatestCandidate){$tb+=@('-d','POSE7_LATEST_CANDIDATE')};if($PerfCandidate){$tb+=@('-d','POSE7_PERF_CANDIDATE')}
 Run-Tool xvlog ($tb+@((Join-Path $root 'src/pose7/pose7_sd_card_tb.sv'),(Join-Path $root 'src/pose7/pose7_standalone_tb.sv')))
 Run-Tool xelab @('pose7_standalone_tb','-s','standalone','-mt','2','-generic_top',"WITH_VIDEO=$([int][bool]$WithVideo)",'-generic_top',"PERF_ONLY=$([int][bool]$PerfOnly)",'-generic_top',"PERF_SAMPLES=$LiveSamples")
 Run-Tool xsim @('standalone','-runall','-log','result.log')
 if($PerfOnly){
  if(!(Select-String result.log -Pattern '^PASS image7 live performance:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Live performance simulation failed'}
  return
 }
 if(!(Select-String -Path result.log -Pattern '^PASS image7 standalone integration' -Quiet) -or (Select-String -Path result.log -Pattern '^\s*(Fatal:|ERROR:|FAIL(\s|:|$))' -Quiet)){throw 'Standalone integration failed'}
 if($WithVideo -and !(Select-String -Path result.log -Pattern '^PASS contended DDR video' -Quiet)){throw 'Missing video contention result'}
 & 'E:\Efinity_Project\FPGA_GAME\.venv-fourpoint\Scripts\python.exe' (Join-Path $root 'tools/check-image7-standalone-packet.py') --capture (Join-Path $sim 'standalone_points.bin')
 if($LASTEXITCODE -ne 0){throw 'Standalone USB oracle failed'}
}finally{Pop-Location}
