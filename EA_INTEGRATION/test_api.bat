@echo off
echo ========================================
echo GOOGLE GEMINI API CONNECTION TEST
echo ========================================
echo.

python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed
    echo Please install Python 3.8+ from https://www.python.org/
    pause
    exit /b 1
)

echo Installing dependencies...
python -m pip install -q google-generativeai
echo.

echo Testing API connection...
echo.
python test_api.py

echo.
pause
