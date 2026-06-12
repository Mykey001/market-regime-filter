@echo off
echo ========================================
echo EA REGIME FILTER AUTO-INTEGRATION
echo Powered by NVIDIA AI
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8+ from https://www.python.org/
    pause
    exit /b 1
)

echo Python found. Checking dependencies...
echo.

REM Install required packages
echo Installing required packages...
python -m pip install -q -r requirements.txt
if errorlevel 1 (
    echo.
    echo WARNING: Some packages may have failed to install
    echo Continuing anyway...
    echo.
)

echo.
echo ========================================
echo STARTING AUTO-INTEGRATION SYSTEM
echo ========================================
echo.
echo Drop your EA files (.mq5) into the 'input' folder
echo Integrated EAs will appear in the 'output' folder
echo.
echo Press Ctrl+C to stop the system
echo.

REM Run the integration script
python auto_integrate.py

pause
