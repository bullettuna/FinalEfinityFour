param([ValidateSet('baseline','candidate')][string]$Variant='candidate',[string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root ('work_sim/pose7_perf_'+$Variant)
New-Item -ItemType Directory -Force $sim|Out-Null
foreach($name in @('model.bin','capture640.bin','expected.vec','stages.vec','trace')){
 Copy-Item -LiteralPath (Join-Path $root ('work_sim/pose7_pipeline/'+$name)) -Destination $sim -Recurse -Force
}
$rtl=if($Variant -eq 'baseline'){Join-Path $root 'tmp/image7_perf_20261029/baseline/rtl'}else{Join-Path $root 'src/pose7'}
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
Push-Location $sim
try{
 $sources=@('pose7_mac16.v','pose7_requant.v','pose7_conv.v','pose7_network.v','pose7_input_pool.v','pose7_decode.v')|ForEach-Object{Join-Path $rtl $_}
 if($Variant -eq 'candidate'){
  $sources=$sources|Where-Object{$_ -notmatch 'pose7_(conv|network)\.v$'}
  $sources+=Get-ChildItem (Join-Path $root 'src/pose7_perf') -Filter '*.v'|Where-Object{$_.Name -notmatch '_tb\.' -and $_.Name -notmatch 'image7_ft_link'}|ForEach-Object{$_.FullName}
 }
 Run xvlog (@('-i',$root)+$sources)
 $tb=@('-sv');if($Variant -eq 'candidate'){$tb+=@('-d','POSE7_PERF_CANDIDATE')}
 Run xvlog ($tb+(Join-Path $root 'src/pose7/pose7_perf_tb.sv'))
 Run xelab @('pose7_perf_tb','-s','perf','-mt','2')
 Run xsim @('perf','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS image7 full pipeline' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:|^FAIL' -Quiet)){throw 'Numerical/performance regression failed'}
 & python (Join-Path $root 'tools/summarize-image7-perf.py') result.log
 if($LASTEXITCODE -ne 0){throw 'Performance summary failed'}
}finally{Pop-Location}
