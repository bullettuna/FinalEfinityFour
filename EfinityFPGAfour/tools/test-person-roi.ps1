param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$FullSize,[string[]]$Tests=@())
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/person_roi'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-Tool([string]$name,[string[]]$arguments){
 $quoted=($arguments|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Test-Snapshot([string]$top,[string]$name,[string[]]$generics=@()){
 if($Tests.Count -gt 0 -and $Tests -notcontains $name){return}
 $arguments=@($top,'-s',$name)
 foreach($g in $generics){$arguments+=@('-generic_top',$g)}
 Invoke-Tool 'xelab' $arguments
 Invoke-Tool 'xsim' @($name,'-runall','-log',"$name.log")
 if(!(Select-String -LiteralPath "$name.log" -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath "$name.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Failed $name"}
}
Push-Location $simDirectory
try{
 $rtl=@('src/isp/Line_Shift_RAM_8Bit.v','src/isp/VIP_Matrix_Generate_3X3_8Bit.v',
 'src/lcd_para.v','src/lcd_driver.v','src/vision/background_mask_pipeline.v',
 'src/vision/person_snapshot_selector.v','src/vision/person_roi_pipeline.v',
 'src/vision/uart_vision_ctrl.v')|ForEach-Object{Join-Path $projectRoot $_}
 $rtl+=@('src/storage/photo_async_fifo.v','src/vision/edge_background_expand.v','src/vision/edge_background_capture.v','src/vision/edge_difference_stats.v')|ForEach-Object{Join-Path $projectRoot $_}
 $rtl+=Join-Path $projectRoot 'src/vision/person_canny_roi_view.v'
 $tb=@('src/vision/background_mask_pipeline_tb.sv','src/vision/background_lcd_alignment_tb.sv',
 'src/vision/person_snapshot_selector_tb.sv','src/vision/person_snapshot_1080p_tb.sv',
 'src/vision/person_roi_pipeline_tb.sv','src/vision/uart_person_roi_tb.sv')|ForEach-Object{Join-Path $projectRoot $_}
 $tb+=Join-Path $projectRoot 'src/vision/edge_background_capture_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/person_dual_source_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/uart_person_view_reference_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/edge_background_tolerance_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/edge_difference_stats_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/uart_person_raw_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/person_raw_refine_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/person_canny_roi_view_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/background_lighting_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/background_lighting_video_tb.sv'
 $tb+=Join-Path $projectRoot 'src/vision/background_white_tb.sv'
 Invoke-Tool 'xvlog' $rtl
 Invoke-Tool 'xvlog' (@('-sv')+$tb)
 Test-Snapshot 'background_mask_pipeline_tb' 'background_mask'
 Test-Snapshot 'background_lighting_tb' 'background_lighting'
 Test-Snapshot 'background_lighting_video_tb' 'background_lighting_video'
 Test-Snapshot 'background_white_tb' 'background_white'
 Test-Snapshot 'background_lighting_video_tb' 'background_white_video' @('WHITE=1')
 Test-Snapshot 'background_mask_pipeline_tb' 'background_mask_bypass' @('NOISE=0')
 Test-Snapshot 'background_mask_pipeline_tb' 'background_mask_gentle' @('NOISE=2')
 Test-Snapshot 'background_mask_pipeline_tb' 'background_mask_weak' @('NOISE=2','REFINE=1')
 Test-Snapshot 'background_lcd_alignment_tb' 'background_lcd_alignment'
 Test-Snapshot 'person_snapshot_selector_tb' 'person_snapshot_selector'
 Test-Snapshot 'person_roi_pipeline_tb' 'person_roi_pipeline'
 Test-Snapshot 'person_roi_pipeline_tb' 'person_roi_pipeline_refine' @('REFINE=1')
 Test-Snapshot 'uart_person_roi_tb' 'uart_person_roi'
 Test-Snapshot 'uart_person_raw_tb' 'uart_person_raw'
 Test-Snapshot 'uart_person_raw_tb' 'uart_person_raw_extra' @('EXTRA=1')
 Test-Snapshot 'uart_person_raw_tb' 'uart_person_raw_zero' @('EXTRA=1','DEFAULT_HIGH=0','DEFAULT_LOW=0')
 Test-Snapshot 'uart_person_raw_tb' 'uart_person_lighting' @('EXTRA=1','DEFAULT_HIGH=0','DEFAULT_LOW=0','LIGHTING=1')
 Test-Snapshot 'uart_person_raw_tb' 'uart_person_white' @('EXTRA=1','DEFAULT_HIGH=0','DEFAULT_LOW=0','LIGHTING=1','WHITE=1')
 Test-Snapshot 'person_raw_refine_tb' 'person_raw_refine'
 Test-Snapshot 'person_canny_roi_view_tb' 'person_canny_roi_view'
 Test-Snapshot 'uart_person_view_reference_tb' 'uart_person_view_reference'
 Test-Snapshot 'edge_difference_stats_tb' 'edge_difference_stats'
 Test-Snapshot 'edge_background_capture_tb' 'edge_background_capture'
 Test-Snapshot 'edge_background_tolerance_tb' 'edge_background_tolerance'
 Test-Snapshot 'person_dual_source_tb' 'person_dual_source'
 if($FullSize){
  Test-Snapshot 'background_lighting_video_tb' 'background_lighting_video_1080p' @('W=1920','H=1080','HT=2200')
  Test-Snapshot 'background_lighting_video_tb' 'background_white_video_1080p' @('W=1920','H=1080','HT=2200','WHITE=1')
  Test-Snapshot 'person_canny_roi_view_tb' 'person_canny_roi_view_1080p' @('W=1920','H=1080','HT=2200')
  Test-Snapshot 'background_mask_pipeline_tb' 'background_mask_weak_1080p' @('WIDTH=1920','HEIGHT=1080','H_TOTAL=2200','NOISE=2','REFINE=1')
  Test-Snapshot 'edge_background_tolerance_tb' 'edge_background_tolerance_1080p' @('W=1920','H=1080','HT=2200')
  Test-Snapshot 'background_mask_pipeline_tb' 'background_mask_1080p' @('WIDTH=1920','HEIGHT=1080','H_TOTAL=2200','NOISE=2')
  Test-Snapshot 'person_snapshot_1080p_tb' 'person_snapshot_1080p'
  Test-Snapshot 'person_snapshot_1080p_tb' 'person_snapshot_refine_1080p' @('REFINE=1')
  Test-Snapshot 'person_dual_source_tb' 'person_dual_source_1080p' @('W=1920','H=1080','HT=2200')
 }
 Write-Host 'PASS image3 background/person ROI regressions'
}finally{Pop-Location}
