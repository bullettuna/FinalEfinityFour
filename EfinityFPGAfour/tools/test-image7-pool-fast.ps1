param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_pool_fast';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
Push-Location $sim
try{
 Run xvlog @('-sv',(Join-Path $root 'src/pose7/pose7_input_pool.v'),(Join-Path $root 'src/pose7_perf/pose7_input_pool_fast.v'),(Join-Path $root 'src/pose7_perf/pose7_pool_equivalence_tb.sv'))
 Run xelab @('pose7_pool_equivalence_tb','-s','pool','-mt','2')
 Run xsim @('pool','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS pose7_input_pool_fast:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'Pool equivalence failed'}
}finally{Pop-Location}
