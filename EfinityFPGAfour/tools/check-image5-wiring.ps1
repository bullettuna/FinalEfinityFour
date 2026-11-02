$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $root 'images/image5_canny'
[xml]$project=Get-Content (Join-Path $dir 'Ti60_Image5_Canny.xml') -Raw
$ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('efx','http://www.efinixinc.com/enf_proj')
$files=@($project.SelectNodes('//efx:design_file',$ns)|ForEach-Object{$_.GetAttribute('name')})
if($files -notcontains 'image5_platform.v' -or $files -contains '../../example_top.v'){throw 'image5 must use its private platform'}
if($project.SelectSingleNode('//efx:top_module',$ns).GetAttribute('name') -ne 'image5_top'){throw 'Wrong image5 top'}
$wrapper=Get-Content (Join-Path $dir 'image5_top.v') -Raw
$platform=Get-Content (Join-Path $dir 'image5_platform.v') -Raw
$pipeline=Get-Content (Join-Path $root 'src/vision/image5_canny_pipeline.v') -Raw
foreach($setting in @('PHOTO_TF_BUILD','ENABLE_PHOTO_TF','SHAPE_BUILD','COLOR_OVERLAY_BUILD','GRAY_EDGE_SPLIT_BUILD','PERSON_BUILD')){
 if($wrapper -notmatch ('\.'+$setting+'\(1\x27b0\)')){throw "Unexpected image5 switch $setting"}
}
foreach($setting in @('ENABLE_KEY_UART','ENABLE_ADC')){
 if($wrapper -notmatch ('\.'+$setting+'\(1\x27b1\)')){throw "Missing image5 input switch $setting"}
}
if($platform -match 'adc_threshold_ctrl\s*#'){throw 'image5 knob must not control Canny'}
foreach($contract in @('image5_adc_uart u_adc_uart_reporter','\.ADC_QUERY_AVAILABLE\(ENABLE_ADC\)',
 '\.query\(w_adc_query\)','\.query_ready\(w_adc_query_ready\)',
 'assign w_edge_threshold_effective_request = w_edge_threshold_request',
 'assign w_canny_low_threshold_effective_request = w_canny_low_threshold_request')){
 if($platform -notmatch $contract){throw "Missing acquisition-only input contract: $contract"}
}
foreach($contract in @('module\s+image5_platform\s*#','\.DEFAULT_VIDEO_MODE\(2\x27d2\)')){
 if(($platform+"`n"+$wrapper) -notmatch $contract){throw "Missing image5 contract: $contract"}
}
foreach($contract in @('DEFAULT_EDGE_THRESHOLD\s*=\s*11\x27d60','DEFAULT_CANNY_LOW_THRESHOLD\s*=\s*11\x27d30',
 'DEFAULT_MEDIAN_ENABLE\s*=\s*1\x27b1','\.EDGE_TEST_PROFILE\(1\x27b1\)',
 '\.edge_cleanup_req\(w_image5_cleanup_request\)','image5_canny_pipeline\s*#',
 '\.median_req\(r_median_enable_active\)','\.cleanup_req\(w_image5_cleanup_request\)',
 '\.high_threshold\(r_edge_threshold_active\)','\.low_threshold\(r_canny_low_threshold_active\)',
 'edge_threshold_cdc\s*#','\.PHOTO_STREAM_BUILD\(ENABLE_PHOTO_TF\)','\.gray_pixel\(w_median_pixel\)','\.out_edge\(w_canny_edge_pixel\)')){
 if($platform -notmatch $contract){throw "Missing image5 platform connection: $contract"}
}
foreach($contract in @('image5_gray_median\s*#','\.per_img_gray\(gray_pixel\)',
 '\.per_img_red\(gray_pixel\)','\.per_img_green\(gray_pixel\)','\.per_img_blue\(gray_pixel\)',
 'median3x3_kernel u_kernel','image5_edge_prune.*?u_prune0','image5_edge_prune.*?u_prune1',
 'neighbours>=2','TOP_GUARD=12','assign out_href=e1','clean_sync<=clean_meta')){
 if($pipeline -notmatch ('(?s)'+$contract)){throw "Missing image5 pipeline connection: $contract"}
}
Write-Host 'PASS image5 private platform, image1 Canny with pre-median, fixed-latency cleanup and frame-boundary thresholds'
& python (Join-Path $PSScriptRoot 'check-ft232h.py')
if($LASTEXITCODE -ne 0){throw 'FT232H final pin/source qualification failed'}
