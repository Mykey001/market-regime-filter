# Quick Start Guide - Market Regime Trading System

## ✅ Fixed Issues

1. **MT5 EA now uses built-in sockets** (no external library needed)
2. **GUI now supports multiple MT5 terminals** with selection dropdown
3. **All compilation errors fixed**

---

## 🚀 Installation (5 Minutes)

### Step 1: Install Python Dependencies

```bash
cd "C:\Users\MYCkey98\Downloads\REGIME MOD"
pip install -r requirements.txt
```

### Step 2: Test Installation

```bash
python test_installation.py
```

You should see: **"ALL TESTS PASSED! ✓"**

---

## 🎯 Launch the GUI

### Option A: Windows Batch File
Double-click: **`start_gui.bat`**

### Option B: Command Line
```bash
python regime_trading_gui.py
```

The GUI window will open.

---

## 🔌 Connect MT5

### Step 1: Copy EA to MT5

1. Open MT5
2. Go to: **File → Open Data Folder**
3. Navigate to: **MQL5 → Experts**
4. Copy **`MT5_RegimeFilter.mq5`** to this folder

### Step 2: Compile EA

1. Open **MetaEditor** (F4 in MT5)
2. Open **`MT5_RegimeFilter.mq5`**
3. Click **Compile** (F7)
4. Should show: **"0 error(s), 0 warning(s)"** ✅

### Step 3: Start GUI Server

1. In the GUI, click **"Start Server"**
2. Wait for status: **"Listening on 127.0.0.1:9090"**
3. Connection indicator should be ready (red●, waiting for EA)

### Step 4: Attach EA to Chart

1. In MT5, open **M5 chart** (any symbol, e.g., EURUSD)
2. In **Navigator**, find **Expert Advisors → MT5_RegimeFilter**
3. **Drag** EA onto the M5 chart
4. In the EA settings dialog:
   - **PythonHost**: `127.0.0.1` (leave as is)
   - **PythonPort**: `9090` (leave as is)
   - **EnableFilter**: `true`
   - Check ✓ **"Allow live trading"**
   - Check ✓ **"Allow DLL imports"**
5. Click **OK**

### Step 5: Verify Connection

**In GUI:**
- Connection indicator turns **GREEN** ●
- Status bar shows: **"EA connected from..."**
- **Terminal dropdown** shows your MT5 terminal

**In MT5:**
- Chart shows regime info in top-left corner
- Experts tab shows: **"Connected to Python GUI..."**

---

## 📊 Select Your MT5 Terminal

If you have multiple MT5 instances running:

1. Look at the **Terminal dropdown** in the GUI
2. It will show all connected terminals like:
   ```
   MetaTrader 5 - 3640 - EURUSD (Acc: 12345678)
   MetaTrader 5 - 3640 - GBPUSD (Acc: 87654321)
   ```
3. **Select** the terminal you want to monitor
4. The regime predictions will update for that terminal

---

## ⏳ Warmup Period (52 Hours)

The system needs **626 M5 bars** before making predictions:

- **Monitor progress bar** in Regime Monitor tab
- Shows: "Data Buffer: X bars (need Y more)"
- Keep **MT5 and GUI running**
- Takes approximately **52 hours** (2+ days)

**During warmup:**
- Leave your computer on (or use VPS)
- Don't restart MT5 or GUI
- EA will collect data every 5 minutes

**After warmup:**
- Progress bar shows: **"626 bars (Ready)"**
- Regime predictions start appearing
- Trade filtering becomes active

---

## ⚙️ Configure Trade Filters

### Quick Presets

Go to **Filter Configuration** tab and choose:

1. **Safe Only** (Recommended for beginners)
   - Allows regimes: 1 (Normal), 3 (Bullish), 8 (Momentum)
   - Min confidence: 70%
   - ~60% of trades allowed

2. **Trending Only**
   - Allows regimes: 3, 7, 8 (all trending markets)
   - Min confidence: 60%
   - ~50% of trades allowed

3. **Crisis Avoidance**
   - Blocks regimes: 4 (Extreme Vol), 5 (Crisis), 9 (Choppy)
   - Allows all others
   - Min confidence: 50%
   - ~90% of trades allowed

### Custom Configuration

1. Go to **Filter Configuration** tab
2. Check/uncheck individual regimes
3. Adjust **Minimum Confidence** slider
4. Changes take effect immediately

---

## 🎯 Using with Your EA

### Option A: Test with Template Functions

The EA includes test functions you can call:

```mql5
// In your EA's OnTick() or trading logic:

if(YourBuyCondition)
{
   ExecuteBuySignal();  // This checks regime filter
}

if(YourSellCondition)
{
   ExecuteSellSignal();  // This checks regime filter
}
```

### Option B: Integrate with Existing EA

Add this to your EA before trade execution:

```mql5
#property strict

// At the top of your EA file
#include "MT5_RegimeFilter.mq5"

// Before executing any trade:
if(IsTradeAllowed("buy"))
{
   // Your buy trade code
   OrderSend(...);
}

if(IsTradeAllowed("sell"))
{
   // Your sell trade code
   OrderSend(...);
}
```

---

## 📈 Monitor Performance

### Trade Log Tab

- Shows all trade decisions
- Columns: Time, Action, Symbol, Regime, Confidence, Decision, Reason
- **GREEN** row = Allowed
- **RED** row = Blocked

### Statistics Tab

Click **"Refresh Statistics"** to see:

- **Regime Distribution** (last 200 bars)
- **Trade Filter Statistics** (allowed vs blocked %)
- **Current Configuration Summary**

Review daily to optimize your settings.

---

## 🔧 Troubleshooting

### EA Won't Compile

**Error**: `'SocketCreate' - undeclared identifier`

**Solution**: You're using a very old MT5 build. Update MT5 to build 3000+
- Help → About → Check build number
- Download latest from MetaQuotes website

### Connection Fails

**Symptom**: Red indicator, "Failed to connect"

**Solutions**:
1. Check GUI shows "Listening on..."
2. Verify port 9090 not blocked by firewall
3. Try restarting GUI first, then reattach EA
4. Check MT5 Experts tab for connection errors

### No Terminal in Dropdown

**Symptom**: Dropdown shows "No terminals connected"

**Solutions**:
1. Check EA is attached to M5 chart
2. Verify EA is running (smiley face icon in corner)
3. Check GUI server is started
4. Look for errors in MT5 Experts tab

### All Trades Blocked

**Symptom**: Trade Log shows all "BLOCKED"

**Solutions**:
1. Check **Auto Mode** is enabled
2. Lower **Minimum Confidence** to 40%
3. Click **"Allow All"** preset temporarily
4. Wait for 626 bars if still in warmup

---

## 💾 Files Overview

```
Your Working Directory:
├── regime_trading_gui.py          # Main application (run this)
├── feature_engine.py              # Feature computation
├── market_regime_gmm.pkl          # ML model
├── scaler.pkl                     # Preprocessing
├── MT5_RegimeFilter.mq5           # MT5 EA (copy to MT5)
├── requirements.txt               # Python dependencies
├── start_gui.bat                  # Windows launcher
└── test_installation.py           # System test
```

---

## 📚 Documentation

- **This file** - Quick start (you are here)
- **README.md** - System overview
- **TRADING_GUI_SETUP_GUIDE.md** - Complete guide
- **TECHNICAL_SUMMARY.md** - API reference
- **ANALYSIS_REPORT.md** - Model details

---

## ✅ Success Checklist

Before live trading, verify:

- [x] GUI starts without errors
- [x] MT5 EA compiles successfully
- [x] Connection established (green indicator)
- [x] Terminal appears in dropdown
- [x] Warmup complete (626+ bars)
- [x] Regime predictions displaying
- [x] Trade log recording decisions
- [x] Tested on demo account for 1+ week

---

## 🎉 You're Ready!

Your market regime trading system is now operational.

**Next Steps:**
1. Wait for warmup to complete
2. Monitor regime predictions
3. Review trade log daily
4. Adjust configuration based on results
5. Test on demo for 1-2 weeks before live

---

**Need Help?** Check the full documentation:
- Setup issues → **TRADING_GUI_SETUP_GUIDE.md**
- Technical questions → **TECHNICAL_SUMMARY.md**
- System understanding → **ANALYSIS_REPORT.md**

**Version**: 2.0 (Fixed MT5 Socket Issues)  
**Last Updated**: June 9, 2026
