param([string]$EfinityRoot='E:\Efinity')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$imageRoot=Join-Path $root 'images/image5_canny'
$name='Ti60_Image5_Canny'
function Fingerprint {
 $files=Get-ChildItem (Join-Path $root 'src'),(Join-Path $root 'pri') -Recurse -File |
  Where-Object {$_.Extension -in '.v','.sv','.vh' -and $_.Name -notmatch '_tb\.'}
 $files+=Get-ChildItem $imageRoot -File | Where-Object {$_.Extension -in '.v','.sdc','.json' -or $_.Name -like '*.peri.xml'}
 ($files | Sort-Object FullName | ForEach-Object {$_.FullName+':'+(Get-FileHash $_.FullName -Algorithm SHA256).Hash}) -join "`n"
}
function PythonCheck([string]$script,[string[]]$extra=@()) {
 & python (Join-Path $PSScriptRoot $script) @extra
 if($LASTEXITCODE -ne 0){throw "$script failed"}
}
Push-Location $imageRoot
try {
 & (Join-Path $PSScriptRoot 'check-image5-wiring.ps1')
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow interface')
 if($LASTEXITCODE -ne 0){throw 'image5 interface failed'}
 PythonCheck 'prepare-image5-ft-constraints.py'
 $before=Fingerprint
 $started=Get-Date
 & cmd.exe /d /c ('call "'+$EfinityRoot+'\bin\setup.bat" && call "'+$EfinityRoot+'\bin\efx_run.bat" '+$name+'.xml --flow compile')
 if($LASTEXITCODE -ne 0){throw 'image5 compile failed'}
 if((Fingerprint) -ne $before){throw 'Sources changed during compile; raw bit is not qualified'}
 foreach($suffix in @('.bit','.timing.rpt','-hierarchical_stats.rpt','.map.v','.pt_timing.rpt')) {
  if((Get-Item "outflow/$name$suffix").LastWriteTime -lt $started){throw "Stale report $suffix"}
 }
 & (Join-Path $PSScriptRoot 'check-image5-wiring.ps1')
 PythonCheck 'check-image5-netlist.py'
 PythonCheck 'check-ft232h.py' @('--reports')
 $text=Get-Content "outflow/$name.timing.rpt" -Raw
 $summary=[regex]::Match($text,'(?s)Setup \(Max\) Clock Relationship(.*?)Clock Relationship Summary \(end\)')
 if(!$summary.Success -or $summary.Value -notmatch 'Hold \(Min\) Clock Relationship'){throw 'Incomplete timing summary'}
 foreach($clock in @('clk_sys','clk_pixel_2x','csi_rxc_i')){
  if(([regex]::Matches($summary.Value,('(?m)^\s+'+$clock+'\s+'+$clock+'\s+'))).Count -ne 2){throw "Missing setup/hold $clock"}
 }
 $rows=[regex]::Matches($summary.Value,'(?m)^\s+\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\([RF]-[RF]\)')
 if($rows.Count -lt 6){throw 'Insufficient constrained relationships'}
 foreach($r in $rows){if([double]::Parse($r.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture) -lt 0){throw "Timing violation: $($r.Value.Trim())"}}
 Copy-Item "outflow/$name.bit" "outflow/${name}_checked.bit"
 $report=@{transport='FT245_ASYNC_FIFO';built=(Get-Date).ToString('s');sourceFingerprintSHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($before)));bitSHA256=(Get-FileHash "outflow/${name}_checked.bit").Hash;timingRelationships=$rows.Count;hardwareTested=$false}
 $report|ConvertTo-Json|Set-Content "outflow/image5_qualification.json" -Encoding utf8
 Write-Host "PASS image5 async FIFO compile, netlist, external conditional budget and $($rows.Count) setup/hold relationships: $imageRoot/outflow/${name}_checked.bit"
}finally {Pop-Location}
