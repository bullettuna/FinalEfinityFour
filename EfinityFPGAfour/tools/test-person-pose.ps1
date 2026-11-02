param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[string]$CppRoot='E:\vscode\cpp\EfinityFour',[string[]]$Tests=@(),[switch]$ShadowScene,[switch]$WhiteScene)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/person_pose'
New-Item -ItemType Directory -Force -Path $sim|Out-Null
function Invoke-Tool([string]$tool,[string[]]$arguments){
 $quoted=($arguments|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
& python (Join-Path $root 'tools/export-pose-templates.py') --check
if($LASTEXITCODE -ne 0){throw 'Template verification failed'}
& g++ -std=c++17 -O2 ('-I'+(Join-Path $CppRoot 'src')) (Join-Path $root 'tools/pose-oracle.cpp') -lgdi32 -luser32 -o (Join-Path $sim 'cpp_oracle.exe')
if($LASTEXITCODE -ne 0){throw 'C++ oracle compilation failed'}
& python (Join-Path $root 'tools/pose-test-vectors.py') $CppRoot $sim
if($LASTEXITCODE -ne 0){throw 'C++ comparison vector generation failed'}
Push-Location $sim
try{
 $rtl=@('src/vision/person_pose_matcher.v','src/vision/person_pose_uart.v','src/vision/person_snapshot_selector.v','src/vision/person_canny_roi_view.v')|ForEach-Object{Join-Path $root $_}
 $rtl+=@('src/isp/Line_Shift_RAM_8Bit.v','src/isp/VIP_Matrix_Generate_3X3_8Bit.v','src/vision/background_mask_pipeline.v','src/vision/person_roi_pipeline.v')|ForEach-Object{Join-Path $root $_}
 Invoke-Tool 'xvlog' (@('-i',$root)+$rtl)
 $testNames=@('person_pose_matcher','person_pose_uart','person_pose_snapshot','person_pose_pipeline')
 $unknown=@($Tests|Where-Object{$testNames -notcontains $_})
 if($unknown.Count -gt 0){throw "Unknown pose test: $($unknown -join ', ')"}
 foreach($test in $testNames){
  if($Tests.Count -gt 0 -and $Tests -notcontains $test){continue}
  Invoke-Tool 'xvlog' @('-sv',(Join-Path $root "src/vision/${test}_tb.sv"))
  $elab=@("${test}_tb",'-s',$test)
  if($ShadowScene -and $test -eq 'person_pose_pipeline'){$elab+=@('-generic_top','SHADOW_SCENE=1')}
  if($WhiteScene -and $test -eq 'person_pose_pipeline'){$elab+=@('-generic_top','WHITE_SCENE=1')}
  Invoke-Tool 'xelab' $elab
  Invoke-Tool 'xsim' @($test,'-runall','-log',"$test.log")
  if(!(Select-String -LiteralPath "$test.log" -Pattern '^PASS ' -Quiet) -or
     (Select-String -LiteralPath "$test.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Failed $test"}
 }
}finally{Pop-Location}
