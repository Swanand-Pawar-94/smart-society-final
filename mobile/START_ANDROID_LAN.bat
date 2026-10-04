@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Smart Society - Physical Android Device via Wi-Fi (LAN Mode)
:: ============================================================
:: Automatically detects PC's active Wi-Fi/Ethernet IPv4 address
:: and launches Flutter with the exact dynamic API_BASE_URL.
:: ============================================================

set SCRIPT_DIR=%~dp0
set TEMP_IP_FILE=%TEMP%\smartsociety_lan_ip_%RANDOM%.txt

if exist "%TEMP_IP_FILE%" del /f /q "%TEMP_IP_FILE%" >nul 2>&1

:: -- STEP 1: Detect Active PC LAN IPv4 Address ----------------
echo [STEP 1] Detecting active PC LAN IPv4 address...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%detect_lan_ip.ps1" -OutputFile "%TEMP_IP_FILE%"

if exist "%TEMP_IP_FILE%" (
    set /p PC_IP=<"%TEMP_IP_FILE%"
    del /f /q "%TEMP_IP_FILE%" >nul 2>&1
)

if not defined PC_IP (
    echo.
    echo [ERROR] Could not automatically detect active LAN IPv4 address!
    echo Please make sure your PC is connected to Wi-Fi or local network.
    echo.
    pause
    exit /b 1
)

set API_URL=http://%PC_IP%:8000/api

:: -- STEP 2: Verify Laravel Backend on Port 8000 --------------
echo [STEP 2] Verifying Laravel API on port 8000...
powershell.exe -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/api/health' -UseBasicParsing -TimeoutSec 2; exit 0 } catch { exit 1 }"
if %errorlevel% neq 0 (
    echo [INFO] Laravel is not responding on port 8000.
    echo        Starting Laravel server on 0.0.0.0:8000...
    start "Laravel API Server" /min cmd /c "cd /d D:\SmartSociety\backend && php artisan serve --host=0.0.0.0 --port=8000"
    timeout /t 3 /nobreak >nul
) else (
    echo [OK] Laravel backend is running.
)

:: -- STEP 3: Print Banner (Exact Required Format) -------------
echo.
echo ========================================
echo Smart Society - Android LAN Mode
echo ========================================
echo PC IP: %PC_IP%
echo API URL: %API_URL%
echo Starting Flutter...
echo ========================================
echo.

:: -- STEP 4: Launch Flutter -----------------------------------
cd /d "%SCRIPT_DIR%"
flutter run --dart-define=API_BASE_URL=%API_URL% --dart-define=API_ENV=lan %*

endlocal