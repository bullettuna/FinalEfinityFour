param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[string[]]$Tests=@('core','video','uart','commands','pipeline','fullhd','motion','weak','body'))
$ErrorActionPreference='Stop'
$unknown=@($Tests|Where-Object{$_ -notin @('core','video','uart','commands','pipeline','fullhd','motion','weak','body')})
if($unknown.Count -gt 0){throw "Unknown skeleton test: $($unknown -join ', ')"}
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/skeleton'
New-Item -ItemType Directory -Force -Path $sim|Out-Null
function Invoke-Tool([string]$tool,[string[]]$arguments){
 $quoted=($arguments|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
& python (Join-Path $root 'tools/skeleton-reference.py') $sim
if($LASTEXITCODE -ne 0){throw 'Reference generation failed'}
& python (Join-Path $root 'tools/body-constraint-reference.py') $sim
if($LASTEXITCODE -ne 0){throw 'Body reference generation failed'}
Push-Location $sim
try{
 Invoke-Tool 'xvlog' @((Join-Path $root 'src/vision/skeleton_thinner.v'),(Join-Path $root 'src/vision/upper_body_constraint.v'))
 if($Tests -contains 'body'){
  foreach($module in @('upper_body_constraint','upper_body_full')){
   Invoke-Tool 'xvlog' @('-sv',(Join-Path $root "src/vision/${module}_tb.sv"))
   Invoke-Tool 'xelab' @("${module}_tb",'-s',$module)
   Invoke-Tool 'xsim' @($module,'-runall','-log',"$module.log")
   if(!(Select-String -LiteralPath "$module.log" -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath "$module.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Failed $module"}
  }
 }
 if($Tests -contains 'motion'){
  Invoke-Tool 'xvlog' @((Join-Path $root 'src/vision/skeleton_video_pipeline.v'))
  Invoke-Tool 'xvlog' @('-sv',(Join-Path $root 'src/vision/skeleton_video_motion_tb.sv'))
  Invoke-Tool 'xelab' @('skeleton_video_motion_tb','-s','skeleton_motion')
  Invoke-Tool 'xsim' @('skeleton_motion','-runall','-log','skeleton_motion.log')
  if(!(Select-String -LiteralPath 'skeleton_motion.log' -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath 'skeleton_motion.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'Failed moving skeleton video'}
 }
 if($Tests -contains 'fullhd'){
  Invoke-Tool 'xvlog' @((Join-Path $root 'src/vision/skeleton_video_pipeline.v'))
  Invoke-Tool 'xvlog' @('-sv',(Join-Path $root 'src/vision/skeleton_video_fullhd_tb.sv'))
  Invoke-Tool 'xelab' @('skeleton_video_fullhd_tb','-s','skeleton_fullhd')
  Invoke-Tool 'xsim' @('skeleton_fullhd','-runall','-log','skeleton_fullhd.log')
  if(!(Select-String -LiteralPath 'skeleton_fullhd.log' -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath 'skeleton_fullhd.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'Failed fullHD skeleton'}
 }
 if($Tests -contains 'weak' -or $Tests -contains 'pipeline'){
  $files=@('src/isp/Line_Shift_RAM_8Bit.v','src/isp/VIP_Matrix_Generate_3X3_8Bit.v','src/vision/background_mask_pipeline.v',
   'src/vision/person_snapshot_selector.v','src/vision/image4_person_pipeline.v','src/vision/skeleton_video_pipeline.v')|ForEach-Object{Join-Path $root $_}
  Invoke-Tool 'xvlog' $files
  foreach($test in @('weak','pipeline')){
   if($Tests -notcontains $test){continue}
   $module=if($test -eq 'weak'){'image4_weak_growth'}else{'image4_pipeline'}
   Invoke-Tool 'xvlog' @('-sv',(Join-Path $root "src/vision/${module}_tb.sv"))
   Invoke-Tool 'xelab' @("${module}_tb",'-s',$module)
   Invoke-Tool 'xsim' @($module,'-runall','-log',"$module.log")
   if(!(Select-String -LiteralPath "$module.log" -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath "$module.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Failed $module"}
  }
 }
 foreach($test in @('uart','commands')){
  if($Tests -notcontains $test){continue}
  $module=if($test -eq 'uart'){'skeleton_uart'}else{'uart_skeleton_ctrl'}
  Invoke-Tool 'xvlog' @((Join-Path $root "src/vision/$module.v"))
  Invoke-Tool 'xvlog' @('-sv',(Join-Path $root "src/vision/${module}_tb.sv"))
  $modes=if($test -eq 'uart'){@(0,1)}else{@(0)}
  foreach($mode in $modes){
   $snapshot="${module}_$mode"
   $elab=@("${module}_tb",'-s',$snapshot)
   if($test -eq 'uart'){$elab+=@('-generic_top',"BODY_MODE=$mode")}
   Invoke-Tool 'xelab' $elab
   Invoke-Tool 'xsim' @($snapshot,'-runall','-log',"$snapshot.log")
   if(!(Select-String -LiteralPath "$snapshot.log" -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath "$snapshot.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Failed $snapshot"}
  }
 }
 if($Tests -contains 'video'){
  Invoke-Tool 'xvlog' @((Join-Path $root 'src/vision/skeleton_video_pipeline.v'))
  Invoke-Tool 'xvlog' @('-sv',(Join-Path $root 'src/vision/skeleton_video_pipeline_tb.sv'))
  Invoke-Tool 'xelab' @('skeleton_video_pipeline_tb','-s','skeleton_video')
  Invoke-Tool 'xsim' @('skeleton_video','-runall','-log','skeleton_video.log')
  if(!(Select-String -LiteralPath 'skeleton_video.log' -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath 'skeleton_video.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'Failed skeleton video'}
 }
 if($Tests -contains 'core'){
  Invoke-Tool 'xvlog' @('-sv',(Join-Path $root 'src/vision/skeleton_thinner_tb.sv'))
  foreach($limited in @(0,1)){
   $name="skeleton_core_$limited"
   Invoke-Tool 'xelab' @('skeleton_thinner_tb','-generic_top',"LIMITED=$limited",'-s',$name)
   Invoke-Tool 'xsim' @($name,'-runall','-log',"$name.log")
   if(!(Select-String -LiteralPath "$name.log" -Pattern '^PASS ' -Quiet) -or (Select-String -LiteralPath "$name.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Failed $name"}
  }
 }
}finally{Pop-Location}
