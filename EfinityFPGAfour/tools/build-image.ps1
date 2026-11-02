param(
    [Parameter(Mandatory=$true)][ValidateSet(1,2,3,4,5)][int]$Image,
    [string]$EfinityRoot='E:\Efinity'
)
$ErrorActionPreference='Stop'
if($Image -eq 2){
    & (Join-Path $PSScriptRoot 'build-image2-p4-menu.ps1') -EfinityRoot $EfinityRoot
    return
}
if($Image -eq 5){
    & (Join-Path $PSScriptRoot 'build-image5.ps1') -EfinityRoot $EfinityRoot
    return
}
$projectRoot=Split-Path $PSScriptRoot -Parent
$profile=switch($Image){1{'image1_vision'}2{'image2_photo'}3{'image3_pose'}4{'image4_skeleton'}5{'image5_canny'}}
$name=switch($Image){1{'Ti60_Image1_Vision'}2{'Ti60_Image2_Photo'}3{'Ti60_Image3_Pose'}4{'Ti60_Image4_Skeleton'}5{'Ti60_Image5_Canny'}}
$imageRoot=Join-Path $projectRoot "images/$profile"
function Get-SourceFingerprint {
    $paths=@()
    if($Image -lt 3){$paths+=Join-Path $projectRoot 'example_top.v'}
    $paths+=Get-ChildItem (Join-Path $projectRoot 'src'),(Join-Path $projectRoot 'pri') -Recurse -File |
        Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}|Select-Object -ExpandProperty FullName
    $paths+=Get-ChildItem $imageRoot -File|Where-Object{$_.Extension -in '.v','.sv','.vh'}|Select-Object -ExpandProperty FullName
    if($Image -in 1,5){
        $paths+=Get-ChildItem $imageRoot -File|Where-Object{$_.Name -like '*.peri.xml' -or $_.Extension -in '.sdc','.json'}|Select-Object -ExpandProperty FullName
    }
    ($paths|Sort-Object -Unique|ForEach-Object{$_+':'+(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}) -join "`n"
}
function Test-ImageRecipe {
    [xml]$project=Get-Content -LiteralPath "$name.xml" -Raw
    $ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
    $ns.AddNamespace('efx','http://www.efinixinc.com/enf_proj')
    if($Image -eq 1){
        & python (Join-Path $PSScriptRoot 'check-image1-median.py')
        if($LASTEXITCODE -ne 0){throw 'Image1 median/Canny input or original-gray alignment wiring failed'}
        & python (Join-Path $PSScriptRoot 'check-image1-inputs.py')
        if($LASTEXITCODE -ne 0){throw 'Image1 final P4 input mapping invalid'}
        & python (Join-Path $PSScriptRoot 'check-image1-menu.py')
        if($LASTEXITCODE -ne 0){throw 'Image1 on-screen menu wiring/isolation failed'}
    }
    if($Image -eq 2){
        & python (Join-Path $PSScriptRoot 'check-image2-adc.py')
        if($LASTEXITCODE -ne 0){throw 'Image2 old P3 ADC/threshold wiring failed'}
    }
    if($Image -eq 3){
        & (Join-Path $PSScriptRoot 'check-image3-wiring.ps1')
    }
    if($Image -eq 4){& (Join-Path $PSScriptRoot 'check-image4-wiring.ps1')}
    if($Image -eq 5){& (Join-Path $PSScriptRoot 'check-image5-wiring.ps1')}
    $expectedSeed=switch($Image){1{'17'}2{'4'}3{'6'}4{'6'}5{'6'}}
    $expectedEffort=switch($Image){1{'2'}default{'2'}}
    foreach($entry in @(@('optimization_level','TIMING_2'),@('seed',$expectedSeed),@('placer_effort_level',$expectedEffort))) {
        $node=$project.SelectSingleNode("//efx:place_and_route/efx:param[@name='$($entry[0])']",$ns)
        if(!$node -or $node.GetAttribute('value') -ne $entry[1]) {throw "Unexpected PNR setting $($entry[0]); reopen the correct image project and check its settings."}
    }
}
Push-Location $imageRoot
try {
    Test-ImageRecipe
    if($Image -eq 5){
        & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
        if($LASTEXITCODE -ne 0){throw 'FT image5 interface generation failed'}
        & python (Join-Path $PSScriptRoot 'prepare-image5-ft-constraints.py')
        if($LASTEXITCODE -ne 0){throw 'FT image5 constraint preparation failed'}
    }
    if($Image -eq 1){
        & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
        if($LASTEXITCODE -ne 0){throw 'Image1 P4 interface generation failed'}
        & python (Join-Path $PSScriptRoot 'prepare-image1-input-constraints.py')
        if($LASTEXITCODE -ne 0){throw 'Image1 clock-domain constraint restore failed'}
    }
    $sourceFingerprint=Get-SourceFingerprint
    $started=Get-Date
    & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow compile')
    if($LASTEXITCODE -ne 0){throw "Image $Image compile failed"}
    Test-ImageRecipe
    if((Get-SourceFingerprint) -ne $sourceFingerprint){throw 'RTL changed during compile; bitstream is stale and will not be marked checked'}
    $timing=Get-Item -LiteralPath "outflow/$name.timing.rpt"
    $bit=Get-Item -LiteralPath "outflow/$name.bit"
    $warningLog=Get-Item -LiteralPath "outflow/$name.warn.log"
    $hierarchy=Get-Item -LiteralPath "outflow/$name-hierarchical_stats.rpt"
    if($warningLog.LastWriteTime -lt $started -or $hierarchy.LastWriteTime -lt $started){throw 'Stale netlist qualification reports'}
    & (Join-Path $PSScriptRoot 'check-image-netlist.ps1') -Image $Image -WarnPath $warningLog.FullName -HierarchyPath $hierarchy.FullName
    if($Image -eq 1){
        & python (Join-Path $PSScriptRoot 'check-image1-inputs.py') --reports
        if($LASTEXITCODE -ne 0){throw 'Image1 mapped ADC/menu inputs invalid'}
    }
    if($Image -eq 5){
        & python (Join-Path $PSScriptRoot 'check-ft232h.py') --reports
        if($LASTEXITCODE -ne 0){throw 'FT interface timing budget failed'}
    }
    if($timing.LastWriteTime -lt $started -or $bit.LastWriteTime -lt $started){throw 'Stale image/report'}
    $text=Get-Content -LiteralPath $timing.FullName -Raw
    $summary=[regex]::Match($text,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
    if(!$summary.Success -or $summary.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Timing summary incomplete'}
    $rows=[regex]::Matches($summary.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
    if($rows.Count -lt 2 -or ([regex]::Matches($summary.Value,'(?m)^\s+clk_pixel_2x\s+clk_pixel_2x\s+')).Count -ne 2){throw 'Pixel-clock setup/hold constraints missing'}
    if($Image -eq 5){
        foreach($relationship in @('csi_rxc_i\s+csi_rxc_i','ft_clk_tx\s+ft_clk_tx','ft_clk_sample\s+ft_clk_tx')){
            if(([regex]::Matches($summary.Value,('(?m)^\s+'+$relationship+'\s+'))).Count -ne 2){throw "Required image5 clock relationship missing: $relationship"}
        }
    }
    foreach($row in $rows){
        if([double]::Parse($row.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw "Image $Image timing violation: $($row.Value.Trim()); do not download the raw bitstream."}
    }
    Copy-Item -LiteralPath $bit.FullName -Destination "outflow/${name}_checked.bit"
    Write-Host "PASS Image $Image compile/export and constrained setup/hold: $imageRoot/outflow/${name}_checked.bit"
} finally {Pop-Location}
