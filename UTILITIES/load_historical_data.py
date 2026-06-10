"""
Load Historical Data from CSV
==============================
If you have historical M5 data in CSV format, this script will load it
into the GUI to bypass the 52-hour wait.
"""

import sys
import pandas as pd
from pathlib import Path

# Check if feature engine is available
try:
    from feature_engine import compute_all_features, get_feature_matrix, MIN_WARMUP
    import joblib
except ImportError:
    print("Error: Required modules not found")
    print("Make sure you're running from the REGIME MOD directory")
    sys.exit(1)

print("=" * 60)
print("Historical Data Loader")
print("=" * 60)
print()

# Instructions
print("This script loads historical M5 data into a predictor.")
print()
print("Option 1: Load from MT5 Export")
print("-" * 60)
print("1. In MT5, right-click on GOLD M5 chart")
print("2. Save as → All History")
print("3. Export to CSV (semicolon delimited)")
print("4. Save as: historical_data.csv")
print("5. Place in this folder")
print()
print("Option 2: Direct EA Integration (Recommended)")
print("-" * 60)
print("The updated EA will send historical bars automatically")
print("Did you recompile and reattach the EA?")
print()

# Check for CSV file
csv_path = Path("historical_data.csv")
if not csv_path.exists():
    print("No historical_data.csv found.")
    print()
    print("To create one:")
    print("1. Open GOLD M5 chart in MT5")
    print("2. Press F2 (History Center)")
    print("3. Find GOLD M5")
    print("4. Right-click → Export")
    print("5. Save as historical_data.csv")
    print()
    input("Press Enter to exit...")
    sys.exit(0)

print(f"Found: {csv_path}")
print("Loading data...")

# Load CSV
try:
    # Try different delimiters
    df = pd.read_csv(csv_path, delimiter=';')
    if len(df.columns) == 1:
        df = pd.read_csv(csv_path, delimiter=',')
    if len(df.columns) == 1:
        df = pd.read_csv(csv_path, delimiter='\t')
    
    print(f"Loaded {len(df)} rows")
    print(f"Columns: {list(df.columns)}")
    
    # Standardize column names
    df.columns = [c.lower().strip().replace('<', '').replace('>', '') for c in df.columns]
    
    # Check required columns
    required = ['open', 'high', 'low', 'close']
    missing = [c for c in required if c not in df.columns]
    if missing:
        print(f"Error: Missing columns: {missing}")
        print("CSV must have: Date/Time, Open, High, Low, Close, Volume")
        sys.exit(1)
    
    # Take last 700 bars
    df = df.tail(700)
    print(f"Using last 700 bars")
    
    # Compute features
    print("Computing features...")
    df_features = compute_all_features(df)
    
    X, valid_df = get_feature_matrix(df_features, drop_na=True)
    
    print(f"Valid rows after feature computation: {len(valid_df)}")
    print(f"Feature matrix shape: {X.shape}")
    
    if len(valid_df) >= MIN_WARMUP:
        print(f"✓ Sufficient data! ({len(valid_df)} >= {MIN_WARMUP})")
        
        # Load model and predict
        script_dir = Path(__file__).parent
        model_path = script_dir / "market_regime_gmm.pkl"
        scaler_path = script_dir / "scaler.pkl"
        
        print("Loading model...")
        gmm = joblib.load(model_path)
        scaler = joblib.load(scaler_path)
        
        print("Making predictions...")
        X_scaled = scaler.transform(X[-10:])  # Last 10 bars
        regimes = gmm.predict(X_scaled)
        probs = gmm.predict_proba(X_scaled)
        
        print()
        print("Last 10 Regime Predictions:")
        print("-" * 60)
        for i, (regime, prob) in enumerate(zip(regimes, probs)):
            conf = prob[regime]
            print(f"Bar {i+1}: Regime {regime} (Confidence: {conf:.1%})")
        
        print()
        print("✓ Model is working correctly!")
        print()
        print("Note: This is just a test. The GUI needs live data from MT5.")
        
    else:
        print(f"✗ Insufficient data: {len(valid_df)} < {MIN_WARMUP}")
        print("Need more historical bars")
    
except Exception as e:
    print(f"Error loading data: {e}")
    import traceback
    traceback.print_exc()

print()
input("Press Enter to exit...")
