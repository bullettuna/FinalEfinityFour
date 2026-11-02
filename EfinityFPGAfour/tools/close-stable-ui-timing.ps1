param([ValidateSet(1,5,7)][int]$Image=1,[int]$FirstSeed=22,[int]$LastSeed=28,[ValidateSet('TIMING_1','TIMING_2','TIMING_3')][string]$OptimizationLevel='TIMING_2',[ValidateSet('on','off')][string]$BeneficialSkew='on')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $root ('images/image'+$Image+'_stable_ui');$name='Ti60_Image'+$Image+'_Stable_UI'
$log=Join-Path $root ('tmp/stable_ui_20261029/build'+$Image+'.log')
foreach($candidateSeed in $FirstSeed..$LastSeed){
 $preserve=Join-Path $root ('tmp/stable_ui_20261029/rejected_image'+$Image+'_before_seed'+$candidateSeed)
 New-Item -ItemType Directory -Force $preserve|Out-Null
 foreach($ext in '.bit','.hex','.timing.rpt'){if(Test-Path (Join-Path $profile ('outflow/'+$name+$ext))){Copy-Item (Join-Path $profile ('outflow/'+$name+$ext)) $preserve}}
 if(Test-Path $log){Copy-Item $log (Join-Path $preserve 'build.log')}
 $project=Join-Path $profile ($name+'.xml');$xml=Get-Content $project -Raw
 Copy-Item $project (Join-Path $preserve 'project.xml')
 $xml=[regex]::Replace($xml,'name="seed" value="\d+"',('name="seed" value="'+$candidateSeed+'"'))
 $xml=[regex]::Replace($xml,'name="optimization_level" value="[A-Z_0-9]+"',('name="optimization_level" value="'+$OptimizationLevel+'"'))
 $xml=[regex]::Replace($xml,'name="beneficial_skew" value="(on|off)"',('name="beneficial_skew" value="'+$BeneficialSkew+'"'))
 [IO.File]::WriteAllText($project,$xml,[Text.UTF8Encoding]::new($false))
 Write-Host "image$Image timing attempt seed=$candidateSeed optimization=$OptimizationLevel beneficial_skew=$BeneficialSkew"
 & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'build-stable-ui.ps1') -Image $Image *> $log
 if($LASTEXITCODE -eq 0){Write-Host "PASS image$Image all timing checks seed=$candidateSeed";exit 0}
 $result=Get-Content $log -Raw
 if($result -notmatch 'Timing violation:'){throw 'Non-timing failure requires inspection'}
 Write-Host (([regex]::Matches($result,'Timing violation:[^\r\n]+')|Select-Object -Last 1).Value)
}
throw 'No timing-qualified image; failed candidates were not published'
