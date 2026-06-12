========================================
     INTEGRATED EA OUTPUT FOLDER
========================================

This folder contains your integrated EAs after AI processing.

WHAT YOU'LL FIND HERE:
----------------------
For each processed EA, you'll get 3 files:

1. YourEA.mq5
   - Your EA with regime filter integrated
   - Ready to compile and use in MT5
   - Zero errors guaranteed

2. RegimeFilterLib.mqh
   - Regime filter library (shared by all EAs)
   - Must be in same folder as your EA

3. YourEA_README.md
   - Complete setup instructions
   - Integration details
   - Usage guide
   - Troubleshooting tips

NEXT STEPS:
-----------
1. Copy BOTH files to MT5 Experts folder:
   - YourEA.mq5
   - RegimeFilterLib.mqh
   
   Location: C:\Users\YourName\AppData\Roaming\MetaQuotes\Terminal\[BROKER_ID]\MQL5\Experts\

2. Start Python GUI:
   - Navigate to: REGIME MOD\CORE_SYSTEM\
   - Run: start_gui.bat
   - Click "Start Server"

3. Use in MT5:
   - Compile EA (F7)
   - Attach to chart
   - Enable "Allow WebRequest"
   - Set EnableRegimeFilter = true

4. Verify:
   - Check Experts tab for "ML Regime Filter: Successfully connected"
   - Watch for regime updates in logs

IMPORTANT:
----------
⚠ RegimeFilterLib.mqh MUST be in the same folder as your EA
⚠ Python GUI must be running with server started
⚠ Test on demo account first!

READ THE README:
----------------
Each EA has its own README with:
- What was changed
- How to install
- How to use
- Regime behaviors
- Trade examples
- Troubleshooting

MULTIPLE EAS:
-------------
You can copy RegimeFilterLib.mqh once and all EAs will share it.
Just make sure it's in the same folder as your EAs.

========================================
Check your EA's README.md for details!
========================================
