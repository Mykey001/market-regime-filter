# Regime Filter Warmup Troubleshooting Guide

## What You're Seeing

Your logs show:
```
[DEBUG] Response: {"allow_trade": false, "regime": -1, "confidence": 0.0, 
         "reason": "No regime data available for XAUUSD - waiting for warmup to complete"}
ML Regime Filter BLOCKED sell grid. Regime: -1, Confidence: 0.0%
```

**This is CORRECT behavior!** ✅ The fix is working - trades are blocked during warmup.

## Why This Happens

### Normal Warmup Process

```
1. EA connects to Python GUI             → ✅ Done
2. EA sends 1300 historical bars         → ❓ Check this
3. Python processes bars (10-30 sec)     → ⏳ Waiting
4. Python calculates regime              → ⏳ Waiting
5. Regime data becomes available         → ❌ Not yet
6. EA can trade with filters applied     → ⏳ Waiting
```

**Your EA is stuck at step 2 or 3** - Python hasn't finished processing the bars yet.

## Diagnostic Steps

### Step 1: Check Connection Logs

Scroll **UP** in your MT5 terminal to find the connection messages. You should see:

```
✅ GOOD - Connection successful:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Regime Filter: Connected to Python GUI at 127.0.0.1:9090
Regime Filter: Requesting 1300 historical bars from broker...
Regime Filter: Got 1300 CLOSED bars from broker. Sending to Python...
  Progress: 200 / 1300 bars sent...
  Progress: 400 / 1300 bars sent...
  Progress: 600 / 1300 bars sent...
  Progress: 800 / 1300 bars sent...
  Progress: 1000 / 1300 bars sent...
  Progress: 1200 / 1300 bars sent...
Regime Filter: Successfully sent all 1300 CLOSED bars!
  Waiting for Python to process and make first prediction...
```

If you DON'T see these messages, the EA didn't send the bars properly.

### Step 2: Check Dashboard Symbol

Look at your dashboard:
- **Dashboard symbol**: What symbol is selected in the dropdown? (shown as "GOLD", "XAUUSD", etc.)
- **EA symbol**: Your EA is running on XAUUSD

**Important**: Each symbol has its own regime data. If the dashboard shows GOLD but your EA is on XAUUSD, they won't match.

### Step 3: Check EA Management Tab

Click the "EA Management" tab in the dashboard and look for your EA:

```
Connected Expert Advisors

EA Name                Symbol    Account     Terminal         Status    Trades
XAUUSD_57357886       XAUUSD    57357886    MetaTrader 5    ● Connected    0
```

If your EA is NOT listed here, the connection isn't working properly.

### Step 4: Check Python Console

Look at the Python console (not the dashboard window) for messages:

```
✅ GOOD:
[BAR] Received bar from XAUUSD
[BUFFER] Symbol: XAUUSD, Buffer size: 1250 bars
[REGIME] Predicting regime for XAUUSD...
[REGIME] Result: Regime 1, Confidence: 99.6%

❌ BAD (No messages):
(Nothing printed - bars not received)
```

## Common Issues & Solutions

### Issue 1: Symbol Mismatch

**Symptom**: Dashboard shows regime data but EA gets regime: -1

**Solution**:
1. Check dashboard dropdown - switch to XAUUSD
2. Or check if broker uses different symbol name (XAUUSD vs GOLD vs XAU/USD)
3. EA Management tab should show your EA's symbol

### Issue 2: Bars Not Sent

**Symptom**: No "Progress: X / 1300 bars sent" messages in logs

**Solution**:
1. Remove EA from chart
2. Restart Python dashboard
3. Reattach EA to chart
4. Watch for connection messages

### Issue 3: Python Still Processing

**Symptom**: Bars sent but regime still -1 after 60+ seconds

**Solution**:
1. Check Python console for errors
2. Look for "Processing historical bars..." message
3. First-time processing takes 10-30 seconds
4. Subsequent updates are instant

### Issue 4: Socket Connection Lost

**Symptom**: Was working, then suddenly regime: -1

**Solution**:
1. Check dashboard "Server Status" indicator (top right)
2. Should show "Server: RUNNING on 9090"
3. If not running, click "Refresh EA List" button
4. Or restart dashboard

## What's Normal vs Abnormal

### ✅ NORMAL (First Connection)

```
Time 00:00 | EA connects
Time 00:01 | Sends 1300 bars (takes 1-2 seconds)
Time 00:02 to 00:30 | regime: -1, trades blocked ← YOU ARE HERE
Time 00:31 | Regime calculated, trades allowed/blocked based on filters
```

**Expectation**: 10-30 seconds of warmup on first connection is normal.

### ❌ ABNORMAL

```
Time 00:00 | EA connects
Time 01:00 | Still regime: -1 after 60 seconds
Time 02:00 | Still regime: -1 after 120 seconds
```

**Problem**: Bars didn't send OR Python isn't processing them.

## Quick Fix Steps

If it's been more than 60 seconds and still showing regime: -1:

### Option 1: Restart Everything
```
1. Close MT5 EA (remove from chart)
2. Restart Python dashboard
3. Wait for "Dashboard ready" message
4. Reattach EA to chart
5. Watch connection logs carefully
```

### Option 2: Check Connection
```
1. In dashboard, click "EA Management" tab
2. Click "Refresh EA List" button
3. Check if your EA appears in the list
4. If not, EA isn't connected properly
```

### Option 3: Check Symbol Data
```
1. In dashboard, select dropdown to XAUUSD
2. Click "Refresh Now" button
3. Charts should update with XAUUSD data
4. Try EA again
```

## Understanding the Dashboard vs EA

### Dashboard Shows:
- **Selected symbol** from dropdown (could be any symbol)
- Global regime filter settings
- Charts for the selected symbol

### EA Uses:
- **Its own symbol** (the chart it's attached to)
- Per-EA filter settings (or global if not configured)
- Requests regime for its specific symbol

**They are independent!** Dashboard showing "Regime 1" for GOLD doesn't mean EA on XAUUSD will see the same regime.

## Expected Timeline

| Time | Event | Status |
|------|-------|--------|
| 0:00 | EA starts | Connecting... |
| 0:01 | Connected | Sending bars... |
| 0:02 | 1300 bars sent | Processing... |
| 0:03-0:30 | Python processing | regime: -1 ⏳ |
| 0:31 | Processing done | regime: 0-7 ✅ |
| 0:32+ | Normal operation | Filtering trades |

## Log Reduction

I've updated the library to reduce log spam. Instead of printing on every tick:

**Before** (every tick):
```
[REGIME FILTER] Trade BLOCKED - No regime data available (warming up)
[REGIME FILTER] Trade BLOCKED - No regime data available (warming up)
[REGIME FILTER] Trade BLOCKED - No regime data available (warming up)
... (hundreds of lines)
```

**After** (once per 10 seconds):
```
[REGIME FILTER] Trade BLOCKED - No regime data available yet (still warming up)
  Symbol: XAUUSD | Waiting for Python to process historical bars...
[10 seconds later...]
[REGIME FILTER] Trade BLOCKED - No regime data available yet (still warming up)
  Symbol: XAUUSD | Waiting for Python to process historical bars...
```

**To apply**: Recompile your EA in MetaEditor.

## Verify It's Working

Once warmup completes, you should see:

### In MT5 Logs:
```
[REGIME FILTER] Trade BLOCKED - No regime data available yet (still warming up)
  Symbol: XAUUSD | Waiting for Python to process historical bars...
[10 seconds later...]
[DEBUG] Parsing response: {"allow_trade": true, "regime": 1, "confidence": 99.6, ...}
[DEBUG] allow_trade found: value=TRUE
ML Regime Filter ALLOWED sell grid. Regime: 1, Confidence: 99.6%
```

### In Dashboard:
- Symbol dropdown: XAUUSD selected
- Regime: Shows "Regime 1 - Low Vol Bullish" (or whatever current regime is)
- Confidence: Shows 99.6%
- Trade Status: Shows ✓ ALLOWED or ✗ BLOCKED based on filters
- EA Management tab: Shows your EA connected

## Still Not Working?

If after following all steps above, regime is still -1 after 2+ minutes:

### Check These:

1. **Python Console Errors**:
   - Look for red error messages
   - Common: "No data for symbol XAUUSD"
   - Common: "Feature calculation failed"

2. **MT5 Data Available**:
   - In MT5, open a chart for XAUUSD M5
   - Verify you have historical data loaded
   - Right-click chart → "Refresh" to load more bars

3. **Firewall Blocking**:
   - Run `src\scripts\fix_firewall.bat` as Administrator
   - Restart Python dashboard

4. **Port Already in Use**:
   - Close other applications using port 9090
   - Or change port in dashboard settings

## Contact Points

**Check These Files**:
- `README.md` - Complete system guide
- `QUICK_START.md` - Setup instructions
- `EA_MANAGEMENT_FIX.md` - Fix documentation
- `CHANGELOG.md` - Version history

**Log Files to Review**:
- MT5 Terminal (Experts tab) - EA connection logs
- Python Console - Server messages
- Dashboard - EA Management tab

---

**Remember**: 10-30 seconds of warmup on first connection is NORMAL and EXPECTED. The fix is working correctly by blocking trades during this period. Be patient and let Python finish processing the bars.
