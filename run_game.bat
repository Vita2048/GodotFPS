@echo off
REM Run the game WITHOUT the Godot editor / debugger (much faster).
set GODOT=C:\Temp\Godot\Godot_v4.7-stable_win64.exe
cd /d "%~dp0"
"%GODOT%" --path "%cd%"
