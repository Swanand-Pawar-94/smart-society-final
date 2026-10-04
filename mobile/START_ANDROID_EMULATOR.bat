@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Smart Society - Android Emulator Launcher
:: ============================================================
:: Maps Android Emulator 10.0.2.2 loopback to host PC port 8000.
:: ============================================================

set SCRIPT_DIR=%~dp0

:: -- STEP 1: Verify Laravel Backend on Port 8000 --------------
echo [STEP 1] Checking Laravel backend on port 8000...
powershell.exe -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/api/health' -UseBasicParsing -TimeoutSec 2; exit 0 } catch { exit 1 }"
if %errorlevel% neq 0 (
    echo [INFO] Starting Laravel API server on 0.0.0.0:8000...
    start "Laravel API Server" /min cmd /c "cd /d D:\SmartSociety\backend && php artisan serve --host=0.0.0.0 --port=8000"
    timeout /t 3 /nobreak >nul
) else (
    echo [OK] Laravel backend is running.
)

:: -- STEP 2: Launch Flutter in Emulator Mode ------------------
echo.
echo ========================================
echo Smart Society - Android Emulator Mode
echo ========================================
echo API URL: http://10.0.2.2:8000/api
echo Starting Flutter...
echo ========================================
echo.

cd /d "%SCRIPT_DIR%"
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api --dart-define=API_ENV=emulator %*

endlocal