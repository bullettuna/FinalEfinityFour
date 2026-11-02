param(
    [switch]$PurgeOutflow
)

# Recycle Efinity/Vivado generated artifacts after a successful build.  The
# default keeps outflow\Ti60_Demo.bit and .hex for programming; pass
# -PurgeOutflow only after copying those release files somewhere safe.
$projectRoot = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName Microsoft.VisualBasic
$recycle = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
$ui = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs

function Send-GeneratedDirectoryToRecycleBin([string]$path) {
    if (Test-Path -LiteralPath $path) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path, $ui, $recycle)
    }
}
function Send-GeneratedFileToRecycleBin([string]$path) {
    if (Test-Path -LiteralPath $path) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, $ui, $recycle)
    }
}

Get-ChildItem -LiteralPath $projectRoot -Directory -Force |
    Where-Object { $_.Name -like 'work_*' -or $_.Name -eq 'xsim.dir' } |
    ForEach-Object {
        # A few legacy work folders contain tracked Efinity placeholders.
        # Leave those intact; only remove wholly generated directories.
        $tracked = @(git -C $projectRoot ls-files -- "$($_.Name)/*")
        if ($tracked.Count -eq 0) {
            Send-GeneratedDirectoryToRecycleBin $_.FullName
        }
    }

@(
    'Ti60_PhotoCaptureIntegration.*', 'Ti60_PhotoPipeline.*',
    'photo_capture_check.*', 'debug_profile.mark_debug.json',
    'xelab.log', 'xelab.pb', 'xsim.jou', 'xsim.log', 'xvlog.log', 'xvlog.pb',
    'xsim_*.backup.jou', 'xsim_*.backup.log'
) | ForEach-Object {
    Get-ChildItem -LiteralPath $projectRoot -File -Force -Filter $_ -ErrorAction SilentlyContinue |
        ForEach-Object { Send-GeneratedFileToRecycleBin $_.FullName }
}

if ($PurgeOutflow) {
    Send-GeneratedDirectoryToRecycleBin (Join-Path $projectRoot 'outflow')
}
