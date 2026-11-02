param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_latest_snapshot';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$name,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/storage/photo_async_fifo.v','src/pose7_latest/pose7_capture_bank.v','src/pose7_latest/pose7_latest_snapshot.v','src/pose7_latest/pose7_latest_snapshot_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv')+$files);Run xelab @('pose7_latest_snapshot_tb','-s','latest','-mt','2');Run xsim @('latest','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS latest snapshot:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Snapshot safety regression failed'}
}finally{Pop-Location}
