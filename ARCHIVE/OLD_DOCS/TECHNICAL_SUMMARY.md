# Technical Summary - Market Regime Detection System

## Quick Reference Card

### System Components
```
feature_engine.py          → Feature computation (14 indicators)
market_regime_gmm.pkl      → Trained Bayesian GMM (10 components)
scaler.pkl                 → RobustScaler (median/IQR normalization)
inspect_model.py           → Model inspection utility
```

### Key Numbers
- **Features:** 14 technical indicators
- **Regimes:** 10 market states
- **Timeframe:** M5 (5-minute bars)
- **Warmup:** 626 bars (~52 hours)
- **Performance:** ~3 sec for 536K bars

---

## Feature List (Copy-Paste Ready)

```python
FEATURE_NAMES = [
    "volatility_1h",      # 1-hour rolling volatility
    "volatility_1d",      # 1-day rolling volatility
    "natr_14",            # Normalized ATR
    "bollinger_width",    # Bollinger Band width ratio
    "trend_short",        # (EMA12 - EMA48) / EMA48
    "trend_long",         # (EMA48 - EMA576) / EMA576
    "macd_hist",          # MACD histogram (normalized)
    "price_position",     # Position in daily range [0,1]
    "rsi_14",             # Wilder's RSI (14-period)
    "rsi_rate",           # RSI change over 1 hour
    "returns_skew",       # Rolling skewness (1-day)
    "volume_ratio",       # Volume surge ratio
    "spread_norm",        # Normalized spread
    "variance_ratio",     # Trending vs mean-reverting
]
```

---

## 10 Market Regimes (Ranked by Frequency)

| # | Weight | Name | Characteristics |
|---|--------|------|-----------------|
| 1 | **27.5%** | **Normal/Calm** | All features near zero, range-bound |
| 8 | 15.0% | Bullish Momentum | Positive trends, high RSI |
| 7 | 14.7% | Bearish Trending | Negative trends, low RSI |
| 3 | 13.1% | Bullish Trending | Positive trends, high RSI, momentum |
| 6 | 9.1% | High Vol Consolidation | High volatility, neutral trend |
| 2 | 7.4% | Volatile Expansion | High vol, wide Bollinger Bands |
| 0 | 5.3% | High Vol Trending | Moderate vol, strong short-term trend |
| 4 | 3.4% | Extreme Vol Spike | Very high vol, bearish reversal |
| 5 | 2.4% | **Crisis Mode** | Extreme vol, panic selling |
| 9 | 2.0% | Choppy/Erratic | High skewness, unstable |

---

## Model Specifications

### Bayesian Gaussian Mixture Model
```
Type: BayesianGaussianMixture
Components: 10
Covariance: Full (component-specific correlations)
Training iterations: 255
Converged: True ✅
```

### Weight Distribution
```
Weights: [0.053, 0.275, 0.074, 0.131, 0.034, 0.024, 
          0.091, 0.147, 0.150, 0.020]
```

### RobustScaler Parameters
```
Method: Median centering + IQR scaling
Features: 14
Outlier resistance: High (uses quantiles, not mean/std)
```

---

## Critical Implementation Notes

### ⚠️ Version Warning
```
Models: scikit-learn 1.9.0
Current: scikit-learn 1.8.0
Action: pip install --upgrade scikit-learn==1.9.0
```

### 📏 Feature Order (CRITICAL)
Features MUST be in this exact order for scaler/model:
```python
[volatility_1h, volatility_1d, natr_14, bollinger_width,
 trend_short, trend_long, macd_hist, price_position,
 rsi_14, rsi_rate, returns_skew, volume_ratio,
 spread_norm, variance_ratio]
```

### 🕐 Warmup Period
- **Minimum bars:** 626 (MIN_WARMUP)
- **Time at M5:** ~52 hours (2.17 days)
- **Reason:** Longest window is 2-day EMA (576) + buffer
- **NaN handling:** First 626 rows must be dropped

---

## Quick Start Code

### 1. Feature Computation
```python
from feature_engine import compute_all_features, get_feature_matrix

# Load OHLCV data
df = pd.read_csv("your_data.csv")

# Compute features
df_features = compute_all_features(df)

# Extract clean matrix (drops NaN warmup rows)
X, valid_df = get_feature_matrix(df_features, drop_na=True)
```

### 2. Regime Prediction
```python
import joblib

# Load models
scaler = joblib.load("scaler.pkl")
gmm = joblib.load("market_regime_gmm.pkl")

# Scale and predict
X_scaled = scaler.transform(X)
regimes = gmm.predict(X_scaled)
probs = gmm.predict_proba(X_scaled)

# Add to dataframe
valid_df['regime'] = regimes
valid_df['confidence'] = probs.max(axis=1)
```

### 3. Regime Analysis
```python
# Distribution
print(valid_df['regime'].value_counts(normalize=True))

# Current regime
current_regime = regimes[-1]
current_prob = probs[-1, current_regime]
print(f"Current: Regime {current_regime} ({current_prob:.1%} confidence)")

# Transition detection
if len(regimes) > 1 and regimes[-1] != regimes[-2]:
    print(f"Regime change: {regimes[-2]} → {regimes[-1]}")
```

---

## Performance Benchmarks

### Feature Engine Speed
```
 2,000 bars: 0.197 seconds
50,000 bars: ~1.5 seconds (estimated)
536,000 bars: ~3 seconds (documented)
```

### Memory Usage
```
Raw data (536K × 6 cols): ~25 MB
Features (536K × 14): ~58 MB
Total peak: ~100 MB (manageable)
```

---

## Column Name Variants (Auto-Handled)

The feature engine automatically normalizes these variants:

| Standard | Variants |
|----------|----------|
| `open` | `Open`, `<OPEN>` |
| `high` | `High`, `<HIGH>` |
| `low` | `Low`, `<LOW>` |
| `close` | `Close`, `<CLOSE>` |
| `tickvol` | `tick_volume`, `volume`, `<TICKVOL>` |
| `spread` | `Spread`, `<SPREAD>` |

---

## Regime Interpretation Guidelines

### High-Frequency Regimes (Use for trading)
- **Regime 1 (27.5%):** Mean reversion strategies
- **Regime 8 (15.0%):** Trend following (bullish)
- **Regime 7 (14.7%):** Trend following (bearish)
- **Regime 3 (13.1%):** Momentum strategies (bullish)

### Low-Frequency Regimes (Risk management)
- **Regime 5 (2.4%):** Exit all positions, crisis mode
- **Regime 4 (3.4%):** Reduce exposure, high volatility
- **Regime 9 (2.0%):** Stay out, erratic behavior

### Moderate-Frequency Regimes
- **Regime 6 (9.1%):** Volatility breakout strategies
- **Regime 2 (7.4%):** Range expansion plays
- **Regime 0 (5.3%):** Short-term scalping

---

## Troubleshooting

### Issue: Features don't match
**Symptom:** ValueError during `scaler.transform()`  
**Solution:** Ensure all 14 features are present in exact order

### Issue: All NaN in output
**Symptom:** No valid rows after feature computation  
**Solution:** Check that input has at least 626 bars

### Issue: Model predictions look wrong
**Symptom:** All regimes = 1 or nonsensical distribution  
**Solution:** 
1. Verify scikit-learn version (1.9.0)
2. Check feature scaling (values should be ~[-3, +3])
3. Ensure input data is M5 timeframe (not M1, M15, etc.)

### Issue: Performance is slow
**Symptom:** >10 seconds for 100K bars  
**Solution:**
1. Update NumPy/Pandas to latest versions
2. Ensure `drop_na=True` in `get_feature_matrix()`
3. Don't recompute features on every tick (cache)

---

## Data Requirements

### Minimum Columns (Required)
```python
['open', 'high', 'low', 'close']
```

### Recommended Columns
```python
['open', 'high', 'low', 'close', 'tickvol', 'spread']
```

### Optional Columns (Ignored)
```python
['date', 'time', 'vol', 'datetime', 'timestamp']
```

### Data Quality Checks
- ✅ No missing values in OHLC
- ✅ High ≥ Low ≥ 0
- ✅ Close within [Low, High]
- ✅ Chronological order (oldest first)
- ✅ No duplicate timestamps

---

## Integration Checklist

### Before First Run
- [ ] Upgrade scikit-learn to 1.9.0
- [ ] Verify input data has ≥626 bars
- [ ] Confirm M5 timeframe (5-minute bars)
- [ ] Check column names match expected format

### After First Run
- [ ] Inspect regime distribution (should match weights)
- [ ] Check confidence levels (avg should be >0.6)
- [ ] Validate no excessive regime switching (noise)
- [ ] Backtest each regime individually

### Production Monitoring
- [ ] Log regime distribution every hour/day
- [ ] Alert if rare regimes persist (4, 5, 9)
- [ ] Track regime transition frequency
- [ ] Monitor feature scaling (detect drift)

---

## Advanced: Incremental Updates

For real-time trading, don't recompute entire history:

```python
# Cache rolling windows
class RealtimeFeatures:
    def __init__(self, warmup_data):
        self.history = warmup_data.copy()
        self.ema_states = self._init_emas()
    
    def update(self, new_bar):
        # Update rolling windows incrementally
        # Update EMA states
        # Compute only latest features
        pass
```

*(Full implementation requires ~200 lines, not shown here)*

---

## Appendix: Regime Means (Raw Values)

```
Regime 0: [ 0.111,  0.782,  0.051,  0.024,  0.196, -0.517,  0.118, ...]
Regime 1: [-0.380, -0.421, -0.454, -0.419, -0.042,  0.037, -0.003, ...]
Regime 2: [ 1.111,  0.486,  1.038,  1.539,  0.173, -0.166,  0.496, ...]
Regime 3: [ 0.069,  0.188,  0.058,  0.055,  0.606,  0.947,  0.038, ...]
Regime 4: [ 2.526,  1.276,  2.098,  3.084, -2.545, -1.224, -1.876, ...]
Regime 5: [ 4.802,  3.597,  5.223,  5.784, -2.318, -3.304,  0.878, ...]
Regime 6: [ 1.520,  2.573,  1.763,  1.351,  0.356, -0.904,  0.102, ...]
Regime 7: [ 0.333,  0.038,  0.263,  0.300, -0.638, -0.090, -0.447, ...]
Regime 8: [ 0.046, -0.154,  0.038,  0.158,  0.351, -0.104,  0.404, ...]
Regime 9: [-0.298,  0.106, -0.376, -0.320,  0.254,  0.815,  0.022, ...]
```

*(Values are in scaled space, not raw feature space)*

---

**Document Version:** 1.0  
**Last Updated:** June 9, 2026  
**Compatibility:** scikit-learn 1.9.0, NumPy 1.24+, Pandas 2.0+
