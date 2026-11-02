param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$WithVideo,[ValidatePattern('^[A-Za-z0-9_-]+$')][string]$SimulationName='pose6_standalone')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root "work_sim/$SimulationName"
New-Item -ItemType Directory -Path $sim -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $root 'tmp/image6_standalone/sdcard/MODEL6.BIN') -Destination (Join-Path $sim 'MODEL6.BIN')
foreach($n in @('capture640.bin','expected.vec')){Copy-Item -LiteralPath (Join-Path $root "work_sim/pose6_pipeline/$n") -Destination (Join-Path $sim $n)}
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/storage/photo_async_fifo.v','src/storage/photo_axi_mux.v','src/storage/sd4_command.v','src/storage/sd4_host.v',
 'src/ft232h/ft_ddr_snapshot.v','src/ft232h/ft_edge_pack.v','src/ft232h/ft_packet_source.v','src/ft232h/ft245_async_tx.v')|ForEach-Object{Join-Path $root $_}
 $files+=Get-ChildItem (Join-Path $root 'src/pose6') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}
 Run-Tool xvlog (@('-i',$root)+$files)
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose6/pose6_sd_card_tb.sv'),(Join-Path $root 'src/pose6/pose6_standalone_tb.sv'))
 Run-Tool xelab @('pose6_standalone_tb','-s','standalone','-generic_top',"WITH_VIDEO=$([int][bool]$WithVideo)")
 Run-Tool xsim @('standalone','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image6 standalone integration' -Quiet) -or (Select-String -Path result.log -Pattern '^\s*(Fatal:|ERROR:|FAIL(\s|:|$))' -Quiet)){throw 'Standalone integration failed'}
 if($WithVideo -and !(Select-String -Path result.log -Pattern '^PASS contended DDR video' -Quiet)){throw 'Missing video contention result'}
 & 'E:\Efinity_Project\FPGA_GAME\.venv-fourpoint\Scripts\python.exe' (Join-Path $root 'tools/check-image6-standalone-packet.py') --capture (Join-Path $sim 'standalone_points.bin')
 if($LASTEXITCODE -ne 0){throw 'Standalone USB oracle failed'}
}finally{Pop-Location}
