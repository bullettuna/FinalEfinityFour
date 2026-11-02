param([string]$EfinityRoot='E:\Efinity',[ValidateSet('map','compile')][string]$Flow='compile')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$imageRoot=Join-Path $root 'images/image7_mocap11_a'
$name='Ti60_Image7_Mocap11_A'
function Fingerprint {
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File |
  Where-Object {$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $imageRoot -File | Where-Object {$_.Extension -in '.v','.vh','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 ($files|Sort-Object FullName|ForEach-Object{$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
Push-Location $imageRoot
try {
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
 if($LASTEXITCODE -ne 0){throw 'image7 interface failed'}
 & python (Join-Path $PSScriptRoot 'prepare-image7-ft-constraints.py')
 if($LASTEXITCODE -ne 0){throw 'image7 constraint preparation failed'}
 $before=Fingerprint
 $started=Get-Date
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" >nul && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow '+$Flow)
 if($LASTEXITCODE -ne 0){throw 'image7 build failed'}
 if((Fingerprint) -ne $before){throw 'Sources changed during build; artifacts need rebuilding'}
 if($Flow -eq 'map'){Write-Host 'PASS image7 synthesis only; not a qualified bitstream';return}
 foreach($suffix in @('.bit','.timing.rpt','.map.v')){
  if((Get-Item "outflow/$name$suffix").LastWriteTime -lt $started){throw "Stale $suffix"}
 }
 $text=Get-Content "outflow/$name.timing.rpt" -Raw
 $summary=[regex]::Match($text,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 if(!$summary.Success -or $summary.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Incomplete timing summary'}
 foreach($clock in @('clk_sys','clk_pixel_2x','csi_rxc_i')){
  if(([regex]::Matches($summary.Value,('(?m)^\s+'+$clock+'\s+'+$clock+'\s+'))).Count -ne 2){throw "Missing setup/hold $clock"}
 }
 $rows=[regex]::Matches($summary.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 6){throw 'Insufficient timing relationships'}
 foreach($r in $rows){if([double]::Parse($r.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw "Timing violation: $($r.Value.Trim())"}}
 Copy-Item "outflow/$name.bit" "outflow/${name}_timing_checked.bit"
 & python (Join-Path $PSScriptRoot 'check-image7-ft.py') --reports
 if($LASTEXITCODE -ne 0){throw 'image7 FT pin/periphery checks failed'}
 & python (Join-Path $PSScriptRoot 'check-image7-netlist.py')
 if($LASTEXITCODE -ne 0){throw 'image7 mapped-path/resource checks failed'}
 & python (Join-Path $PSScriptRoot 'check-image7-mipi.py')
 if($LASTEXITCODE -ne 0){throw 'image7 experimental MIPI margin check failed'}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$sourceHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($before)))).Replace('-','')}finally{$sha.Dispose()}
 $report=@{built=(Get-Date).ToString('s');sourceFingerprintSHA256=$sourceHash;mappedNetlistSHA256=(Get-FileHash "outflow/$name.map.v").Hash;bitSHA256=(Get-FileHash "outflow/${name}_timing_checked.bit").Hash;timingRelationships=$rows.Count;hardwareTested=$false;rtlRegressionRequired=$true}
 $report|ConvertTo-Json|Set-Content 'outflow/image7_qualification.json' -Encoding utf8
 Write-Host 'PASS image7 timing; independent RTL/board verification still required'
}finally{Pop-Location}
