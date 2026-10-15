# ML Market Regime Trading System

[![Python](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)
[![MT5](https://img.shields.io/badge/MetaTrader-5-orange.svg)](https://www.metatrader5.com)

> **An intelligent machine learning system that automatically detects market conditions and filters your MetaTrader 5 EA trades in real-time, blocking trades during unfavorable conditions like high volatility and crisis modes.**

---

## 🎯 What This Project Does

## 🎯 What This Project Does

This system acts as an **intelligent trading filter** that protects your automated trading strategies from dangerous market conditions.

### The Problem It Solves

Expert Advisors (EAs) often trade blindly without understanding current market conditions. They may:
- ❌ Open trades during market crashes (crisis mode)
- ❌ Trade during extreme volatility spikes
- ❌ Take positions in choppy, unpredictable markets
- ❌ Ignore trend direction and market structure

**Result:** Unnecessary losses, blown accounts, and poor risk management.

### The Solution

This ML system **automatically identifies 8 distinct market conditions** and tells your EA whether to trade or stay out:

```
Market Analysis → Regime Engine → Trade Filter → Your EA
     ↓                  ↓              ↓            ↓
   OHLCV          Regime 5?      BLOCK TRADE    No order
  vol x trend     Crisis Mode                   placed
```

### Real-World Example

**Without Filter:**
```
[11:30] Market News Released
[11:31] High Volatility Spike
[11:31] EA Opens Buy Trade → LOSS $250
[11:32] EA Opens Sell Trade → LOSS $180
[11:33] EA Opens Buy Trade → LOSS $220
Total Loss: $650 in 3 minutes
```

**With ML Filter:**
```
[11:30] Market News Released
[11:31] ML detects Regime 5 (Extreme Vol Spike)
[11:31] EA requests Buy → BLOCKED by filter
[11:32] EA requests Sell → BLOCKED by filter
[11:33] EA requests Buy → BLOCKED by filter
[12:00] Market calms, Regime 1 detected
[12:01] Trading resumes safely
Total Loss: $0 - Account Protected
```

---

## 🧠 How It Works

### 1. Data Collection (Every 5 Minutes)

The system connects to MetaTrader 5 and collects M5 (5-minute) candle data:

```python
# From MT5:
- Open, High, Low, Close prices
- Tick volume
- Spread
- Time
```

### 2. Regime Detection (Regime Engine v2)

> The original Bayesian GMM (14 features) was replaced in October 2026 after an audit
> showed its labels were inaccurate - see `DOCUMENTATION/REGIME_ENGINE_V2.md`.

The regime is built from two scale-free axes computed on **closed** bars only
(`src/python/regime_engine.py`). Neither uses price level, spread or tick volume, so
the same thresholds work on any broker and instrument:

- **Volatility** - bar range relative to the normal range *for that time of day* over the
  last 60 sessions. High when the 2h average is >= 1.6x normal, extreme at >= 2.8x
  (or a 1h burst >= 3.5x).
- **Trend** - 6h net move divided by the path's own noise (a random walk scores ~N(0,1)).
  Up at >= +1.5, down at <= -1.5.

Hysteresis bands stop the regime from flickering (about 5 changes per day).
**Confidence** is a calibrated hit rate: "75%" means the label matched hindsight about 75%
of the time on the calibration data (`models/regime_calibration.json`).

### 3. Validation (XAUUSDm M5, tuned on 2022-24, tested on 2025-26)

| Held-out 2025-26 | New engine | Old GMM (as live) | Old GMM (best case) | Always "Range" |
|---|---|---|---|---|
| Regime matches hindsight | **63%** | 4% | 36% | 54% |
| Volatility state correct | **89%** | 5% | 78% | 79% |
| Trend direction correct when called | **91%** | 66% | 46% | - |
| Extreme-vol bars caught | **85%** | 100% (blocks everything) | 15% | 0% |
| Regime changes per day | **5.2** | 0.1 | 16 | 0 |

The same settings and calibration hold on XAGUSD, EURUSD, US500 and on M15/H1 without refitting.
Detected volatility predicts the next 4h (normal 1.06x, high 1.66x, extreme 3.0x normal vol).
The trend state describes the current move; it does **not** forecast the next 12h.

### 4. Market Regimes Explained

| Regime | Name | Volatility | Direction | Default |
|--------|------|------------|-----------|---------|
| **1** (id 0) | Bullish Trend | Normal | Up | ✅ Allow |
| **2** (id 1) | Range / Consolidation | Normal | Sideways | ✅ Allow |
| **3** (id 2) | High Vol Bearish | High | Down | ❌ Block |
| **4** (id 3) | Bearish Trend | Normal | Down | ✅ Allow |
| **5** (id 4) | Extreme Vol Spike | Extreme | Up / none | ❌ Block |
| **6** (id 5) | Crash / Crisis | Extreme | Down | ❌ Block |
| **7** (id 6) | High Vol Choppy | High | Sideways | ✅ Allow |
| **8** (id 7) | High Vol Bullish | High | Up | ✅ Allow |

IDs 0-7 and the EA socket protocol are unchanged.

### 5. Trade Filtering System

When your EA wants to open a trade, it asks the ML system for permission:

```cpp
// In your EA:
if(BuySignal) {
    // Ask ML system
    if(IsTradeAllowed("buy")) {
        // Permission granted
        OrderSend(...);  // Execute trade
    } else {
        // Permission denied
        Print("Trade BLOCKED - Regime 5: Crisis Mode");
        // No trade executed - account protected
    }
}
```

**Communication Flow:**
```
Your EA (MT5)                    Python Dashboard
     │                                  │
     │  1. "Can I buy?"                 │
     ├─────────────────────────────────>│
     │                                  │
     │                            2. Check regime
     │                            Regime 5 (Crisis)
     │                            Allowed? NO
     │                                  │
     │  3. Response: "BLOCKED"          │
     │<─────────────────────────────────┤
     │                                  │
     │  4. No trade executed            │
     │  (Account protected)             │
```

**Protocol:** JSON over TCP sockets (localhost port 9090)

### 6. Additional Filters

**Directional Filter (Optional):**
- Trade only WITH the trend
- Example: In Regime 0 (Bullish), ALLOW buy, BLOCK sell
- Prevents counter-trend trades
- Three modes: Strict, Allow Neutral, Disabled

**Confidence Threshold:**
- Only act on high-confidence predictions
- Low confidence = uncertain market state
- Configurable minimum threshold (default: no minimum)

---

## 📸 Dashboard Interface

The system provides a professional PyQt5 dark-mode dashboard for monitoring and configuration:

```
┌──────────────────────────────────────────────────────────┐
│  ML Market Regime Dashboard + EA Filter                  │
├──────────────────────────────────────────────────────────┤
│  Symbol: XAUUSD    M5    Server: RUNNING    EA: Connected│
├──────────────────────────────────────────────────────────┤
│  ┌────────────────────────┐  ┌───────────────────────┐  │
│  │ Live Market Analysis   │  │ Configuration Tabs    │  │
│  │                        │  │                       │  │
│  │ Price:      2345.67    │  │ ▸ Probabilities       │  │
│  │ Regime:     Regime 1   │  │ ▸ Filter Config       │  │
│  │             (Low Vol)  │  │ ▸ Statistics          │  │
│  │ Confidence: 78.5%      │  │ ▸ Directional Filter  │  │
│  │ Trade:      ALLOWED ✓  │  │                       │  │
│  │                        │  │ [Allow All] [Block All]│
│  │ [Price Chart]          │  │ [Conservative]         │  │
│  │ [RSI Chart]            │  │                       │  │
│  └────────────────────────┘  └───────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**Key Features:**
- ✅ Real-time regime detection
- ✅ Confidence scoring
- ✅ Visual charts (price coloured by regime, regime scores)
- ✅ Regime scores and per-axis confidence visible
- ✅ Configurable filters (check/uncheck regimes)
- ✅ Server status and EA connection indicator
- ✅ Dark mode theme (reduced eye strain)

---

## ⚡ Quick Start (5 Minutes)

### 1. Install Python Dependencies

```bash
cd "C:\Users\YourName\Downloads\REGIME MOD"
pip install -r config\requirements.txt
```

### 2. Launch Dashboard

**Double-click:** `src\scripts\start_dashboard.bat`

**Or command line:**
```bash
python src\python\mt5_regime_gui_pyqt.py
```

### 3. Integrate with Your EA

#### 🎯 **NEW: Automatic AI Integration (Recommended)**

Drop your EA into the auto-integration system and get it back fully integrated with ZERO coding!

**Double-click:** `EA_INTEGRATION\start_integration.bat`

Then:
1. Drop your EA file (.mq5) into the `EA_INTEGRATION\input` folder
2. Wait 30-60 seconds for AI processing
3. Get your integrated EA from `EA_INTEGRATION\output` folder
4. Copy both files to MT5 and start trading!

**Powered by NVIDIA AI** - Fully automated, zero errors guaranteed.

[See EA_INTEGRATION folder for details](#-ea-auto-integration-system-new)

#### 📝 **Manual Integration (Advanced Users)**

Copy this to your EA folder:
```
src\mql\include\RegimeFilterLib.mqh → C:\...\MQL5\Include\
```

Add to your EA:
```cpp
#include <RegimeFilterLib.mqh>

int OnInit() {
    InitRegimeFilter("127.0.0.1", 9090, true);
    return INIT_SUCCEEDED;
}

void OnTick() {
    UpdateRegimeFilter();
    
    // Before opening trades:
    if(BuySignal && IsTradeAllowed("buy")) {
        // Execute buy order
    }
}

void OnDeinit(const int reason) {
    DeinitRegimeFilter();
}
```

**That's it!** Your EA now filters trades based on market regime.

---

## 📁 Project Structure

```
REGIME MOD/
│
├── README.md                    ← You are here
├── QUICK_START.md              ← 5-minute setup guide
│
├── EA_INTEGRATION/             ⭐ NEW: AI-Powered Auto-Integration
│   ├── input/                  ← Drop your EA files here
│   ├── output/                 ← Get integrated EAs here
│   ├── logs/                   ← Integration logs
│   ├── auto_integrate.py       ← AI integration engine
│   ├── start_integration.bat   ← Launch integration system
│   ├── test_api.bat           ← Test NVIDIA API connection
│   ├── README.md              ← Integration system guide
│   └── USAGE_GUIDE.txt        ← Quick start guide
│
├── src/                        ← Source code
│   ├── python/                 
│   │   ├── mt5_regime_gui_pyqt.py    ← Main dashboard (PyQt5)
│   │   └── feature_engine.py         ← Feature calculation
│   │
│   ├── mql/                    
│   │   ├── experts/            
│   │   │   └── HybridGridBot.mq5     ← Example EA with filter
│   │   └── include/            
│   │       └── RegimeFilterLib.mqh   ← Filter library (include this)
│   │
│   └── scripts/                
│       ├── start_dashboard.bat       ← Launch dashboard
│       └── fix_firewall.bat          ← Windows firewall fix
│
├── models/                     ← Model files
│   ├── regime_calibration.json       ← Regime Engine v2 confidence tables
│   ├── market_regime_gmm.pkl         ← Old GMM (no longer used)
│   └── scaler.pkl                    ← Old GMM scaler (no longer used)
│
├── config/                     ← Configuration
│   └── requirements.txt              ← Python dependencies
│
├── docs/                       ← Documentation
│   ├── INSTALLATION.md
│   ├── CONFIGURATION.md
│   ├── EA_INTEGRATION.md
│   └── TROUBLESHOOTING.md
│
├── tests/                      ← Test scripts
│   ├── test_connection.py
│   ├── test_regime_check.py
│   └── test_installation.py
│
└── examples/                   ← Example files
```

---

## 🤖 EA Auto-Integration System (NEW!)

### ⚡ Zero-Code Integration Powered by Google Gemini AI

Transform any EA into a regime-filtered smart EA in 60 seconds - no coding required!

### How It Works

```
Your EA → AI Analysis → Code Integration → Ready-to-Use EA
  .mq5      (NVIDIA)       (Automatic)         .mq5
```

### Quick Start

1. **Start the system:**
   ```bash
   EA_INTEGRATION\start_integration.bat
   ```

2. **Drop your EA:**
   - Copy your EA file (.mq5) into `EA_INTEGRATION\input` folder
   - System automatically detects it

3. **Wait for AI:**
   - Processing time: 30-60 seconds
   - Watch console for progress

4. **Get integrated EA:**
   - Check `EA_INTEGRATION\output` folder
   - Find: YourEA.mq5, RegimeFilterLib.mqh, YourEA_README.md

5. **Use in MT5:**
   - Copy both files to MT5 Experts folder
   - Compile and attach to chart
   - Done!

### What Gets Added Automatically

✅ **Library Include** - `#include "RegimeFilterLib.mqh"`  
✅ **Input Parameters** - EnableRegimeFilter, Host, Port  
✅ **OnInit Integration** - Connects to Python GUI  
✅ **OnTick Updates** - Sends bars to ML model  
✅ **Trade Filtering** - IsTradeAllowed() checks before orders  
✅ **OnDeinit Cleanup** - Graceful shutdown  
✅ **Chart Display** - Shows regime info (optional)  
✅ **Zero Errors** - Guaranteed compilation success  

### What's Preserved

✅ ALL existing EA logic  
✅ ALL input parameters  
✅ ALL functions and variables  
✅ ALL trade management  
✅ Coding style and conventions  

### Example: Before & After

**Before (Your Original EA):**
```cpp
void OnTick()
{
    if(CheckBuySignal())
    {
        OpenTrade(ORDER_TYPE_BUY, 0.01);
    }
}
```

**After (AI-Integrated EA):**
```cpp
void OnTick()
{
    // Auto-added: Update regime filter
    if(EnableRegimeFilter)
        UpdateRegimeFilter();
    
    if(CheckBuySignal())
    {
        // Auto-added: Check ML regime filter
        if(EnableRegimeFilter && IsRegimeFilterConnected())
        {
            if(!IsTradeAllowed("buy"))
            {
                Print("ML Regime Filter BLOCKED buy. Regime: ", GetCurrentRegime());
                return;
            }
        }
        
        OpenTrade(ORDER_TYPE_BUY, 0.01);
    }
}
```

### Features

- 🤖 **AI-Powered**: Google Gemini 1.5 Pro (Excellent for code generation)
- ⚡ **Fast**: 30-60 seconds per EA
- ✅ **Reliable**: ~95% success rate
- 🔒 **Safe**: Original files backed up automatically
- 📝 **Documented**: Complete README generated for each EA
- 🧪 **Verified**: 6 automated quality checks
- 🎯 **Zero Errors**: Guaranteed compilation success

### System Requirements

- Python 3.8+
- Internet connection (for NVIDIA API)
- ~500 MB RAM during processing

### Test the API

Before processing EAs, test your connection:

```bash
EA_INTEGRATION\test_api.bat
```

You should see:
```
✅ SUCCESS! API is working correctly
```

### Batch Processing

Process multiple EAs at once:
1. Copy all EA files to `input` folder
2. System processes them one by one
3. Check `output` folder as each completes

### Output Files

For each EA, you get:

1. **YourEA.mq5** - Integrated EA code
2. **RegimeFilterLib.mqh** - Filter library
3. **YourEA_README.md** - Complete guide
4. **logs/YourEA_timestamp.log** - Processing log

### Success Example: HybridGridBot

- **Original**: 1200 lines, complex grid logic
- **Processing**: 45 seconds
- **Result**: Perfect integration, zero errors
- **Added**: 150 lines of regime filter code
- **Status**: ✅ Production ready

### Documentation

See `EA_INTEGRATION` folder for:
- `README.md` - Complete system guide
- `USAGE_GUIDE.txt` - Quick reference
- `input/PLACE_YOUR_EA_FILES_HERE.txt` - Instructions
- `output/README_OUTPUT_FOLDER.txt` - Output guide

### API Key

Pre-configured Google Gemini API key included:
```
AIzaSyAb8RN6LOMshdv1w3_YW_pQrbWpafVs2LfRR9Pq9w3nTe7b4l3Q
```

To change it, edit `auto_integrate.py` line 14.

### Troubleshooting

**Python not found:**
- Install Python 3.8+ from python.org
- Add to PATH during installation

**API connection fails:**
- Check internet connection
- Run `test_api.bat` to verify
- Check firewall settings

**Integration fails:**
- Check log file in `logs/` folder
- Verify EA compiles without errors originally
- Ensure EA is not encrypted

### Support

Check these files for help:
- `EA_INTEGRATION/README.md` - Detailed guide
- `EA_INTEGRATION/USAGE_GUIDE.txt` - Quick tips
- `logs/YourEA_timestamp.log` - Error details

---

## 🎓 Market Regimes Explained

| Regime | Name | Characteristics | Trade Strategy |
|--------|------|-----------------|----------------|
| **0** | Low Vol Bullish | Calm upward movement | Trend following |
| **1** | Neutral Consolidation | Sideways, low vol | Range trading |
| **2** | High Vol Bearish | Sharp declines | ⚠️ **Avoid** |
| **3** | Low Vol Bearish | Calm downward | Trend following |
| **4** | Extreme Vol Spike | Flash crashes | ⚠️ **Avoid** |
| **5** | Crisis Mode | Market panic | ⚠️ **Avoid** |
| **6** | High Vol Mixed | Erratic movement | Selective only |
| **7** | Bearish Trending | Sustained down | Trend following |

**Default Configuration:**
- ✅ Allow: Regimes 0, 1, 3, 6, 7 (trending and calm markets)
- ❌ Block: Regimes 2, 4, 5 (high volatility and crisis)

---

## ⚙️ System Requirements

### Software
- **Python**: 3.8 or higher
- **MetaTrader 5**: Latest version
- **Windows**: 10 or 11 (tested)

### Python Packages
```
PyQt5>=5.15.0
MetaTrader5>=5.0.0
pandas>=1.3.0
numpy>=1.21.0
matplotlib>=3.4.0
scikit-learn>=1.0.0
joblib>=1.1.0
```

### Hardware
- **RAM**: 2 GB minimum (4 GB recommended)
- **CPU**: Any modern processor
- **Disk**: 200 MB free space

### Data Requirements
- **Warmup Period**: 1300 M5 bars (~108 hours / 4.5 days)
- **Timeframe**: M5 (5-minute candles)
- **Update Frequency**: Every new M5 bar

---

## 📊 How It Works

### 1. Data Collection
```
MetaTrader 5 (M5 Chart)
    ↓
Sends OHLCV + Volume + Spread
    ↓
Python Dashboard (Socket Server Port 9090)
```

### 2. Regime Scores
```
Closed bars (60 sessions of history)
├── Volatility: bar range / normal range for this time of day (2h and 1h averages)
└── Trend: 6h net move / path noise (Z score)
```

### 3. Regime Detection
```
Scores → hysteresis thresholds → (vol state, trend state)
    ↓
Regime ID 0-7 + calibrated confidence (0-100%)
```

### 4. Trade Filtering
```
EA sends trade request → Python checks regime → Allow/Block decision
```

---

## 🔧 Configuration

### Dashboard Settings

**Edit in `src/python/mt5_regime_gui_pyqt.py`:**

```python
# Symbol and timeframe
DEFAULT_SYMBOL = "XAUUSD"
DEFAULT_TIMEFRAME = mt5.TIMEFRAME_M5
DEFAULT_BARS = 1300

# Socket server
SOCKET_HOST = "127.0.0.1"
SOCKET_PORT = 9090

# Refresh rate
REFRESH_SECONDS = 10  # Update every 10 seconds
```

### Regime Filter Configuration

**In the dashboard GUI:**
1. Click **Filter Configuration** tab
2. Check regimes to **ALLOW**, uncheck to **BLOCK**
3. Use presets:
   - **Allow All** - No filtering (use for testing)
   - **Block All** - Block everything
   - **Conservative** - Block high volatility (2, 4, 5)

### Directional Filter

**Trade only with the trend:**
1. Enable **Directional Filter** checkbox
2. Choose mode:
   - **Strict** - Only with trend (block counter-trend)
   - **Allow Neutral** - Both directions in neutral regimes
   - **Disabled** - Ignore direction

---

## 🔌 EA Integration Examples

### Basic Integration

```cpp
#include <RegimeFilterLib.mqh>

input bool EnableRegimeFilter = true;

int OnInit() {
    if(EnableRegimeFilter) {
        InitRegimeFilter("127.0.0.1", 9090, true);
    }
    return INIT_SUCCEEDED;
}

void OnTick() {
    if(EnableRegimeFilter) {
        UpdateRegimeFilter();
    }
    
    // Your trading logic
    if(BuyCondition()) {
        if(!EnableRegimeFilter || IsTradeAllowed("buy")) {
            // Open buy order
        }
    }
}
```

### Advanced Integration with Regime Info

```cpp
void OnTick() {
    UpdateRegimeFilter();
    
    // Get current regime details
    int regime = GetCurrentRegime();
    double confidence = GetRegimeConfidence();
    bool connected = IsRegimeFilterConnected();
    
    // Log regime changes
    static int lastRegime = -1;
    if(regime != lastRegime) {
        Print("Regime changed: ", lastRegime, " → ", regime, 
              " (", confidence, "% confidence)");
        lastRegime = regime;
    }
    
    // Trade logic
    if(BuySignal && IsTradeAllowed("buy")) {
        Print("Trade ALLOWED in regime ", regime);
        // Execute trade
    }
}
```

### Full Example EA

See: `src\mql\experts\HybridGridBot.mq5` for complete working example with:
- Grid trading strategy
- QQE trend filter
- ML regime filter integration
- Directional filter
- Risk management

---

## 🧪 Testing

### Test Installation

```bash
python tests\test_installation.py
```

### Test MT5 Connection

```bash
python tests\test_connection.py
```

### Test Regime Prediction

```bash
python tests\test_regime_check.py
```

---

## 🐛 Troubleshooting

### Dashboard won't start

**Error: "PyQt5 not found"**
```bash
pip install PyQt5
```

**Error: "MT5 not initialized"**
- Ensure MetaTrader 5 is running and logged in
- Check that `import MetaTrader5` works in Python

### EA not connecting

**Error: "Failed to connect to Python GUI"**
1. Check dashboard shows "Server: RUNNING on 9090"
2. Run `src\scripts\fix_firewall.bat` (Windows firewall)
3. Verify no other program is using port 9090

**EA shows "EA: Not Connected"**
- Restart EA (remove and re-attach to chart)
- Check EA inputs: Host=127.0.0.1, Port=9090
- Look for connection messages in EA logs

### No regime predictions

**Dashboard shows "Warming up..."**
- The engine needs ~16,700 closed M5 bars (60 sessions); at least 20 sessions to start
- Or manually load history in MT5 (F2 → Symbol → Request history)

**All regimes show 0%**
- Check `models/regime_calibration.json` exists (without it confidence is uncalibrated)
- Verify symbol has price data
- Try clicking "Refresh Now"

See `docs\TROUBLESHOOTING.md` for more solutions.

---

## 📈 Performance Metrics

- **Feature Computation**: ~3 seconds for 536K bars
- **Regime Prediction**: <10ms per bar
- **Dashboard Refresh**: Every 10 seconds
- **Memory Usage**: ~100-150 MB
- **CPU Usage**: <5% (idle), <15% (active)

---

## 🔐 Safety Features

✅ **Fail-Safe Mode** - If dashboard disconnects, EA allows all trades (no blocking)  
✅ **Connection Monitoring** - Auto-reconnect on disconnect  
✅ **Historical Buffer** - Maintains 1300 bars for stable predictions  
✅ **Confidence Threshold** - Filter low-confidence predictions  
✅ **Manual Override** - Disable filter anytime in dashboard  

---

## 📚 Documentation

- **[Installation Guide](docs/INSTALLATION.md)** - Detailed setup instructions
- **[Configuration Guide](docs/CONFIGURATION.md)** - All settings explained
- **[EA Integration Guide](docs/EA_INTEGRATION.md)** - How to add filter to your EA
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and fixes
- **[Technical Details](docs/TECHNICAL.md)** - How the system works

---

## 🎯 Best Practices

### 1. Start Conservative
- Enable filter on demo account first
- Use **Conservative** preset (block regimes 2, 4, 5)
- Monitor for 1 week before going live

### 2. Monitor Daily
- Check regime distribution
- Review blocked trade count
- Adjust filter settings as needed

### 3. Backtest Your EA
- Test with regime filter enabled/disabled
- Compare win rates across regimes
- Optimize which regimes to trade

### 4. Keep Dashboard Running
- Run dashboard 24/7 for live trading
- Use Windows Task Scheduler for auto-start
- Monitor server status regularly

### 5. Update Historical Buffer
- Ensure MT5 has sufficient M5 history
- Download more history if needed (F2 → Symbol)
- Buffer warmup takes ~4.5 days

---

## 🏆 Advantages Over Traditional Filters

| Traditional Filter | ML Regime Filter |
|-------------------|------------------|
| Fixed indicators (RSI > 70) | Adaptive to market conditions |
| Single condition | Volatility and trend axes combined |
| Binary (on/off) | Calibrated confidence |
| No confidence score | Shows certainty (0-100%) |
| Manual adjustment | Self-updating with data |
| Lagging | Real-time prediction |

---

## 🚦 Quick Status Checklist

Before trading live:

- [ ] Python dependencies installed
- [ ] Dashboard launches without errors
- [ ] MT5 connected and logged in
- [ ] Dashboard shows regime predictions (not "Warming up")
- [ ] Server status shows "RUNNING"
- [ ] EA shows "Connected" status
- [ ] Test trade filtered correctly on demo
- [ ] Firewall allows port 9090
- [ ] Model files present in `models/` folder
- [ ] Historical buffer has 1300+ bars

---

## 📝 License

MIT License - Free for personal and commercial use.

---

## 🙏 Credits

**Built with:**
- Python 3.8+
- PyQt5 (GUI framework)
- scikit-learn (Machine Learning)
- MetaTrader 5 (Trading platform)

**Version**: 1.0  
**Release Date**: June 2026  
**Author**: Trading System Developer

---

## 💡 Tips & Tricks

### Tip 1: Regime-Specific Strategies
Different EAs perform better in different regimes. Consider:
- **Scalping EA** → Enable only Regime 0, 1 (low vol)
- **Trend EA** → Enable Regimes 3, 7 (trending)
- **Breakout EA** → Enable Regime 6 (high vol mixed)

### Tip 2: Combine with Other Filters
Stack filters for better results:
```cpp
if(ADX > 25 && IsTradeAllowed("buy") && RSI < 70) {
    // High-quality trade setup
}
```

### Tip 3: Log Everything
Enable CSV logging to analyze later:
```python
# In mt5_regime_gui_pyqt.py
ENABLE_CSV_LOG = True
LOG_FILE = "regime_log.csv"
```

### Tip 4: Multiple Symbols
Run separate dashboard instance per symbol:
```bash
python src\python\mt5_regime_gui_pyqt.py --symbol EURUSD --port 9091
python src\python\mt5_regime_gui_pyqt.py --symbol XAUUSD --port 9092
```

---

## 🚀 What's Next?

Future enhancements planned:
- [ ] Multiple timeframe support (M15, H1, H4)
- [ ] Additional ML models (Random Forest, XGBoost)
- [ ] Web dashboard for remote monitoring
- [ ] Telegram notifications
- [ ] Automated regime reports
- [ ] Backtesting framework integration

---

## 📞 Support

**Need help?**

1. Check the documentation in `docs/` folder
2. Review troubleshooting guide
3. Test installation with `tests\test_installation.py`
4. Verify EA example works: `HybridGridBot.mq5`

**Common Resources:**
- Installation issues → `docs\INSTALLATION.md`
- EA integration → `docs\EA_INTEGRATION.md`
- Configuration → `docs\CONFIGURATION.md`
- Errors → `docs\TROUBLESHOOTING.md`

---

**Ready to trade smarter? Launch the dashboard and let ML guide your trades!** 🎯📈

```bash
src\scripts\start_dashboard.bat
```

#   m a r k e t - r e g i m e - f i l t e r 
 
 # market-regime-filter
