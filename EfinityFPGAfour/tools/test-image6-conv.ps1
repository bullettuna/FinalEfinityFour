param([int]$Layers=10,[string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose6_conv'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
& 'E:\Efinity_Project\FPGA_GAME\.venv-fourpoint\Scripts\python.exe' (Join-Path $PSScriptRoot 'pose6-conv-vectors.py') --output $sim
if($LASTEXITCODE -ne 0){throw 'Convolution vectors failed'}
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $sources=@('pose6_mac16.v','pose6_requant.v','pose6_conv.v')|ForEach-Object{Join-Path $root ('src/pose6/'+$_)}
 Run-Tool xvlog (@('-i',$root)+$sources)
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose6/pose6_conv_tb.sv'))
 Run-Tool xelab @('pose6_conv_tb','-s','pose6_conv','-generic_top',"LAYERS=$Layers")
 Run-Tool xsim @('pose6_conv','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image6 tiled convolution' -Quiet)){throw 'No all-layer PASS marker'}
}finally{Pop-Location}
