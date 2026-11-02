param([Parameter(Mandatory)][ValidateSet(1,2,5,7)][int]$Image,[string]$EfinityRoot='E:\Efinity',[switch]$ReuseMapped,[switch]$QualifyOnly)
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$folder='image'+$Image+'_four_boot';$name='Ti60_Image'+$Image+'_Four_Boot';$profile=Join-Path $root ('images/'+$folder)
function Fingerprint {
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $profile,(Join-Path $root 'images/four_boot_common') -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 if($Image -in 5,7){$files+=Get-ChildItem (Join-Path $root 'images/image5_canny') -File|Where-Object{$_.Extension -in '.v','.vh'}}
 ($files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
function Check([string]$script,[string[]]$extra=@()){
 & python (Join-Path $PSScriptRoot $script) @extra
 if($LASTEXITCODE -ne 0){throw "$script failed"}
}
$lock=[IO.File]::Open((Join-Path $root ('tmp/four-image'+$Image+'.lock')),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
Push-Location $profile
try{
 Check 'check-four-image.py' @('--image',[string]$Image)
 if($ReuseMapped -or $QualifyOnly){
  $mapped=Get-Item ('outflow/'+$name+'.map.v')
  foreach($line in (Fingerprint).Split("`n")){
   $path=$line.Substring(0,$line.Length-65)
   if([IO.Path]::GetExtension($path) -ne '.sdc' -and (Get-Item -LiteralPath $path).LastWriteTime -gt $mapped.LastWriteTime){throw "Runtime newer than cached mapping: $path"}
  }
  $mapHash=(Get-FileHash $mapped.FullName).Hash
 }else{
  & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
  if($LASTEXITCODE -ne 0){throw 'Interface generation failed'}
  $prep=switch($Image){1{'prepare-image1-input-constraints.py'}2{'prepare-image1-input-constraints.py'}5{'prepare-image5-ft-constraints.py'}7{'prepare-image7-ft-constraints.py'}}
  Check $prep @('--profile',$folder,'--project',$name)
 }
 $before=Fingerprint;$started=Get-Date;$xmlHash=(Get-FileHash ($name+'.xml')).Hash
 if(!$QualifyOnly){
  $flow=if($ReuseMapped){'pnr'}else{'compile'}
  & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow '+$flow)
  if($LASTEXITCODE -ne 0){throw "image$Image $flow failed"}
 }
 if($ReuseMapped -and !$QualifyOnly){
  if((Get-FileHash ('outflow/'+$name+'.map.v')).Hash -ne $mapHash){throw 'Mapping changed'}
  & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow pgm')
  if($LASTEXITCODE -ne 0){throw 'Bitstream generation failed'}
 }
 if((Fingerprint) -ne $before){throw 'Runtime source changed during build'}
 foreach($suffix in @('.bit','.hex','.timing.rpt','.map.v','-hierarchical_stats.rpt','.cdc.rpt','.pt.rpt')){
  if(($ReuseMapped -or $QualifyOnly) -and $suffix -in '.map.v','.pt.rpt'){continue}
  $cutoff=if($QualifyOnly){$mapped.LastWriteTime}else{$started}
  if((Get-Item ('outflow/'+$name+$suffix)).LastWriteTime -lt $cutoff){throw "Stale $suffix"}
 }
 $timing=Get-Content ('outflow/'+$name+'.timing.rpt') -Raw
 $section=[regex]::Match($timing,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 if(!$section.Success -or $section.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Missing timing summary'}
 $rows=[regex]::Matches($section.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 28){throw 'Missing constrained setup/hold relationships'}
 foreach($row in $rows){if([double]::Parse($row.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw ("Timing violation: "+$row.Value.Trim())}}
 if((Get-Content ('outflow/'+$name+'.cdc.rpt') -Raw) -notmatch 'No Synchronizer warnings to report.'){throw 'CDC review required'}
 Check 'check-four-image.py' @('--image',[string]$Image,'--reports')
 if($Image -eq 7){
  Check 'check-image7-ft.py' @('--profile',$folder,'--project',$name,'--reports')
  Check 'check-image7-mipi.py' @('--report',(Join-Path $profile ('outflow/'+$name+'.timing.rpt')),'--sdc',(Join-Path $profile ($name+'.pt.sdc')))
 }
 Copy-Item ('outflow/'+$name+'.bit') ('outflow/'+$name+'_checked.bit')
 Copy-Item ('outflow/'+$name+'.hex') ('outflow/'+$name+'_checked.hex')
 $sha=[Security.Cryptography.SHA256]::Create();$fp=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($before)))).Replace('-','');$sha.Dispose()
 [IO.File]::WriteAllText((Join-Path $profile 'outflow/runtime_fingerprint.txt'),$before,(New-Object Text.UTF8Encoding($false)))
 @{image=$Image;built=(Get-Date).ToString('s');sourceFingerprintSHA256=$fp;projectSHA256=(Get-FileHash ($name+'.xml')).Hash;reusedMapped=[bool]$ReuseMapped;qualifiedExistingBuild=[bool]$QualifyOnly;bitSHA256=(Get-FileHash ('outflow/'+$name+'_checked.bit')).Hash;hexSHA256=(Get-FileHash ('outflow/'+$name+'_checked.hex')).Hash;timingRelationships=$rows.Count;hardwareTested=$false;flashWritten=$false}|ConvertTo-Json|Set-Content 'outflow/qualification.json' -Encoding utf8
 Write-Host "PASS image$Image four-slot qualified build"
}finally{Pop-Location;$lock.Dispose()}
