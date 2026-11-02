param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[string[]]$Tests=@())
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/image5_menu'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $rtl=@('images/image5_canny/image5_menu_ctrl.v','images/image5_canny/image5_menu_cdc.v',
  'images/image5_canny/image5_menu_text_rom.v','images/image5_canny/image5_menu_render.v',
  'images/image5_canny/image5_menu_vision_ctrl.v','src/ui/menu_font_8x8.v','src/ui/key_press_debounce.v',
  'images/image5_canny/image5_ft_uart_control.v')|ForEach-Object{Join-Path $root $_}
 $tb=@('src/ui/image5_menu_ctrl_tb.sv','src/ui/image5_menu_key_tb.sv',
  'src/ui/image5_menu_video_tb.sv')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-sv','-i',$root)+$rtl+$tb)
 foreach($test in @('image5_menu_ctrl','image5_menu_key','image5_menu_video')){
  if($Tests.Count -gt 0 -and $Tests -notcontains $test){continue}
  Run-Tool xelab @("${test}_tb",'-s',$test,'-mt','2')
  Run-Tool xsim @($test,'-runall','-log',"$test.log")
  if(!(Select-String -LiteralPath "$test.log" -Pattern '^PASS ' -Quiet) -or
     (Select-String -LiteralPath "$test.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "Menu regression failed: $test"}
 }
}finally{Pop-Location}
