param([string]$ComPort='COM30',[int]$Seconds=30)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$python=Join-Path (Split-Path $root -Parent) 'FPGA_GAME/.venv-fourpoint/Scripts/python.exe'
if(!(Test-Path -LiteralPath $python)){throw "Python environment missing: $python"}
$logs=Join-Path $root 'work_sim/image6_video_logs'
New-Item -ItemType Directory -Path $logs -Force|Out-Null
$log=Join-Path $logs ('video-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.jsonl')
& $python (Join-Path $PSScriptRoot 'read-image6-video.py') --port $ComPort --seconds $Seconds | Tee-Object -FilePath $log
if($LASTEXITCODE -ne 0){throw "Video diagnostic failed; partial log: $log"}
Write-Host "Video diagnostic log: $log"
