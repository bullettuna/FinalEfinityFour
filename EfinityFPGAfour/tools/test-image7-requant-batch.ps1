param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_requant_batch';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
Push-Location $sim
try{
 Run xvlog @('-sv',(Join-Path $root 'src/pose7/pose7_requant.v'),(Join-Path $root 'src/pose7_perf/pose7_requant_batch.v'),(Join-Path $root 'src/pose7_perf/pose7_requant_batch_tb.sv'))
 Run xelab @('pose7_requant_batch_tb','-s','batch','-mt','2')
 Run xsim @('batch','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS pose7_requant_batch:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Batch requant equivalence failed'}
}finally{Pop-Location}
