"""
Quick Warmup - Generate synthetic historical data for testing
==============================================================
This creates fake GOLD M5 data to test the system without waiting.
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import socket
import json
import time

print("=" * 60)
print("QUICK WARMUP - Synthetic Data Generator")
print("=" * 60)
print()
print("This will send 700 synthetic GOLD M5 bars to the GUI")
print("so you can test the system without waiting 52 hours.")
print()
print("Make sure the GUI is running and server is started!")
print()
input("Press Enter to continue...")

# Generate synthetic GOLD data
print("\nGenerating 700 synthetic GOLD M5 bars...")
np.random.seed(42)

# Start from a realistic GOLD price
base_price = 4260.0
n_bars = 700

# Generate realistic price movement
returns = np.random.normal(0, 0.0005, n_bars)  # Small returns
prices = base_price * np.exp(np.cumsum(returns))

# Generate OHLC
opens = prices
highs = opens + np.abs(np.random.normal(0, 2, n_bars))
lows = opens - np.abs(np.random.normal(0, 2, n_bars))
closes = opens + np.random.normal(0, 1, n_bars)

# Ensure high >= close >= low
closes = np.clip(closes, lows, highs)

# Generate volume and spread
volumes = np.random.randint(50, 500, n_bars)
spreads = np.random.randint(10, 30, n_bars)

# Generate timestamps (going back from now)
end_time = datetime.now()
times = [end_time - timedelta(minutes=5*i) for i in range(n_bars-1, -1, -1)]

print("✓ Synthetic data generated")

# Connect to GUI
print("\nConnecting to GUI at 127.0.0.1:9090...")
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(('127.0.0.1', 9090))
    print("✓ Connected")
except Exception as e:
    print(f"✗ Failed to connect: {e}")
    print("\nMake sure:")
    print("1. GUI is running")
    print("2. You clicked 'Start Server'")
    print("3. Port 9090 is correct")
    input("\nPress Enter to exit...")
    exit(1)

# Send handshake
print("\nSending handshake...")
handshake = {
    "type": "handshake",
    "terminal": "QuickWarmup - Synthetic",
    "symbol": "GOLD",
    "account": 999999
}
sock.sendall((json.dumps(handshake) + "\n").encode('utf-8'))
time.sleep(0.1)

# Send all bars
print(f"\nSending {n_bars} bars...")
for i in range(n_bars):
    bar = {
        "type": "bar",
        "terminal": "QuickWarmup - Synthetic",
        "symbol": "GOLD",
        "time": times[i].strftime("%Y.%m.%d %H:%M"),
        "open": round(opens[i], 2),
        "high": round(highs[i], 2),
        "low": round(lows[i], 2),
        "close": round(closes[i], 2),
        "tickvol": int(volumes[i]),
        "spread": int(spreads[i])
    }
    
    sock.sendall((json.dumps(bar) + "\n").encode('utf-8'))
    
    if (i + 1) % 100 == 0:
        print(f"  Sent {i+1}/{n_bars} bars...")
        time.sleep(0.05)

print(f"✓ All {n_bars} bars sent!")

# Close connection
sock.close()

print()
print("=" * 60)
print("DONE!")
print("=" * 60)
print()
print("Check the GUI:")
print("- Data Buffer should show: 700 bars (Ready)")
print("- Regime predictions should appear")
print("- Terminal dropdown should show: QuickWarmup - Synthetic")
print()
input("Press Enter to exit...")
