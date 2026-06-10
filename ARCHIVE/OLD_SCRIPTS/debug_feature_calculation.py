"""
Debug Feature Calculation - Why is regime changing without visible market changes?

HYPOTHESIS: The data buffer or feature calculation is corrupted/unstable
"""

import sys
import os
import pickle
import pandas as pd
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'CORE_SYSTEM'))

from feature_engine import compute_all_features, FEATURE_NAMES, MIN_WARMUP

print("=" * 80)
print("DATA BUFFER & FEATURE CALCULATION DEBUG")
print("=" * 80)

print("\n🎯 PURPOSE OF DATA BUFFER:")
print("-" * 80)
print("""
The data buffer exists because the ML model needs HISTORICAL DATA to compute
rolling features like:

  - volatility_1h   → needs last 12 bars (1 hour of M5 data)
  - volatility_1d   → needs last 288 bars (1 day of M5 data)
  - trend_long      → needs last 576 bars (2 days for EMA calculation)
  - RSI, MACD, ATR  → need 14-50 bars for proper calculation

The model CANNOT predict regime from just the current bar alone!
It needs context: "How volatile has the market been over the last hour? day?"

MINIMUM DATA NEEDED: 626 bars (MIN_WARMUP)
  - 576 bars for longest rolling window (2-day EMA)
  - +50 bars to handle NaN values from diff/returns calculations

WITHOUT the buffer:
  ❌ No rolling volatility → can't detect vol spikes
  ❌ No trend indicators → can't detect regime
  ❌ No historical context → meaningless prediction

So the buffer is ESSENTIAL, not optional!
""")

print("\n🔍 YOUR ISSUE: Regime changes without visible market changes")
print("-" * 80)
print("""
If regime switches from 7 → 4 but:
  - No large candle visible
  - No news event
  - Price seems stable

Then one of these is happening:

1. BUFFER CORRUPTION:
   └─ Buffer has duplicate bars, missing bars, or wrong timestamps
   
2. FEATURE CALCULATION ERROR:
   └─ Rolling windows are computed wrong
   
3. BUFFER SIZE ISSUE:
   └─ Buffer keeps growing/shrinking causing feature instability
   
4. DATA QUALITY ISSUE:
   └─ Receiving bad data from MT5 (zero prices, extreme values)
   
5. AUTO-REFRESH BUG:
   └─ Auto-refresh every 10 seconds recalculates with SAME data
      but gets DIFFERENT features (should be impossible!)

Let's test each hypothesis...
""")

# Load model
model_path = os.path.join(os.path.dirname(__file__), 'CORE_SYSTEM', 'market_regime_gmm.pkl')
scaler_path = os.path.join(os.path.dirname(__file__), 'CORE_SYSTEM', 'scaler.pkl')

try:
    with open(model_path, 'rb') as f:
        model = pickle.load(f)
    with open(scaler_path, 'rb') as f:
        scaler = pickle.load(f)
    print("\n✓ Model loaded")
except:
    print("\n✗ Cannot load model (wrong pickle version?)")
    print("  This is OK for debugging buffer issues")
    model = None
    scaler = None

print("\n" + "=" * 80)
print("TEST 1: Feature Calculation Stability")
print("=" * 80)
print("\nGenerating stable test data (no volatility changes)...")

# Create perfectly stable data
np.random.seed(42)
n_bars = 1300

prices = []
base_price = 4175.0

for i in range(n_bars):
    # Tiny random walk: ±0.1 pips per bar (ultra-stable)
    change = np.random.normal(0, 0.1)
    base_price += change
    prices.append(base_price)

# Create OHLC
data = []
for i, close in enumerate(prices):
    high = close + abs(np.random.normal(0, 0.05))
    low = close - abs(np.random.normal(0, 0.05))
    open_price = (high + low) / 2
    
    data.append({
        'time': 1000000 + i * 300,
        'open': open_price,
        'high': high,
        'low': low,
        'close': close,
        'tickvol': 1000,
        'spread': 3
    })

df = pd.DataFrame(data)

print(f"✓ Created {len(df)} bars")
print(f"  Price: {df['close'].min():.2f} - {df['close'].max():.2f}")
print(f"  Range: {df['close'].max() - df['close'].min():.2f} pips (should be tiny)")
print(f"  Std dev: {df['close'].std():.4f} (should be ~0.1)")

# Compute features
print("\nComputing features...")
df = compute_all_features(df)

print(f"✓ Features computed")
print(f"  Total rows: {len(df)}")
print(f"  Valid rows: {len(df.dropna(subset=FEATURE_NAMES))}")

# Test: Predict regime multiple times on SAME data
print("\n" + "=" * 80)
print("TEST 2: Prediction Stability (CRITICAL TEST)")
print("=" * 80)
print("\nPredicting regime 10 times on the EXACT SAME data...")
print("If predictions differ, we have a BUG in the feature calculation!")

if model and scaler:
    df_clean = df.dropna(subset=FEATURE_NAMES)
    
    if len(df_clean) > 0:
        # Take last bar
        features = df_clean[FEATURE_NAMES].iloc[-1:]
        
        predictions = []
        confidences = []
        
        for i in range(10):
            features_scaled = scaler.transform(features)
            regime = model.predict(features_scaled)[0]
            probs = model.predict_proba(features_scaled)[0]
            confidence = probs[regime]
            
            predictions.append(regime)
            confidences.append(confidence)
            
            print(f"  Attempt {i+1}: Regime {regime}, Confidence {confidence:.1%}")
        
        # Check stability
        unique_regimes = set(predictions)
        
        print("\n" + "-" * 80)
        if len(unique_regimes) == 1:
            print("✅ STABLE: All 10 predictions gave same regime")
            print("   Feature calculation is DETERMINISTIC (good!)")
        else:
            print("❌ UNSTABLE: Got different regimes!")
            print(f"   Regimes: {unique_regimes}")
            print("   This should be IMPOSSIBLE with same data!")
            print("   BUG: Feature calculation or model is non-deterministic!")
    else:
        print("✗ No valid data after NaN drop")
else:
    print("⚠️ Skipped (model not loaded)")

print("\n" + "=" * 80)
print("TEST 3: Feature Sensitivity to Small Price Changes")
print("=" * 80)
print("\nTesting: How much does regime change with tiny price movements?")

if model and scaler:
    # Create two datasets: identical except last bar differs by 0.5 pips
    df1 = df.copy()
    df2 = df.copy()
    
    # Modify last close by 0.5 pips
    df2.iloc[-1, df2.columns.get_loc('close')] += 0.5
    
    # Recompute features
    df1 = compute_all_features(df1)
    df2 = compute_all_features(df2)
    
    df1_clean = df1.dropna(subset=FEATURE_NAMES)
    df2_clean = df2.dropna(subset=FEATURE_NAMES)
    
    if len(df1_clean) > 0 and len(df2_clean) > 0:
        features1 = df1_clean[FEATURE_NAMES].iloc[-1:]
        features2 = df2_clean[FEATURE_NAMES].iloc[-1:]
        
        features1_scaled = scaler.transform(features1)
        features2_scaled = scaler.transform(features2)
        
        regime1 = model.predict(features1_scaled)[0]
        regime2 = model.predict(features2_scaled)[0]
        
        probs1 = model.predict_proba(features1_scaled)[0]
        probs2 = model.predict_proba(features2_scaled)[0]
        
        print(f"\nDataset 1 (last close: {df1.iloc[-1]['close']:.2f}):")
        print(f"  Regime: {regime1}, Confidence: {probs1[regime1]:.1%}")
        
        print(f"\nDataset 2 (last close: {df2.iloc[-1]['close']:.2f}):")
        print(f"  Regime: {regime2}, Confidence: {probs2[regime2]:.1%}")
        
        print(f"\nPrice difference: 0.5 pips")
        
        if regime1 == regime2:
            print("✅ ROBUST: Same regime despite 0.5 pip change")
        else:
            print("❌ SENSITIVE: Regime changed from tiny 0.5 pip move!")
            print("   This suggests model is too sensitive or features are unstable")
else:
    print("⚠️ Skipped (model not loaded)")

print("\n" + "=" * 80)
print("TEST 4: Buffer Size Impact")
print("=" * 80)
print("\nTesting: Does buffer size affect predictions?")
print("(It shouldn't if we always use last 626+ bars)")

if model and scaler:
    # Test with different buffer sizes
    for buffer_size in [700, 1000, 1300]:
        df_test = df.tail(buffer_size).copy()
        df_test = compute_all_features(df_test)
        df_test_clean = df_test.dropna(subset=FEATURE_NAMES)
        
        if len(df_test_clean) > 0:
            features = df_test_clean[FEATURE_NAMES].iloc[-1:]
            features_scaled = scaler.transform(features)
            regime = model.predict(features_scaled)[0]
            probs = model.predict_proba(features_scaled)[0]
            
            print(f"\nBuffer size: {buffer_size} bars → Valid: {len(df_test_clean)} bars")
            print(f"  Regime: {regime}, Confidence: {probs[regime]:.1%}")
else:
    print("⚠️ Skipped (model not loaded)")

print("\n" + "=" * 80)
print("HYPOTHESIS: THE AUTO-REFRESH BUG")
print("=" * 80)

print("""
You added auto-refresh every 10 seconds to update the Regime Monitor tab.

POTENTIAL BUG:
  - refresh_regime_monitor() calls predictor.predict()
  - predict() uses the SAME data buffer (no new bars)
  - BUT: Features might be recalculated from scratch?
  - If recalculation is non-deterministic → regime flips!

CODE TO CHECK (regime_trading_gui.py):

def refresh_regime_monitor(self):
    if self.predictor and self.predictor.current_regime is not None:
        # Re-predict with current data
        regime, confidence, probs = self.predictor.predict()  ← THIS LINE
        
        if regime is not None:
            self.update_regime_display(regime, confidence, probs)

QUESTION: Does predict() recalculate features or use cached features?

If it RECALCULATES:
  - Same data + recalculation = should give same result
  - IF different results → BUG in feature calculation!

If it uses CACHED features:
  - Should always give same result (deterministic)

Let's check the predictor implementation...
""")

print("\n" + "=" * 80)
print("RECOMMENDED ACTIONS")
print("=" * 80)

print("""
1. DISABLE AUTO-REFRESH TEMPORARILY:
   └─ Comment out the auto-refresh timer in regime_trading_gui.py
   └─ Test if regime still flips without refresh
   └─ This isolates whether auto-refresh is the cause

2. ADD LOGGING TO PREDICTOR:
   └─ Log feature values before prediction
   └─ Check if features change when they shouldn't
   └─ Log: "predict() called, features hash: <hash>"

3. CHECK BUFFER MANAGEMENT:
   └─ Does buffer grow indefinitely?
   └─ Are old bars properly removed?
   └─ Are timestamps unique and sorted?

4. TEST WITH STATIC DATA:
   └─ Disconnect from MT5
   └─ Load 1300 bars from CSV
   └─ Predict regime 100 times
   └─ All predictions should be identical

5. COMPARE WITH OLD GUI:
   └─ Your old mt5_regime_gui.py was stable
   └─ What's different in the new implementation?
   └─ Did we introduce non-determinism?
""")

print("\n" + "=" * 80)
print("NEXT STEPS")
print("=" * 80)

print("""
1. Share the console output from Python GUI:
   └─ Are there "[WARMUP FIX] Sending regime..." messages every 10 sec?
   └─ Does regime change in console without new bars?

2. Check Statistics tab:
   └─ Does it show regime changing frequently?
   └─ Or is it stable there but flipping in Regime Monitor?

3. Temporarily disable auto-refresh:
   └─ Edit: regime_trading_gui.py
   └─ Comment line: self.regime_refresh_timer.start(10000)
   └─ Restart GUI and test for 10 minutes
   └─ Does regime still flip?

If regime is stable with auto-refresh disabled:
  → BUG is in refresh_regime_monitor() function

If regime still flips with auto-refresh disabled:
  → BUG is in how new bars are processed or buffer management

Either way, we'll hunt it down! 🔍
""")

print("\n" + "=" * 80)
