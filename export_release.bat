@echo off
setlocal
cd /d "%~dp0"

set GODOT=C:\Temp\Godot\Godot_v4.7-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=C:\Temp\Godot\Godot_v4.7-stable_win64.exe

echo Exporting release build to build\GodotFPS.exe ...
if not exist build mkdir build

"%GODOT%" --headless --path "%cd%" --export-release "Windows Desktop" "%cd%\build\GodotFPS.exe"
if errorlevel 1 (
  echo.
  echo Export failed. Install export templates in Godot:
  echo   Editor -^> Manage Export Templates -^> Download and Install
  echo Then re-run this script, or use Project -^> Export in the editor.
  pause
  exit /b 1
)

echo.
echo Done. Launching release build...
start "" "%cd%\build\GodotFPS.exe"
endlocal
