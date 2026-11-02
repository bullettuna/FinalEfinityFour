param([string]$EfinityRoot='E:\Efinity',[switch]$ReuseMapped)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $root 'images/image2_video_guard'
$name='Ti60_Image2_Video_Guard'
function Fingerprint {
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $profile -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 ($files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
$lock=[IO.File]::Open((Join-Path $root 'tmp/image2-video-guard.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
Push-Location $profile
try{
 & python (Join-Path $PSScriptRoot 'check-image2-video-guard.py')
 if($LASTEXITCODE -ne 0){throw 'Image2 P4 source check failed'}
 if($ReuseMapped){
  $mapped=Get-Item ('outflow/'+$name+'.map.v')
  $runtimePaths=(Fingerprint).Split("`n")|ForEach-Object{$_.Substring(0,$_.Length-65)}
  # SDC is consumed by PNR and may intentionally change for timing trials.
  # RTL, pad configuration and coefficient inputs must predate the mapping.
  foreach($runtimePath in $runtimePaths){if([IO.Path]::GetExtension($runtimePath) -ne '.sdc' -and (Get-Item -LiteralPath $runtimePath).LastWriteTime -gt $mapped.LastWriteTime){throw "Runtime input newer than cached mapping: $runtimePath"}}
  $mappedHash=(Get-FileHash -LiteralPath $mapped.FullName).Hash
 }else{
  & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
  if($LASTEXITCODE -ne 0){throw 'Image2 interface generation failed'}
  & python (Join-Path $PSScriptRoot 'prepare-image1-input-constraints.py') --profile image2_video_guard --project $name
  if($LASTEXITCODE -ne 0){throw 'Constraint restoration failed'}
 }
 $before=Fingerprint;$started=Get-Date
 $flow=if($ReuseMapped){'pnr'}else{'compile'}
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow '+$flow)
 if($LASTEXITCODE -ne 0){throw 'Image2 compilation failed'}
 if($ReuseMapped){
  if((Get-FileHash ('outflow/'+$name+'.map.v')).Hash -ne $mappedHash){throw 'Cached mapping changed during PNR'}
  & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow pgm')
  if($LASTEXITCODE -ne 0){throw 'Bitstream generation failed'}
 }
 if((Fingerprint) -ne $before){throw 'Runtime source changed during build'}
 foreach($suffix in @('.bit','.hex','.timing.rpt','.map.v','-hierarchical_stats.rpt','.cdc.rpt','.pt.rpt')){
  if($ReuseMapped -and $suffix -in '.map.v','.pt.rpt'){continue}
  if((Get-Item ('outflow/'+$name+$suffix)).LastWriteTime -lt $started){throw "Stale $suffix"}
 }
 $timing=Get-Content ('outflow/'+$name+'.timing.rpt') -Raw
 $section=[regex]::Match($timing,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 if(!$section.Success -or $section.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Missing timing summary'}
 $rows=[regex]::Matches($section.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 28){throw 'Missing constrained relationships'}
 foreach($row in $rows){if([double]::Parse($row.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw ("Timing violation: "+$row.Value.Trim())}}
 if((Get-Content ('outflow/'+$name+'.cdc.rpt') -Raw) -notmatch 'No Synchronizer warnings to report.'){throw 'CDC review required'}
 & python (Join-Path $PSScriptRoot 'check-image2-video-guard.py') --reports
 if($LASTEXITCODE -ne 0){throw 'Mapped pins/menu/capture check failed'}
 & (Join-Path $PSScriptRoot 'check-image-netlist.ps1') -Image 2 -WarnPath ('outflow/'+$name+'.warn.log') -HierarchyPath ('outflow/'+$name+'-hierarchical_stats.rpt')
 Copy-Item ('outflow/'+$name+'.bit') ('outflow/'+$name+'_checked.bit')
 Copy-Item ('outflow/'+$name+'.hex') ('outflow/'+$name+'_checked.hex')
 $sha=[Security.Cryptography.SHA256]::Create()
 $fingerprint=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($before)))).Replace('-','');$sha.Dispose()
 @{built=(Get-Date).ToString('s');sourceFingerprintSHA256=$fingerprint;projectSHA256=(Get-FileHash ($name+'.xml')).Hash;reusedMapped=[bool]$ReuseMapped;bitSHA256=(Get-FileHash ('outflow/'+$name+'_checked.bit')).Hash;hexSHA256=(Get-FileHash ('outflow/'+$name+'_checked.hex')).Hash;timingRelationships=$rows.Count;hardwareTested=$false;flashWritten=$false}|ConvertTo-Json|Set-Content 'outflow/qualification.json' -Encoding utf8
 Write-Host 'PASS image2 video guard candidate: pins, capture resources, setup/hold and CDC'
}finally{Pop-Location;$lock.Dispose()}
