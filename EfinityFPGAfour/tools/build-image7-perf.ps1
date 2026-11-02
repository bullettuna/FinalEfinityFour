param([string]$EfinityRoot='E:\Efinity')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $root 'images/image7_perf_a';$name='Ti60_Image7_Perf_A'
function Check([string]$tool,[string[]]$argv=@()){
 & python (Join-Path $PSScriptRoot $tool) @argv
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
function Fingerprint{
 foreach($contract in 'pose7_layer_config.vh','pose7_boot_identity.vh','pose7_model_identity.vh'){
  if((Get-FileHash (Join-Path $profile $contract)).Hash -ne (Get-FileHash (Join-Path $root ('images/image7_mocap11_a/'+$contract))).Hash){throw 'Shared model contract differs from fingerprinted copy'}
 }
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $profile -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 ($files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
$lock=[IO.File]::Open((Join-Path $root 'tmp/image7-perf-build.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
Push-Location $profile
try{
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
 if($LASTEXITCODE -ne 0){throw 'Candidate interface failed'}
 Check 'prepare-image7-ft-constraints.py' @('--profile','image7_perf_a','--project',$name)
 $before=Fingerprint;$started=Get-Date
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow compile')
 if($LASTEXITCODE -ne 0){throw 'Candidate compilation failed'}
 if((Fingerprint) -ne $before){throw 'Source changed during candidate build'}
 foreach($ext in '.bit','.hex','.timing.rpt','.map.v','-hierarchical_stats.rpt','.cdc.rpt'){
  if((Get-Item ('outflow/'+$name+$ext)).LastWriteTime -lt $started){throw "Stale $ext"}
 }
 $t=Get-Content ('outflow/'+$name+'.timing.rpt') -Raw
 $section=[regex]::Match($t,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 $rows=[regex]::Matches($section.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 28){throw 'Missing setup/hold relationships'}
 foreach($row in $rows){if([double]::Parse($row.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw ('Timing violation: '+$row.Value.Trim())}}
 if((Get-Content ('outflow/'+$name+'.cdc.rpt') -Raw) -notmatch 'No Synchronizer warnings to report.'){throw 'CDC review required'}
 Check 'check-multiboot.py' @('--image','7','--profile','image7_perf_a','--project',$name,'--mapped')
 Check 'check-image7-mipi.py' @('--report',('outflow/'+$name+'.timing.rpt'),'--sdc',($name+'.pt.sdc'))
 Check 'check-image7-ft.py' @('--profile','image7_perf_a','--project',$name,'--reports')
 $report=@{built=(Get-Date).ToString('s');sourceFingerprintSHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($before)));bitSHA256=(Get-FileHash ('outflow/'+$name+'.bit')).Hash;hexSHA256=(Get-FileHash ('outflow/'+$name+'.hex')).Hash;timingRelationships=$rows.Count;hardwareTested=$false;clockHz=96000000}
 $report|ConvertTo-Json|Set-Content 'outflow/perf_qualification.json' -Encoding utf8
 Write-Host 'PASS image7 performance candidate: resources, all setup/hold paths, MIPI margin, async FT pins and multiboot'
}finally{Pop-Location;$lock.Dispose()}
