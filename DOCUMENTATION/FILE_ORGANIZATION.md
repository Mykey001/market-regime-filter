# Production File Organization

## 📁 Recommended Folder Structure

```
REGIME MOD/
│
├── 📂 CORE_SYSTEM/                    ← Main production files
│   ├── regime_trading_gui.py          ← Main GUI application
│   ├── feature_engine.py              ← Feature computation
│   ├── market_regime_gmm.pkl          ← Trained model
│   ├── scaler.pkl                     ← Scaler
│   ├── requirements.txt               ← Python dependencies
│   └── start_gui.bat                  ← Windows launcher
│
├── 📂 MT5_EA/                         ← MetaTrader Expert Advisors
│   ├── MT5_RegimeFilter.mq5           ← Main filter EA
│   ├── MT4_RegimeFilter.mq4           ← MT4 version
│   └── INTEGRATION_EXAMPLES.mq5       ← Code examples
│
├── 📂 DOCUMENTATION/                   ← User guides
│   ├── README.md                      ← Quick start
│   ├── QUICK_START.md                 ← 5-minute guide
│   ├── TRADING_GUI_SETUP_GUIDE.md     ← Complete setup
│   ├── HOW_TO_INTEGRATE_YOUR_EA.md    ← Integration guide
│   ├── ANALYSIS_REPORT.md             ← System analysis
│   ├── TECHNICAL_SUMMARY.md           ← API reference
│   ├── PROJECT_SUMMARY.md             ← Overview
│   ├── FIXES_AND_IMPROVEMENTS.md      ← Changelog
│   └── INTEGRATION_DIAGRAM.txt        ← Visual guides
│
├── 📂 UTILITIES/                       ← Helper scripts
│   ├── test_installation.py           ← System test
│   ├── test_connection.py             ← Connection test
│   ├── quick_warmup.py                ← Synthetic data (testing)
│   ├── load_historical_data.py        ← CSV loader
│   ├── simple_test_server.py          ← Debug server
│   └── fix_firewall.bat               ← Firewall fixer
│
├── 📂 TROUBLESHOOTING/                 ← Problem solving
│   ├── TROUBLESHOOTING_4014.md        ← Connection errors
│   ├── DEPLOYMENT_CHECKLIST.md        ← Deployment guide
│   └── STARTUP_CHECKLIST.txt          ← Quick checklist
│
└── 📂 ARCHIVE/                         ← Old/backup files
    ├── inspect_model.py               ← Model inspector
    └── (other test files)
```

---

## 🎯 Quick Access Guide

### For Daily Trading

**Run This:**
```bash
cd "REGIME MOD/CORE_SYSTEM"
python regime_trading_gui.py
```

Or double-click: `CORE_SYSTEM/start_gui.bat`

### For MT5 Integration

**Copy This:**
```
REGIME MOD/MT5_EA/MT5_RegimeFilter.mq5
→ Copy to: MT5/MQL5/Experts/
```

### For Help

**Read These (in order):**
1. `DOCUMENTATION/QUICK_START.md`
2. `DOCUMENTATION/HOW_TO_INTEGRATE_YOUR_EA.md`
3. `TROUBLESHOOTING/` folder if issues

---

## 🧹 Clean Up Script

Run this to organize your current folder:

```bash
python organize_files.py
```

---

## 📦 What to Keep vs Archive

### ✅ KEEP (Production)

- ✅ `regime_trading_gui.py`
- ✅ `feature_engine.py`
- ✅ `market_regime_gmm.pkl`
- ✅ `scaler.pkl`
- ✅ `MT5_RegimeFilter.mq5`
- ✅ `requirements.txt`
- ✅ `start_gui.bat`
- ✅ All documentation in DOCUMENTATION/

### 📁 ARCHIVE (Testing/Debug)

- 📁 `quick_warmup.py` (only for testing)
- 📁 `simple_test_server.py` (debugging only)
- 📁 `test_*.py` (testing tools)
- 📁 `inspect_model.py` (one-time use)

### 🗑️ DELETE (If Confident)

- 🗑️ Old versions with errors
- 🗑️ Duplicate files
- 🗑️ `historical_data.csv` (if exists and not needed)

---

## 🚀 Production Deployment Checklist

### For Your Trading PC

```
REGIME MOD/CORE_SYSTEM/
├── regime_trading_gui.py        ← Run this
├── feature_engine.py
├── market_regime_gmm.pkl
├── scaler.pkl
├── requirements.txt
└── start_gui.bat
```

### For MT5 Terminal

```
MT5/MQL5/Experts/
└── MT5_RegimeFilter.mq5         ← Attach to charts
```

### Documentation (Keep Accessible)

```
REGIME MOD/DOCUMENTATION/
├── QUICK_START.md               ← Read first
├── HOW_TO_INTEGRATE_YOUR_EA.md  ← For integration
└── TROUBLESHOOTING_4014.md      ← If errors
```

---

## 🔄 Version Control

If using Git:

```gitignore
# .gitignore
__pycache__/
*.pyc
*.log
test_*.py
quick_warmup.py
simple_test_server.py
historical_data.csv
ARCHIVE/
```

Keep in Git:
- CORE_SYSTEM/
- MT5_EA/
- DOCUMENTATION/
- requirements.txt
- README.md
