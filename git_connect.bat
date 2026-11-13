@echo off
rem One-time: links this folder to github.com/Yotonick/battlebit so "git pull" works.
rem Needs Git for Windows. Local files are not deleted.
cd /d "%~dp0"
where git >nul 2>&1 || (echo Git is not installed: https://git-scm.com/download/win & pause & exit /b 1)
if exist ".git" (echo Already linked. & git pull & pause & exit /b 0)
git init -q -b main
git remote add origin https://github.com/Yotonick/battlebit.git
git fetch -q --depth 1 origin main || (echo Fetch failed & pause & exit /b 1)
git reset -q origin/main
git branch -q -u origin/main
git status --short
echo Done. Now the folder is linked to GitHub.
pause
