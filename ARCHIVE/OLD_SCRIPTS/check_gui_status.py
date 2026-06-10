"""
Quick check: Is the GUI code updated with the warmup fix?
"""

import sys
import os

# Add CORE_SYSTEM to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'CORE_SYSTEM'))

print("=" * 70)
print("GUI CODE STATUS CHECK")
print("=" * 70)

# Read the GUI file
gui_file = os.path.join(os.path.dirname(__file__), 'CORE_SYSTEM', 'regime_trading_gui.py')

try:
    with open(gui_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    print("\nChecking for WARMUP FIX...")
    print("-" * 70)
    
    # Check 1: Auto-refresh timer exists
    if 'regime_refresh_timer' in content:
        print("✓ Auto-refresh timer found")
    else:
        print("✗ Auto-refresh timer NOT FOUND")
    
    # Check 2: refresh_regime_monitor function exists
    if 'def refresh_regime_monitor' in content:
        print("✓ refresh_regime_monitor() function found")
    else:
        print("✗ refresh_regime_monitor() function NOT FOUND")
    
    # Check 3: Most important - send regime after bar
    if 'elif data_type == "bar":' in content:
        bar_section_start = content.find('elif data_type == "bar":')
        bar_section_end = content.find('elif data_type ==', bar_section_start + 1)
        if bar_section_end == -1:
            bar_section_end = content.find('def ', bar_section_start + 1)
        
        bar_section = content[bar_section_start:bar_section_end]
        
        if 'send_trade_decision' in bar_section:
            print("✓ WARMUP FIX APPLIED: Regime sent back to EA after each bar")
            print("\n  The fix is in the code!")
        else:
            print("✗ WARMUP FIX MISSING: Regime NOT sent back to EA after bar")
            print("\n  The bar section does NOT send regime updates!")
            print("  This is why EA stays in WARMING UP forever!")
    
    print("\n" + "=" * 70)
    print("DIAGNOSIS:")
    print("=" * 70)
    
    if 'send_trade_decision' in bar_section:
        print("\n✓ Code is UPDATED with the fix")
        print("\n⚠️  BUT YOU NEED TO:")
        print("   1. CLOSE the Python GUI completely")
        print("   2. RESTART it: run CORE_SYSTEM\\start_gui.bat")
        print("   3. Click 'Start Server'")
        print("   4. Remove EA from chart and reattach")
        print("\n   The fix is in the code, but you need to restart GUI!")
    else:
        print("\n✗ Code is NOT updated properly")
        print("   The warmup fix is missing from the bar processing section")
        
except Exception as e:
    print(f"Error reading GUI file: {e}")

print("\n" + "=" * 70)
