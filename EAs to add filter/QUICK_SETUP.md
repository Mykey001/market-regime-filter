# Quick Setup Guide - RSI EA with Regime Filter

## ✅ Files You Need

Your EA folder should have these 2 files:
- ✅ `RSI_EA_exitv5_AOI_MS_v2.mq5` (updated EA)
- ✅ `RegimeFilterLib.mqh` (regime filter library)

## 🚀 5-Minute Setup

### 1. Copy Files
Copy both files to your MT5 Experts folder:
```
C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[BROKER_ID]\MQL5\Experts\
```

### 2. Start Python GUI
```
REGIME MOD\CORE_SYSTEM\start_gui.bat
```
Click **"Start Server"** button

### 3. Compile EA in MT5
1. Open MetaEditor (F4 in MT5)
2. Open `RSI_EA_exitv5_AOI_MS_v2.mq5`
3. Press F7 to compile
4. Should show: `0 errors, 0 warnings` ✅

### 4. Attach EA to Chart
1. Open chart (e.g., GOLD M5)
2. Drag EA onto chart
3. ✅ Check "Allow DLL imports"
4. ✅ Check "Allow WebRequest"
5. Click OK

### 5. Verify Connection
Check Experts tab, should see:
```
=== Regime Filter Initializing ===
Regime Filter: Connected to Python GUI at 127.0.0.1:9090
ML REGIME FILTER: CONNECTED ✅
```

## ❓ Troubleshooting

### Compile Errors?
**Error:** `cannot open include file 'RegimeFilterLib.mqh'`
**Fix:** Both files must be in the SAME folder!

### Connection Failed?
**Error:** `Regime Filter: Failed to connect`
**Fix:** 
1. Python GUI must be running
2. Click "Start Server" button
3. Check firewall: Run `fix_firewall.bat` as Admin

### EA Not Filtering Trades?
**Check:**
1. Chart comment shows: `ML Regime: X | Confidence: XX% | Status: Connected`
2. If "Disconnected" → check Python GUI
3. Experts log shows "Trade BLOCKED" messages when blocking

## 📊 Expected Behavior

### When Working Correctly:
✅ Chart comment shows current regime
✅ Experts log shows regime filter messages
✅ Trade comments include: `RSI_EA | R3 | C85%`
✅ Python GUI shows request counters incrementing
✅ Some trades get blocked (this is GOOD!)

### Typical Block Rate:
- 20-40% of trades blocked (the bad ones!)
- More blocks during choppy/crisis periods
- Fewer blocks during calm/trending periods

## 🎯 Quick Test

Generate a trade signal (RSI < 30 or > 70):
1. Watch Python GUI - should see request counter increase
2. Check Experts log - should see regime info
3. If trade executes - comment will show regime
4. If trade blocked - log will say "BLOCKED by Regime Filter"

---

**Need help?** Check `REGIME_FILTER_INTEGRATION.md` for detailed info!
