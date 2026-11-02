param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image7_usb_sender';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$name,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/ft232h/ft245_async_tx.v','images/image7_usb_points/pose7_usb_packet.v','images/image7_usb_points/pose7_usb_sender.v','images/image7_usb_points/image7_usb_sender_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run xvlog (@('-sv')+$files);Run xelab @('image7_usb_sender_tb','-s','sender','-mt','2');Run xsim @('sender','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS USB point sender:' -Quiet) -or (Select-String result.log -Pattern '^Fatal:|^ERROR:' -Quiet)){throw 'USB sender failed'}
 & python (Join-Path $PSScriptRoot 'check-image7-usb-sender.py') (Join-Path $sim 'sender_packets.bin')
 if($LASTEXITCODE -ne 0){throw 'Point packet wire oracle failed'}
}finally{Pop-Location}
