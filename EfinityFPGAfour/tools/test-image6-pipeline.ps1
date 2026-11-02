param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose6_pipeline'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
& 'E:\Efinity_Project\FPGA_GAME\.venv-fourpoint\Scripts\python.exe' (Join-Path $PSScriptRoot 'pose6-conv-vectors.py') --output $sim
if($LASTEXITCODE -ne 0){throw 'Pipeline vectors failed'}
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $sources=@('pose6_mac16.v','pose6_requant.v','pose6_conv.v','pose6_network.v','pose6_input_pool.v','pose6_decode.v')|ForEach-Object{Join-Path $root ('src/pose6/'+$_)}
 Run-Tool xvlog (@('-i',$root)+$sources)
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose6/pose6_pipeline_tb.sv'))
 Run-Tool xelab @('pose6_pipeline_tb','-s','pose6_pipeline')
 Run-Tool xsim @('pose6_pipeline','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image6 full pipeline' -Quiet)){throw 'No full-pipeline PASS marker'}
}finally{Pop-Location}
