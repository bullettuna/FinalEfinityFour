param(
    [string]$VivadoRoot = 'F:\vivado\Vivado\2024.2'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$simDirectory = Join-Path $projectRoot 'work_sim/image1_menu'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null

function Invoke-VivadoTool([string]$name, [string[]]$toolArguments) {
    $quoted = ($toolArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    & cmd.exe /d /c ('call "' + $VivadoRoot + '\settings64.bat" >nul && call "' + $VivadoRoot + '\bin\' + $name + '.bat" ' + $quoted)
    if ($LASTEXITCODE -ne 0) { throw "$name failed" }
}

$sources = @(
    'src/ui/menu_font_8x8.v',
    'src/ui/menu_text_rom.v',
    'src/ui/key_press_debounce.v',
    'src/ui/menu_ctrl.v',
    'src/ui/menu_text_render.v',
    'src/ui/key_press_debounce_tb.sv',
    'src/ui/menu_ctrl_tb.sv',
    'src/ui/menu_text_render_tb.sv'
) | ForEach-Object { Join-Path $projectRoot $_ }

Push-Location $simDirectory
try {
    Invoke-VivadoTool 'xvlog' (@('-sv', '-i', $projectRoot) + $sources)

    Invoke-VivadoTool 'xelab' @('key_press_debounce_tb', '-s', 'menu_key_sim')
    Invoke-VivadoTool 'xsim' @('menu_key_sim', '-runall', '-log', 'menu_key.log')
    if (!(Select-String -LiteralPath 'menu_key.log' -Pattern '^PASS key_press_debounce' -Quiet) -or
        (Select-String -LiteralPath 'menu_key.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {
        throw 'Menu physical GPIO key debounce regression failed'
    }

    Invoke-VivadoTool 'xelab' @('menu_ctrl_tb', '-s', 'menu_ctrl_sim')
    Invoke-VivadoTool 'xsim' @('menu_ctrl_sim', '-runall', '-log', 'menu_ctrl.log')
    if (!(Select-String -LiteralPath 'menu_ctrl.log' -Pattern '^PASS menu_ctrl' -Quiet) -or
        (Select-String -LiteralPath 'menu_ctrl.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {
        throw 'menu_ctrl regression failed'
    }

    Invoke-VivadoTool 'xelab' @('menu_text_render_tb', '-s', 'menu_render_sim')
    Invoke-VivadoTool 'xsim' @('menu_render_sim', '-runall', '-log', 'menu_render.log')
    if (!(Select-String -LiteralPath 'menu_render.log' -Pattern '^PASS menu_text_render' -Quiet) -or
        (Select-String -LiteralPath 'menu_render.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {
        throw 'menu_text_render regression failed'
    }

    Write-Host "PASS image1 menu controller and overlay: $simDirectory"
}
finally {
    Pop-Location
}
