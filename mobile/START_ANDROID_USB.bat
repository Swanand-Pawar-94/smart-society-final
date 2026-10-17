@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Nivora - Physical Android Device via USB (ADB Reverse)
:: ============================================================
:: Connects physical phone to PC via USB cable.
:: Uses ADB reverse to map phone port 8000 -> PC port 8000.
:: ============================================================

set SCRIPT_DIR=%~dp0

:: -- STEP 1: Check whether ADB is available -------------------
echo [STEP 1] Checking ADB availability...
set ADB=
if defined ADB_CUSTOM if exist "%ADB_CUSTOM%" set ADB=%ADB_CUSTOM%
if not defined ADB where adb.exe >nul 2>&1 && set ADB=adb.exe
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if not defined ADB if exist "%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe" set ADB=%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe
if not defined ADB if exist "C:\Android\platform-tools\adb.exe" set ADB=C:\Android\platform-tools\adb.exe

if not defined ADB (
    echo [ERROR] adb.exe could not be found!
    echo Please ensure Android SDK platform-tools is installed.
    echo Default path: %%LOCALAPPDATA%%\Android\Sdk\platform-tools\adb.exe
    pause
    exit /b 1
)
echo [OK] ADB found: "%ADB%"

:: -- STEP 2: Detect Connected Android Device ------------------
echo.
echo [STEP 2] Detecting connected Android device...
set DEVICE_ID=
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
    if "%%b"=="device" (
        set DEVICE_ID=%%a
    )
)

if not defined DEVICE_ID (
    echo [ERROR] No authorized Android device detected over USB!
    echo.
    echo Checklist:
    echo   1. Ensure phone is connected via USB cable.
    echo   2. Enable USB Debugging in Developer Options on your phone.
    echo   3. Accept the "Allow USB debugging?" prompt on the phone screen.
    echo   4. If prompted on the phone, select "File Transfer / Android Auto" mode.
    pause
    exit /b 1
)
echo [OK] Connected device: %DEVICE_ID%

:: -- STEP 3: Setup ADB Reverse Mapping ------------------------
echo.
echo [STEP 3] Setting up ADB reverse (phone:8000 -> PC:8000)...
"%ADB%" -s %DEVICE_ID% reverse tcp:8000 tcp:8000
if %errorlevel% neq 0 (
    echo [ERROR] Failed to set up adb reverse.
    pause
    exit /b 1
)

:: -- STEP 4: Verify the Reverse Mapping -----------------------
echo.
echo [STEP 4] Verifying ADB reverse mapping...
"%ADB%" -s %DEVICE_ID% reverse --list
echo [OK] Reverse mapping confirmed.

:: -- STEP 5: Start Laravel on Port 8000 -----------------------
echo.
echo [STEP 5] Checking Laravel backend on port 8000...
powershell.exe -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/api/health' -UseBasicParsing -TimeoutSec 2; exit 0 } catch { exit 1 }"
if %errorlevel% neq 0 (
    echo [INFO] Starting Laravel API server on 0.0.0.0:8000...
    start "Laravel API Server" /min cmd /c "cd /d D:\SmartSociety\backend && php artisan serve --host=0.0.0.0 --port=8000"
    timeout /t 3 /nobreak >nul
) else (
    echo [OK] Laravel backend is running.
)

:: -- STEP 6: Launch Flutter with USB Dart Defines -------------
echo.
echo ========================================
echo Nivora - Android USB Mode
echo ========================================
echo Device         : %DEVICE_ID%
echo API URL        : http://127.0.0.1:8000/api
echo Reverse Tunnel : Active (tcp:8000)
echo Starting Flutter...
echo ========================================
echo.

cd /d "%SCRIPT_DIR%"
flutter run -d %DEVICE_ID% --dart-define=API_BASE_URL=http://127.0.0.1:8000/api --dart-define=API_ENV=usb %*

endlocal