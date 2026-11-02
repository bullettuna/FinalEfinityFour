param([Parameter(Mandatory)][ValidateSet(1,5,7)][int]$Image,[string]$EfinityRoot='E:\Efinity')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$folder=switch($Image){1{'image1_vision'}5{'image5_canny'}7{'image7_mocap11_a'}}
$name=switch($Image){1{'Ti60_Image1_Vision'}5{'Ti60_Image5_Canny'}7{'Ti60_Image7_Mocap11_A'}}
$profile=Join-Path $root ('images/'+$folder)
function Fingerprint {
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File|Where-Object{$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $profile -File|Where-Object{$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 if($Image -eq 1){$files+=Get-Item (Join-Path $root 'example_top.v')}
 ($files|Sort-Object FullName -Unique|ForEach-Object{$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
function PythonCheck([string]$script,[string[]]$extra=@()){
 & python (Join-Path $PSScriptRoot $script) @extra
 if($LASTEXITCODE -ne 0){throw "$script failed"}
}
# Hold a per-profile lock for the entire interface/synthesis/PNR operation.
# A second invocation must never overwrite an active build's databases.
$buildLock=[IO.File]::Open((Join-Path $root ("tmp/multiboot-image"+$Image+".lock")),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
Push-Location $profile
try{
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
 if($LASTEXITCODE -ne 0){throw 'Internal configuration interface generation failed'}
 $prep=switch($Image){1{'prepare-image1-input-constraints.py'}5{'prepare-image5-ft-constraints.py'}7{'prepare-image7-ft-constraints.py'}}
 PythonCheck $prep
 $before=Fingerprint;$started=Get-Date
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow compile')
 if($LASTEXITCODE -ne 0){throw "image$Image compilation failed"}
 if((Fingerprint) -ne $before){throw 'Runtime source changed during build'}
 foreach($suffix in @('.bit','.hex','.timing.rpt','.map.v','-hierarchical_stats.rpt','.cdc.rpt')){
  if((Get-Item ('outflow/'+$name+$suffix)).LastWriteTime -lt $started){throw "Stale $suffix"}
 }
 $timing=Get-Content ('outflow/'+$name+'.timing.rpt') -Raw
 $section=[regex]::Match($timing,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 if(!$section.Success -or $section.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Missing timing summary'}
 $rows=[regex]::Matches($section.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 28){throw 'Missing constrained setup/hold relationships'}
 foreach($row in $rows){if([double]::Parse($row.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw ("Timing violation: "+$row.Value.Trim())}}
 if((Get-Content ('outflow/'+$name+'.cdc.rpt') -Raw) -notmatch 'No Synchronizer warnings to report.'){throw 'CDC review required'}
 PythonCheck 'check-multiboot.py' @('--image',[string]$Image,'--mapped')
 if($Image -eq 7){PythonCheck 'check-image7-mipi.py';PythonCheck 'check-image7-ft.py' @('--reports')}
 Copy-Item ('outflow/'+$name+'.bit') ('outflow/'+$name+'_multiboot_checked.bit')
 Copy-Item ('outflow/'+$name+'.hex') ('outflow/'+$name+'_multiboot_checked.hex')
 $report=@{image=$Image;built=(Get-Date).ToString('s');sourceFingerprintSHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($before)));bitSHA256=(Get-FileHash ('outflow/'+$name+'_multiboot_checked.bit')).Hash;hexSHA256=(Get-FileHash ('outflow/'+$name+'_multiboot_checked.hex')).Hash;timingRelationships=$rows.Count;hardwareTested=$false;flashWritten=$false}
 $report|ConvertTo-Json|Set-Content 'outflow/multiboot_qualification.json' -Encoding utf8
 Write-Host "PASS image$Image multiboot build, mapped controller, capacity and all setup/hold checks"
}finally{Pop-Location;$buildLock.Dispose()}
