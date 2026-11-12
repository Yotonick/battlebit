@echo off
rem Runs the game. Downloads Godot into .engine\ on the first run.
setlocal
call "%~dp0tools\get_godot.bat" || (pause & exit /b 1)
start "" "%GODOT%" --path "%~dp0game" %*
