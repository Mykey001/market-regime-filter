@echo off
echo ============================================================
echo Starting Live Market Regime Dashboard with EA Filter
echo ============================================================
echo.
echo This dashboard:
echo   - Shows live regime analysis (your working calculation)
echo   - Listens on port 9090 for EA trade requests
echo   - Automatically allows/blocks trades based on regime
echo.
echo Press Ctrl+C to stop the server
echo ============================================================
echo.

cd /d "%~dp0"
python mt5_regime_gui.py

pause
