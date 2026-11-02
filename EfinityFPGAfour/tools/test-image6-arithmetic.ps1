param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose6_arithmetic'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
& python (Join-Path $PSScriptRoot 'pose6-vectors.py') --output $sim
if($LASTEXITCODE -ne 0){throw 'Vector generation failed'}
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 Run-Tool xvlog @((Join-Path $root 'src/pose6/pose6_mac16.v'),(Join-Path $root 'src/pose6/pose6_requant.v'))
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose6/pose6_arithmetic_tb.sv'))
 Run-Tool xelab @('pose6_arithmetic_tb','-s','pose6_arithmetic')
 Run-Tool xsim @('pose6_arithmetic','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS ' -Quiet)){throw 'No arithmetic PASS marker'}
}finally{Pop-Location}
