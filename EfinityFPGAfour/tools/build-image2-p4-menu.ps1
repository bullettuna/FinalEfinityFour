param([string]$EfinityRoot='E:\Efinity')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$profile=Join-Path $root 'images/image2_p4_menu'
$name='Ti60_Image2_P4_Menu'
function Fingerprint {
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $profile -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 ($files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
$lock=[IO.File]::Open((Join-Path $root 'tmp/image2-p4-menu.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
Push-Location $profile
try{
 & python (Join-Path $PSScriptRoot 'check-image2-p4-menu.py')
 if($LASTEXITCODE -ne 0){throw 'Image2 P4 source check failed'}
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
 if($LASTEXITCODE -ne 0){throw 'Image2 interface generation failed'}
 & python (Join-Path $PSScriptRoot 'prepare-image1-input-constraints.py') --profile image2_p4_menu --project $name
 if($LASTEXITCODE -ne 0){throw 'Constraint restoration failed'}
 $before=Fingerprint;$started=Get-Date
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow compile')
 if($LASTEXITCODE -ne 0){throw 'Image2 compilation failed'}
 if((Fingerprint) -ne $before){throw 'Runtime source changed during build'}
 foreach($suffix in @('.bit','.hex','.timing.rpt','.map.v','-hierarchical_stats.rpt','.cdc.rpt','.pt.rpt')){
  if((Get-Item ('outflow/'+$name+$suffix)).LastWriteTime -lt $started){throw "Stale $suffix"}
 }
 $timing=Get-Content ('outflow/'+$name+'.timing.rpt') -Raw
 $section=[regex]::Match($timing,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 if(!$section.Success -or $section.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Missing timing summary'}
 $rows=[regex]::Matches($section.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 28){throw 'Missing constrained relationships'}
 foreach($row in $rows){if([double]::Parse($row.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw ("Timing violation: "+$row.Value.Trim())}}
 if((Get-Content ('outflow/'+$name+'.cdc.rpt') -Raw) -notmatch 'No Synchronizer warnings to report.'){throw 'CDC review required'}
 & python (Join-Path $PSScriptRoot 'check-image2-p4-menu.py') --reports
 if($LASTEXITCODE -ne 0){throw 'Mapped pins/menu/capture check failed'}
 & (Join-Path $PSScriptRoot 'check-image-netlist.ps1') -Image 2 -WarnPath ('outflow/'+$name+'.warn.log') -HierarchyPath ('outflow/'+$name+'-hierarchical_stats.rpt')
 Copy-Item ('outflow/'+$name+'.bit') ('outflow/'+$name+'_checked.bit')
 Copy-Item ('outflow/'+$name+'.hex') ('outflow/'+$name+'_checked.hex')
 $sha=[Security.Cryptography.SHA256]::Create()
 $fingerprint=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($before)))).Replace('-','');$sha.Dispose()
 @{built=(Get-Date).ToString('s');sourceFingerprintSHA256=$fingerprint;bitSHA256=(Get-FileHash ('outflow/'+$name+'_checked.bit')).Hash;hexSHA256=(Get-FileHash ('outflow/'+$name+'_checked.hex')).Hash;timingRelationships=$rows.Count;hardwareTested=$false;flashWritten=$false}|ConvertTo-Json|Set-Content 'outflow/qualification.json' -Encoding utf8
 Write-Host 'PASS image2 P4 menu build: pins, capture resources, setup/hold and CDC'
}finally{Pop-Location;$lock.Dispose()}
