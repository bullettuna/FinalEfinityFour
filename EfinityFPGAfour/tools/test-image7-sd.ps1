param([string]$VivadoRoot='F:\vivado\Vivado\2024.2',[switch]$SuccessOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$sim=Join-Path $root 'work_sim/pose7_sd'
New-Item -ItemType Directory -Path $sim -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $root 'tmp/image7_mocap11_a/sdcard/MODEL7.BIN') -Destination (Join-Path $sim 'MODEL7.BIN')
function Run-Tool([string]$name,[string[]]$toolArgs){
 $quoted=($toolArgs|ForEach-Object{'"'+$_+'"'}) -join ' '
 & cmd.exe /d /c ('call "'+$VivadoRoot+'\settings64.bat" >nul && call "'+$VivadoRoot+'\bin\'+$name+'.bat" '+$quoted)
 if($LASTEXITCODE -ne 0){throw "$name failed"}
}
Push-Location $sim
try{
 $files=@('src/storage/sd4_command.v','src/storage/sd4_host.v','src/pose7/pose7_fat_reader.v','src/pose7/pose7_sd_boot.v')|ForEach-Object{Join-Path $root $_}
 Run-Tool xvlog (@('-i',$root)+$files)
 Run-Tool xvlog @('-sv',(Join-Path $root 'src/pose7/pose7_sd_card_tb.sv'),(Join-Path $root 'src/pose7/pose7_sd_boot_tb.sv'))
 $cases=@(@(1,2048,0),@(0,0,0))
 if(!$SuccessOnly){foreach($f in 1..7){$cases+=,@(1,2048,$f)}}
 foreach($c in $cases){
  $name="sd_$($c[0])_$($c[1])_$($c[2])"
  Run-Tool xelab @('pose7_sd_boot_tb','-s',$name,'-generic_top',"SDSC=$($c[0])",'-generic_top',"VOLUME_LBA=$($c[1])",'-generic_top',"FAULT=$($c[2])")
  Run-Tool xsim @($name,'-runall','-log',"$name.log")
  if(!(Select-String -Path "$name.log" -Pattern '^PASS SD4 boot' -Quiet) -or (Select-String -Path "$name.log" -Pattern 'Fatal:|ERROR:|FAIL' -Quiet)){throw "SD test failed: $name"}
 }
}finally{Pop-Location}
