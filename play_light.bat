@echo off
rem Lighter Godot renderer (Mobile). Fewer effects, usually much faster on weak GPUs.
call "%~dp0play.bat" --rendering-method mobile %*
