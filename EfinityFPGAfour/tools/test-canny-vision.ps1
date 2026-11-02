param([string]$VivadoRoot='F:\vivado\Vivado\2024.2', [string[]]$Tests=@(
    'grey_tb','canny_kernel_tb','canny_edge_tb','rgb_edge_colorizer_tb',
    'binary_close_rgb_tb','shape_overlay_tb','shape_hough_rectangle_tb',
    'median3x3_kernel_tb','gray_canny_alignment_tb','canny_color_border_tb'))
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$simDirectory=Join-Path $projectRoot 'work_sim/canny_vision'
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-VivadoTool([string]$name,[string[]]$toolArguments) {
    $quotedArguments=($toolArguments | ForEach-Object { '"'+$_+'"' }) -join ' '
    & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quotedArguments)
    if($LASTEXITCODE -ne 0){throw "$name failed"}
}
function Test-Snapshot([string]$top) {
    Invoke-VivadoTool 'xelab' @($top,'-s',$top)
    Invoke-VivadoTool 'xsim' @($top,'-runall','-log',"$top.log")
    if(!(Select-String -LiteralPath "$top.log" -Pattern '^PASS|^RESULT: ALL.*PASSED' -Quiet) -or
       (Select-String -LiteralPath "$top.log" -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {throw "Regression failed: $simDirectory/$top.log"}
}
$sourceFiles=@(
 'src/isp/Line_Shift_RAM_8Bit.v', 'src/isp/VIP_Matrix_Generate_3X3_8Bit.v',
 'src/vision/grey_tb.v', 'src/vision/canny_kernel_tb.v',
 'src/vision/canny_edge_tb.v', 'src/vision/rgb_edge_colorizer_tb.v',
 'src/vision/binary_close_rgb_tb.v', 'src/vision/shape_overlay_tb.v',
 'src/vision/shape_hough_rectangle_tb.v',
 'src/vision/median3x3_kernel_tb.v'
 'src/vision/gray_canny_alignment_tb.v'
 'src/vision/canny_color_border_tb.v'
) | ForEach-Object {Join-Path $projectRoot $_}
$sourceFiles += Get-ChildItem (Join-Path $projectRoot 'src/vision') -Filter '*.v' -File |
    Where-Object {$_.Name -notmatch '_tb\.v$'} | Select-Object -ExpandProperty FullName
Push-Location $simDirectory
try {
    # RTL is Verilog-2000 (e.g. Gaussian's "cross" is legal there).
    # Only testbenches need SystemVerilog for assertions.
    $rtlFiles=$sourceFiles | Where-Object {$_ -notmatch '_tb\.v$'}
    $tbFiles=$sourceFiles | Where-Object {$_ -match '_tb\.v$'}
    Invoke-VivadoTool 'xvlog' (@('-i',$projectRoot)+$rtlFiles)
    Invoke-VivadoTool 'xvlog' (@('-sv')+$tbFiles)
    foreach($top in $Tests) {
        Test-Snapshot $top
    }
    if($Tests -contains 'gray_canny_alignment_tb') {
        Invoke-VivadoTool 'xelab' @('gray_canny_alignment_tb','-generic_top','WIDTH=1920','-s','gray_canny_alignment_1920')
        Invoke-VivadoTool 'xsim' @('gray_canny_alignment_1920','-runall','-log','gray_canny_alignment_1920.log')
        if(!(Select-String -LiteralPath 'gray_canny_alignment_1920.log' -Pattern '^PASS ' -Quiet) -or
           (Select-String -LiteralPath 'gray_canny_alignment_1920.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {throw '1920-wide raw gray alignment failed'}
    }
    if($Tests -contains 'canny_color_border_tb') {
        Invoke-VivadoTool 'xelab' @('canny_color_border_tb','-generic_top','WIDTH=1920','-s','canny_color_border_1920')
        Invoke-VivadoTool 'xsim' @('canny_color_border_1920','-runall','-log','canny_color_border_1920.log')
        if(!(Select-String -LiteralPath 'canny_color_border_1920.log' -Pattern '^PASS ' -Quiet) -or
           (Select-String -LiteralPath 'canny_color_border_1920.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)) {throw '1920-wide colour border regression failed'}
    }
    Write-Host ('PASS selected Canny vision/shape regressions: '+($Tests -join ', '))
} finally {Pop-Location}
