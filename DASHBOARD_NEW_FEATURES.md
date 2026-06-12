# PyQt Dashboard - New Features

## Overview
The PyQt dashboard has been enhanced with two major features:

1. **Terminal Scanner** - Automatically detect and select MetaTrader terminals on Windows
2. **EA Management System** - Manage multiple EAs with individual filter configurations

---

## 1. Terminal Scanner

### What It Does
Automatically scans your Windows machine for installed MetaTrader 4 and MetaTrader 5 terminals.

### How to Use
1. Click the **"Select Terminal"** button in the top control panel
2. A dialog will open and automatically scan for terminals
3. You'll see a list of all detected MT4/MT5 installations
4. Double-click or select a terminal and click OK
5. The selected terminal is displayed in the control panel

### What It Scans
- Windows Registry entries (HKEY_CURRENT_USER and HKEY_LOCAL_MACHINE)
- Common installation paths:
  - `C:\Program Files\MetaTrader 4`
  - `C:\Program Files\MetaTrader 5`
  - `C:\Program Files (x86)\MetaTrader 4`
  - `C:\Program Files (x86)\MetaTrader 5`

### Terminal Information Displayed
- Broker name
- Version (MT4 or MT5)
- Installation path
- Data path

---

## 2. EA Management System

### What It Does
Allows you to manage multiple Expert Advisors, each with their own filter configurations.

### Features

#### Individual EA Configurations
Each EA can have different settings:
- **Allowed Regimes** - Choose which regimes this EA can trade in
- **Min Confidence** - Set minimum confidence threshold (0-100%)
- **Directional Filter** - Configure counter-trend blocking
  - Strict: Only with trend
  - Allow Neutral: Both ways in neutral regimes
  - Disabled: Allow all directions
- **Volatility Filter** - Filter by volatility level (high/low/any)

#### EA Management Tab
The new "EA Management" tab shows:
- **EA Name** - Identifier of the EA
- **Symbol** - Trading pair (e.g., XAUUSD, EURUSD)
- **Account** - Account number
- **Filter Config** - Human-readable summary of filter rules
- **Actions** - Configure button for each EA

### How to Use

#### Step 1: EA Connection
When an EA connects to the dashboard, it automatically registers itself with a handshake message containing:
```json
{
  "type": "handshake",
  "ea_name": "HybridGridBot",
  "terminal": "MetaTrader 5",
  "symbol": "XAUUSD",
  "account": "12345678"
}
```

#### Step 2: Configure EA
1. Go to the **"EA Management"** tab
2. Find your EA in the list
3. Click the **"Configure"** button
4. Set up filters specific to this EA:
   - Check/uncheck regimes to allow
   - Set minimum confidence threshold
   - Configure directional filter mode
   - Enable volatility filter if needed
5. Click **OK** to save

#### Step 3: Trade Requests
When the EA requests a trade, the dashboard uses that EA's specific configuration:
```json
{
  "type": "trade_request",
  "ea_name": "HybridGridBot",
  "symbol": "XAUUSD",
  "action": "buy"
}
```

The dashboard responds with:
```json
{
  "allow_trade": true,
  "regime": 3,
  "confidence": 78.5,
  "reason": "EA 'HybridGridBot': Regime 4 (bearish): BUY ALLOWED"
}
```

### Example Use Cases

#### Conservative EA for High Volatility
```
EA Name: SafeGrid
Allowed Regimes: R1, R2, R3, R4, R7 (block R5, R6 - crisis modes)
Min Confidence: 70%
Directional Filter: Strict
Volatility Filter: Low only
```

#### Aggressive EA for Trending Markets
```
EA Name: TrendHunter
Allowed Regimes: R1, R4, R8 (trending regimes only)
Min Confidence: 60%
Directional Filter: Strict (with trend only)
Volatility Filter: High only
```

#### Neutral EA for Range Trading
```
EA Name: RangeBot
Allowed Regimes: R2 (neutral/consolidation)
Min Confidence: 50%
Directional Filter: Allow Neutral (both directions)
Volatility Filter: Low only
```

---

## Benefits

### Multiple Strategies Simultaneously
Run different EAs with different risk profiles on the same dashboard:
- Conservative EA blocks high-volatility regimes
- Aggressive EA only trades trending regimes
- Range EA only trades neutral/consolidation regimes

### Centralized Monitoring
- See all connected EAs at a glance
- Monitor trade counts and connection status
- Easily modify configurations without restarting EAs

### Per-EA Risk Management
- Each EA has independent filter rules
- Different confidence thresholds per strategy
- Custom directional filters per EA logic

---

## Integration with MQL5 EAs

### Required Handshake
Your EA must send a handshake when connecting:

```mql5
string handshake = "{\"type\":\"handshake\",\"ea_name\":\"MyEA\",\"terminal\":\"MT5\",\"symbol\":\"XAUUSD\",\"account\":\"12345\"}\\n";
if(SocketSend(socket, handshake, StringLen(handshake)) < 0) {
   Print("Handshake failed");
}
```

### Trade Request with EA Name
Include EA name in every trade request:

```mql5
string request = "{\"type\":\"trade_request\",\"ea_name\":\"MyEA\",\"symbol\":\"XAUUSD\",\"action\":\"buy\"}\\n";
if(SocketSend(socket, request, StringLen(request)) < 0) {
   Print("Request failed");
}
```

---

## Technical Details

### Terminal Scanner
- **Class**: `TerminalScanner`
- **Method**: `scan_installed_terminals()`
- **Returns**: List of dicts with terminal info
- **Registry paths scanned**: MetaQuotes entries in HKCU and HKLM
- **File system check**: Common Program Files directories

### EA Configuration
- **Class**: `EAConfig`
- **Storage**: Dictionary `connected_eas`
- **Socket mapping**: Dictionary `ea_socket_map`
- **Persistence**: In-memory (reset on dashboard restart)

### Configuration Dialog
- **Class**: `EAConfigDialog`
- **Parent**: RegimeDashboard
- **Modal**: Yes
- **Returns**: Updated EAConfig object

---

## Future Enhancements

Potential additions:
- Save/load EA configurations to file
- Export configuration presets
- Trade history per EA
- Performance statistics per EA
- Multiple terminal connections simultaneously
- Auto-reconnect for disconnected EAs

---

## Troubleshooting

### Terminal Scanner Shows No Terminals
1. Ensure MetaTrader is installed
2. Try manual installation path entry
3. Check Windows Registry for MetaQuotes entries
4. Run dashboard as Administrator

### EA Not Appearing in List
1. Verify EA sends handshake on connect
2. Check EA includes `ea_name` in handshake
3. Ensure socket connection is established
4. Check console output for registration messages

### EA Configuration Not Applied
1. Verify trade requests include `ea_name`
2. Check EA name matches exactly (case-sensitive)
3. Ensure EA is showing as "connected" (green) in table
4. Refresh EA list after configuration changes

---

## Summary

These new features transform the dashboard into a **multi-EA control center**, allowing you to:
- ✅ Automatically discover available terminals
- ✅ Manage multiple EAs with different strategies
- ✅ Configure individual filter rules per EA
- ✅ Monitor all connections in one place
- ✅ Apply different risk profiles to different EAs

Perfect for traders running multiple strategies simultaneously!
