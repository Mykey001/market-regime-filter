"""
Data Buffer Diagnostic Tool
============================
Quick check to see if your data buffer issue is related to:
1. Model loading
2. Feature computation
3. Data format
4. Buffer management
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'CORE_SYSTEM'))

print("=" * 70)
print("DATA BUFFER DIAGNOSTIC TOOL")
print("=" * 70)
print()

# Test 1: Check imports
print("TEST 1: Checking imports...")
try:
    import numpy as np
    import pandas as pd
    import joblib
    from feature_engine import compute_all_features, get_feature_matrix, FEATURE_NAMES, MIN_WARMUP
    print("  ✓ All imports successful")
    print(f"  ✓ MIN_WARMUP = {MIN_WARMUP} bars")
except Exception as e:
    print(f"  ✗ Import failed: {e}")
    sys.exit(1)

print()

# Test 2: Check model files
print("TEST 2: Checking model files...")
model_path = "CORE_SYSTEM/market_regime_gmm.pkl"
scaler_path = "CORE_SYSTEM/scaler.pkl"

try:
    if os.path.exists(model_path):
        model = joblib.load(model_path)
        print(f"  ✓ Model loaded: {type(model).__name__}")
    else:
        print(f"  ✗ Model file not found: {model_path}")
        sys.exit(1)
    
    if os.path.exists(scaler_path):
        scaler = joblib.load(scaler_path)
        print(f"  ✓ Scaler loaded: {type(scaler).__name__}")
    else:
        print(f"  ✗ Scaler file not found: {scaler_path}")
        sys.exit(1)
except Exception as e:
    print(f"  ✗ Error loading: {e}")
    sys.exit(1)

print()

# Test 3: Simulate data buffer
print("TEST 3: Simulating data buffer...")
print("  Creating synthetic bar data (like MT5 would send)...")

np.random.seed(42)
n_bars = 1300  # UPDATED from 700 to 1300
base_price = 4260.0

# Simulate realistic GOLD price movement
returns = np.random.normal(0, 0.0005, n_bars)
prices = base_price * np.exp(np.cumsum(returns))

# Create data buffer (list of dicts, like GUI receives)
data_buffer = []
for i in range(n_bars):
    bar = {
        "time": f"2026-06-09 {10 + i // 12:02d}:{(i % 12) * 5:02d}",
        "open": float(prices[i] + np.random.randn() * 0.5),
        "high": float(prices[i] + abs(np.random.randn() * 2)),
        "low": float(prices[i] - abs(np.random.randn() * 2)),
        "close": float(prices[i]),
        "tickvol": int(np.random.randint(50, 500)),
        "spread": int(np.random.randint(10, 30))
    }
    # Ensure OHLC validity
    bar["high"] = max(bar["open"], bar["high"], bar["close"])
    bar["low"] = min(bar["open"], bar["low"], bar["close"])
    
    data_buffer.append(bar)

print(f"  ✓ Created buffer with {len(data_buffer)} bars")
print(f"  ✓ First bar: time={data_buffer[0]['time']}, close={data_buffer[0]['close']:.2f}")
print(f"  ✓ Last bar: time={data_buffer[-1]['time']}, close={data_buffer[-1]['close']:.2f}")

print()

# Test 4: Buffer to DataFrame conversion
print("TEST 4: Converting buffer to DataFrame...")
try:
    df = pd.DataFrame(data_buffer)
    print(f"  ✓ DataFrame created: {df.shape}")
    print(f"  ✓ Columns: {list(df.columns)}")
    print(f"  ✓ Price range: {df['close'].min():.2f} - {df['close'].max():.2f}")
except Exception as e:
    print(f"  ✗ Conversion failed: {e}")
    sys.exit(1)

print()

# Test 5: Feature computation
print("TEST 5: Computing features...")
try:
    df_features = compute_all_features(df)
    print(f"  ✓ Features computed")
    print(f"  ✓ DataFrame shape: {df_features.shape}")
    print(f"  ✓ Feature columns added: {len(FEATURE_NAMES)}")
except Exception as e:
    print(f"  ✗ Feature computation failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print()

# Test 6: Feature extraction
print("TEST 6: Extracting feature matrix...")
try:
    X, valid_df = get_feature_matrix(df_features, drop_na=True)
    print(f"  ✓ Feature matrix extracted")
    print(f"  ✓ Original bars: {len(df_features)}")
    print(f"  ✓ Valid bars (after NaN drop): {len(valid_df)}")
    print(f"  ✓ Feature matrix shape: {X.shape}")
    
    if len(X) < MIN_WARMUP:
        print(f"  ⚠️ WARNING: Not enough valid data!")
        print(f"     Need: {MIN_WARMUP} bars")
        print(f"     Have: {len(X)} bars")
        print(f"     Missing: {MIN_WARMUP - len(X)} bars")
    else:
        print(f"  ✓ Sufficient data ({len(X)} >= {MIN_WARMUP})")
except Exception as e:
    print(f"  ✗ Extraction failed: {e}")
    sys.exit(1)

print()

# Test 7: Prediction
print("TEST 7: Testing prediction...")
if len(X) > 0:
    try:
        X_current = X[-1:, :]
        X_scaled = scaler.transform(X_current)
        regime = model.predict(X_scaled)[0]
        probs = model.predict_proba(X_scaled)[0]
        confidence = probs[regime]
        
        print(f"  ✓ Prediction successful!")
        print(f"  ✓ Regime: {regime}")
        print(f"  ✓ Confidence: {confidence * 100:.1f}%")
        print()
        print("  Regime probabilities:")
        for i, prob in enumerate(probs):
            if prob > 0.001:  # Only show non-zero
                bar = "█" * int(prob * 30)
                print(f"    Regime {i}: {prob * 100:5.1f}% {bar}")
    except Exception as e:
        print(f"  ✗ Prediction failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
else:
    print("  ⚠️ Skipping prediction test (no valid data)")

print()

# Test 8: Buffer management
print("TEST 8: Testing buffer management...")
try:
    # Simulate adding a new bar
    new_bar = {
        "time": "2026-06-09 15:30",
        "open": 4262.0,
        "high": 4263.5,
        "low": 4261.5,
        "close": 4263.0,
        "tickvol": 234,
        "spread": 15
    }
    
    data_buffer.append(new_bar)
    print(f"  ✓ Added new bar, buffer size: {len(data_buffer)}")
    
    # Simulate buffer trimming (keep last MIN_WARMUP + 500)
    max_size = MIN_WARMUP + 500
    if len(data_buffer) > max_size:
        data_buffer = data_buffer[-max_size:]
        print(f"  ✓ Trimmed buffer to {len(data_buffer)} bars")
    
    # Recompute with new data
    df = pd.DataFrame(data_buffer)
    df_features = compute_all_features(df)
    X, valid_df = get_feature_matrix(df_features, drop_na=True)
    
    if len(X) > 0:
        X_current = X[-1:, :]
        X_scaled = scaler.transform(X_current)
        regime = model.predict(X_scaled)[0]
        probs = model.predict_proba(X_scaled)[0]
        confidence = probs[regime]
        
        print(f"  ✓ Updated prediction with new bar")
        print(f"  ✓ New regime: {regime} (confidence: {confidence * 100:.1f}%)")
    
except Exception as e:
    print(f"  ✗ Buffer management failed: {e}")
    sys.exit(1)

print()
print("=" * 70)
print("ALL TESTS PASSED! ✅")
print("=" * 70)
print()
print("Summary:")
print("  • Data buffer simulation: Working")
print("  • Feature computation: Working")
print("  • Regime prediction: Working")
print("  • Buffer management: Working")
print()
print("Your data buffer system is functioning correctly!")
print()
print("If you're having issues in the GUI:")
print("  1. Check that EA is sending data (MT5 Experts log)")
print("  2. Check that GUI server is running (Status: RUNNING)")
print("  3. Check firewall isn't blocking port 9090")
print("  4. See check_data_buffer.md for detailed diagnostics")
print()
