# EPR_ML_DataLogger_v1 (1).mq5 - Regime Filter Integration Complete (LOCAL)

## Integration Date
2026-06-13 01:31:48

## Integration Method
**LOCAL RULE-BASED INTEGRATION** (No AI API required!)

This EA was integrated using a rule-based pattern matching system that doesn't require any AI API keys. The integration is based on proven patterns from successful integrations like HybridGridBot.

## What Was Added

### 1. Library Include
```cpp
#include "RegimeFilterLib.mqh"
```

### 2. Input Parameters
```cpp
input bool     EnableRegimeFilter = true;      // Enable ML regime filter
input string   RegimeFilterHost = "127.0.0.1"; // Python GUI host
input int      RegimeFilterPort = 9090;        // Python GUI port
```

### 3. Initialization (in OnInit)
```cpp
if(EnableRegimeFilter)
{
    if(InitRegimeFilter(RegimeFilterHost, RegimeFilterPort, EnableRegimeFilter))
    {
        Print("ML Regime Filter: Successfully connected to Python GUI");
    }
}
```

### 4. Real-Time Updates (in OnTick)
```cpp
if(EnableRegimeFilter)
{
    UpdateRegimeFilter();
}
```

### 5. Trade Filtering
```cpp
if(EnableRegimeFilter && IsRegimeFilterConnected())
{
    if(!IsTradeAllowed("buy"))  // or "sell"
    {
        Print("ML Regime Filter BLOCKED trade");
        return;  // Trade cancelled
    }
}
```

### 6. Cleanup (in OnDeinit)
```cpp
if(EnableRegimeFilter)
{
    DeinitRegimeFilter();
}
```

## How to Use

### Step 1: Copy Files to MT5
1. Copy BOTH files to your MT5 Experts folder:
   - `EPR_ML_DataLogger_v1 (1).mq5` (your integrated EA)
   - `RegimeFilterLib.mqh` (regime filter library)
   
Location: `C:\Users\YourName\AppData\Roaming\MetaQuotes\Terminal\[BROKER_ID]\MQL5\Experts\`

### Step 2: Start Python GUI
1. Navigate to: `REGIME MOD\CORE_SYSTEM\`
2. Double-click: `start_gui.bat`
3. Click **"Start Server"** button
4. Verify: `Server: RUNNING on 127.0.0.1:9090`

### Step 3: Attach EA to Chart
1. Open MT5
2. Open any chart (recommended: M5 timeframe)
3. Drag `EPR_ML_DataLogger_v1 (1).mq5` onto chart
4. Check "Allow DLL imports"
5. Check "Allow WebRequest"
6. Set `EnableRegimeFilter = true`
7. Click OK

### Step 4: Verify Connection
Check Experts tab for:
```
=== Initializing ML Regime Filter ===
ML Regime Filter: Successfully connected to Python GUI
```

## Regime Behaviors

| Regime | Name | Buys | Sells | Description |
|--------|------|------|-------|-------------|
| 1 | Normal/Calm | ✅ | ✅ | Stable conditions |
| 2 | Low Vol | ✅ | ✅ | Small movements |
| 3 | Bullish Trending | ✅ | 🚫 | Strong uptrend |
| 4 | Extreme Vol Spike | 🚫 | 🚫 | Very dangerous |
| 5 | Crisis Mode | 🚫 | 🚫 | Market panic |
| 6 | High Volatility | ⚠️ | ⚠️ | Use caution |
| 7 | Bearish Trending | 🚫 | ✅ | Strong downtrend |
| 8 | Bullish Momentum | ✅ | 🚫 | Very bullish |
| 9 | Choppy/Erratic | 🚫 | 🚫 | Random noise |

*Customize these in Python GUI Settings*

## Troubleshooting

### EA shows "DISCONNECTED"
- Check Python GUI is running
- Click "Start Server" in GUI
- Verify port 9090 is open

### Compilation errors
- Ensure `RegimeFilterLib.mqh` is in same folder as EA
- Check MT5 allows WebRequest to 127.0.0.1
- Recompile EA (F7)

### Trades not being placed
- Check current regime (4, 5, 9 block all trades)
- Verify filter is connected
- Check other EA filters

## Integration Quality

✅ Rule-based integration (no AI errors)  
✅ Proven pattern matching  
✅ Based on successful examples  
✅ 100% deterministic results  
✅ No API dependencies  

---

**Integration Method:** LOCAL (Rule-Based)  
**Quality:** Verified  
**Status:** Ready to Use  

Happy Trading! 🚀
