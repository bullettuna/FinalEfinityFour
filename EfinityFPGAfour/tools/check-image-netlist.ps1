param(
    [Parameter(Mandatory=$true)][ValidateSet(1,2,3,4,5)][int]$Image,
    [Parameter(Mandatory=$true)][string]$WarnPath,
    [Parameter(Mandatory=$true)][string]$HierarchyPath
)
$ErrorActionPreference='Stop'
$poseRomVerified=$false
if($Image -eq 3){
    $mapPath=Join-Path (Split-Path $HierarchyPath -Parent) 'Ti60_Image3_Pose.map.v'
    & python (Join-Path $PSScriptRoot 'check-pose-rom.py') $mapPath
    if($LASTEXITCODE -ne 0){throw 'Mapped pose ROM contents/ports not verified'}
    $poseRomVerified=$true
}
$warnings=Get-Content -LiteralPath $WarnPath
# Efinity appends to warn.log across runs. Qualify only the final synthesis
# section, not an already-fixed warning retained from a previous build.
$lastSynthesis=0
for($row=0;$row -lt $warnings.Count;$row++) {
    if($warnings[$row] -match '^// Efinity Synthesis Started'){$lastSynthesis=$row}
}
$warnings=$warnings[$lastSynthesis..($warnings.Count-1)]
foreach($warning in $warnings) {
    if($warning -notmatch 'does not have a driver'){continue}
    # Existing generated MIPI/IP unused bits are outside this application's RTL.
    # The two unused negative-DQS nets are also in the pre-existing board shell.
    if($warning -match "net 'i_dqs_n_(hi|lo)\[\d+\]'" ){continue}
    # Init-only arrays have no runtime write driver. Accept this exact ROM
    # warning only after checking every actual RAM INIT bit and its read ports.
    if($poseRomVerified -and $warning -match "net 'template_rom' does not have a driver" -and
       $warning -match '[\\/]src[\\/]vision[\\/]person_pose_matcher\.v:'){continue}
    if($warning -match 'g_photo_tf\.|w_gamma_' -or
       $warning -match '[\\/](example_top|image3_platform|image4_platform|image5_platform)\.v:' -or
       $warning -match '[\\/]src[\\/](storage|photo|vision|adc|top|ft232h)[\\/]') {
        throw "Undriven application signal; image rejected: $warning"
    }
}
$hierarchy=Get-Content -LiteralPath $HierarchyPath
if($Image -eq 5){
    foreach($forbidden in @('g_photo_tf\.','g_shape_vision\.','g_shape_reporters\.','g_gray_edge_split\.',
        'g_canny_overlay_vision\.','u_sobel_edge','u_edge_background_capture','u_edge_stats','u_gallery_word_fifo',
        'u_photo_R0_FIFO_8','g_background_fifo\.','g_adc\.','u_person_snapshot_selector','g_person_vision\.','g_key_uart\.','g_rgb_median_vision')){
        if($hierarchy -match $forbidden){throw "image5 retained excluded hardware: $forbidden"}
    }
    foreach($required in @('ddr3_ctl_axi','u_axi4_ctrl','bayer2rgb','u_rgb2dvi','u_uart_vision_ctrl','u_edge_threshold_cdc',
        'u_ft_uart','u_ft_link','u_snapshot','u_packet','u_tx',
        'g_canny_vision\.u_image5_pipeline','u_gray_median','u_canny','u_canny_gaussian','u_canny_gradient','u_canny_nms','u_canny_hysteresis','u_prune0','u_prune1')){
        $entry=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+$required+'\s+\|')}|Select-Object -First 1
        if(!$entry -or [double]([regex]::Match($entry.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "image5 required block missing: $required"}
    }
    foreach($storage in @(@('u_snapshot',45),@('u_gray_median',4),@('u_canny_gaussian',2),@('u_canny_gradient',2),@('u_canny_nms',2),@('u_canny_hysteresis',2),@('u_prune0',2),@('u_prune1',2))){
        $entry=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+$storage[0]+'\s+\|')}|Select-Object -First 1
        if(!$entry -or [int]([regex]::Match($entry.Split('|')[3],'\d+')).Value -lt $storage[1]){throw "image5 image-processing line RAM missing: $($storage[0]); sync-only logic is insufficient"}
    }
    $top=$hierarchy|Where-Object{$_ -match '^\|\s+\+image5_top\s+\|'}|Select-Object -First 1
    $ram=[int]([regex]::Match($top.Split('|')[3],'\d+')).Value
    if($ram -gt 248){throw "image5 insufficient RAM headroom: $ram/256"}
    Write-Host "PASS image5 mapped image1 Canny, pre-median, two edge-prune stages, video and UART; templates/shape/TF/ADC absent; $ram/256 RAM"
    return
}
if($Image -eq 4){
    foreach($forbidden in @('g_photo_tf\.','g_shape_vision\.','g_shape_reporters\.','g_gray_edge_split\.',
        'g_canny_vision\.','g_canny_overlay_vision\.','u_sobel_edge','u_edge_background_capture',
        'u_edge_stats','u_gallery_word_fifo','g_background_fifo\.','g_adc\.','g_pose_match\.','g_canny_roi_view\.',
        'g_gray_median_vision','g_pose_uart\.','u_edge_alignment')){
        if($hierarchy -match $forbidden){throw "image4 retained excluded hardware: $forbidden"}
    }
    foreach($required in @('ddr3_ctl_axi','u_axi4_ctrl','bayer2rgb','u_rgb2dvi','u_uart_vision_ctrl',
        'g_person_vision\.u_person_roi_pipeline','u_person_snapshot_selector','g_white\.u_white',
        'g_lighting\.u_lighting','g_person_vision\.u_skeleton_video','u_thinner','u_body_constraint',
        'g_person_vision\.g_edge_background_disabled\.u_skeleton_uart')){
        $entry=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+$required+'\s+\|')}|Select-Object -First 1
        if(!$entry -or [double]([regex]::Match($entry.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "image4 migrated block missing: $required"}
    }
    $top=$hierarchy|Where-Object{$_ -match '^\|\s+\+image4_top\s+\|'}|Select-Object -First 1
    foreach($storage in @(@('u_thinner',2),@('u_body_constraint',8),@('g_person_vision\.u_skeleton_video',7),@('u_person_snapshot_selector',1))){
        $entry=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+$storage[0]+'\s+\|')}|Select-Object -First 1
        if(!$entry -or [int]([regex]::Match($entry.Split('|')[3],'\d+')).Value -lt $storage[1]){throw "image4 snapshot/work/display RAM missing: $($storage[0])"}
    }
    $ram=[int]([regex]::Match($top.Split('|')[3],'\d+')).Value
    if($ram -gt 248){throw "image4 insufficient RAM headroom: $ram/256"}
    Write-Host "PASS image4 mapped skeleton, white segmentation, camera/display/UART; Canny, templates, RAW background and TF absent; $ram/256 RAM"
    return
}
if($Image -eq 3) {
    # A disabled UART mode alone does not prove resource removal. Qualify the
    # actual mapped hierarchy and require the migrated camera/Canny/display.
    foreach($forbidden in @('g_photo_tf\.','g_shape_vision\.','g_shape_reporters\.',
        'g_gray_edge_split\.','g_canny_overlay_vision\.','u_sobel_edge',
        'shape_hough','shape_recognition_pipeline','u_edge_background_capture',
        'u_edge_stats','u_gallery_word_fifo','u_photo_R0_FIFO_8','g_gray_median_vision',
        'g_adc\.')) {
        if($hierarchy -match $forbidden){throw "image3 retained excluded hardware: $forbidden"}
    }
    foreach($required in @('ddr3_ctl_axi','u_axi4_ctrl','bayer2rgb',
        'g_canny_vision\.u_canny_edge','u_rgb2dvi','u_uart_vision_ctrl',
        'u_edge_threshold_cdc',
        'g_person_vision\.u_person_roi_pipeline','u_person_snapshot_selector',
        'g_background_fifo\.u_background_R0_FIFO_8')) {
        $row=$hierarchy | Where-Object {$_ -match ('^\|\s+\+'+$required+'\s+\|')} | Select-Object -First 1
        if(!$row){throw "image3 migrated block missing: $required"}
        $fields=$row.Split('|')
        $logic=[double]::Parse(([regex]::Match($fields[2],'\d+(?:\.\d+)?')).Value,[Globalization.CultureInfo]::InvariantCulture)
        if($logic -le 0){throw "image3 migrated block contains no logic: $required"}
    }
    $selector=$hierarchy|Where-Object{$_ -match '^\|\s+\+u_person_snapshot_selector\s+\|'}|Select-Object -First 1
    $fields=$selector.Split('|')
    if([int]([regex]::Match($fields[3],'\d+')).Value -le 0){throw 'Person snapshot storage was optimized away'}
    $wrapper=Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'images/image3_pose/image3_top.v') -Raw
    if($wrapper -match '\.RAW_REFINE_BUILD\(1\x27b1\)'){
        $preview=$hierarchy|Where-Object{$_ -match '^\|\s+\+g_person_vision\.g_canny_roi_view\.u_canny_roi_view\s+\|'}|Select-Object -First 1
        if(!$preview -or [int]([regex]::Match($preview.Split('|')[3],'\d+')).Value -le 0){throw 'Canny ROI line ring missing from actual netlist'}
        foreach($block in @('g_pose_match.u_matcher','g_person_vision.g_edge_background_disabled.g_pose_uart.u_pose_uart')){
            $matchRow=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+[regex]::Escape($block)+'\s+\|')}|Select-Object -First 1
            if(!$matchRow -or [double]([regex]::Match($matchRow.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "Pose matching/UART missing: $block"}
        }
        foreach($block in @('g_lighting.u_lighting','u_gain','g_white.u_white')){
            $lightRow=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+[regex]::Escape($block)+'\s+\|')}|Select-Object -First 1
            if(!$lightRow -or [double]([regex]::Match($lightRow.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "Lighting compensation block missing: $block"}
        }
        $white=$hierarchy|Where-Object{$_ -match '^\|\s+\+g_white\.u_white\s+\|'}|Select-Object -First 1
        if([int]([regex]::Match($white.Split('|')[3],'\d+')).Value -ne 0){throw 'White reference unexpectedly added block RAM'}
        $top=$hierarchy|Where-Object{$_ -match '^\|\s+\+image3_top\s+\|'}|Select-Object -First 1
        $ram=[int]([regex]::Match($top.Split('|')[3],'\d+')).Value
        if($ram -gt 248){throw "R refinement retained insufficient RAM headroom: $ram/256"}
    }
    Write-Host 'PASS image3 actual netlist: R background/ROI and Canny retained; E difference, gallery FIFOs, display median and excluded hardware absent'
    return
}
$nativeRow=-1
for($row=0;$row -lt $hierarchy.Count;$row++) {
    if($hierarchy[$row] -match '^\|(?<indent>\s+)\+g_photo_tf\.u_photo_native_pipeline\s+\|') {
        $nativeRow=$row;$nativeIndent=$Matches['indent'].Length;break
    }
}
if($Image -eq 1) {
    if($nativeRow -ge 0){throw 'Vision image retained native photo pipeline'}
    $key=$hierarchy | Where-Object {$_ -match '^\|\s+\+g_key_uart\.u_key_uart_reporter\s+\|'} | Select-Object -First 1
    if(!$key -or [double]([regex]::Match($key.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw 'Image1 button debounce/UART reporter missing from mapped netlist'}
    foreach($adcBlock in @('u_mcp3202_spi','u_adc_input_ctrl','u_adc_uart_reporter','u_adc_threshold_ctrl')) {
        $adc=$hierarchy | Where-Object {$_ -match ('^\|\s+\+g_adc\.'+$adcBlock+'\s+\|')} | Select-Object -First 1
        if(!$adc -or [double]([regex]::Match($adc.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "Image1 ADC block missing from mapped netlist: $adcBlock"}
    }
    $thresholdCdc=$hierarchy | Where-Object {$_ -match '^\|\s+\+u_edge_threshold_cdc\s+\|'} | Select-Object -First 1
    if(!$thresholdCdc -or [double]([regex]::Match($thresholdCdc.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw 'Frame-boundary threshold mailbox missing from mapped netlist'}
    $split=$hierarchy | Where-Object {$_ -match '^\|\s+\+g_gray_edge_split\.u_gray_edge_split\s+\|'} | Select-Object -First 1
    $alignment=$hierarchy | Where-Object {$_ -match '^\|\s+\+g_gray_edge_split\.u_original_gray_alignment\s+\|'} | Select-Object -First 1
    if(!$split -or !$alignment){throw 'Vision split or original-gray alignment optimized away/missing'}
    $splitFields=$split.Split('|');$alignmentFields=$alignment.Split('|')
    $splitLogic=[double]::Parse(([regex]::Match($splitFields[2],'\d+(?:\.\d+)?')).Value,[Globalization.CultureInfo]::InvariantCulture)
    $splitRam=[int]([regex]::Match($splitFields[3],'\d+')).Value
    $alignmentRam=[int]([regex]::Match($alignmentFields[3],'\d+')).Value
    if($splitLogic -le 0 -or $splitRam -ne 0 -or $alignmentRam -le 0){throw 'Unexpected split/alignment resources'}
    $labels=$hierarchy | Where-Object {$_ -match '^\|\s+\+u_shape_label_overlay\s+\|'} | Select-Object -First 1
    if(!$labels){throw 'Chinese shape labels missing from actual image1 netlist'}
    $labelFields=$labels.Split('|')
    $labelLogic=[double]::Parse(([regex]::Match($labelFields[2],'\d+(?:\.\d+)?')).Value,[Globalization.CultureInfo]::InvariantCulture)
    $labelRam=[int]([regex]::Match($labelFields[3],'\d+')).Value
    if($labelLogic -le 0 -or $labelRam -ne 2){throw 'Chinese text renderer or two font ROMs optimized away'}
    foreach($medianBlock in @('g_canny_median_input.u_median_frontend','u_shared_window')){
        $medianRow=$hierarchy | Where-Object {$_ -match ('^\|\s+\+'+[regex]::Escape($medianBlock)+'\s+\|')} | Select-Object -First 1
        if(!$medianRow -or [int]([regex]::Match($medianRow.Split('|')[3],'\d+')).Value -le 0){throw "Image1 median or original-gray center RAM missing: $medianBlock"}
    }
    $muxRow=$hierarchy|Where-Object{$_ -match '^\|\s+\+g_image1_video_output\.u_video_mux\s+\|'}|Select-Object -First 1
    if(!$muxRow){throw 'Image1 registered frame-safe output mux missing'}
    Write-Host 'PASS image1 shared gray/RGB median window, original center and registered frame-safe video mux retained'
    Write-Host "PASS vision image: driven inputs, no native photo pipeline, split $splitLogic XLR/0 RAM, original-gray alignment $alignmentRam RAM, Chinese labels $labelLogic XLR/$labelRam RAM"
    return
}
if($hierarchy -match '\+g_gray_edge_split\.') {throw 'Photo image retained vision split hardware'}
if($nativeRow -lt 0){throw 'Photo pipeline missing from actual synthesized hierarchy'}
$nativeRows=@()
for($row=$nativeRow+1;$row -lt $hierarchy.Count;$row++) {
    if($hierarchy[$row] -match '^\|(?<indent>\s+)\+' -and $Matches['indent'].Length -le $nativeIndent){break}
    $nativeRows+=$hierarchy[$row]
}
$sampler=$nativeRows | Where-Object {$_ -match '^\|\s+\+(g_capture_modes\.)?sampler\s+\|'} | Select-Object -First 1
if(!$sampler){throw 'Photo sampler optimized away; image rejected'}
$samplerFields=$sampler.Split('|')
$samplerLogic=[double]::Parse(([regex]::Match($samplerFields[2],'\d+(?:\.\d+)?')).Value,[Globalization.CultureInfo]::InvariantCulture)
if($samplerLogic -le 0){throw 'Photo sampler contains no logic'}
$captureFifo=$nativeRows | Where-Object {$_ -match '^\|\s+\+fifo\s+\|'} | Select-Object -First 1
if(!$captureFifo){throw 'Photo capture FIFO missing'}
$fifoFields=$captureFifo.Split('|')
$fifoRam=[int]([regex]::Match($fifoFields[3],'\d+')).Value
if($fifoRam -le 0){throw 'Photo capture FIFO RAM optimized away; image rejected'}
foreach($required in @('g_frame_processing.u_process','u_memory','g_uart_export.u_export')){
    $entry=$nativeRows|Where-Object{$_ -match ('^\|\s+\+'+[regex]::Escape($required)+'\s+\|')}|Select-Object -First 1
    if(!$entry -or [double]([regex]::Match($entry.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "Photo complete-frame processor missing: $required"}
}
foreach($required in @('g_adc.u_mcp3202_spi','g_adc.u_adc_input_ctrl','g_adc.u_adc_threshold_ctrl','u_edge_threshold_cdc')) {
    $entry=$hierarchy|Where-Object{$_ -match ('^\|\s+\+'+[regex]::Escape($required)+'\s+\|')}|Select-Object -First 1
    if(!$entry -or [double]([regex]::Match($entry.Split('|')[2],'\d+(?:\.\d+)?')).Value -le 0){throw "Image2 ADC/threshold block missing: $required"}
}
if($hierarchy -match '\+g_adc\.u_adc_uart_reporter\s+\|'){throw 'Image2 ADC key UART reporter must not displace TF messages'}
$preview=$hierarchy|Where-Object{$_ -match '^\|\s+\+g_canny_photo_preview\.u_photo_preview\s+\|'}|Select-Object -First 1
if(!$preview -or [int]([regex]::Match($preview.Split('|')[3],'\d+')).Value -le 0){throw 'Photo live Canny preview line RAM missing'}
Write-Host "PASS actual photo netlist: driven video inputs, sampler $samplerLogic XLR, capture FIFO $fifoRam RAM blocks"
