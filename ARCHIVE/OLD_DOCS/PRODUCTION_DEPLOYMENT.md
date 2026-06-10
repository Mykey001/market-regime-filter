# Production Deployment Guide

## 🎯 Objective

Deploy the regime trading system for **live trading** with **real MT5 data**.

---

## ✅ Pre-Deployment Checklist

- [ ] System tested with synthetic data successfully
- [ ] Connection to MT5 working (error 4014 resolved)
- [ ] Historical data loading works
- [ ] Regime predictions appear correctly
- [ ] Trade filtering tested
- [ ] Files organized into production structure

---

## 🚀 Deployment Steps

### Step 1: Organize Files (5 minutes)

```bash
cd "C:\Users\MYCkey98\Downloads\REGIME MOD"
python organize_files.py
```

Answer `y` when prompted. This creates:
- `CORE_SYSTEM/` - Production files
- `MT5_EA/` - MetaTrader EAs
- `DOCUMENTATION/` - Guides
- `UTILITIES/` - Helper scripts
- `TROUBLESHOOTING/` - Problem solving

### Step 2: Deploy to MT5 (2 minutes)

1. Open **Windows Explorer**
2. Navigate to: `REGIME MOD\MT5_EA\`
3. Copy `MT5_RegimeFilter.mq5`
4. Paste to: `C:\Users\[YourUser]\AppData\Roaming\MetaQuotes\Terminal\[TerminalID]\MQL5\Experts\`

Or easier:
1. In MT5: **File → Open Data Folder**
2. Navigate to: **MQL5 → Experts**
3. Paste `MT5_RegimeFilter.mq5`

### Step 3: Compile EA (1 minute)

1. In MT5: Press **F4** (MetaEditor)
2. Navigate to: **Experts → MT5_RegimeFilter.mq5**
3. Double-click to open
4. Press **F7** (Compile)
5. Verify: **"0 error(s), 0 warning(s)"** ✅
6. Close MetaEditor

### Step 4: Start Production GUI (1 minute)

```bash
cd "C:\Users\MYCkey98\Downloads\REGIME MOD\CORE_SYSTEM"
python regime_trading_gui.py
```

Or double-click: `CORE_SYSTEM\start_gui.bat`

1. GUI opens
2. Click **"Start Server"**
3. Wait for: **"Listening on 127.0.0.1:9090"**
4. Leave GUI running

### Step 5: Attach EA to Live Charts (2 minutes)

For each symbol you want to trade:

1. Open **M5 chart** (GOLD, USDCHF, EURUSD, etc.)
2. Navigator → Expert Advisors → **MT5_RegimeFilter**
3. **Drag onto chart**
4. Settings:
   - PythonHost: `127.0.0.1`
   - PythonPort: `9090`
   - EnableFilter: `true`
5. Check ✓ **Allow live trading**
6. Check ✓ **Allow DLL imports**
7. Click **OK**

### Step 6: Verify Each Connection (1 minute per chart)

**In MT5 Experts Tab:**
```
Regime Filter EA initializing...
Connected to Python GUI at 127.0.0.1:9090
Sending 700 historical bars for warmup...
Retrieved 700 historical bars
Sent 100 / 700 bars...
...
Historical bars sent successfully!
```

**In GUI:**
- Terminal dropdown shows: **"MetaTrader 5 - 5833 - GOLD (Acc: ...)"**
- Data Buffer: **700 bars (Ready)** ✅
- Regime predictions showing (not synthetic!)

### Step 7: Configure Filters (5 minutes)

1. Go to **Filter Configuration** tab
2. Choose strategy:
   - **Conservative**: Click "Safe Only (1,3,8)" + Min Confidence 70%
   - **Balanced**: Enable regimes 1,3,6,7,8 + Min Confidence 60%
   - **Aggressive**: Enable all except 4,5,9 + Min Confidence 50%
3. Verify **Auto Mode** is checked ✓

### Step 8: Monitor (First Hour)

1. Watch **Trade Log** tab for decisions
2. Check **Statistics** tab every 15 minutes
3. Verify regimes change appropriately with market
4. Ensure no "stuck" regime (e.g., not all bars showing regime 4)

---

## 🔍 Verification Tests

### Test 1: Real Data Loading

**Select terminal in GUI dropdown**

Expected:
- Buffer fills instantly (0 → 700 bars in 2 seconds)
- Regime shows actual market state (not always regime 4)
- Predictions update every 5 minutes

**If regime stuck on "Extreme Vol Spike":**
- You're still on synthetic terminal
- Select the REAL MetaTrader terminal from dropdown

### Test 2: Regime Changes

**Watch for 30 minutes**

Expected:
- Regime should change at least once
- Confidence varies (not always 100%)
- Different regimes in Statistics tab distribution

**If regime never changes:**
- Check you selected correct terminal
- Verify EA is sending new bars (check MT5 Experts tab)
- Restart GUI and EA

### Test 3: Trade Filtering

**In Filter Config: Block regime 1**

Expected:
- When regime 1 active, Trade Status shows **"BLOCKED ✗"**
- When other regime active, shows **"ALLOWED ✓"**
- Trade Log records blocks with reason

---

## 🎯 Production Configuration Recommendations

### For Conservative Trading

```
Filter Configuration:
- Allowed Regimes: 1, 3, 8 only
- Min Confidence: 70%
- Auto Mode: ON

Expected:
- ~40-50% of time allows trading
- Avoids volatile/crisis periods
- Higher win rate, fewer trades
```

### For Aggressive Trading

```
Filter Configuration:
- Allowed Regimes: 0, 1, 2, 3, 6, 7, 8
- Min Confidence: 55%
- Auto Mode: ON

Expected:
- ~70-80% of time allows trading
- Blocks only extreme conditions (4,5,9)
- More trades, lower win rate
```

### For Trend-Only Trading

```
Filter Configuration:
- Allowed Regimes: 3, 7, 8 only
- Min Confidence: 65%
- Auto Mode: ON

Expected:
- ~30-40% of time allows trading
- Only trending markets
- Best for momentum strategies
```

---

## 📊 Monitoring Dashboard

### Daily Checklist

Morning (Market Open):
- [ ] GUI running with "Stop Server" visible
- [ ] All terminals connected (green ●)
- [ ] Data buffers show "Ready"
- [ ] Regime predictions updating

Every 4 Hours:
- [ ] Check Statistics tab
- [ ] Review Trade Log
- [ ] Verify regime distribution makes sense
- [ ] Check no errors in MT5 Experts tab

Evening (Market Close):
- [ ] Review day's trade decisions
- [ ] Note most common regime
- [ ] Adjust filter if needed
- [ ] Export Trade Log (optional)

### Key Metrics to Track

| Metric | How to Check | Good Sign |
|--------|--------------|-----------|
| Connection Stability | Green indicator | 99%+ uptime |
| Regime Distribution | Statistics tab | Varied (not stuck) |
| Trade Allowance Rate | Statistics tab | Matches your config |
| Buffer Status | Monitor tab | Always "Ready" |
| Prediction Confidence | Monitor tab | Avg 60-80% |

---

## 🆘 Production Issues

### Issue: Regime Stuck on One Value

**Symptoms:**
- Always shows same regime (e.g., always regime 4)
- Confidence always 100%
- No regime changes over hours

**Solution:**
1. Check terminal dropdown - make sure NOT on "QuickWarmup - Synthetic"
2. Select actual MT5 terminal
3. Verify EA is sending new bars (check MT5 Experts tab)
4. If still stuck, remove and reattach EA

### Issue: Buffer Keeps Resetting

**Symptoms:**
- Buffer goes from 700 → 2 → 700 repeatedly
- Regimes reset

**Solution:**
- EA is reconnecting repeatedly
- Check MT5 connection stable
- Verify firewall not blocking
- Check MT5 Experts tab for disconnection messages

### Issue: Trades Not Being Filtered

**Symptoms:**
- Trade Log shows all "ALLOWED" even in blocked regimes
- Filter seems inactive

**Solution:**
1. Verify **Auto Mode** is checked ✓
2. Check **EnableFilter = true** in EA settings
3. Verify regime filter checkboxes are working
4. Restart GUI and EA

---

## 🎓 Production Best Practices

### 1. Keep GUI Running 24/7

- Run on VPS for reliability
- Or dedicated trading PC
- Don't close GUI while trading active

### 2. One GUI, Multiple Charts

- One GUI instance can handle 5-10 MT5 charts
- Switch between terminals using dropdown
- Each terminal has independent predictor

### 3. Log Everything

Add this to GUI for CSV logging (optional):

```python
# In log_trade method
with open("trade_decisions.csv", "a") as f:
    f.write(f"{timestamp},{symbol},{action},{regime},{confidence},{decision},{reason}\n")
```

### 4. Backup Configuration

Note your filter settings:

```
Date: __________
Allowed Regimes: ____________
Min Confidence: __%
Notes: _______________________
```

### 5. Regular Review

- Weekly: Review regime distribution, adjust filters
- Monthly: Analyze which regimes are most profitable
- Quarterly: Consider retraining model with recent data

---

## 📁 Production File Locations

### On Trading PC

```
C:\TradingSystem\
├── REGIME MOD\
│   └── CORE_SYSTEM\
│       ├── regime_trading_gui.py    ← Run this
│       ├── feature_engine.py
│       ├── market_regime_gmm.pkl
│       └── scaler.pkl
```

### In MT5

```
MT5\MQL5\Experts\
└── MT5_RegimeFilter.mq5             ← Compiled
```

### Documentation

```
C:\TradingSystem\REGIME MOD\DOCUMENTATION\
├── QUICK_START.md                   ← Quick reference
├── HOW_TO_INTEGRATE_YOUR_EA.md      ← Integration
└── TROUBLESHOOTING_4014.md          ← Fixes
```

---

## ✅ Production Deployment Complete

**When all green:**
- ✅ GUI running on production PC/VPS
- ✅ EA attached to live charts
- ✅ Real data loading (700 bars)
- ✅ Regimes changing naturally
- ✅ Filter configuration set
- ✅ Auto mode enabled
- ✅ Monitoring dashboard active

**System is LIVE and production-ready!** 🚀

---

**Next:** Read `HOW_TO_INTEGRATE_YOUR_EA.md` to add filter to your trading EA.

**Support:** Check `TROUBLESHOOTING/` folder for common issues.

**Version**: Production 1.0  
**Date**: June 9, 2026
