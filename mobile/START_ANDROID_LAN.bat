@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Nivora - Physical Android Device via Wi-Fi (LAN Mode)
:: ============================================================
:: Automatically detects PC's active Wi-Fi/Ethernet IPv4 address,
:: verifies Laravel backend on LAN IP, checks connected device,
:: and launches Flutter with the exact dynamic API_BASE_URL.
:: ============================================================

set SCRIPT_DIR=%~dp0
set TEMP_IP_FILE=%TEMP%\nivora_lan_ip_%RANDOM%.txt

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

:: -- STEP 2: Verify Laravel Backend on LAN IP:Port 8000 -------
echo [STEP 2] Verifying Laravel API on LAN (http://%PC_IP%:8000/api/health)...
powershell.exe -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://%PC_IP%:8000/api/health' -UseBasicParsing -TimeoutSec 3; exit 0 } catch { exit 1 }"
if %errorlevel% neq 0 (
    echo [INFO] Laravel is not responding on http://%PC_IP%:8000/api/health.
    echo        Starting Laravel server on 0.0.0.0:8000...
    :: If a stale process is bound to 127.0.0.1 only, terminate it
    powershell.exe -NoProfile -Command "$conn = Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue; if ($conn) { $pids = $conn.OwningProcess | Select-Object -Unique; foreach ($p in $pids) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } }"
    start "Laravel API Server" /min cmd /c "cd /d D:\SmartSociety\backend && php artisan serve --host=0.0.0.0 --port=8000"
    timeout /t 4 /nobreak >nul
    powershell.exe -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://%PC_IP%:8000/api/health' -UseBasicParsing -TimeoutSec 3; exit 0 } catch { exit 1 }"
    if %errorlevel% neq 0 (
        echo [WARNING] Laravel started, but http://%PC_IP%:8000/api/health is still not reachable.
        echo Please ensure Windows Firewall allows incoming connections on port 8000 for Private networks.
    ) else (
        echo [OK] Laravel backend is running and reachable on LAN.
    )
) else (
    echo [OK] Laravel backend is running and reachable on LAN.
)

:: -- STEP 3: Detect Android Device & Subnet -------------------
echo.
echo [STEP 3] Checking connected Android device...
set ADB=
if defined ADB_CUSTOM if exist "%ADB_CUSTOM%" set ADB=%ADB_CUSTOM%
if not defined ADB where adb.exe >nul 2>&1 && set ADB=adb.exe
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if not defined ADB if exist "%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe" set ADB=%USERPROFILE%\AppData\Local\Android\Sdk\platform-tools\adb.exe
if not defined ADB if exist "C:\Android\platform-tools\adb.exe" set ADB=C:\Android\platform-tools\adb.exe

set DEVICE_ID=
set DEVICE_STATUS=No USB device detected (Flutter will search for available devices)
if defined ADB (
    for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
        if "%%b"=="device" (
            set DEVICE_ID=%%a
            set DEVICE_STATUS=%%a (USB Connected)
        )
    )
)

:: Subnet check if device is reachable over ADB
if defined DEVICE_ID (
    echo [OK] Detected connected device: %DEVICE_ID%
    for /f "tokens=2 delims=/ " %%p in ('"%ADB%" -s %DEVICE_ID% shell "ip -f inet addr show wlan0 2>/dev/null" ^| findstr /i "inet "') do (
        set DEVICE_WLAN_IP=%%p
    )
    if defined DEVICE_WLAN_IP (
        echo [INFO] Phone Wi-Fi IP: !DEVICE_WLAN_IP!
        :: Extract first three octets of PC_IP and DEVICE_WLAN_IP for subnet check
        for /f "tokens=1,2,3 delims=." %%a in ("%PC_IP%") do set PC_SUBNET=%%a.%%b.%%c
        for /f "tokens=1,2,3 delims=." %%a in ("!DEVICE_WLAN_IP!") do set PHONE_SUBNET=%%a.%%b.%%c
        if not "!PC_SUBNET!"=="!PHONE_SUBNET!" (
            echo.
            echo [WARNING] Subnet mismatch detected!
            echo           PC Subnet    : !PC_SUBNET!.x (%PC_IP%)
            echo           Phone Subnet : !PHONE_SUBNET!.x (!DEVICE_WLAN_IP!)
            echo           Please ensure both PC and phone are connected to the SAME Wi-Fi network.
            echo.
        ) else (
            echo [OK] Phone and PC are on the same Wi-Fi subnet (!PC_SUBNET!.x).
        )
    )
) else (
    echo [INFO] Device Status: %DEVICE_STATUS%
)

:: -- STEP 4: Print Banner -------------------------------------
echo.
echo ========================================
echo Nivora - Android LAN Mode
echo ========================================
echo PC IP        : %PC_IP%
echo API URL      : %API_URL%
echo Device Status: %DEVICE_STATUS%
echo Starting Flutter...
echo ========================================
echo.

:: -- STEP 5: Launch Flutter -----------------------------------
cd /d "%SCRIPT_DIR%"
if defined DEVICE_ID (
    flutter run -d %DEVICE_ID% --dart-define=API_BASE_URL=%API_URL% --dart-define=API_ENV=lan %*
) else (
    flutter run --dart-define=API_BASE_URL=%API_URL% --dart-define=API_ENV=lan %*
)

endlocal