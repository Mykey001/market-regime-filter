"""
Installation Test Script
========================
Verifies that all components are properly installed and working.
Run this before starting the GUI for the first time.
"""

import sys
import os
from pathlib import Path

print("=" * 60)
print("Market Regime Trading System - Installation Test")
print("=" * 60)
print()

# Test 1: Python version
print("Test 1: Python Version")
print("-" * 60)
py_version = sys.version_info
print(f"Python version: {py_version.major}.{py_version.minor}.{py_version.micro}")
if py_version.major >= 3 and py_version.minor >= 8:
    print("✓ Python version OK (3.8+)")
else:
    print("✗ Python version too old (need 3.8+)")
    sys.exit(1)
print()

# Test 2: Required packages
print("Test 2: Required Packages")
print("-" * 60)

packages = {
    "numpy": None,
    "pandas": None,
    "sklearn": "scikit-learn",
    "PyQt5": None,
    "joblib": None,
}

all_packages_ok = True
for module_name, package_name in packages.items():
    pkg_display = package_name if package_name else module_name
    try:
        mod = __import__(module_name)
        version = getattr(mod, "__version__", "unknown")
        print(f"✓ {pkg_display:20s} version {version}")
        
        # Special check for scikit-learn version
        if module_name == "sklearn":
            if not version.startswith("1.9"):
                print(f"  ⚠ Warning: scikit-learn should be 1.9.0 (found {version})")
    except ImportError:
        print(f"✗ {pkg_display:20s} NOT FOUND")
        all_packages_ok = False

if not all_packages_ok:
    print()
    print("Missing packages! Install with:")
    print("  pip install -r requirements.txt")
    sys.exit(1)
print()

# Test 3: Required files
print("Test 3: Required Files")
print("-" * 60)

script_dir = Path(__file__).parent
required_files = [
    "market_regime_gmm.pkl",
    "scaler.pkl",
    "feature_engine.py",
    "regime_trading_gui.py",
]

all_files_ok = True
for filename in required_files:
    filepath = script_dir / filename
    if filepath.exists():
        size = filepath.stat().st_size
        print(f"✓ {filename:30s} ({size:,} bytes)")
    else:
        print(f"✗ {filename:30s} NOT FOUND")
        all_files_ok = False

if not all_files_ok:
    print()
    print("Missing files! Ensure all files are in the same directory.")
    sys.exit(1)
print()

# Test 4: Feature engine
print("Test 4: Feature Engine")
print("-" * 60)
try:
    from feature_engine import compute_all_features, FEATURE_NAMES, MIN_WARMUP
    print(f"✓ Feature engine imported successfully")
    print(f"  Features: {len(FEATURE_NAMES)}")
    print(f"  Warmup period: {MIN_WARMUP} bars")
except Exception as e:
    print(f"✗ Feature engine import failed: {e}")
    sys.exit(1)
print()

# Test 5: Model loading
print("Test 5: Model Loading")
print("-" * 60)
try:
    import joblib
    import warnings
    
    # Suppress version warnings for this test
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        
        gmm = joblib.load(script_dir / "market_regime_gmm.pkl")
        scaler = joblib.load(script_dir / "scaler.pkl")
    
    print(f"✓ GMM model loaded")
    print(f"  Components: {gmm.n_components}")
    print(f"  Converged: {gmm.converged_}")
    
    print(f"✓ Scaler loaded")
    print(f"  Type: {type(scaler).__name__}")
    
except Exception as e:
    print(f"✗ Model loading failed: {e}")
    sys.exit(1)
print()

# Test 6: Quick prediction test
print("Test 6: Prediction Test")
print("-" * 60)
try:
    import numpy as np
    import pandas as pd
    
    # Generate synthetic test data
    np.random.seed(42)
    n = 700
    price = 1.0850 + np.cumsum(np.random.randn(n) * 0.0001)
    
    test_df = pd.DataFrame({
        "open": price + np.random.randn(n) * 0.0001,
        "high": price + np.abs(np.random.randn(n) * 0.0002),
        "low": price - np.abs(np.random.randn(n) * 0.0002),
        "close": price,
        "tickvol": np.random.randint(100, 500, n).astype(float),
        "spread": np.random.randint(1, 5, n).astype(float),
    })
    
    # Compute features
    from feature_engine import compute_all_features, get_feature_matrix
    df_features = compute_all_features(test_df)
    X, valid_df = get_feature_matrix(df_features, drop_na=True)
    
    if len(X) == 0:
        print("✗ Feature computation produced no valid rows")
        sys.exit(1)
    
    print(f"✓ Features computed: {X.shape}")
    
    # Scale and predict
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        X_scaled = scaler.transform(X[-1:, :])
        regime = gmm.predict(X_scaled)[0]
        probs = gmm.predict_proba(X_scaled)[0]
    
    print(f"✓ Prediction successful")
    print(f"  Test regime: {regime}")
    print(f"  Confidence: {probs[regime]:.1%}")
    
except Exception as e:
    print(f"✗ Prediction test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
print()

# Test 7: PyQt5 GUI test
print("Test 7: PyQt5 GUI")
print("-" * 60)
try:
    from PyQt5.QtWidgets import QApplication
    app = QApplication([])
    print("✓ PyQt5 GUI framework OK")
    app.quit()
except Exception as e:
    print(f"✗ PyQt5 test failed: {e}")
    sys.exit(1)
print()

# All tests passed
print("=" * 60)
print("ALL TESTS PASSED! ✓")
print("=" * 60)
print()
print("System is ready to use. You can now:")
print("  1. Run 'python regime_trading_gui.py' to start the GUI")
print("  2. Or double-click 'start_gui.bat' on Windows")
print()
print("Next steps:")
print("  - Read TRADING_GUI_SETUP_GUIDE.md for setup instructions")
print("  - Configure your MetaTrader EA connection")
print("  - Wait for 626 bars warmup before trading")
print()
