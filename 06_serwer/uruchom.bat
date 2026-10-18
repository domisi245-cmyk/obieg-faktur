@echo off
chcp 65001 >nul
title Obieg faktur - serwer
cd /d "%~dp0"

if not exist node_modules (
  echo Instaluje biblioteki - tylko za pierwszym razem...
  call npm install --no-audit --no-fund
)

echo.
echo Aplikacja: http://localhost:3000
echo Zamknij to okno, zeby zatrzymac serwer.
echo.
start "" cmd /c "timeout /t 2 >nul & start http://localhost:3000"
node serwer.js
pause
