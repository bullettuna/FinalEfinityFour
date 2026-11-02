param([string]$PlatformPath,[string]$ProjectPath,[string]$WrapperPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$imageRoot=Join-Path $root 'images/image3_pose'
if(!$ProjectPath){$ProjectPath=Join-Path $imageRoot 'Ti60_Image3_Pose.xml'}
if(!$PlatformPath){$PlatformPath=Join-Path $imageRoot 'image3_platform.v'}
if(!$WrapperPath){$WrapperPath=Join-Path $imageRoot 'image3_top.v'}
[xml]$project=Get-Content -LiteralPath $ProjectPath -Raw
$ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('efx','http://www.efinixinc.com/enf_proj')
$files=@($project.SelectNodes('//efx:design_file',$ns)|ForEach-Object{$_.GetAttribute('name')})
if($files -notcontains 'image3_platform.v' -or $files -contains '../../example_top.v'){throw 'image3 must use its private platform'}
$wrapper=Get-Content -LiteralPath $WrapperPath -Raw
$platform=Get-Content -LiteralPath $PlatformPath -Raw
foreach($setting in @('PERSON_BUILD','ENABLE_ADC','PHOTO_TF_BUILD','EDGE_BACKGROUND_BUILD','GRAY_MEDIAN_BUILD')){
 $expected=if($setting -eq 'PERSON_BUILD'){'1'}else{'0'}
 if($wrapper -notmatch ('\.'+$setting+'\(1\x27b'+$expected+'\)')){throw "Unexpected image3 build switch $setting"}
}
foreach($connection in @(
 'module\s+image3_platform\s*#\(',
 'if\s*\(ENABLE_ADC\)\s*begin\s*:\s*g_adc',
 '\.threshold_update\(w_uart_threshold_update\)',
 '\.uart_update\(w_uart_threshold_update\)',
 '\.high_request\(w_edge_threshold_effective_request\)',
 '\.low_request\(w_canny_low_threshold_effective_request\)',
 '\.high_threshold\s*\(r_edge_threshold_active\)',
 '\.low_threshold\s*\(r_canny_low_threshold_active\)',
 'edge_threshold_cdc\s*#',
 'if\s*\(EDGE_BACKGROUND_BUILD\)\s*begin\s*:\s*g_edge_background',
 '\.PERSON_EDGE_AVAILABLE\(EDGE_BACKGROUND_BUILD\)',
 '\.MEDIAN_AVAILABLE\(GRAY_MEDIAN_BUILD\)',
 'PHOTO_STREAM_BUILD\(ENABLE_PHOTO_TF\|\|\(PERSON_BUILD&&EDGE_BACKGROUND_BUILD\)\)',
 'person_roi_pipeline\s*#\s*\(\s*\.DUAL_SOURCE\(EDGE_BACKGROUND_BUILD\)',
 '\.background_capture_i\(w_background_capture_request&&!w_person_edge_source_request&&!w_white_background_request\)',
 '\.background_read_enable_i\(PERSON_BUILD&&!w_person_edge_source_request&&!w_white_mode_active\)',
 '\.background_raw\(aligned_background\)',
 '\.current_raw\(lcd_red\)',
 'if\s*\(!PHOTO_TF_BUILD\)\s*begin\s*:\s*g_canny_vision',
 'if\s*\(!PHOTO_TF_BUILD\s*&&\s*GRAY_MEDIAN_BUILD\)\s*begin\s*:\s*g_gray_median_vision'
)){
 if($platform -notmatch $connection){throw "Missing R/Canny build or wiring contract: $connection"}
}
if($wrapper -match '\.RAW_REFINE_BUILD\(1\x27b1\)'){
 foreach($connection in @('\.RAW_REFINE\(RAW_REFINE_BUILD\)',
  '\.POSE_MATCH\(RAW_REFINE_BUILD\)',
  '\.PERSON_VERSION\(RAW_REFINE_BUILD\?"P":',
  '\.LIGHTING_AVAILABLE\(RAW_REFINE_BUILD\)',
  '\.lighting_req\(w_lighting_suppress_request\)',
  '\.lighting_suppress_req\(w_lighting_suppress_request\)',
  '\.WHITE_AVAILABLE\(RAW_REFINE_BUILD\)',
  '\.white_req\(w_white_background_request\)',
  '\.white_background_req\(w_white_background_request\)',
  '\.white_ready\(w_white_model_ready\)',
  '\.source_valid\(person_candidate_valid&&\(w_white_mode_active\|\|!w_background_stream_fault\)\)',
  '\.canny_pixel\(w_edge_pixel!=0\)',
  '\.pose_config_changed\(pose_signature!=pose_signature_d\)',
  'person_pose_uart\s*#\(\.CLOCK_HZ\(96000000\),\.REPORT_HZ\(2\)\)\s+u_pose_uart',
  '\.sample_tick\(pose_tick\)',
  'if\(RAW_REFINE_BUILD\)begin\s*:\s*g_canny_roi_view',
  '\.edge_pixel\(w_edge_pixel!=0\)', '\.target_vsync\(person_vsync\)',
  '\.bbox_valid\(person_candidate_valid\)',
  'w_video_rgb\s*=\s*canny_roi_active\?canny_roi_rgb')){
  if($platform -notmatch $connection){throw "Missing R refinement/Canny ROI connection: $connection"}
 }
}
Write-Host 'PASS image3 R-only background, retained Canny, disabled E capture/DDR stream/median and private platform wiring'
