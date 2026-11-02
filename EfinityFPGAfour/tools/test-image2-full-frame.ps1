param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$ConnectivityOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$name=if($ConnectivityOnly){'image2_connectivity_tall'}else{'image2_canny_full_frame'}
$sim=Join-Path $root "work_sim/$name"
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 if(!$ConnectivityOnly){
  # An independently known invariant: every pixel in a constant image has zero
  # gradient, so the complete output is black at any positive thresholds.
  [IO.File]::WriteAllText((Join-Path $sim 'input0.hex'),('0053'+"`n")*(960*540))
  [IO.File]::WriteAllText((Join-Path $sim 'edge0_1_1.hex'),('0000'+"`n")*(960*540))
 }
 $rtl=@('src/storage/photo_work_memory.v','src/photo/photo_frame_process.v','src/photo/photo_frame_process_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-sv')+$rtl)
 $generics=if($ConnectivityOnly){@('-generic_top','WIDTH=32','-generic_top','HEIGHT=540','-generic_top','QUICK=3')}else{
  @('-generic_top','WIDTH=960','-generic_top','HEIGHT=540','-generic_top','QUICK=2')}
 Run-Tool xelab (@('photo_frame_process_tb','-s',$name)+$generics)
 Run-Tool xsim @($name,'-runall','-log',"$name.log")
 if(!(Select-String "$name.log" -Pattern '^PASS ' -Quiet) -or (Select-String "$name.log" -Pattern 'Fatal:|Error:|ERROR:|FAIL ' -Quiet)){throw "Failed $name"}
}finally{Pop-Location}
