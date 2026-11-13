@echo off
rem Lighter renderer (Mobile) + DirectX 12.
call "%~dp0play.bat" --rendering-method mobile --rendering-driver d3d12 %*
