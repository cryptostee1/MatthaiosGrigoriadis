@echo off
setlocal
chcp 65001 >nul
set "SCRIPT=%~dp0GITONAS_CONNECT_FREE_SETUP.ps1"
if not exist "%SCRIPT%" (
 echo Missing GITONAS_CONNECT_FREE_SETUP.ps1 in the same folder.
 pause
 exit /b 1
)
echo GITONAS CONNECT - Free Windows Telegram setup
echo Bot token is only entered on this computer.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
if errorlevel 1 echo Setup not complete. Read the message above.
pause
endlocal
