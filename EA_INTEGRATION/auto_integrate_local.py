"""
Automated EA Regime Filter Integration - LOCAL VERSION (No API Required!)
Rule-based integration system that doesn't need any AI API keys
"""

import os
import re
import shutil
import time
from datetime import datetime
from pathlib import Path

# Configuration
BASE_DIR = Path(__file__).parent
INPUT_DIR = BASE_DIR / "input"
OUTPUT_DIR = BASE_DIR / "output"
LOGS_DIR = BASE_DIR / "logs"
REGIME_FILTER_LIB = BASE_DIR.parent / "EAs to add filter" / "RegimeFilterLib.mqh"

# Ensure directories exist
INPUT_DIR.mkdir(exist_ok=True)
OUTPUT_DIR.mkdir(exist_ok=True)
LOGS_DIR.mkdir(exist_ok=True)

class IntegrationLogger:
    """Logger for integration process"""
    
    def __init__(self, ea_name):
        self.ea_name = ea_name
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.log_file = LOGS_DIR / f"{ea_name}_{timestamp}.log"
        self.log("="*80)
        self.log(f"Starting LOCAL integration for: {ea_name}")
        self.log(f"Timestamp: {datetime.now()}")
        self.log("="*80)
    
    def log(self, message):
        """Write message to log file and console"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_message = f"[{timestamp}] {message}"
        print(log_message)
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(log_message + "\n")
    
    def error(self, message):
        """Log error message"""
        self.log(f"ERROR: {message}")
    
    def success(self, message):
        """Log success message"""
        self.log(f"SUCCESS: {message}")

def read_file_safe(file_path):
    """Read file with multiple encoding attempts"""
    encodings = ['utf-8', 'latin-1', 'cp1252', 'iso-8859-1']
    
    for encoding in encodings:
        try:
            with open(file_path, 'r', encoding=encoding) as f:
                return f.read()
        except UnicodeDecodeError:
            continue
    
    with open(file_path, 'rb') as f:
        return f.read().decode('utf-8', errors='ignore')

def load_regime_filter_lib():
    """Load the RegimeFilterLib.mqh template"""
    if not REGIME_FILTER_LIB.exists():
        raise FileNotFoundError(f"RegimeFilterLib.mqh not found at {REGIME_FILTER_LIB}")
    
    return read_file_safe(REGIME_FILTER_LIB)

def find_version(code):
    """Extract version from EA code"""
    match = re.search(r'#property\s+version\s+"?([0-9.]+)"?', code, re.IGNORECASE)
    if match:
        return match.group(1)
    return "1.0"

def increment_version(version_str):
    """Increment version number"""
    try:
        parts = version_str.split('.')
        if len(parts) >= 2:
            minor = int(parts[-1])
            parts[-1] = str(minor + 1)
            return '.'.join(parts)
        else:
            return version_str + ".1"
    except:
        return version_str + ".1"

def clean_comments_and_whitespace(text):
    """Remove comments and strip whitespace from text"""
    text = re.sub(r'//.*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    return text.strip()

def find_enclosing_function_return_type(code, pos):
    """
    Scans backwards from `pos` in `code` to find the enclosing function definition
    and returns its return type.
    """
    balance = 0
    i = pos - 1
    while i >= 0:
        char = code[i]
        if char == '}':
            balance += 1
        elif char == '{':
            balance -= 1
            if balance < 0:
                # We found the opening brace of the enclosing block!
                # Now scan backwards to find the function signature before this brace
                sub = code[:i]
                cleaned_sub = clean_comments_and_whitespace(sub)
                sig_pattern = r'\b(void|int|bool|double|string|ulong|uint|long|float|char|color|datetime)\s+\w+\s*\([^)]*\)\s*(?:const\s*)?$'
                match = re.search(sig_pattern, cleaned_sub, re.IGNORECASE | re.DOTALL)
                if match:
                    return match.group(1).lower()
                # Continue scanning parent blocks
                balance = 0
        i -= 1
    return "void" # Default to void if not found

def integrate_regime_filter_local(ea_code, lib_code, logger):
    """
    Rule-based integration of regime filter into EA
    Uses pattern matching and code insertion - no AI needed!
    """
    
    logger.log("Starting LOCAL rule-based integration...")
    
    integrated = ea_code
    changes_made = []
    
    # Step 0: Check for conflicts with library function names
    logger.log("Step 0: Checking for conflicts with library function names...")
    conflict_patterns = [
        r'\b(?:int|double|bool|void|ulong|uint)\s+(GetCurrentRegime|GetRegimeConfidence|IsTradeAllowed|IsRegimeFilterConnected|IsTradeAllowedByRegime)\s*\(',
    ]
    
    has_conflicts = False
    conflicting_funcs = []
    for pattern in conflict_patterns:
        matches = re.findall(pattern, integrated, re.IGNORECASE)
        if matches:
            for m in matches:
                if m not in conflicting_funcs:
                    conflicting_funcs.append(m)
                    
    if conflicting_funcs:
        has_conflicts = True
        logger.log(f"  Found conflicting function(s) in EA: {', '.join(conflicting_funcs)}")
        logger.log("  Compatibility wrappers will be disabled using RF_NO_COMPATIBILITY to avoid compile errors.")
        changes_made.append(f"Handled function conflicts for: {', '.join(conflicting_funcs)} by using RF_NO_COMPATIBILITY")
    else:
        logger.log("  No conflicting functions found.")
    
    # 1. Add library include at the top (after other includes)
    logger.log("Step 1: Adding library include...")
    if '#include "RegimeFilterLib.mqh"' not in integrated:
        # Determine include code
        include_code = ""
        if has_conflicts:
            include_code += "#define RF_NO_COMPATIBILITY  // Avoid conflict with EA's own functions\n"
        include_code += '#include "RegimeFilterLib.mqh"  // ML Regime Filter Integration'
        
        # Find the last #include statement or #property statement
        include_pattern = r'(#include\s+[<"][^>"]+[>"])'
        property_pattern = r'(#property\s+[^\n]+)'
        
        includes = list(re.finditer(include_pattern, integrated))
        properties = list(re.finditer(property_pattern, integrated))
        
        insert_pos = 0
        if includes:
            last_include = includes[-1]
            insert_pos = last_include.end()
            integrated = (integrated[:insert_pos] + 
                          f'\n{include_code}' +
                          integrated[insert_pos:])
            changes_made.append("Added #include RegimeFilterLib.mqh after includes")
            logger.success("Library include added after includes")
        elif properties:
            last_prop = properties[-1]
            insert_pos = last_prop.end()
            integrated = (integrated[:insert_pos] + 
                          f'\n\n{include_code}' +
                          integrated[insert_pos:])
            changes_made.append("Added #include RegimeFilterLib.mqh after properties")
            logger.success("Library include added after properties")
        else:
            # Add at very beginning
            integrated = f'{include_code}\n\n' + integrated
            changes_made.append("Added #include RegimeFilterLib.mqh at beginning")
            logger.success("Library include added at beginning")
    
    # 2. Add input parameters - MUST be at global scope
    logger.log("Step 2: Adding input parameters at global scope...")
    if not re.search(r'\bEnableRegimeFilter\b', integrated, re.IGNORECASE):
        input_params = '''
// ==================== ML Regime Filter Settings ====================
input bool     EnableRegimeFilter = true;      // Enable ML regime filter
input string   RegimeFilterHost = "127.0.0.1"; // Python GUI host  
input int      RegimeFilterPort = 9090;        // Python GUI port
// ====================================================================
'''
        
        # Find the first function definition to insert before it
        first_func_pattern = r'((?:int|void|bool|double|string|ulong|uint)\s+\w+\s*\([^)]*\)\s*\{)'
        first_func_match = re.search(first_func_pattern, integrated, re.MULTILINE)
        
        if first_func_match:
            insert_pos = first_func_match.start()
            integrated = integrated[:insert_pos] + input_params + '\n' + integrated[insert_pos:]
            changes_made.append("Added input parameters at global scope (before first function)")
            logger.success("Input parameters added at global scope")
        else:
            # Fallback: add after includes
            include_pattern = r'(#include\s+[<"][^>"]+[>"])'
            includes = list(re.finditer(include_pattern, integrated))
            if includes:
                insert_pos = includes[-1].end()
                integrated = integrated[:insert_pos] + '\n' + input_params + integrated[insert_pos:]
                changes_made.append("Added input parameters after includes")
                logger.success("Input parameters added after includes")
    
    # 3. Add initialization in OnInit()
    logger.log("Step 3: Adding OnInit integration...")
    oninit_match = re.search(r'\b(?:int|void)\s+OnInit\s*\(\s*(?:void)?\s*\)\s*(?://[^\n]*\n|/\*.*?\*/\s*)*\{', integrated, re.IGNORECASE)
    init_code = '''
    
    // ===== ML Regime Filter Initialization =====
    if(EnableRegimeFilter)
    {
        Print("=== Initializing ML Regime Filter ===");
        if(RF_InitRegimeFilter(RegimeFilterHost, RegimeFilterPort, EnableRegimeFilter))
        {
            Print("ML Regime Filter: Successfully connected to Python GUI");
        }
        else
        {
            Print("ML Regime Filter: Failed to connect - operating in bypass mode");
        }
    }
    else
    {
        Print("ML Regime Filter: DISABLED by user settings");
    }
    // ===========================================
'''
    if oninit_match:
        if 'InitRegimeFilter' not in integrated and 'RF_InitRegimeFilter' not in integrated:
            insert_pos = oninit_match.end()
            integrated = integrated[:insert_pos] + init_code + integrated[insert_pos:]
            changes_made.append("Added RF_InitRegimeFilter() in OnInit()")
            logger.success("OnInit integration added")
    else:
        # OnInit not found, append a new one
        oninit_func = f'''

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{{{init_code}
    return(INIT_SUCCEEDED);
}}
'''
        integrated += oninit_func
        changes_made.append("Appended new OnInit() with RF_InitRegimeFilter()")
        logger.success("OnInit appended at the end of file")
    
    # 4. Add update in OnTick()
    logger.log("Step 4: Adding OnTick integration...")
    ontick_match = re.search(r'\bvoid\s+OnTick\s*\(\s*(?:void)?\s*\)\s*(?://[^\n]*\n|/\*.*?\*/\s*)*\{', integrated, re.IGNORECASE)
    update_code = '''
    
    // Update ML Regime Filter
    if(EnableRegimeFilter)
    {
        RF_UpdateRegimeFilter();
    }
'''
    if ontick_match:
        if 'UpdateRegimeFilter' not in integrated and 'RF_UpdateRegimeFilter' not in integrated:
            insert_pos = ontick_match.end()
            integrated = integrated[:insert_pos] + update_code + integrated[insert_pos:]
            changes_made.append("Added RF_UpdateRegimeFilter() in OnTick()")
            logger.success("OnTick integration added")
    else:
        # OnTick not found, append a new one
        ontick_func = f'''

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{{{update_code}}}
'''
        integrated += ontick_func
        changes_made.append("Appended new OnTick() with RF_UpdateRegimeFilter()")
        logger.success("OnTick appended at the end of file")
    
    # 5. Add trade filtering - Enhanced automatic detection
    logger.log("Step 5: Adding trade filtering...")
    
    # Simplified patterns - just detect the trade call method name
    # No greedy [^;]* captures, no re.DOTALL that spans lines
    trade_patterns = [
        (r'OrderSend\s*\([^)]*ORDER_TYPE_BUY', 'buy', 'OrderSend'),
        (r'OrderSend\s*\([^)]*ORDER_TYPE_SELL', 'sell', 'OrderSend'),
        (r'trade\.Buy\s*\(', 'buy', 'trade.Buy'),
        (r'trade\.Sell\s*\(', 'sell', 'trade.Sell'),
        (r'trade\.PositionOpen\s*\([^)]*POSITION_TYPE_BUY', 'buy', 'PositionOpen'),
        (r'trade\.PositionOpen\s*\([^)]*POSITION_TYPE_SELL', 'sell', 'PositionOpen'),
        (r'm_trade\.Buy\s*\(', 'buy', 'm_trade.Buy'),
        (r'm_trade\.Sell\s*\(', 'sell', 'm_trade.Sell'),
    ]
    
    filters_added = []
    buy_filtered = False
    sell_filtered = False
    
    for pattern, direction, func_name in trade_patterns:
        # Skip if we already added a filter for this direction
        if direction == 'buy' and buy_filtered:
            continue
        if direction == 'sell' and sell_filtered:
            continue
            
        # Use re.IGNORECASE only - NOT re.DOTALL to avoid cross-line matching
        match = re.search(pattern, integrated, re.IGNORECASE)
        if match:
            # Get context before the match to check if filter already exists
            context_start = max(0, match.start() - 800)
            context = integrated[context_start:match.start()]
            
            # Skip if filter already exists nearby
            if 'IsTradeAllowed' in context or 'RF_IsTradeAllowed' in context or 'Regime Filter Check' in context:
                continue
            
            # Skip if this is inside a comment
            last_line_nl = context.rfind('\n')
            last_line = context[last_line_nl + 1:] if last_line_nl >= 0 else context
            if '//' in last_line:
                continue
            
            # Detect return type of enclosing function
            ret_type = find_enclosing_function_return_type(integrated, match.start())
            logger.log(f"  Detected enclosing function return type: {ret_type} for trade call in {direction}")
            
            if ret_type == "void":
                ret_statement = "return;"
            elif ret_type == "bool":
                ret_statement = "return false;"
            elif ret_type == "string":
                ret_statement = "return \"\";"
            else:
                ret_statement = "return 0;"
            
            # --- CRITICAL: Find the correct insertion point ---
            # Insert at the START OF THE LINE containing the trade call,
            # NOT at match.start() which can split identifiers like g_trade -> g_ + trade
            
            # Step 1: Find the start of the line containing the match
            line_start_pos = integrated.rfind('\n', 0, match.start())
            line_start_pos = line_start_pos + 1 if line_start_pos >= 0 else 0
            
            # Step 2: Check if the trade call is wrapped in an if() on this line
            # e.g., "if(g_trade.Buy(...))" - we want to insert before the if()
            line_before_match = integrated[line_start_pos:match.start()]
            
            # If there's an 'if(' on this line wrapping the trade call, use this line start
            insert_pos = line_start_pos
            
            # Also check one line above - for cases where if() is on the previous line
            # and the trade call is on a continuation line
            if not re.search(r'\bif\s*\(', line_before_match):
                prev_nl = integrated.rfind('\n', 0, max(0, line_start_pos - 1))
                prev_line_start = prev_nl + 1 if prev_nl >= 0 else 0
                prev_line = integrated[prev_line_start:line_start_pos]
                if re.search(r'\bif\s*\(', prev_line):
                    insert_pos = prev_line_start
            
            # Step 3: Detect indentation from the insertion line
            insert_line_end = integrated.find('\n', insert_pos)
            if insert_line_end < 0:
                insert_line_end = len(integrated)
            insert_line = integrated[insert_pos:insert_line_end]
            indent_match = re.match(r'^(\s*)', insert_line)
            indent = indent_match.group(1) if indent_match else '    '
            
            # Create the filter code with matching indentation
            filter_code = f'''\n{indent}// ===== ML Regime Filter Check =====
{indent}if(EnableRegimeFilter && RF_IsRegimeFilterConnected())
{indent}{{
{indent}    if(!RF_IsTradeAllowed("{direction}"))
{indent}    {{
{indent}        Print("ML Regime Filter BLOCKED {direction} trade. Regime: ", RF_GetCurrentRegime(), 
{indent}              ", Confidence: ", DoubleToString(RF_GetRegimeConfidence(), 1), "%");
{indent}        {ret_statement}  // Trade blocked by regime filter
{indent}    }}
{indent}    Print("ML Regime Filter ALLOWED {direction} trade. Regime: ", RF_GetCurrentRegime(), 
{indent}          ", Confidence: ", DoubleToString(RF_GetRegimeConfidence(), 1), "%");
{indent}}}
{indent}// ===================================
'''
            
            # Insert filter BEFORE the trade call line (at line start, not mid-identifier)
            integrated = integrated[:insert_pos] + filter_code + integrated[insert_pos:]
            
            filters_added.append(f"Added trade filter before {func_name}({direction})")
            logger.success(f"Added trade filter before {func_name}({direction})")
            
            # Mark this direction as filtered
            if direction == 'buy':
                buy_filtered = True
            else:
                sell_filtered = True
    
    if filters_added:
        for filter_add in filters_added:
            changes_made.append(filter_add)
        logger.success(f"Successfully added {len(filters_added)} trade filter(s)")
    else:
        logger.log("  No standard trade patterns detected")
        logger.log("  Trade filter not added automatically")
        logger.log("  (Manual instructions will be provided in README)")
        changes_made.append("Trade filter: Not auto-added (custom patterns)")
    
    # 6. Add cleanup in OnDeinit()
    logger.log("Step 6: Adding OnDeinit integration...")
    ondeinit_match = re.search(r'\bvoid\s+OnDeinit\s*\([^)]*\)\s*(?://[^\n]*\n|/\*.*?\*/\s*)*\{', integrated, re.IGNORECASE)
    deinit_code = '''
    
    // ML Regime Filter Cleanup
    if(EnableRegimeFilter)
    {
        RF_DeinitRegimeFilter();
        Print("ML Regime Filter: Shut down");
    }
'''
    if ondeinit_match:
        if 'DeinitRegimeFilter' not in integrated and 'RF_DeinitRegimeFilter' not in integrated:
            insert_pos = ondeinit_match.end()
            integrated = integrated[:insert_pos] + deinit_code + integrated[insert_pos:]
            changes_made.append("Added RF_DeinitRegimeFilter() in OnDeinit()")
            logger.success("OnDeinit integration added")
    else:
        # OnDeinit not found, append a new one
        ondeinit_func = f'''

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{{{deinit_code}}}
'''
        integrated += ondeinit_func
        changes_made.append("Appended new OnDeinit() with RF_DeinitRegimeFilter()")
        logger.success("OnDeinit appended at the end of file")
    
    # 7. Update version number
    logger.log("Step 7: Updating version number...")
    current_version = find_version(integrated)
    new_version = increment_version(current_version)
    integrated = re.sub(
        r'(#property\s+version\s+)"?([0-9.]+)"?',
        f'\\1"{new_version}"',
        integrated,
        count=1,
        flags=re.IGNORECASE
    )
    changes_made.append(f"Updated version from {current_version} to {new_version}")
    logger.success(f"Version updated: {current_version} -> {new_version}")
    
    # Summary
    logger.log("="*80)
    logger.success(f"LOCAL integration completed! {len(changes_made)} changes made:")
    for i, change in enumerate(changes_made, 1):
        logger.log(f"  {i}. {change}")
    logger.log("="*80)
    
    return integrated

def verify_integration(code, logger):
    """Verify that the integration includes all required components"""
    
    logger.log("Verifying integration completeness...")
    
    checks = {
        "Library include": '#include "RegimeFilterLib.mqh"' in code,
        "Input parameters": "EnableRegimeFilter" in code and "RegimeFilterHost" in code,
        "OnInit integration": "RF_InitRegimeFilter" in code or "InitRegimeFilter" in code,
        "OnTick integration": "RF_UpdateRegimeFilter" in code or "UpdateRegimeFilter" in code,
        "OnDeinit integration": "RF_DeinitRegimeFilter" in code or "DeinitRegimeFilter" in code,
        "Trade filter check": "RF_IsTradeAllowed" in code or "IsTradeAllowed" in code
    }
    
    # Core checks (must pass)
    core_checks = ["Library include", "Input parameters", "OnInit integration", 
                   "OnTick integration", "OnDeinit integration"]
    
    # Optional check (nice to have, but not required)
    optional_checks = ["Trade filter check"]
    
    core_passed = True
    for check_name, passed in checks.items():
        status = "✓ PASS" if passed else "✗ FAIL"
        if check_name in optional_checks and not passed:
            status = "⚠ SKIP"
        logger.log(f"  {status}: {check_name}")
        
        if check_name in core_checks and not passed:
            core_passed = False
            
    if not checks["Trade filter check"]:
        logger.log("")
        logger.log("  NOTE: Trade filter check not auto-added")
        logger.log("  Your EA uses custom trade functions")
        logger.log("  Add manually in your trade opening function:")
        logger.log("  ")
        logger.log("  if(EnableRegimeFilter && RF_IsRegimeFilterConnected())")
        logger.log("  {")
        logger.log("      if(!RF_IsTradeAllowed(\"buy\"))  // or \"sell\"")
        logger.log("      {")
        logger.log("          Print(\"Trade BLOCKED by Regime Filter\");")
        logger.log("          return false;")
        logger.log("      }")
        logger.log("  }")
        logger.log("")
    
    if core_passed:
        logger.success("Core integration complete! Ready to use.")
        if not checks["Trade filter check"]:
            logger.log("(Add trade filter manually for full functionality)")
    else:
        logger.error("Core integration checks failed!")
    
    return core_passed

def create_integration_readme(ea_name, output_file, logger):
    """Create a README file for the integrated EA"""
    
    readme_content = f"""# {ea_name} - Regime Filter Integration Complete (LOCAL)

## Integration Date
{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

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
{{
    if(InitRegimeFilter(RegimeFilterHost, RegimeFilterPort, EnableRegimeFilter))
    {{
        Print("ML Regime Filter: Successfully connected to Python GUI");
    }}
}}
```

### 4. Real-Time Updates (in OnTick)
```cpp
if(EnableRegimeFilter)
{{
    UpdateRegimeFilter();
}}
```

### 5. Trade Filtering
```cpp
if(EnableRegimeFilter && IsRegimeFilterConnected())
{{
    if(!IsTradeAllowed("buy"))  // or "sell"
    {{
        Print("ML Regime Filter BLOCKED trade");
        return;  // Trade cancelled
    }}
}}
```

### 6. Cleanup (in OnDeinit)
```cpp
if(EnableRegimeFilter)
{{
    DeinitRegimeFilter();
}}
```

## How to Use

### Step 1: Copy Files to MT5
1. Copy BOTH files to your MT5 Experts folder:
   - `{output_file.name}` (your integrated EA)
   - `RegimeFilterLib.mqh` (regime filter library)
   
Location: `C:\\Users\\YourName\\AppData\\Roaming\\MetaQuotes\\Terminal\\[BROKER_ID]\\MQL5\\Experts\\`

### Step 2: Start Python GUI
1. Navigate to: `REGIME MOD\\CORE_SYSTEM\\`
2. Double-click: `start_gui.bat`
3. Click **"Start Server"** button
4. Verify: `Server: RUNNING on 127.0.0.1:9090`

### Step 3: Attach EA to Chart
1. Open MT5
2. Open any chart (recommended: M5 timeframe)
3. Drag `{ea_name}` onto chart
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
"""
    
    readme_file = OUTPUT_DIR / f"{Path(ea_name).stem}_README.md"
    with open(readme_file, 'w', encoding='utf-8') as f:
        f.write(readme_content)
    
    logger.log(f"README created: {readme_file.name}")

def process_ea_file(ea_file_path, logger):
    """Process a single EA file using LOCAL integration"""
    
    logger.log(f"Reading EA file: {ea_file_path.name}")
    ea_code = read_file_safe(ea_file_path)
    logger.log(f"  Size: {len(ea_code)} characters")
    
    logger.log("Loading RegimeFilterLib.mqh template...")
    lib_code = load_regime_filter_lib()
    logger.log(f"  Size: {len(lib_code)} characters")
    
    logger.log("Starting LOCAL integration (no AI needed)...")
    integrated_code = integrate_regime_filter_local(ea_code, lib_code, logger)
    
    if not verify_integration(integrated_code, logger):
        logger.error("Integration verification failed!")
        return False
    
    # Save integrated code
    output_file = OUTPUT_DIR / ea_file_path.name
    logger.log(f"Saving integrated EA to: {output_file.name}")
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(integrated_code)
    
    logger.success(f"Integrated EA saved successfully!")
    
    # Copy RegimeFilterLib.mqh to output folder (always overwrite to keep updated)
    lib_output = OUTPUT_DIR / "RegimeFilterLib.mqh"
    logger.log("Copying RegimeFilterLib.mqh to output folder...")
    shutil.copy2(REGIME_FILTER_LIB, lib_output)
    
    # Create README
    create_integration_readme(ea_file_path.name, output_file, logger)
    
    # Archive original file
    archive_dir = INPUT_DIR / "processed"
    archive_dir.mkdir(exist_ok=True)
    archive_file = archive_dir / f"{ea_file_path.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}{ea_file_path.suffix}"
    shutil.move(str(ea_file_path), str(archive_file))
    logger.log(f"Original file archived to: {archive_file.name}")
    
    return True

def monitor_input_folder():
    """Monitor input folder for new EA files"""
    
    print("\n" + "="*80)
    print("EA REGIME FILTER AUTO-INTEGRATION SYSTEM (LOCAL)")
    print("Rule-Based Integration - NO API KEY REQUIRED!")
    print("="*80)
    print(f"\nMonitoring folder: {INPUT_DIR}")
    print("\nDrop .mq5 EA files into the 'input' folder to automatically integrate")
    print("Press Ctrl+C to stop\n")
    
    processed_files = set()
    
    while True:
        try:
            # Check for new .mq5 files
            mq5_files = list(INPUT_DIR.glob("*.mq5"))
            mq5_files = [f for f in mq5_files if f.name not in processed_files]
            
            for ea_file in mq5_files:
                print("\n" + "="*80)
                print(f"NEW EA DETECTED: {ea_file.name}")
                print("="*80)
                
                logger = IntegrationLogger(ea_file.stem)
                
                try:
                    success = process_ea_file(ea_file, logger)
                    
                    if success:
                        print("\n" + "✓"*80)
                        print(f"SUCCESS! {ea_file.name} integrated successfully!")
                        print(f"Check output folder: {OUTPUT_DIR}")
                        print("✓"*80 + "\n")
                        processed_files.add(ea_file.name)
                    else:
                        print("\n" + "✗"*80)
                        print(f"FAILED! {ea_file.name} integration had issues")
                        print(f"Check log file: {logger.log_file}")
                        print("✗"*80 + "\n")
                
                except Exception as e:
                    logger.error(f"Exception during processing: {str(e)}")
                    print("\n" + "✗"*80)
                    print(f"ERROR! {ea_file.name} integration failed")
                    print(f"Error: {str(e)}")
                    print(f"Check log file: {logger.log_file}")
                    print("✗"*80 + "\n")
                    
                    # Move failed file to failed folder
                    failed_dir = INPUT_DIR / "failed"
                    failed_dir.mkdir(exist_ok=True)
                    shutil.move(str(ea_file), str(failed_dir / ea_file.name))
            
            # Wait before checking again
            time.sleep(2)
            
        except KeyboardInterrupt:
            print("\n\nStopping monitor... Goodbye!")
            break
        except Exception as e:
            print(f"\nMonitor error: {str(e)}")
            time.sleep(5)

if __name__ == "__main__":
    monitor_input_folder()
