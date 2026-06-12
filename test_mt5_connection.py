#!/usr/bin/env python3
"""
Quick test script to diagnose MT5 connection and symbol issues.
Run this while MT5 is open and logged in.
"""

import MetaTrader5 as mt5

print("="*60)
print("MT5 CONNECTION DIAGNOSTIC TEST")
print("="*60)

# Try to connect
print("\n1. Attempting to initialize MT5...")
if not mt5.initialize():
    error = mt5.last_error()
    print(f"   ❌ FAILED to connect!")
    print(f"   Error: {error}")
    print("\n   TROUBLESHOOTING:")
    print("   - Make sure MT5 is running")
    print("   - Make sure you are logged into an account")
    print("   - Try closing and reopening MT5")
    exit(1)

print("   ✓ Successfully connected to MT5!")

# Get terminal info
print("\n2. Getting terminal information...")
term_info = mt5.terminal_info()
if term_info:
    print(f"   Company: {term_info.company}")
    print(f"   Name: {term_info.name}")
    print(f"   Path: {term_info.path}")
    print(f"   Data Path: {term_info.data_path}")
    print(f"   Connected: {term_info.connected}")
else:
    print("   ❌ Could not get terminal info")

# Get account info
print("\n3. Getting account information...")
acc_info = mt5.account_info()
if acc_info:
    print(f"   Login: {acc_info.login}")
    print(f"   Server: {acc_info.server}")
    print(f"   Company: {acc_info.company}")
    print(f"   Currency: {acc_info.currency}")
    print(f"   Balance: {acc_info.balance}")
else:
    print("   ❌ Could not get account info")
    print("   Make sure you are LOGGED IN to an account!")

# Test symbol retrieval
print("\n4. Testing symbol retrieval...")

print("\n   Method 1: symbols_get() - visible symbols only")
symbols1 = mt5.symbols_get()
count1 = len(symbols1) if symbols1 else 0
print(f"   Found: {count1} symbols")
if symbols1 and len(symbols1) > 0:
    print(f"   First 10: {[s.name for s in symbols1[:10]]}")

print("\n   Method 2: symbols_get(group='*') - all symbols")
symbols2 = mt5.symbols_get(group="*")
count2 = len(symbols2) if symbols2 else 0
print(f"   Found: {count2} symbols")
if symbols2 and len(symbols2) > 0:
    print(f"   First 10: {[s.name for s in symbols2[:10]]}")

print("\n   Method 3: symbols_total() - total count")
total = mt5.symbols_total()
print(f"   Total: {total}")

# Search for GOLD specifically
print("\n5. Searching for GOLD symbol...")
gold_symbols = []

if symbols2:
    gold_symbols = [s.name for s in symbols2 if 'GOLD' in s.name.upper() or 'XAU' in s.name.upper()]

if gold_symbols:
    print(f"   ✓ Found gold-related symbols: {gold_symbols}")
else:
    print("   ❌ No GOLD or XAU symbols found")
    print("\n   Checking if 'GOLD' exists as exact match...")
    gold_info = mt5.symbol_info("GOLD")
    if gold_info:
        print(f"   ✓ Symbol 'GOLD' exists!")
        print(f"      Visible: {gold_info.visible}")
        print(f"      Description: {gold_info.description}")
        print(f"      Path: {gold_info.path}")
    else:
        print("   ❌ Symbol 'GOLD' does not exist in this terminal")

# Try to select and enable GOLD
print("\n6. Attempting to select 'GOLD' symbol...")
if mt5.symbol_select("GOLD", True):
    print("   ✓ Successfully selected GOLD")
    gold_info = mt5.symbol_info("GOLD")
    if gold_info:
        print(f"   Description: {gold_info.description}")
        print(f"   Digits: {gold_info.digits}")
        print(f"   Point: {gold_info.point}")
else:
    print("   ❌ Could not select GOLD")

# Cleanup
mt5.shutdown()

print("\n" + "="*60)
print("TEST COMPLETE")
print("="*60)
print("\nIf GOLD was not found, possible reasons:")
print("1. Symbol might be named differently (XAUUSD, Gold, etc.)")
print("2. Symbol might not be available with this broker")
print("3. You might be connected to a different MT5 instance")
print("4. Market Watch might need symbols added manually")
print("\nNext steps:")
print("- Check the symbol name in MT5's Market Watch")
print("- Right-click in Market Watch → Show All")
print("- Try searching for 'XAU' or 'Gold' in Market Watch")
