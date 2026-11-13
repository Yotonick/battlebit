@echo off
rem Same game, but through DirectX 12 instead of Vulkan (sometimes faster on AMD).
call "%~dp0play.bat" --rendering-driver d3d12 %*
