@echo off
rem Opens the project in the Godot editor (F5 there runs the game).
setlocal
call "%~dp0tools\get_godot.bat" || (pause & exit /b 1)
start "" "%GODOT%" --path "%~dp0game" -e
