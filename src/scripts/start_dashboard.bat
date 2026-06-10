@echo off
cls
echo.
echo ╔══════════════════════════════════════════════════════════╗
echo ║  ML Market Regime Trading System - Dashboard Launcher   ║
echo ║  Version 1.0 - Professional Edition                      ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

REM Change to project root directory
cd /d "%~dp0..\.."

REM Check if Python is available
echo [1/5] Checking Python installation...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo.
    echo Please install Python 3.8+ from https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)
python --version
echo [OK] Python found
echo.

REM Check if PyQt5 is installed
echo [2/5] Checking PyQt5 installation...
python -c "import PyQt5" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PyQt5 is not installed
    echo.
    echo To install PyQt5:
    echo   pip install PyQt5
    echo.
    echo Or install all dependencies:
    echo   pip install -r config\requirements.txt
    echo.
    pause
    exit /b 1
)
echo [OK] PyQt5 found
echo.

REM Check if MetaTrader5 is installed
echo [3/5] Checking MetaTrader5 Python package...
python -c "import MetaTrader5" >nul 2>&1
if errorlevel 1 (
    echo [ERROR] MetaTrader5 package not installed
    echo.
    echo To install:
    echo   pip install MetaTrader5
    echo.
    pause
    exit /b 1
)
echo [OK] MetaTrader5 package found
echo.

REM Check if model files exist
echo [4/5] Checking ML model files...
if not exist "models\market_regime_gmm.pkl" (
    echo [ERROR] Model file not found: models\market_regime_gmm.pkl
    echo.
    echo Please ensure model files are in the models\ directory
    pause
    exit /b 1
)
if not exist "models\scaler.pkl" (
    echo [ERROR] Scaler file not found: models\scaler.pkl
    echo.
    echo Please ensure model files are in the models\ directory
    pause
    exit /b 1
)
echo [OK] Model files found
echo.

REM Launch dashboard
echo [5/5] Launching dashboard...
echo.
echo ─────────────────────────────────────────────────────────
echo  IMPORTANT NOTES:
echo  • Ensure MetaTrader 5 is running and logged in
echo  • Wait for regime predictions to load (warmup period)
echo  • Configure filters in the GUI Filter Configuration tab
echo  • Server will start on port 9090 for EA connection
echo ─────────────────────────────────────────────────────────
echo.
timeout /t 2 >nul

python src\python\mt5_regime_gui_pyqt.py

if errorlevel 1 (
    echo.
    echo [ERROR] Dashboard failed to start
    echo Check the error messages above
    echo.
    echo Common solutions:
    echo  1. Verify MT5 is running and logged in
    echo  2. Check all dependencies: pip install -r config\requirements.txt
    echo  3. Run tests\test_installation.py to diagnose
    echo.
    pause
)

exit /b 0
