param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$PerfCandidate,[switch]$LatestCandidate)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root $(if($LatestCandidate){"work_sim/pose7_latest_interlocks"}elseif($PerfCandidate){"work_sim/pose7_perf_interlocks"}else{"work_sim/pose7_reconfig_interlocks"})
New-Item -ItemType Directory -Path $sim -Force|Out-Null
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
 if($LatestCandidate){$PerfCandidate=$true;$files+=Get-ChildItem (Join-Path $root 'src/pose7_latest') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}}
 if($PerfCandidate){$files+=Get-ChildItem (Join-Path $root 'src/pose7_perf') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.'}|ForEach-Object{$_.FullName}}
 Run-Tool xvlog (@('-i',$root)+$files)
 $tb=@('-sv');if($LatestCandidate){$tb+=@('-d','POSE7_LATEST_CANDIDATE')};if($PerfCandidate){$tb+=@('-d','POSE7_PERF_CANDIDATE')}
 Run-Tool xvlog ($tb+(Join-Path $root 'src/pose7/pose7_reconfig_interlock_tb.sv'))
 Run-Tool xelab @('pose7_reconfig_interlock_tb','-s','interlock','-mt','2')
 Run-Tool xsim @('interlock','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image7 reconfiguration interlocks:' -Quiet) -or
    (Select-String -Path result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Reconfiguration interlock failed'}
}finally{Pop-Location}
