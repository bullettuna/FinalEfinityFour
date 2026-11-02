param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$FullHD,[ValidateSet(0,1)][int]$InitialMedian=0,[switch]$VideoTiming)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$width=64;$height=48
if($FullHD){$width=1920;$height=1080}
if($VideoTiming){$testTop='image1_video_timing_tb'}else{$testTop='image1_median_canny_tb'}
$simDirectory=Join-Path $projectRoot "work_sim/image1_median_${width}x${height}"
if($InitialMedian -eq 1){$simDirectory+='_boot_on'}
if($VideoTiming){$simDirectory+='_video_timing'}
New-Item -ItemType Directory -Path $simDirectory -Force | Out-Null
function Invoke-VivadoTool([string]$name,[string[]]$toolArguments){
 $quoted=($toolArguments|ForEach-Object{'"'+$_+'"'})-join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
& python (Join-Path $PSScriptRoot 'check-image1-median.py')
if($LASTEXITCODE -ne 0){throw 'Image1 median top-level wiring failed'}
$sources=@('src/lcd_para.v','src/lcd_driver.v','src/isp/Line_Shift_RAM_8Bit.v','src/isp/VIP_Matrix_Generate_3X3_8Bit.v')|ForEach-Object{Join-Path $projectRoot $_}
$sources+=Get-ChildItem (Join-Path $projectRoot 'src/vision') -Filter '*.v' -File | Where-Object{$_.Name -notmatch '_tb\.v$'} | Select-Object -ExpandProperty FullName
$sources+=Join-Path $projectRoot "src/vision/$testTop.v"
Push-Location $simDirectory
try{
 Invoke-VivadoTool 'xvlog' (@('-i',$projectRoot)+$sources)
 $generics=@('-generic_top',"WIDTH=$width",'-generic_top',"HEIGHT=$height")
 if(!$VideoTiming){$generics+=@('-generic_top',"INITIAL_MEDIAN=$InitialMedian")}elseif($FullHD){$generics+=@('-generic_top','FRAMES=8')}
 Invoke-VivadoTool 'xelab' (@($testTop)+$generics+@('-s','image1_median'))
 Invoke-VivadoTool 'xsim' @('image1_median','-runall','-log','image1_median.log')
 if(!(Select-String -LiteralPath 'image1_median.log' -Pattern '^PASS ' -Quiet) -or
    (Select-String -LiteralPath 'image1_median.log' -Pattern 'Fatal:|Error:|ERROR:|FAIL' -Quiet)){throw 'Image1 median/Canny regression failed'}
 Write-Host "PASS image1 median regression: $simDirectory"
}finally{Pop-Location}
