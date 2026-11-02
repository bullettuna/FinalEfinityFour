@echo off
setlocal EnableExtensions
cd /d "%~dp0FPGA_GAME"

set "PYEXE="
set "LOGDIR=%~dp0FPGA_GAME\logs"
set "LOGFILE=%LOGDIR%\launcher.log"

echo [SoulRider] looking for a Python that already has cv2 / numpy / scipy / PIL / ultralytics ...

REM 1) The proven interpreter on this machine (Python 3.13.11 + torch 2.11.0+cu128 + ultralytics 8.4.183)
call :probe "%~dp0..\..\FPGA_GAME\.venv-fourpoint\Scripts\python.exe"
REM 2) Windows py launcher
if not defined PYEXE call :probe "py -3"
REM 3) whatever "python" resolves to on PATH
if not defined PYEXE call :probe "python"

if not defined PYEXE goto no_python

echo [SoulRider] using: %PYEXE%
echo [SoulRider] starting bridge on http://127.0.0.1:8765 ...

if not exist "%LOGDIR%" mkdir "%LOGDIR%"
start "SoulRiderBridge" /min cmd /c ""%PYEXE%" bridge.py --no-browser --detection-mode eleven_point > "%LOGFILE%" 2>&1"

set "TRIES=0"

:wait_ready
curl.exe -s --max-time 1 "http://127.0.0.1:8765/state" >nul 2>nul
if not errorlevel 1 goto open_game
set /a TRIES+=1
if %TRIES% GEQ 80 goto not_ready
powershell.exe -NoProfile -Command "Start-Sleep -Milliseconds 250" >nul 2>nul
goto wait_ready

:open_game
echo [SoulRider] bridge is ready. Opening the game ...
start "" "http://127.0.0.1:8765/game/"
echo.
echo   game   : http://127.0.0.1:8765/game/
echo   debug  : http://127.0.0.1:8765/game/debug.html
echo   panel  : http://127.0.0.1:8765/panel
echo   state  : http://127.0.0.1:8765/state
echo.
echo This window can be closed. The bridge keeps running in a minimised window.
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 5" >nul 2>nul
exit /b 0

:not_ready
echo.
echo [SoulRider] bridge did not answer on port 8765 within 20 seconds.
echo.
if exist "%LOGFILE%" (
    echo --- last lines of launcher.log ---
    powershell.exe -NoProfile -Command "Get-Content -LiteralPath '%LOGFILE%' -Tail 25"
    echo -----------------------------------
)
echo.
echo Run this by hand to see the full error:
echo   cd /d "%~dp0FPGA_GAME"
echo   "%PYEXE%" bridge.py --no-browser --detection-mode eleven_point
echo.
pause
exit /b 1

:no_python
echo.
echo [SoulRider] No usable Python interpreter was found.
echo.
echo You need Python 3.10+ with these packages installed:
echo   opencv-python  ultralytics  scipy  numpy  Pillow
echo.
echo If Python is not installed yet, download the 64-bit installer here:
echo   https://www.python.org/downloads/release/python-31311/
echo   file: python-3.13.11-amd64.exe
echo   IMPORTANT: tick "Add python.exe to PATH" on the first screen.
echo.
echo Then install the packages once:
echo   py -3 -m pip install opencv-python ultralytics
echo.
pause
exit /b 1

:probe
if defined PYEXE exit /b 0
if "%~1"=="" exit /b 0
%~1 -c "import cv2, numpy, scipy, PIL, ultralytics" >nul 2>nul
if errorlevel 1 exit /b 0
for /f "usebackq delims=" %%P in (`%~1 -c "import sys;print(sys.executable)"`) do set "PYEXE=%%P"
exit /b 0
