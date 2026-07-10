@echo off
setlocal
set WEBUIDIR=%~dp0
set NODE=C:\Program Files\nodejs\node.exe

if not exist "%NODE%" (
    echo ERROR: Node.js not found at %NODE%
    pause
    exit /b 1
)

cd /d "%WEBUIDIR%"
echo ============================================
echo  DekatronPC WebUI - Dev Server
echo ============================================
echo.
echo Starting Vite dev server on http://localhost:5173
echo Press Ctrl+C to stop.
echo.
"%NODE%" ".\node_modules\vite\bin\vite.js" --host

pause
