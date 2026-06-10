@echo off
echo ========================================
echo Fixing Windows Firewall for Python
echo ========================================
echo.
echo This will add Python to Windows Firewall exceptions
echo.
pause

echo Adding firewall rule...

REM Find Python executable
where python > python_path.txt 2>nul
set /p PYTHON_PATH=<python_path.txt
del python_path.txt

echo Found Python at: %PYTHON_PATH%
echo.

REM Add inbound rule
netsh advfirewall firewall add rule name="Python Regime Trading GUI" dir=in action=allow program="%PYTHON_PATH%" enable=yes

if errorlevel 1 (
    echo.
    echo ERROR: Failed to add firewall rule
    echo Please run this script as Administrator
    echo Right-click fix_firewall.bat and select "Run as Administrator"
    pause
    exit /b 1
)

echo.
echo ========================================
echo SUCCESS! Firewall rule added
echo ========================================
echo.
echo Now try these steps:
echo 1. Close MT5 EA (remove from chart)
echo 2. In Python GUI, click "Stop Server" then "Start Server"
echo 3. Reattach EA to MT5 chart
echo.
pause
