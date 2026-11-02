param([string]$VivadoRoot='F:\vivado\Vivado\2024.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose6_video'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/storage/photo_async_fifo.v','src/storage/photo_axi_mux.v',
 'src/ft232h/ft_ddr_snapshot.v','src/ft232h/ft_edge_pack.v','src/ft232h/ft_packet_source.v',
 'src/ft232h/ft245_async_tx.v','src/ft232h/image5_ft_link.v',
 'src/pose6/pose6_mac16.v','src/pose6/pose6_requant.v','src/pose6/pose6_conv.v',
 'src/pose6/pose6_network.v','src/pose6/pose6_input_pool.v','src/pose6/pose6_decode.v',
 'src/pose6/pose6_packet.v','src/pose6/pose6_uart_loader.v','src/pose6/pose6_debug_uart.v','src/pose6/pose6_axi_master.v','src/pose6/pose6_video_diag.v','src/pose6/image6_ft_link.v')|
 ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-i',$root)+$files)
 Run-Tool xvlog @('-sv','-i',$root,(Join-Path $root 'src/pose6/pose6_video_coexist_tb.sv'))
 Run-Tool xelab @('pose6_video_coexist_tb','-s','pose6_video')
 Run-Tool xsim @('pose6_video','-runall','-log','result.log')
 if(!(Select-String -Path result.log -Pattern '^PASS image6 video coexistence' -Quiet) -or
    (Select-String -Path result.log -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw 'Video coexistence regression failed'}
}finally{Pop-Location}
