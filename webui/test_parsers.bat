@echo off
setlocal enabledelayedexpansion
set NODE=C:\Program Files\nodejs\node.exe
if not exist "%NODE%" (
    echo ERROR: Node.js not found at %NODE%
    echo Download from https://nodejs.org/ and install to default location.
    pause
    exit /b 1
)
set SCRIPT=%~dp0test_parsers.mjs
set LIB=%~dp0..\rtl\run\vtube_cells.lib
set VERILOG=%~dp0..\rtl\run\IpLine_synth.v
if not exist "%LIB%" (
    echo ERROR: Liberty file not found: %LIB%
    pause
    exit /b 1
)
if not exist "%VERILOG%" (
    echo ERROR: Verilog file not found: %VERILOG%
    pause
    exit /b 1
)
echo ============================================
echo  DekatronPC Stage 1 - Parser Tests
echo ============================================
echo.
echo Liberty:  %LIB%
echo Verilog:  %VERILOG%
echo.
"%NODE%" "%SCRIPT%" "%LIB%" "%VERILOG%" 2>&1
if errorlevel 1 (
    echo.
    echo TESTS FAILED
    pause
    exit /b 1
)
echo.
echo TESTS PASSED
pause
exit /b 0
