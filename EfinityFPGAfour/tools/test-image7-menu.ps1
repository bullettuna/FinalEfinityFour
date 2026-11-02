param(
    [string]$VivadoRoot = 'F:\vivado\Vivado\2024.2',
    [switch]$UartOnly
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$simDirectory = Join-Path $projectRoot 'work_sim/image7_menu'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null

function Invoke-VivadoTool([string]$name, [string[]]$toolArguments) {
    $quoted = ($toolArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    & cmd.exe /d /c ('call "' + $VivadoRoot + '\settings64.bat" >nul && call "' + $VivadoRoot + '\bin\' + $name + '.bat" ' + $quoted)
    if ($LASTEXITCODE -ne 0) { throw "$name failed" }
}

$sources = @('src/ui/menu_font_8x8.v','src/ui/key_press_debounce.v','src/ui/key_press_debounce_tb.sv','src/pose7/pose7_debug_uart.v','src/pose7/pose7_video_diag.v','src/uart/uart_tx_arbiter.v','src/pose7/pose7_conv.v','src/pose7/pose7_mac16.v','src/pose7/pose7_requant.v')
$sources += Get-ChildItem (Join-Path $projectRoot 'src/pose7/ui') -File | Where-Object {$_.Extension -in '.v','.sv'} | ForEach-Object {$_.FullName}
$sources = $sources | ForEach-Object {if([IO.Path]::IsPathRooted($_)){$_}else{Join-Path $projectRoot $_}}

Push-Location $simDirectory
try {
    Invoke-VivadoTool 'xvlog' (@('-sv', '-i', $projectRoot) + $sources)

    if($UartOnly){
      Invoke-VivadoTool 'xelab' @('image7_menu_uart_tb','-s','image7_menu_uart')
      Invoke-VivadoTool 'xsim' @('image7_menu_uart','-runall','-log','image7_menu_uart.log')
      if(!(Select-String -Path image7_menu_uart.log -Pattern '^PASS image7_menu_uart:' -Quiet)){throw 'UART contention failed'}
      return
    }
    Invoke-VivadoTool 'xelab' @('key_press_debounce_tb', '-s', 'menu_key_sim')
    Invoke-VivadoTool 'xsim' @('menu_key_sim', '-runall', '-log', 'menu_key.log')
    if (!(Select-String -LiteralPath 'menu_key.log' -Pattern '^PASS key_press_debounce' -Quiet) -or
        (Select-String -LiteralPath 'menu_key.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {
        throw 'Menu physical GPIO key debounce regression failed'
    }

    Invoke-VivadoTool 'xelab' @('image7_menu_ctrl_tb', '-s', 'menu_ctrl_sim')
    Invoke-VivadoTool 'xsim' @('menu_ctrl_sim', '-runall', '-log', 'menu_ctrl.log')
    if (!(Select-String -LiteralPath 'menu_ctrl.log' -Pattern '^PASS image7_menu_ctrl' -Quiet) -or
        (Select-String -LiteralPath 'menu_ctrl.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {
        throw 'menu_ctrl regression failed'
    }

    Invoke-VivadoTool 'xelab' @('image7_menu_text_render_tb', '-s', 'menu_render_sim')
    Invoke-VivadoTool 'xsim' @('menu_render_sim', '-runall', '-log', 'menu_render.log')
    if (!(Select-String -LiteralPath 'menu_render.log' -Pattern '^PASS image7_menu_text_render' -Quiet) -or
        (Select-String -LiteralPath 'menu_render.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {
        throw 'menu_text_render regression failed'
    }

    foreach($block in @('image7_menu_config','image7_menu_cdc','image7_menu_uart','image7_tile_guard')) {
      Invoke-VivadoTool 'xelab' @(($block+'_tb'),'-s',$block)
      Invoke-VivadoTool 'xsim' @($block,'-runall','-log',($block+'.log'))
      if(!(Select-String -LiteralPath ($block+'.log') -Pattern ('^PASS '+$block) -Quiet) -or
         (Select-String -LiteralPath ($block+'.log') -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)){throw "$block failed"}
    }
    Write-Host "PASS image7 menu controller and overlay: $simDirectory"
}
finally {
    Pop-Location
}

