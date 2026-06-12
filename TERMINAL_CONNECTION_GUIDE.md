# Terminal Connection Guide

## Problem
The terminal scanner may not detect all MT5 installations automatically, especially if they're installed in non-standard locations.

## Solution
We've added multiple ways to connect:

---

## Method 1: Connect to Running MT5 (RECOMMENDED)

This is the easiest and most reliable method:

### Steps:
1. **Open MetaTrader 5** and **log in to your account**
2. Keep MT5 running in the background
3. Open the PyQt Dashboard
4. Click **"Select Terminal"** button
5. Go to the **"Connect to Running MT5"** tab
6. Click **"Connect to Running MT5"** button
7. The dashboard will connect directly to the running MT5 instance
8. You'll see:
   - ✓ Connected!
   - Broker name
   - Account number
   - Installation path
9. Click **OK** to confirm

### Why This Works
- Direct API connection to running MT5
- No registry scanning needed
- Gets live terminal info
- Most reliable method

---

## Method 2: Auto-Detect Terminals

If you want to see all installed terminals:

### Steps:
1. Click **"Select Terminal"** button
2. Stay on the **"Auto-Detect"** tab
3. Click **"Scan for Terminals"**
4. The scanner will check:
   - Running MT5 instance (if logged in)
   - `%APPDATA%\MetaQuotes\Terminal\*` folders
   - Windows Registry entries
   - Common installation paths
5. Select a terminal from the list
6. Click **OK**

### What Gets Scanned
```
Checked Locations:
✓ Running MT5 API connection
✓ %APPDATA%\Roaming\MetaQuotes\Terminal\*
✓ HKEY_CURRENT_USER\Software\MetaQuotes\Terminal
✓ C:\Program Files\MetaTrader 5
✓ C:\Program Files (x86)\MetaTrader 5
```

---

## How Dashboard Works Now

### Startup Behavior
1. Dashboard opens **without fetching data**
2. Socket server starts (listening for EAs)
3. You see "No terminal selected" in the control panel
4. **You must select a terminal before regime data loads**

### After Terminal Selection
1. Terminal info displays in control panel (green text)
2. Dashboard automatically fetches market data
3. Regime prediction displays
4. Auto-refresh timer continues every 10 seconds
5. Socket server ready for EA connections

---

## Troubleshooting

### "No terminals found"
**Solution:** Use Method 1 (Connect to Running MT5)
- Ensure MT5 is open and logged in
- Try the manual connection tab

### "Failed to connect"
**Possible causes:**
1. MT5 not running → Open MT5
2. MT5 not logged in → Log in to account
3. Python MetaTrader5 package issue → Reinstall: `pip install MetaTrader5`

### "MT5 initialize failed"
**Solution:**
```bash
# Reinstall MT5 Python package
pip uninstall MetaTrader5
pip install MetaTrader5
```

### Scanner finds multiple terminals
**What to do:**
- If you have multiple MT5 installations, they'll all show up
- Select the one that's currently logged in
- Or use Method 1 to auto-connect to the running one

---

## Technical Details

### Scanner Methods Priority
1. **Direct API**: Tries `mt5.initialize()` first (most reliable)
2. **AppData scan**: Checks `%APPDATA%\MetaQuotes\Terminal\*`
3. **Registry scan**: Reads Windows Registry
4. **Common paths**: Checks Program Files

### Terminal Info Collected
```python
{
    "name": "Broker Name - Account 12345 (MT5 - Connected)",
    "path": "C:\\Program Files\\MetaTrader 5",
    "data_path": "C:\\Users\\...\\AppData\\Roaming\\MetaQuotes\\Terminal\\...",
    "version": "MT5",
    "broker": "Broker Name",
    "account": "12345",
    "connected": True
}
```

### Data Flow
```
User clicks "Select Terminal"
    ↓
Terminal selector dialog opens
    ↓
Method 1: Connect to running MT5
    OR
Method 2: Scan and select
    ↓
Terminal info saved
    ↓
Dashboard fetches market data
    ↓
Regime prediction starts
    ↓
Auto-refresh continues
```

---

## Best Practices

### For Single MT5 Installation
1. Open and log in to MT5
2. Use "Connect to Running MT5" method
3. Fastest and most reliable

### For Multiple MT5 Installations
1. Use "Auto-Detect" to see all terminals
2. Select the one currently logged in
3. Dashboard will use that terminal for data

### For Server/Automated Setup
1. Ensure MT5 is running and logged in before starting dashboard
2. Use programmatic connection via MT5 API
3. Consider auto-connecting on dashboard startup (future enhancement)

---

## Future Improvements

Planned features:
- [ ] Auto-connect to running MT5 on startup
- [ ] Remember last selected terminal
- [ ] Switch terminals without restart
- [ ] Multiple terminal connections simultaneously
- [ ] Terminal health monitoring
- [ ] Auto-reconnect on disconnect

---

## Summary

**Quick Start:**
1. Open MT5 → Log in
2. Open Dashboard → Click "Select Terminal"
3. Go to "Connect to Running MT5" tab → Click connect
4. Done! Dashboard is now fetching regime data

**The key change:** Dashboard no longer tries to fetch data at startup. You must select a terminal first, then it starts fetching data. This prevents connection errors when MT5 isn't ready.
