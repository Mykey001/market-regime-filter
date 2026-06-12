@echo off
echo ========================================
echo EA REGIME FILTER AUTO-INTEGRATION
echo LOCAL VERSION (No API Key Required!)
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

echo Python found. No dependencies needed for local version!
echo.

echo ========================================
echo STARTING LOCAL INTEGRATION SYSTEM
echo ========================================
echo.
echo This version uses RULE-BASED integration
echo NO AI API key required!
echo.
echo Drop your EA files (.mq5) into the 'input' folder
echo Integrated EAs will appear in the 'output' folder
echo.
echo Press Ctrl+C to stop the system
echo.

REM Run the local integration script
python auto_integrate_local.py

pause
