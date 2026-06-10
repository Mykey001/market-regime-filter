@echo off
echo ========================================
echo Market Regime Trading GUI Launcher
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8 or later
    pause
    exit /b 1
)

echo Python detected: 
python --version
echo.

REM Check if required files exist
if not exist "market_regime_gmm.pkl" (
    echo ERROR: market_regime_gmm.pkl not found
    echo Please ensure all model files are in the same directory
    pause
    exit /b 1
)

if not exist "scaler.pkl" (
    echo ERROR: scaler.pkl not found
    echo Please ensure all model files are in the same directory
    pause
    exit /b 1
)

if not exist "feature_engine.py" (
    echo ERROR: feature_engine.py not found
    echo Please ensure all model files are in the same directory
    pause
    exit /b 1
)

echo All required files found!
echo.

REM Check if dependencies are installed
echo Checking dependencies...
python -c "import PyQt5" >nul 2>&1
if errorlevel 1 (
    echo.
    echo WARNING: PyQt5 not found
    echo Installing dependencies from requirements.txt...
    echo.
    pip install -r requirements.txt
    if errorlevel 1 (
        echo.
        echo ERROR: Failed to install dependencies
        echo Please run manually: pip install -r requirements.txt
        pause
        exit /b 1
    )
)

echo.
echo Starting Market Regime Trading GUI...
echo.
python regime_trading_gui.py

if errorlevel 1 (
    echo.
    echo ERROR: GUI failed to start
    echo Check the error messages above
    pause
)
