param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_pipeline'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $sources=@('pose7_mac16.v','pose7_requant.v','pose7_conv.v','pose7_network.v','pose7_input_pool.v','pose7_decode.v')|ForEach-Object{Join-Path $root ('src/pose7/'+$_)}
 Run-Tool xvlog (@('-i',$root)+$sources)
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose7/pose7_pipeline_tb.sv'))
 Run-Tool xelab @('pose7_pipeline_tb','-s','pose7_pipeline')
 Run-Tool xsim @('pose7_pipeline','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image7 full pipeline' -Quiet)){throw 'No full-pipeline PASS marker'}
}finally{Pop-Location}
