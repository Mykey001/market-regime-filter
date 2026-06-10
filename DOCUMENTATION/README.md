# Market Regime Trading Control Center

![Version](https://img.shields.io/badge/version-1.0-blue)
![Python](https://img.shields.io/badge/python-3.8+-green)
![License](https://img.shields.io/badge/license-MIT-orange)

**Professional trading GUI** that uses machine learning to detect market regimes and filter EA trades in real-time.

---

## 🚀 Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Launch GUI

**Windows**: Double-click `start_gui.bat`

**Command Line**:
```bash
python regime_trading_gui.py
```

### 3. Connect MetaTrader

1. Copy `MT4_RegimeFilter.mq4` (or MT5 version) to MetaTrader Experts folder
2. Compile in MetaEditor
3. Attach to M5 chart
4. Verify green connection indicator in GUI

---

## 📊 Features

### Real-Time Regime Detection
- **10 market regimes** automatically identified
- **Live confidence scores** for each prediction
- **Visual indicators** with color-coding

### Intelligent Trade Filtering
- **Block trades in unfavorable regimes** (crisis, choppy markets)
- **Allow trades in trending/calm regimes**
- **Configurable confidence thresholds**

### Professional Interface
- ✅ Multi-tab layout (Monitor, Filter, Log, Statistics)
- ✅ Real-time regime probabilities display
- ✅ Complete trade decision audit trail
- ✅ Quick preset configurations

### Socket-Based EA Integration
- ✅ Works with **any MetaTrader EA**
- ✅ Bidirectional communication (MT4 ↔ Python)
- ✅ Auto-reconnection on disconnect
- ✅ Template code included

---

## 📁 Project Structure

```
REGIME MOD/
│
├── regime_trading_gui.py          # Main GUI application
├── feature_engine.py              # Feature computation (14 indicators)
├── market_regime_gmm.pkl          # Trained Bayesian GMM model
├── scaler.pkl                     # RobustScaler for normalization
│
├── MT4_RegimeFilter.mq4           # MetaTrader 4 EA template
├── MT5_RegimeFilter.mq5           # MetaTrader 5 EA template
│
├── requirements.txt               # Python dependencies
├── start_gui.bat                  # Windows launcher script
│
├── README.md                      # This file
├── TRADING_GUI_SETUP_GUIDE.md     # Complete setup instructions
├── ANALYSIS_REPORT.md             # Full system analysis
└── TECHNICAL_SUMMARY.md           # Quick reference
```

---

## 🎯 How It Works

### 1. Data Flow

```
MT4/MT5 Chart (M5)
       │
       │ Every 5 minutes
       ▼
   [Socket Send]
       │
       ▼
Python GUI receives OHLCV data
       │
       ▼
Feature Engine computes 14 indicators
       │
       ▼
GMM Model predicts regime (0-9)
       │
       ▼
Filter evaluates trade request
       │
       ▼
   [Socket Send]
       │
       ▼
EA receives ALLOW/BLOCK decision
```

### 2. 10 Market Regimes

| ID | Name | Trade Strategy |
|----|------|----------------|
| 0 | High Vol Trending | Scalping |
| 1 | **Normal/Calm** | Mean reversion (most common) |
| 2 | Volatile Expansion | Breakout trading |
| 3 | **Bullish Trending** | Trend following |
| 4 | Extreme Vol Spike | ⚠️ **Avoid trading** |
| 5 | **Crisis Mode** | ⚠️ **Avoid trading** |
| 6 | High Vol Consolidation | Range trading |
| 7 | **Bearish Trending** | Trend following |
| 8 | **Bullish Momentum** | Momentum strategies |
| 9 | Choppy/Erratic | ⚠️ **Avoid trading** |

### 3. 14 Technical Features

**Volatility**: 1h vol, 1d vol, ATR, Bollinger width  
**Trend**: Short EMA, long EMA, MACD, price position  
**Momentum**: RSI, RSI rate, skewness  
**Microstructure**: Volume ratio, spread, variance ratio

---

## ⚙️ Configuration Examples

### Conservative (Safe Trading Only)

```
Minimum Confidence: 70%
Allowed Regimes: 1, 3, 8
Auto Mode: ✓
```

### Aggressive (All Trending)

```
Minimum Confidence: 50%
Allowed Regimes: 0, 3, 7, 8
Auto Mode: ✓
```

### Crisis Avoidance

```
Minimum Confidence: 60%
Blocked Regimes: 4, 5, 9
Auto Mode: ✓
```

---

## 🔧 System Requirements

### Software
- **Python**: 3.8 or later
- **MetaTrader**: MT4 or MT5
- **OS**: Windows 10/11 (tested)

### Hardware
- **RAM**: 2 GB minimum
- **CPU**: Any modern processor
- **Disk**: 100 MB free space

### Data Requirements
- **Warmup Period**: 626 M5 bars (≈52 hours)
- **Update Frequency**: Every 5 minutes
- **Buffer Size**: Last 1000 bars kept in memory

---

## 📚 Documentation

- **[Complete Setup Guide](TRADING_GUI_SETUP_GUIDE.md)** - Step-by-step installation and configuration
- **[Analysis Report](ANALYSIS_REPORT.md)** - Detailed system analysis and recommendations
- **[Technical Summary](TECHNICAL_SUMMARY.md)** - Quick reference for developers

---

## 🐛 Troubleshooting

### GUI won't start
```bash
# Check Python version
python --version

# Reinstall dependencies
pip install -r requirements.txt --force-reinstall
```

### EA not connecting
1. Verify port 9090 is not blocked by firewall
2. Check that "Start Server" was clicked in GUI
3. Ensure EA parameters match GUI settings (host/port)

### No regime predictions
- Wait for 626 bars warmup (≈52 hours)
- Check that chart is M5 timeframe
- Verify model files exist in same directory

See **[Setup Guide](TRADING_GUI_SETUP_GUIDE.md)** for more troubleshooting tips.

---

## 🎨 Screenshots

### Main Interface
```
┌─────────────────────────────────────────────────┐
│ Connection & Control                            │
│ Host: 127.0.0.1  Port: 9090  ● [Auto Mode ✓]  │
├─────────────────────────────────────────────────┤
│ Current Market Regime                           │
│ Regime:        1: Normal/Calm                   │
│ Confidence:    78.5%                            │
│ Trade Status:  ALLOWED ✓                        │
├─────────────────────────────────────────────────┤
│ Regime Probabilities                            │
│ 0  High Vol Trending         2.1%              │
│ 1  Normal/Calm              78.5% ◄── Current  │
│ 2  Volatile Expansion        5.2%              │
│ ...                                             │
└─────────────────────────────────────────────────┘
```

---

## 🤝 Integration with Your EA

Add this to your existing EA:

```mql4
#include <socket-library-mt4-mt5.mqh>

ClientSocket* regimeFilter = NULL;

int OnInit()
{
   regimeFilter = new ClientSocket("127.0.0.1", 9090);
   return(INIT_SUCCEEDED);
}

bool CheckRegime(string action)
{
   if(regimeFilter == NULL) return true;
   
   string json = "{\"type\":\"trade_request\",";
   json += "\"symbol\":\"" + Symbol() + "\",";
   json += "\"action\":\"" + action + "\"}";
   
   regimeFilter.Send(json);
   string response = regimeFilter.Receive("\r\n", 1000);
   
   return (StringFind(response, "\"allow_trade\":true") >= 0);
}

// In your trade logic:
if(BuySignal && CheckRegime("buy"))
{
   OrderSend(...);  // Execute trade
}
```

---

## 📈 Performance

- **Feature computation**: ~3 seconds for 536K bars
- **Regime prediction**: <10ms per bar
- **GUI refresh rate**: 1 second
- **Memory usage**: ~100 MB
- **CPU usage**: <5% (idle), <20% (active)

---

## 🔐 Safety Features

- ✅ **Fail-safe defaults**: Allows trades if GUI disconnects
- ✅ **Audit trail**: All decisions logged with timestamps
- ✅ **Manual override**: Disable auto mode anytime
- ✅ **Confidence thresholds**: Prevent low-confidence predictions

---

## 📝 License

MIT License - Free for personal and commercial use

---

## 🎓 Learning Resources

### Understand the Model
1. Read `ANALYSIS_REPORT.md` for full system breakdown
2. Check `feature_engine.py` docstrings for feature explanations
3. Review `TECHNICAL_SUMMARY.md` for quick reference

### Customize for Your Strategy
1. Adjust regime filters in GUI
2. Modify confidence thresholds
3. Add logging to track performance
4. Backtest with historical data

---

## 🚦 Quick Status Check

Run this to verify everything is ready:

```bash
# Check Python
python --version

# Check dependencies
python -c "import PyQt5, numpy, pandas, sklearn, joblib; print('All dependencies OK')"

# Check model files
dir *.pkl

# Test feature engine
python feature_engine.py
```

All green? You're ready to launch! 🎉

---

## 💡 Pro Tips

1. **Start conservative**: Enable only regimes 1, 3, 8 initially
2. **Monitor for a week**: Review statistics daily
3. **Adjust based on results**: Fine-tune confidence and regime filters
4. **Keep buffer full**: Avoid restarting MT unnecessarily
5. **Log everything**: Enable CSV logging for analysis

---

## 📞 Support

**Found a bug?** Check the troubleshooting section in `TRADING_GUI_SETUP_GUIDE.md`

**Need help?** Review these documents:
- Setup issues → `TRADING_GUI_SETUP_GUIDE.md`
- Technical details → `TECHNICAL_SUMMARY.md`
- System analysis → `ANALYSIS_REPORT.md`

---

**Built with Python, PyQt5, and Machine Learning** ⚡

**Version 1.0 | June 2026**
