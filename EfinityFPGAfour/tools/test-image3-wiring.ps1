$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$checker=Join-Path $PSScriptRoot 'check-image3-wiring.ps1'
$temporary=Join-Path $root 'tmp/image3_wiring_tests'
New-Item -ItemType Directory -Force -Path $temporary|Out-Null
& $checker
function Reject([string]$kind,[string]$before,[string]$after){
 $file=switch($kind){'Platform'{'image3_platform.v'}'Wrapper'{'image3_top.v'}'Project'{'Ti60_Image3_Pose.xml'}}
 $text=Get-Content (Join-Path $root ('images/image3_pose/'+$file)) -Raw
 if(!$text.Contains($before)){throw "Test mutation absent: $before"}
 $bad=Join-Path $temporary ($kind+'_'+[guid]::NewGuid().ToString('N')+'_'+$file)
 [IO.File]::WriteAllText($bad,$text.Replace($before,$after))
 $args=@{};$args[$kind+'Path']=$bad;$rejected=$false
 try{& $checker @args}catch{$rejected=$true;Write-Host "PASS rejects $kind mutation: $before"}
 if(!$rejected){throw "Wiring mutation accepted: $before"}
}
Reject 'Wrapper' ".EDGE_BACKGROUND_BUILD(1'b0)" ".EDGE_BACKGROUND_BUILD(1'b1)"
Reject 'Wrapper' ".GRAY_MEDIAN_BUILD(1'b0)" ".GRAY_MEDIAN_BUILD(1'b1)"
Reject 'Wrapper' ".ENABLE_ADC(1'b0)" ".ENABLE_ADC(1'b1)"
Reject 'Platform' '.uart_update(w_uart_threshold_update)' ".uart_update(1'b0)"
Reject 'Platform' '.high_request(w_edge_threshold_effective_request)' '.high_request(w_edge_threshold_request)'
Reject 'Platform' ".high_threshold`t(r_edge_threshold_active)" ".high_threshold`t(11'd2047)"
Reject 'Platform' 'if(EDGE_BACKGROUND_BUILD)begin : g_edge_background' 'if(1)begin : g_edge_background'
Reject 'Platform' '.background_raw(aligned_background)' '.background_raw(0)'
Reject 'Platform' 'PHOTO_STREAM_BUILD(ENABLE_PHOTO_TF||(PERSON_BUILD&&EDGE_BACKGROUND_BUILD))' 'PHOTO_STREAM_BUILD(1)'
Reject 'Platform' 'if (!PHOTO_TF_BUILD) begin : g_canny_vision' 'if (0) begin : g_canny_vision'
Reject 'Project' 'name="image3_platform.v"' 'name="../../example_top.v"'
Reject 'Platform' '.RAW_REFINE(RAW_REFINE_BUILD)' '.RAW_REFINE(0)'
Reject 'Platform' '.POSE_MATCH(RAW_REFINE_BUILD)' '.POSE_MATCH(0)'
Reject 'Platform' '.PERSON_VERSION(RAW_REFINE_BUILD?"P":' '.PERSON_VERSION(RAW_REFINE_BUILD?"W":'
Reject 'Platform' '.LIGHTING_AVAILABLE(RAW_REFINE_BUILD)' '.LIGHTING_AVAILABLE(0)'
Reject 'Platform' '.lighting_req(w_lighting_suppress_request)' '.lighting_req(0)'
Reject 'Platform' '.WHITE_AVAILABLE(RAW_REFINE_BUILD)' '.WHITE_AVAILABLE(0)'
Reject 'Platform' '.white_req(w_white_background_request)' '.white_req(0)'
Reject 'Platform' '.white_ready(w_white_model_ready)' '.white_ready()'
Reject 'Platform' '.background_read_enable_i(PERSON_BUILD&&!w_person_edge_source_request&&!w_white_mode_active)' '.background_read_enable_i(PERSON_BUILD&&!w_person_edge_source_request)'
Reject 'Platform' '.source_valid(person_candidate_valid&&(w_white_mode_active||!w_background_stream_fault))' '.source_valid(person_candidate_valid&&!w_background_stream_fault)'
Reject 'Platform' '.canny_pixel(w_edge_pixel!=0)' '.canny_pixel(0)'
Reject 'Platform' '.sample_tick(pose_tick)' '.sample_tick(0)'
Reject 'Platform' '.REPORT_HZ(2)' '.REPORT_HZ(0)'
Reject 'Platform' '.edge_pixel(w_edge_pixel!=0)' '.edge_pixel(0)'
Reject 'Platform' '.target_vsync(person_vsync)' '.target_vsync(0)'
Write-Host 'PASS R/Canny top-level wiring negative controls'
