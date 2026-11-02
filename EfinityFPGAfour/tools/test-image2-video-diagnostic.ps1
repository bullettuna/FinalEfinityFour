param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image2_video_diagnostic';New-Item -ItemType Directory -Force $sim|Out-Null
function Run([string]$tool,[string[]]$argv){
 $q=($argv|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$tool+'.bat" '+$q)
 if($LASTEXITCODE -ne 0){throw "$tool failed"}
}
Push-Location $sim
try{
 Run xvlog @('-sv','-i',$root,(Join-Path $root 'images/image2_video_guard/image2_video_diagnostic.v'),(Join-Path $root 'images/image2_video_guard/image2_video_diagnostic_tb.sv'))
 Run xelab @('image2_video_diagnostic_tb','-s','diagnostic','-mt','2');Run xsim @('diagnostic','-runall','-log','result.log')
 if(!(Select-String result.log -Pattern '^PASS ' -Quiet) -or (Select-String result.log -Pattern 'Fatal:|ERROR:|FAIL ' -Quiet)){throw 'Diagnostic regression failed'}
 & python -c "import struct,zlib;from pathlib import Path;p=Path('image2_video_diag.bin').read_bytes();assert len(p)==56 and p[:4]==b'P2D1';assert zlib.crc32(p[:52])==struct.unpack_from('<I',p,52)[0];v=struct.unpack_from('<12I',p,4);assert v[1:4]==(3,2,11) and v[7:9]==(1,7) and v[11]==6,v;print('PASS independent image2 diagnostic packet decode and CRC32',v)"
 if($LASTEXITCODE -ne 0){throw 'Independent packet check failed'}
}finally{Pop-Location}
