# Symbol Naming Guide

## Problem Solved
Different brokers use different symbol naming conventions. The dashboard now automatically handles these variations.

---

## Common Symbol Variations

### Gold (XAU/USD)
Different brokers name gold symbols differently:
- `XAUUSD` - Standard
- `XAUUSDm` - Micro lots (common with Exness, Roboforex)
- `XAUUSD.m` - Micro lots (alternative format)
- `XAUUSD_m` - Micro lots (alternative format)
- `XAUUSDi` - Index/Cash
- `XAUUSDc` - Contract
- `XAUUSD#` - Special contract
- `XAUUSDpro` - Pro account
- `GOLD` - Alternative name

### EUR/USD
- `EURUSD`
- `EURUSDm` - Micro
- `EURUSD.m`
- `EURUSDi` - Index
- `EURUSDc` - Contract

### Other Pairs
Similar patterns apply to all symbols.

---

## Automatic Symbol Matching

The dashboard now includes **smart symbol matching** that:

### 1. Tries Exact Match First
```python
Requested: "XAUUSD"
Found: "XAUUSD" ✓ (exact match)
```

### 2. Tries Case-Insensitive Match
```python
Requested: "xauusd"
Found: "XAUUSD" ✓ (case doesn't matter)
```

### 3. Tries Common Suffixes
```python
Requested: "XAUUSD"
Checks: XAUUSDm, XAUUSD.m, XAUUSD_m, XAUUSDi, XAUUSDc, etc.
Found: "XAUUSDm" ✓ (auto-corrected)
```

### 4. Tries Partial Match
```python
Requested: "XAUUSD"
Scans all symbols containing "XAUUSD"
Found: "XAUUSDm" ✓ (partial match)
```

---

## How to Use

### Method 1: Type and Let Auto-Correct
1. Type standard symbol name: `XAUUSD`
2. Click "Refresh Now"
3. Dashboard auto-finds correct broker symbol: `XAUUSDm`
4. Data loads automatically

**Console output:**
```
[SYMBOL] Found match: 'XAUUSD' → 'XAUUSDm'
[DATA] Fetched 800 bars for XAUUSDm (requested: XAUUSD)
```

### Method 2: Browse Available Symbols (RECOMMENDED)
1. Click **"Browse..."** button next to symbol input
2. A dialog opens showing all available symbols
3. Use search box to filter (type "XAU" to see gold symbols)
4. Double-click or select and click OK
5. Symbol automatically fills in the input box

**Benefits:**
- ✅ See exactly what symbols are available in your broker
- ✅ No guessing symbol names
- ✅ Filter by typing (instant search)
- ✅ Shows all variations

---

## Symbol Browser Features

### Search/Filter
```
Type in search box: "XAU"
Instantly shows:
  - XAUUSDm
  - XAUEURm
  - XAUJPYm
  - etc.
```

### Quick Selection
- **Double-click** any symbol to select it immediately
- Or **click once** and press OK

### Symbol Count
Shows: "Found 350 symbols" or "Showing 5 symbols" (when filtered)

---

## Error Handling

### Symbol Not Found
If symbol isn't available, you get a helpful error:

```
Symbol 'XAUUSD' not found.

Available gold symbols:
  • XAUUSDm
  • XAUEURm
  • XAUGBPm
  • GOLDEUR
  • GOLDGBP
```

### No Symbols Found
If broker has no matching symbols:
```
Symbol 'XAUUSD' not found.
No gold symbols found in this broker.
```

---

## Common Scenarios

### Scenario 1: Broker Uses 'm' Suffix
**Your input:** `XAUUSD`
**Broker has:** `XAUUSDm`
**Result:** ✓ Auto-corrected to `XAUUSDm`

### Scenario 2: Broker Uses Standard Names
**Your input:** `XAUUSD`
**Broker has:** `XAUUSD`
**Result:** ✓ Exact match

### Scenario 3: Unknown Symbol
**Your input:** `GOLD99`
**Broker has:** No match
**Result:** ✗ Error message with suggestions

### Scenario 4: Browse First
1. Click "Browse..."
2. See broker has: `XAUUSDm`, `XAUUSDi`, `XAUUSD.m`
3. Select `XAUUSDm` (micro lots)
4. ✓ Symbol filled automatically

---

## Best Practices

### For Single Broker
1. **First time:** Click "Browse..." to see available symbols
2. **Note the exact name:** e.g., `XAUUSDm`
3. **Future use:** Can type `XAUUSD` (auto-corrects) or exact name

### For Multiple Brokers
1. Use "Browse..." for each broker first
2. Note differences in naming
3. Let auto-correction handle it

### For EAs
When EAs send symbol names, they should:
```json
{
  "symbol": "XAUUSD",  // Standard name
  "action": "buy"
}
```
Dashboard will auto-correct to broker's actual symbol name.

---

## Technical Details

### Matching Algorithm
```python
def find_matching_symbol(requested_symbol):
    1. Exact match
    2. Case-insensitive match
    3. Try suffixes: m, .m, _m, i, .i, _i, c, .c, _c, #, pro, .pro
    4. Partial match (contains substring)
    5. Return None if not found
```

### Suffix Priority
Checked in order:
1. `m` (micro) - most common
2. `.m` (dotted micro)
3. `_m` (underscored micro)
4. `i` (index)
5. `c` (contract)
6. `#` (special)
7. `pro` (pro accounts)

### Console Logging
All symbol operations are logged:
```
[SYMBOL] Found match: 'XAUUSD' → 'XAUUSDm'
[SYMBOL] Partial match: 'EUR' → 'EURUSDm'
[SYMBOL] No match found for 'INVALID'
[DATA] Fetched 800 bars for XAUUSDm (requested: XAUUSD)
```

---

## Symbol Browser Dialog

### Layout
```
┌─────────────────────────────────────┐
│ Browse Available Symbols            │
├─────────────────────────────────────┤
│ Search: [__________________]        │
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ AUDCADm                         │ │
│ │ AUDJPYm                         │ │
│ │ EURUSDm                         │ │
│ │ GBPUSDm                         │ │
│ │ USDJPYm                         │ │
│ │ XAUUSDm                         │ │ ← Gold symbols
│ │ XAGUSDm                         │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ Found 350 symbols. Double-click to  │
│ select.                             │
├─────────────────────────────────────┤
│               [OK]  [Cancel]        │
└─────────────────────────────────────┘
```

### Keyboard Shortcuts
- **Type to search** - Instant filter
- **Double-click** - Select and close
- **Enter** - Select current and close
- **Escape** - Cancel

---

## Summary

### Problem
Your broker uses `XAUUSDm` but you typed `XAUUSD`

### Solution
✅ **Automatic correction** - Dashboard finds `XAUUSDm`  
✅ **Symbol browser** - See all available symbols  
✅ **Smart matching** - Handles common variations  
✅ **Error messages** - Suggests alternatives if not found

### Quick Start
1. Connect to terminal
2. Click "Browse..." next to symbol input
3. Select your symbol
4. Click "Refresh Now"
5. Done!

**No more "Symbol not found" errors!** 🎉
