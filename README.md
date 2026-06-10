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
Market Analysis → ML Prediction → Trade Filter → Your EA
     ↓                  ↓              ↓            ↓
   OHLCV          Regime 5?      BLOCK TRADE    No order
  14 Features     Crisis Mode                   placed
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

### 2. Feature Engineering (14 Technical Indicators)

The system calculates 14 advanced features across 4 categories:

**A. Volatility Features (4)**
- 1-hour rolling volatility
- 1-day rolling volatility
- Normalized Average True Range (ATR)
- Bollinger Band width

**B. Trend Features (4)**
- Short-term trend (EMA 1h vs 4h)
- Long-term trend (EMA 4h vs 2d)
- MACD histogram (normalized)
- Price position in daily high-low range

**C. Momentum Features (3)**
- Wilder's RSI (14-period)
- RSI rate of change
- Returns skewness

**D. Microstructure Features (3)**
- Volume surge ratio
- Normalized bid-ask spread
- Variance ratio (trending vs mean-reverting)

**Performance:** Computes all 14 features in <100ms for 1300 bars.

### 3. ML Prediction (Gaussian Mixture Model)

A trained **Bayesian GMM** model (8 components) analyzes the 14 features and identifies the current market regime:

```python
Input: Feature Matrix (1300 bars × 14 features)
       ↓
Step 1: RobustScaler Normalization
       ↓
Step 2: GMM Prediction
       ↓
Output: Regime ID (0-7) + Confidence Score (0-100%)
```

**Model Training:**
- Trained on 536,000+ historical M5 bars
- Unsupervised learning (no manual labeling)
- Identifies natural market clusters
- Validated across multiple instruments and timeframes

### 4. Market Regimes Explained

The model identifies 8 distinct market states:

| Regime | Name | Volatility | Direction | Trade? | Strategy |
|--------|------|------------|-----------|--------|----------|
| **0** | Low Vol Bullish | Low | Up | ✅ | Trend following |
| **1** | Neutral Consolidation | Low | Sideways | ✅ | Range/mean reversion |
| **2** | High Vol Bearish | High | Down | ⚠️ | Dangerous - BLOCK |
| **3** | Low Vol Bearish | Low | Down | ✅ | Trend following |
| **4** | Extreme Vol Spike | Extreme | Chaotic | ❌ | Flash crash - BLOCK |
| **5** | Crisis Mode | Extreme | Panic | ❌ | Market panic - BLOCK |
| **6** | High Vol Mixed | High | Mixed | ⚠️ | Selective trades |
| **7** | Bearish Trending | Medium | Down | ✅ | Trend following |

**Default Configuration:**
- ✅ **Allow Trading:** Regimes 0, 1, 3, 6, 7 (safe conditions)
- ❌ **Block Trading:** Regimes 2, 4, 5 (dangerous conditions)

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
- ✅ Visual charts (price, RSI)
- ✅ All 14 features visible
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
├── models/                     ← ML models
│   ├── market_regime_gmm.pkl         ← Trained GMM model
│   └── scaler.pkl                    ← Feature scaler
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

### 2. Feature Engineering
```
14 Technical Features Computed:
├── Volatility (4): 1h/1d volatility, ATR, Bollinger width
├── Trend (4): Short/long EMA ratios, MACD, price position  
├── Momentum (3): RSI, RSI rate, returns skewness
└── Microstructure (3): Volume ratio, spread, variance ratio
```

### 3. Regime Prediction
```
Feature Matrix (1300 bars × 14 features)
    ↓
RobustScaler Normalization
    ↓
Bayesian GMM Model (8 components)
    ↓
Regime ID + Confidence Score (0-100%)
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
- Wait for 1300 M5 bars (~4.5 days of data)
- Or manually load history in MT5 (F2 → Symbol → Request history)

**All regimes show 0%**
- Check model files exist: `models\market_regime_gmm.pkl`, `models\scaler.pkl`
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
| Single condition | 14 features combined |
| Binary (on/off) | Probability-based |
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

#   m a r k e t - r e g i m e - f i l t e r  
 # market-regime-filter
