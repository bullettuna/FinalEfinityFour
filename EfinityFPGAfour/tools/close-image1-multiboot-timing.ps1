param([int]$FirstSeed=19,[int]$LastSeed=26)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$project=Join-Path $root 'images/image1_vision/Ti60_Image1_Vision.xml'
$log=Join-Path $root 'tmp/multiboot-build1.log'
foreach($candidateSeed in $FirstSeed..$LastSeed){
 $xml=Get-Content -LiteralPath $project -Raw
 $xml=[regex]::Replace($xml,'name="seed" value="\d+"',('name="seed" value="'+$candidateSeed+'"'))
 [IO.File]::WriteAllText($project,$xml,[Text.UTF8Encoding]::new($false))
 Write-Host "image1 timing attempt seed=$candidateSeed"
 & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'build-multiboot-image.ps1') -Image 1 *> $log
 if($LASTEXITCODE -eq 0){Write-Host "PASS image1 complete timing closure seed=$candidateSeed";exit 0}
 $result=Get-Content -LiteralPath $log -Raw
 Copy-Item -LiteralPath $log -Destination (Join-Path $root ("tmp/multiboot-image1-rejected-seed"+$candidateSeed+'.log'))
 if($result -notmatch 'Timing violation:'){throw 'Non-timing failure: inspect multiboot-build1.log before another attempt'}
 Write-Host (([regex]::Matches($result,'Timing violation:[^\r\n]+')|Select-Object -Last 1).Value)
}
throw 'No seed met every setup/hold constraint; no failed bitstream was published'
