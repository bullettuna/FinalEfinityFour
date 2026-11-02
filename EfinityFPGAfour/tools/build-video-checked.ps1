param([string]$EfinityRoot='E:\Efinity')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
function Test-Recipe {
    [xml]$project=Get-Content -LiteralPath (Join-Path $projectRoot 'Ti60_Demo.xml') -Raw
    $ns=New-Object System.Xml.XmlNamespaceManager($project.NameTable)
    $ns.AddNamespace('efx','http://www.efinixinc.com/enf_proj')
    foreach($entry in @(@('optimization_level','TIMING_2'),@('seed','3'),@('placer_effort_level','2'))) {
        $node=$project.SelectSingleNode("//efx:place_and_route/efx:param[@name='$($entry[0])']",$ns)
        if(!$node -or $node.GetAttribute('value') -ne $entry[1]) {throw "PNR recipe changed: $($entry[0]) must be $($entry[1]). Close/reopen Efinity and correct its old settings before compiling."}
    }
}
Push-Location $projectRoot
try {
    Test-Recipe
    $started=Get-Date
    & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" && call "'+$EfinityRoot+'\bin\efx_run.bat" Ti60_Demo.xml --flow compile')
    if($LASTEXITCODE -ne 0) {throw 'Efinity compile failed; no checked image exported'}
    Test-Recipe
    $timingFile=Get-Item -LiteralPath 'outflow/Ti60_Demo.timing.rpt'
    $bitFile=Get-Item -LiteralPath 'outflow/Ti60_Demo.bit'
    if($timingFile.LastWriteTime -lt $started -or $bitFile.LastWriteTime -lt $started) {throw 'Stale timing/bitstream; no checked image exported'}
    $report=Get-Content -LiteralPath $timingFile.FullName -Raw
    $summary=[regex]::Match($report,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
    if(!$summary.Success) {throw 'Cannot find timing summary'}
    if($summary.Value -notmatch 'Hold \(Min\) Clock Relationship') {throw 'Hold timing summary missing'}
    $relationships=[regex]::Matches($summary.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
    if($relationships.Count -lt 2) {throw 'Timing relationships missing'}
    if(([regex]::Matches($summary.Value,'(?m)^\s+clk_pixel_2x\s+clk_pixel_2x\s+')).Count -ne 2) {throw 'Pixel-clock setup/hold constraints missing'}
    foreach($relationship in $relationships) {
        if([double]::Parse($relationship.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0) {
            throw "Timing violation: $($relationship.Value.Trim()). Do not download the raw .bit; no checked image exported."
        }
    }
    Copy-Item -LiteralPath $bitFile.FullName -Destination 'outflow/Ti60_Demo_video_checked.bit'
    Write-Host 'PASS compile and constrained setup/hold; download outflow/Ti60_Demo_video_checked.bit'
} finally {Pop-Location}
