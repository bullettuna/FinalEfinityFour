$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $root 'images/image4_skeleton'
[xml]$project=Get-Content (Join-Path $dir 'Ti60_Image4_Skeleton.xml') -Raw
$ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
$ns.AddNamespace('efx','http://www.efinixinc.com/enf_proj')
$files=@($project.SelectNodes('//efx:design_file',$ns)|ForEach-Object{$_.GetAttribute('name')})
if($files -notcontains 'image4_platform.v' -or $files -contains '../../example_top.v'){throw 'image4 must use private platform'}
$wrapper=Get-Content (Join-Path $dir 'image4_top.v') -Raw
$platform=Get-Content (Join-Path $dir 'image4_platform.v') -Raw
foreach($setting in @('PERSON_BUILD','RAW_REFINE_BUILD','ENABLE_ADC','PHOTO_TF_BUILD','ENABLE_PHOTO_TF','EDGE_BACKGROUND_BUILD','GRAY_MEDIAN_BUILD','SHAPE_BUILD','COLOR_OVERLAY_BUILD','GRAY_EDGE_SPLIT_BUILD')){
 $expected=if($setting -in 'PERSON_BUILD','RAW_REFINE_BUILD'){'1'}else{'0'}
 if($wrapper -notmatch ('\.'+$setting+'\(1\x27b'+$expected+'\)')){throw "Unexpected image4 build switch $setting"}
}
foreach($contract in @('module\s+image4_platform\s*#','uart_skeleton_ctrl\s*#','\.PERSON_VERSION\("4"\)',
 '\.PERSON_EXTRA_VIEW\(1\x27b1\)','\.BACKGROUND_BUILD\(1\x27b0\)','\.background_capture_i\(1\x27b0\)',
 '\.background_read_enable_i\(1\x27b0\)','if \(1\x27b0\) begin : g_canny_vision',
 'image4_person_pipeline\s*#','\.POSE_MATCH\(0\)','\.WEAK_GROWTH\(1\x27b0\)','\.selected_pixel\(selected_pixel\)',
 '\.REPORT_SECONDS\(2\)','\.report_enable\(w_person_view_request==3\x27d6\)','\.BODY_AVAILABLE\(1\)','\.sample_body_valid\(skeleton_body_valid\)','skeleton_video_pipeline u_skeleton_video','skeleton_uart\s*#','\.current_raw\(lcd_red\)',
 '\.out_vsync\(mask_vsync\)','\.in_vsync\(mask_vsync\)','\.out_vsync\(person_vsync\)')){
 if($platform -notmatch $contract){throw "Missing image4 wiring contract: $contract"}
}
Write-Host 'PASS private image4 wiring and disabled legacy hardware'
