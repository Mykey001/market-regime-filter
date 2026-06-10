"""
Quick test script to verify regime calculation matches what EA will see
"""
import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import joblib
import os
from feature_engine import compute_all_features, get_feature_matrix, FEATURE_NAMES

# Load model and scaler
script_dir = os.path.dirname(os.path.abspath(__file__))

model_paths = [
    os.path.join(script_dir, "market_regime_model.pkl"),
    os.path.join(script_dir, "market_regime_gmm.pkl"),
]

scaler_paths = [
    os.path.join(script_dir, "regime_scaler.pkl"),
    os.path.join(script_dir, "scaler.pkl"),
]

model = None
for path in model_paths:
    if os.path.exists(path):
        try:
            model = joblib.load(path)
            print(f"✓ Loaded model: {os.path.basename(path)}")
            break
        except Exception as e:
            print(f"✗ Failed to load {path}: {e}")

scaler = None
for path in scaler_paths:
    if os.path.exists(path):
        try:
            scaler = joblib.load(path)
            print(f"✓ Loaded scaler: {os.path.basename(path)}")
            break
        except Exception as e:
            print(f"✗ Failed to load {path}: {e}")

if model is None or scaler is None:
    print("\n❌ ERROR: Could not load model or scaler!")
    exit(1)

# Configuration
REGIME_NAMES = {
    0: "Regime 1 - Low Vol Bullish",
    1: "Regime 2 - Neutral Consolidation",
    2: "Regime 3 - High Vol Bearish",
    3: "Regime 4 - Low Vol Bearish",
    4: "Regime 5 - Extreme Vol Spike",
    5: "Regime 6 - Crisis Mode",
    6: "Regime 7 - High Vol Mixed",
    7: "Regime 8 - Bearish Trending"
}

REGIME_DIRECTION = {
    0: "bullish", 1: "neutral", 2: "bearish", 3: "bearish",
    4: "neutral", 5: "bearish", 6: "neutral", 7: "bearish",
}

REGIME_FILTER_CONFIG = {
    0: True, 1: True, 2: False, 3: True,
    4: False, 5: False, 6: True, 7: True,
}

# Fetch data
print("\n" + "="*60)
print("TESTING CURRENT REGIME CALCULATION")
print("="*60)

if not mt5.initialize():
    print(f"❌ MT5 initialize failed: {mt5.last_error()}")
    exit(1)

symbol = "XAUUSD"
timeframe = mt5.TIMEFRAME_M5
bars = 800

print(f"\nFetching {bars} bars for {symbol} on M5...")

rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)
mt5.shutdown()

if rates is None:
    print("❌ Failed to fetch rates!")
    exit(1)

df = pd.DataFrame(rates)
df["time"] = pd.to_datetime(df["time"], unit="s")

print(f"✓ Fetched {len(df)} bars")
print(f"  Latest bar time: {df['time'].iloc[-1]}")
print(f"  Close price: {df['close'].iloc[-1]:.2f}")

# Calculate features
print("\nCalculating features...")
df_feat = compute_all_features(df)
X, valid_df = get_feature_matrix(df_feat, drop_na=True)

print(f"✓ After feature calculation: {len(valid_df)} valid bars")

# Predict regime
latest = valid_df.iloc[[-1]]
X_latest = latest[FEATURE_NAMES].values.astype(np.float64)
X_scaled = scaler.transform(X_latest)

regime_id = model.predict(X_scaled)[0]

if hasattr(model, "predict_proba"):
    probabilities = model.predict_proba(X_scaled)[0]
elif hasattr(model, "score_samples"):
    result = model.score_samples(X_scaled)
    if isinstance(result, tuple) and len(result) == 2:
        probabilities = result[1][0]
else:
    probabilities = None

confidence = float(np.max(probabilities) * 100) if probabilities is not None else 0.0

# Display results
print("\n" + "="*60)
print("CURRENT REGIME PREDICTION")
print("="*60)
print(f"Internal Regime ID: {regime_id}")
print(f"Display Name: {REGIME_NAMES.get(regime_id, 'Unknown')}")
print(f"Confidence: {confidence:.1f}%")
print(f"Direction: {REGIME_DIRECTION.get(regime_id, 'unknown')}")
print(f"Filter Status: {'ALLOWED ✓' if REGIME_FILTER_CONFIG.get(regime_id, True) else 'BLOCKED ✗'}")

# Check trade scenarios
print("\n" + "="*60)
print("TRADE DECISION SIMULATION")
print("="*60)

regime_direction = REGIME_DIRECTION.get(regime_id, "neutral")
filter_allowed = REGIME_FILTER_CONFIG.get(regime_id, True)

for action in ["buy", "sell"]:
    print(f"\n{action.upper()} Trade:")
    
    # Check basic filter
    if not filter_allowed:
        print(f"  ❌ BLOCKED - Regime {regime_id} is disabled in filter config")
        continue
    
    # Check directional filter (strict mode)
    if regime_direction == "bullish" and action == "sell":
        print(f"  ❌ BLOCKED - Regime is BULLISH, SELL is counter-trend")
    elif regime_direction == "bearish" and action == "buy":
        print(f"  ❌ BLOCKED - Regime is BEARISH, BUY is counter-trend")
    elif regime_direction == "neutral":
        print(f"  ❌ BLOCKED - Regime is NEUTRAL (strict mode blocks all)")
    else:
        print(f"  ✅ ALLOWED - {action.upper()} is with the trend ({regime_direction})")

# Show probabilities
if probabilities is not None:
    print("\n" + "="*60)
    print("ALL REGIME PROBABILITIES")
    print("="*60)
    for i, prob in enumerate(probabilities):
        marker = "⭐" if i == regime_id else "  "
        print(f"{marker} {REGIME_NAMES.get(i, f'Regime {i}'):30s} {prob*100:6.2f}%")

print("\n" + "="*60)
print("This is what your EA should see when it queries the GUI!")
print("="*60)
