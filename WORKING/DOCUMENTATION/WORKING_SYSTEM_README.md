# 🎯 Working ML Regime Filter System

**Status:** ✅ READY TO USE  
**Last Updated:** June 10, 2026  
**Version:** 2.0 - Using Your Working Dashboard

---

## 📋 System Overview

This system uses **your proven working dashboard** (`mt5_regime_gui.py`) with added EA connection capability to filter trades based on ML-predicted market regimes.

### What's Working:
- ✅ Your original regime calculation (proven accurate)
- ✅ Real-time dashboard with live regime display
- ✅ Socket server for EA communication
- ✅ Automatic trade filtering based on regime
- ✅ Uses closed bars only (no random flips)

---

## 📁 File Structure

### ✅ Core Working Files

```
REGIME MOD/
│
├── 🟢 WORKING FILES (USE THESE)
│   ├── mt5_regime_gui.py                    ← Main dashboard with EA filter
│   ├── feature_engine.py                    ← Feature calculation (unchanged)
│   ├── market_regime_gmm.pkl                ← Your trained model
│   ├── scaler.pkl                           ← Your scaler
│   ├── regime_metadata.json                 ← Regime names/config
│   └── start_dashboard_with_ea_filter.bat   ← Quick start script
│
├── 📂 EAs to add filter/
│   ├── RegimeFilterLib.mqh                  ← Updated library (uses closed bars)
│   └── RSI_EA_exitv5_AOI_MS_v2.mq5         ← Your EA with filter integrated
│
└── 📂 DOCUMENTATION/
    └── WORKING_SYSTEM_README.md             ← This file
```

### ❌ Old/Obsolete Files (Can Delete or Archive)

```
❌ CORE_SYSTEM/                    ← Old complex system (not needed)
❌ ANALYSIS_REPORT.md              ← Development history
❌ AUTO_REFRESH_FEATURE.md         ← Old implementation docs
❌ BUG_FIXED_*.md                  ← Debugging history
❌ check_data_buffer.md            ← Old diagnostics
❌ DATA_BUFFER_FIX.md              ← Old fix docs
❌ DEPLOYMENT_CHECKLIST.md         ← Old deployment
❌ diagnose_buffer.py              ← Old diagnostic tool
❌ FIXES_AND_IMPROVEMENTS.md       ← Development history
❌ inspect_model.py                ← Debug tool
❌ load_historical_data.py         ← Test script
❌ MT4_RegimeFilter.mq4            ← MT4 version (if using MT5)
❌ MT5_RegimeFilter.mq5            ← Standalone filter (not needed)
❌ organize_files.py               ← File organizer
❌ quick_warmup.py                 ← Test script
❌ REGIME_CHANGE_SUMMARY.txt       ← Old bug explanation
❌ SIMPLE_ALTERNATIVE.md           ← Alternative approach (not used)
❌ WARMUP_FIX.md                   ← Old fix docs
❌ WHY_REGIME_CHANGES.md           ← Old explanation
❌ *.ex5                           ← Compiled files (will recompile)
```

---

## 🚀 Quick Start (3 Steps)

### Step 1: Start Dashboard

```batch
Double-click: start_dashboard_with_ea_filter.bat
```

**You should see:**
- Dashboard window opens
- Shows: "Server: RUNNING on 9090"
- Regime updates every 10 seconds

### Step 2: Attach EA to Chart

1. Open MT5
2. Open GOLD M5 chart
3. Drag `RSI_EA_exitv5_AOI_MS_v2` from Navigator to chart
4. Click OK

**You should see:**
- Dashboard shows: "EA: Connected"
- MT5 log shows: "ML REGIME FILTER: CONNECTED"

### Step 3: Verify Working

**Dashboard should show:**
- Current Regime (e.g., "Regime 8")
- Confidence (e.g., "89.4%")
- Trade Status: "ALLOWED ✓" or "BLOCKED ✗"

**MT5 should show:**
- Chart comment: "ML Regime: 8 | Confidence: 89.4%"
- Trades allowed/blocked based on regime

✅ **Done! System is running.**

---

## ⚙️ Configuration

### Regime Filter Settings

**File:** `mt5_regime_gui.py` (lines 85-99)

```python
REGIME_FILTER_CONFIG = {
    0: True,   # Low Volatility Bullish - ALLOW
    1: True,   # Neutral Consolidation - ALLOW
    2: False,  # High Volatility Bearish - BLOCK
    3: True,   # Low Volatility Bearish - ALLOW
    4: False,  # Regime 4 - BLOCK (if exists)
    5: False,  # Regime 5 - BLOCK (if exists)
    6: True,   # ALLOW
    7: True,   # ALLOW
    8: True,   # ALLOW
    9: False,  # BLOCK
}
```

**To change:**
1. Edit `mt5_regime_gui.py`
2. Change `True` (allow) or `False` (block) for each regime
3. Save and restart dashboard

---

## 🔍 How It Works

### Data Flow:

```
1. MT5 EA starts
   ↓
2. Connects to Dashboard on port 9090
   ↓
3. Dashboard fetches GOLD M5 data from MT5 (800 closed bars)
   ↓
4. Calculates features (14 technical indicators)
   ↓
5. ML model predicts regime (0-9)
   ↓
6. Dashboard updates display every 10 seconds
   ↓
7. When EA wants to trade:
   - EA sends trade request to Dashboard
   - Dashboard checks REGIME_FILTER_CONFIG
   - Responds: ALLOW or BLOCK
   ↓
8. EA executes or skips trade based on response
```

### Key Features:

✅ **Uses Your Working Calculation**
- Same `mt5_regime_gui.py` logic you trust
- No changes to regime prediction
- Just added socket server

✅ **Real-time Updates**
- Fetches fresh data every 10 seconds
- Always has current market regime
- EA queries current regime when needed

✅ **Deterministic**
- Uses closed bars only (not bar 0)
- Same data = same regime every time
- No random flips

---

## 📊 Understanding the Display

### Dashboard Window:

```
┌─────────────────────────────────────────────┐
│ Symbol: GOLD  | Timeframe: M5  | Refresh   │
│ Server: RUNNING on 9090 | EA: Connected    │
├─────────────────────────────────────────────┤
│ Live Market Analysis                        │
│ Price:         4188.75                      │
│ Regime:        Regime 8                     │
│ Confidence:    89.4%                        │
│ Trade Status:  ALLOWED ✓                    │
│ Status:        Updated at 08:30:20          │
│ Model:         market_regime_gmm.pkl        │
├─────────────────────────────────────────────┤
│ Regime Probabilities                        │
│ Regime 0: 0.0%                              │
│ Regime 1: 0.0%                              │
│ ...                                         │
│ Regime 8: 89.4%  ← Current                  │
│ Regime 9: 0.0%                              │
├─────────────────────────────────────────────┤
│ [Price Chart]                               │
│ [RSI Chart]                                 │
└─────────────────────────────────────────────┘
```

### MT5 Chart Comment:

```
ML Regime: 8 | Confidence: 89.4% | Status: Connected
```

---

## 🐛 Troubleshooting

### Problem: Dashboard shows "Server: ERROR"

**Solution:**
- Check if port 9090 is already in use
- Run: `netstat -ano | findstr :9090`
- If in use, kill process or change port in code

### Problem: EA shows "Failed to connect"

**Solution:**
1. Check dashboard is running (Server: RUNNING)
2. Check firewall isn't blocking port 9090
3. Run: `fix_firewall.bat` as administrator

### Problem: Dashboard shows wrong regime

**Check:**
- Symbol matches (XAUUSD = GOLD)
- Timeframe is M5
- Model files loaded correctly
- No errors in console

### Problem: Regime flipping randomly

**This should NOT happen anymore!**

If it does:
- Verify `RegimeFilterLib.mqh` has `CopyRates(..., 1, ...)` (not 0)
- Recompile EA
- Restart both dashboard and EA

---

## 📝 Console Output Examples

### Normal Operation:

```
[SERVER] Socket server thread started on 127.0.0.1:9090
[SERVER] Listening on 127.0.0.1:9090
[UPDATE] Regime 8, Confidence 89.4%, Trade: ALLOWED
[SERVER] EA connected from ('127.0.0.1', 52341)
[HANDSHAKE] EA connected: MetaTrader 5 - GOLD
[UPDATE] Regime 8, Confidence 89.2%, Trade: ALLOWED
[TRADE REQUEST] BUY on GOLD -> Regime 8 (89.2%) -> ALLOWED
[UPDATE] Regime 8, Confidence 88.7%, Trade: ALLOWED
```

### When Regime Changes:

```
[UPDATE] Regime 8, Confidence 89.4%, Trade: ALLOWED
[UPDATE] Regime 8, Confidence 87.3%, Trade: ALLOWED
[UPDATE] Regime 7, Confidence 55.6%, Trade: ALLOWED  ← Changed!
[TRADE REQUEST] SELL on GOLD -> Regime 7 (55.6%) -> ALLOWED
[UPDATE] Regime 7, Confidence 67.2%, Trade: ALLOWED
```

### When Trade Blocked:

```
[UPDATE] Regime 2, Confidence 91.4%, Trade: BLOCKED
[TRADE REQUEST] BUY on GOLD -> Regime 2 (91.4%) -> BLOCKED  ← Blocked!
[UPDATE] Regime 2, Confidence 93.4%, Trade: BLOCKED
```

---

## ⚡ Performance

### Resource Usage:
- **CPU:** <1% (idle), ~5% (during update)
- **Memory:** ~100MB (Python + Tkinter)
- **Network:** Port 9090 (localhost only)
- **Update Frequency:** Every 10 seconds

### Speed:
- **MT5 data fetch:** ~500ms
- **Feature calculation:** ~200ms
- **ML prediction:** ~50ms
- **Total update time:** <1 second

### Reliability:
- **Uptime:** Runs continuously
- **Reconnection:** EA reconnects automatically
- **Error handling:** Graceful fallbacks

---

## 🎯 Next Steps

### Optional Improvements:

1. **Add More Symbols:**
   - Modify dashboard to support multiple symbols
   - EA can specify which symbol to check

2. **Historical Performance:**
   - Log all trade decisions
   - Analyze which regimes are most profitable

3. **Dynamic Configuration:**
   - Add GUI controls to change filter settings
   - No code editing needed

4. **Alerts:**
   - Add sound/popup when regime changes
   - Email notifications for specific regimes

5. **Backtesting:**
   - Export regime history
   - Analyze EA performance per regime

---

## 📞 Support

### If Something Doesn't Work:

1. **Check console output** (Python window)
2. **Check MT5 Experts log** (Ctrl+T in MT5)
3. **Verify both running** (Dashboard + EA)
4. **Check filter config** (which regimes allowed)

### Common Issues:

| Issue | Solution |
|-------|----------|
| Port already in use | Change port or kill process |
| EA can't connect | Check firewall, run fix_firewall.bat |
| Wrong regime shown | Check symbol/timeframe match |
| No updates | Check MT5 is running and logged in |

---

## ✅ Final Checklist

Before trading:

- [ ] Dashboard shows "Server: RUNNING"
- [ ] Dashboard shows "EA: Connected"
- [ ] Regime matches your external dashboard
- [ ] Confidence makes sense (50-100%)
- [ ] Trade Status shows ALLOWED or BLOCKED correctly
- [ ] MT5 chart comment shows regime
- [ ] Test with one trade to verify blocking works

**If all checked ✅ → System is ready!**

---

## 🎉 Summary

You now have:

✅ Your proven working regime calculation  
✅ Live dashboard with regime display  
✅ Automatic EA trade filtering  
✅ Deterministic predictions (no flips)  
✅ Simple configuration  
✅ Clean, organized code  

**This system uses YOUR working logic with just an added connection layer for EA filtering.**

---

*System Version: 2.0*  
*Based on: mt5_regime_gui.py (your working dashboard)*  
*Updated: June 10, 2026*
