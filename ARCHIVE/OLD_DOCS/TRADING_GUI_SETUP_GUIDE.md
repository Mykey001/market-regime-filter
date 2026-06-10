# Market Regime Trading GUI - Complete Setup Guide

## 📋 Table of Contents

1. [System Overview](#system-overview)
2. [Prerequisites](#prerequisites)
3. [Installation Steps](#installation-steps)
4. [GUI Configuration](#gui-configuration)
5. [MetaTrader EA Integration](#metatrader-ea-integration)
6. [Usage Instructions](#usage-instructions)
7. [Troubleshooting](#troubleshooting)

---

## System Overview

The Market Regime Trading GUI is a **professional trading control center** that:

- ✅ **Connects to any MetaTrader EA** via socket communication
- ✅ **Predicts market regimes in real-time** using the trained GMM model
- ✅ **Filters EA trades** based on configurable regime rules
- ✅ **Displays live regime probabilities** and confidence levels
- ✅ **Logs all trade decisions** with full audit trail
- ✅ **Supports both auto and manual modes**

### Architecture

```
┌─────────────────┐         Socket          ┌──────────────────┐
│  MetaTrader EA  │ ◄─────────────────────► │   Python GUI     │
│  (MT4 or MT5)   │    JSON over TCP/IP     │  (PyQt5 App)     │
└─────────────────┘                         └──────────────────┘
                                                      │
                                                      ▼
                                            ┌──────────────────┐
                                            │ Regime Predictor │
                                            │ (GMM Model)      │
                                            └──────────────────┘
```

---

## Prerequisites

### 1. Python Requirements

Install Python 3.8+ and the following packages:

```bash
pip install numpy pandas scikit-learn==1.9.0 PyQt5 joblib
```

### 2. MetaTrader Requirements

- **MT4 or MT5** terminal installed
- **Socket library** for MetaTrader:
  - Download from: https://www.mql5.com/en/code/26623
  - Place `socket-library-mt4-mt5.mqh` in `MQL4/Include` or `MQL5/Include`

### 3. Model Files

Ensure these files are in the same directory as `regime_trading_gui.py`:

```
market_regime_gmm.pkl
scaler.pkl
feature_engine.py
```

---

## Installation Steps

### Step 1: Download All Files

Place these files in `C:\Users\MYCkey98\Downloads\REGIME MOD\`:

```
regime_trading_gui.py         # Main GUI application
feature_engine.py             # Feature computation engine
market_regime_gmm.pkl         # Trained GMM model
scaler.pkl                    # Trained scaler
MT4_RegimeFilter.mq4          # MT4 EA template
MT5_RegimeFilter.mq5          # MT5 EA template
```

### Step 2: Install Python Dependencies

Open Command Prompt and run:

```bash
cd "C:\Users\MYCkey98\Downloads\REGIME MOD"
pip install numpy pandas scikit-learn==1.9.0 PyQt5 joblib
```

### Step 3: Test GUI

Run the GUI to verify installation:

```bash
python regime_trading_gui.py
```

You should see the main window with:
- ✅ Model: Loaded (green checkmark)
- ● Connection status indicator (red = not connected)

---

## GUI Configuration

### Main Window Overview

```
┌───────────────────────────────────────────────────────────────┐
│  Connection & Control                                          │
│  Host: 127.0.0.1  Port: 9090  [Start Server]  ● [Auto Mode ✓] │
├───────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┬─────────────────┬────────────┬──────────┐│
│  │ Regime Monitor  │ Filter Config   │ Trade Log  │ Statistics││
│  └─────────────────┴─────────────────┴────────────┴──────────┘│
│                                                                 │
└───────────────────────────────────────────────────────────────┘
```

### Tab 1: Regime Monitor

Displays:
- **Current Regime** (0-9 with name and color)
- **Confidence Level** (percentage)
- **Trade Status** (ALLOWED ✓ or BLOCKED ✗)
- **Regime Probabilities** (all 10 regimes)
- **Data Buffer Status** (bars collected vs 626 needed)

### Tab 2: Filter Configuration

Configure trade filtering:

#### Minimum Confidence Threshold
- Set minimum confidence required to allow trades
- Default: 50%
- Range: 0-100%

#### Allowed Regimes
- Check/uncheck each regime to allow/block trades
- Color-coded indicators for each regime

#### Quick Presets
- **Allow All**: Enable trading in all regimes
- **Block All**: Disable all trading
- **Trending Only**: Enable regimes 3, 7, 8 (trending markets)
- **Safe Only**: Enable regimes 1, 3, 8 (calm and bullish)

### Tab 3: Trade Log

Shows all trade decisions:
- Time of request
- Symbol and action (buy/sell/close)
- Current regime and confidence
- Decision (ALLOWED/BLOCKED)
- Reason for decision

### Tab 4: Statistics

Displays:
- Regime distribution (last 200 bars)
- Trade filter statistics (allowed vs blocked)
- Current filter configuration summary

---

## MetaTrader EA Integration

### Option A: Use Provided Template (Recommended)

1. **Copy EA file** to MetaTrader:
   - MT4: Copy `MT4_RegimeFilter.mq4` to `MQL4/Experts/`
   - MT5: Copy `MT5_RegimeFilter.mq5` to `MQL5/Experts/`

2. **Compile EA** in MetaEditor (F7)

3. **Attach to chart**:
   - Drag EA onto any M5 chart
   - Set parameters:
     - `PythonHost`: 127.0.0.1 (if local)
     - `PythonPort`: 9090 (must match GUI)
     - `EnableFilter`: true

4. **EA will automatically**:
   - Connect to GUI
   - Send bar data every 5 minutes
   - Request permission before each trade

### Option B: Integrate with Existing EA

Add this code to your existing EA:

```mql4
// 1. Include at top of file
#include <socket-library-mt4-mt5.mqh>

// 2. Add global variables
ClientSocket* regimeClient = NULL;
bool regimeAllowed = true;

// 3. In OnInit()
regimeClient = new ClientSocket("127.0.0.1", 9090);

// 4. Before executing trades
bool CheckRegimeFilter(string action)
{
   if(regimeClient == NULL || !regimeClient.IsSocketConnected())
      return true;  // Allow if not connected
   
   string json = "{\"type\":\"trade_request\",";
   json += "\"symbol\":\"" + Symbol() + "\",";
   json += "\"action\":\"" + action + "\"}";
   
   regimeClient.Send(json);
   string response = regimeClient.Receive("\r\n", 1000);
   
   // Parse response to get allow_trade boolean
   return (StringFind(response, "\"allow_trade\":true") >= 0);
}

// 5. In your trade logic
if(BuyCondition && CheckRegimeFilter("buy"))
{
   // Execute buy trade
}
```

---

## Usage Instructions

### Starting the System

1. **Start Python GUI first**:
   ```bash
   python regime_trading_gui.py
   ```

2. **Click "Start Server"** in the GUI

3. **Wait for "Listening on 127.0.0.1:9090"** message

4. **Attach EA to MT4/MT5 chart**

5. **Verify connection**:
   - GUI status indicator turns green (●)
   - Status bar shows "Connected to EA at..."

### Collecting Data

The system needs **626 M5 bars** (≈52 hours) to warm up:

- Monitor the **Data Buffer** progress bar
- Wait until it shows "Ready"
- Regime predictions start appearing automatically

### Configuring Trade Filters

#### Example 1: Only Trade in Calm/Trending Markets

1. Go to **Filter Configuration** tab
2. Click **"Block All"**
3. Check only:
   - ☑ 1: Normal/Calm
   - ☑ 3: Bullish Trending
   - ☑ 8: Bullish Momentum
4. Set **Minimum Confidence** to 60%

#### Example 2: Avoid Crisis Regimes

1. Go to **Filter Configuration** tab
2. Click **"Allow All"**
3. Uncheck:
   - ☐ 4: Extreme Vol Spike
   - ☐ 5: Crisis Mode
   - ☐ 9: Choppy/Erratic

#### Example 3: Conservative Trading

1. Set **Minimum Confidence** to 70%
2. Enable only regimes 1, 3, 8
3. Check **Auto Mode**

### Monitoring Performance

Check **Statistics** tab regularly:

```
REGIME STATISTICS (Last 200 bars)
==================================================
1: Normal/Calm              75 bars (37.5%)
3: Bullish Trending         40 bars (20.0%)
8: Bullish Momentum         30 bars (15.0%)
...

TRADE FILTER STATISTICS
==================================================
Total trade requests: 50
Allowed: 35 (70.0%)
Blocked: 15 (30.0%)
```

---

## Troubleshooting

### Issue 1: "Model: Files Not Found"

**Cause**: Model files missing

**Solution**:
```bash
# Verify files exist
dir "C:\Users\MYCkey98\Downloads\REGIME MOD\*.pkl"

# Should show:
# market_regime_gmm.pkl
# scaler.pkl
```

### Issue 2: Connection Fails

**Symptoms**: Red status indicator, "Failed to connect"

**Solutions**:

1. **Check port availability**:
   ```bash
   netstat -an | findstr 9090
   ```
   If port is in use, change port number

2. **Firewall blocking**:
   - Add Python to Windows Firewall exceptions
   - Or temporarily disable firewall to test

3. **Wrong host/port in EA**:
   - Verify EA input parameters match GUI settings

### Issue 3: EA Not Sending Data

**Symptoms**: Buffer stays at 0 bars

**Solutions**:

1. **Check EA logs** (Experts tab in MT terminal):
   ```
   Should see:
   "Connected to Python GUI at 127.0.0.1:9090"
   "Sending bar data..."
   ```

2. **Verify M5 timeframe**:
   - EA must be on M5 chart
   - Check chart period indicator

3. **Socket library missing**:
   - Ensure `socket-library-mt4-mt5.mqh` is in Include folder
   - Recompile EA

### Issue 4: All Trades Blocked

**Cause**: Filter too restrictive or low confidence

**Solutions**:

1. **Lower confidence threshold** to 40-50%
2. **Enable more regimes** (try "Allow All" preset)
3. **Check current regime** in Regime Monitor tab
4. **Disable Auto Mode** temporarily to allow all trades

### Issue 5: Model Prediction Errors

**Symptoms**: "Prediction error" in console

**Solutions**:

1. **Check scikit-learn version**:
   ```bash
   pip show scikit-learn
   # Should be 1.9.0
   ```

2. **Upgrade if needed**:
   ```bash
   pip install --upgrade scikit-learn==1.9.0
   ```

3. **Verify feature engine**:
   ```bash
   python feature_engine.py
   # Should run self-test successfully
   ```

---

## Advanced Configuration

### Custom Port

To use a different port (e.g., 8888):

1. **In GUI**: Change port before clicking "Start Server"
2. **In EA**: Set `PythonPort = 8888` in input parameters

### Remote Connection

To connect from a different computer:

1. **Get server IP**:
   ```bash
   ipconfig
   # Note IPv4 Address (e.g., 192.168.1.100)
   ```

2. **In GUI**: Set host to `0.0.0.0` (listen on all interfaces)

3. **In EA**: Set `PythonHost = "192.168.1.100"` (server IP)

4. **Configure firewall** to allow port 9090

### Logging to File

Add this code to GUI for persistent logging:

```python
# In log_trade method
import csv

with open("trade_decisions.csv", "a", newline="") as f:
    writer = csv.writer(f)
    writer.writerow([timestamp, symbol, action, regime, confidence, decision, reason])
```

---

## Tips for Optimal Usage

### 1. Start with Conservative Settings
- Enable only regimes 1, 3, 8 initially
- Set confidence threshold to 60%
- Monitor for a few days before adjusting

### 2. Review Statistics Daily
- Check regime distribution
- Verify filter is not blocking too many trades
- Adjust based on market conditions

### 3. Backtest Before Live Trading
- Run GUI with historical data playback
- Verify filter logic matches your strategy
- Test edge cases (regime transitions)

### 4. Keep Data Buffer Full
- Don't restart MT unless necessary
- If restarted, wait 52 hours for full warmup

### 5. Monitor Regime Transitions
- Watch for frequent regime switches (noise)
- Consider raising confidence threshold if unstable

---

## Support Files

All files are located in:
```
C:\Users\MYCkey98\Downloads\REGIME MOD\
```

**Need help?** Check these documents:
- `ANALYSIS_REPORT.md` - Full system analysis
- `TECHNICAL_SUMMARY.md` - Quick reference guide
- `feature_engine.py` - Contains feature documentation

---

**Version**: 1.0  
**Last Updated**: June 9, 2026  
**Compatibility**: Python 3.8+, MT4/MT5, Windows
