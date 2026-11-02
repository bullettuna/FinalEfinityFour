param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/background_axi'
New-Item -ItemType Directory -Path $simDirectory -Force|Out-Null
function Invoke-Tool([string]$name,[string[]]$arguments){
 $quoted=($arguments|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $simDirectory
try{
 $files=@('src/storage/photo_async_fifo.v','src/storage/gallery_word_fifo.v','src/axi/axi4_ctrl.v',
 'src/axi/axi4_background_tb.sv','src/vision/edge_background_expand.v','src/vision/edge_background_capture.v','src/axi/axi4_edge_background_tb.sv')|ForEach-Object{Join-Path $projectRoot $_}
 Invoke-Tool 'xvlog' (@('-sv')+$files)
 Invoke-Tool 'xelab' @('axi4_background_tb','-s','axi4_background')
 Invoke-Tool 'xsim' @('axi4_background','-runall','-log','axi4_background.log')
 if(!(Select-String -LiteralPath 'axi4_background.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'axi4_background.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'AXI background regression failed'}
 Invoke-Tool 'xelab' @('axi4_background_tb','-generic_top','PHOTO=0','-s','axi4_background_no_photo')
 Invoke-Tool 'xsim' @('axi4_background_no_photo','-runall','-log','axi4_background_no_photo.log')
 if(!(Select-String -LiteralPath 'axi4_background_no_photo.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'axi4_background_no_photo.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'AXI R-only background regression failed'}
 Invoke-Tool 'xelab' @('axi4_background_tb','-generic_top','PHOTO=0','-generic_top','ASYNC_VIDEO=1','-s','axi4_background_async')
 Invoke-Tool 'xsim' @('axi4_background_async','-runall','-log','axi4_background_async.log')
 if(!(Select-String -LiteralPath 'axi4_background_async.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'axi4_background_async.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'Asynchronous AXI background mode regression failed'}
 Invoke-Tool 'xelab' @('axi4_edge_background_tb','-s','axi4_edge_background')
 Invoke-Tool 'xsim' @('axi4_edge_background','-runall','-log','axi4_edge_background.log')
 if(!(Select-String -LiteralPath 'axi4_edge_background.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'axi4_edge_background.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'AXI E background regression failed'}
 Invoke-Tool 'xelab' @('axi4_edge_background_tb','-generic_top','TOLERANCE=1','-s','axi4_edge_tolerance')
 Invoke-Tool 'xsim' @('axi4_edge_tolerance','-runall','-log','axi4_edge_tolerance.log')
 if(!(Select-String -LiteralPath 'axi4_edge_tolerance.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'axi4_edge_tolerance.log' -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'AXI tolerant E background regression failed'}
}finally{Pop-Location}
