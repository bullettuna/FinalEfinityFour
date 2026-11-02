param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_latest_control';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$name,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/storage/photo_async_fifo.v','src/storage/photo_axi_mux.v','src/storage/sd4_command.v','src/storage/sd4_host.v','src/ft232h/ft_ddr_snapshot.v','src/ft232h/ft_edge_pack.v','src/ft232h/ft_packet_source.v','src/ft232h/ft245_async_tx.v','src/ft232h/ft_uart_control.v')|ForEach-Object{Join-Path $root $_}
 foreach($dir in 'src/pose7','src/pose7_perf','src/pose7_latest'){$files+=Get-ChildItem (Join-Path $root $dir) -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}}
 Run xvlog (@('-i',$root)+$files);Run xvlog @('-sv',(Join-Path $root 'src/pose7_latest/pose7_latest_control_tb.sv'))
 Run xelab @('pose7_latest_control_tb','-s','control','-mt','2');Run xsim @('control','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS latest USB control:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Latest USB compatibility failed'}
}finally{Pop-Location}
