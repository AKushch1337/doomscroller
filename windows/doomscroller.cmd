@echo off
rem doomscroller for Windows: runs doomscroller.ps1 next to this file.
rem Put this folder on PATH to use the `doomscroller` command.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0doomscroller.ps1" %*
exit /b %ERRORLEVEL%
