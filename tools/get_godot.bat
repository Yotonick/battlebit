@echo off
rem Finds Godot in .engine\, downloads it there on the first run.
rem Sets GODOT to the editor exe. Used by play.bat and editor.bat.
set GODOT_VER=4.7.1
set ENGINE=%~dp0..\.engine
set GODOT=%ENGINE%\Godot_v%GODOT_VER%-stable_win64.exe
if exist "%GODOT%" goto :ok
echo Downloading Godot %GODOT_VER% (about 85 MB, only once)...
if not exist "%ENGINE%" mkdir "%ENGINE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/godotengine/godot/releases/download/%GODOT_VER%-stable/Godot_v%GODOT_VER%-stable_win64.exe.zip' -OutFile '%ENGINE%\godot.zip'; Expand-Archive -Force '%ENGINE%\godot.zip' '%ENGINE%'; Remove-Item '%ENGINE%\godot.zip'"
if not exist "%GODOT%" (
  echo ERROR: could not download Godot. Check the internet connection.
  exit /b 1
)
:ok
if not exist "%~dp0..\game\.godot" (
  echo First run: importing project files...
  "%GODOT%" --headless --path "%~dp0..\game" --import >nul 2>&1
)
exit /b 0
