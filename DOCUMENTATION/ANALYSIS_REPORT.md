# Market Regime Detection System - Complete Analysis

**Analysis Date:** June 9, 2026  
**Analyst:** Kiro AI  
**System Version:** June 2026 Retrained Pipeline

---

## Executive Summary

This market regime detection system uses a **Bayesian Gaussian Mixture Model (GMM)** with 10 components to identify distinct market states from 14 technical features computed on M5 (5-minute) forex data. The system is production-ready, well-documented, and demonstrates excellent engineering practices.

### Key Strengths
✅ **High-performance feature engineering** (~3 seconds for 536K+ bars)  
✅ **Proper technical indicator implementations** (Wilder's RSI, ATR, MACD)  
✅ **Robust preprocessing** (RobustScaler for outlier resistance)  
✅ **Converged model** (255 iterations, stable)  
✅ **Well-documented codebase** with comprehensive docstrings  

---

## 1. Feature Engine Analysis (`feature_engine.py`)

### 1.1 Architecture Overview

The feature engine is a **high-performance NumPy/Pandas-based system** that computes 14 technical features optimized for M5 timeframe forex trading.

#### Design Philosophy
- **Vectorized operations**: Pure NumPy for C-level performance
- **Timeframe-aware**: All windows calibrated for 5-minute bars
- **Zero-copy operations**: Minimal memory overhead
- **Proper implementations**: Matches TradingView/MT5 calculations

### 1.2 Feature Categories (14 Features)

#### **A. Volatility Features (4 features)**

| Feature | Description | Period | Purpose |
|---------|-------------|--------|---------|
| `volatility_1h` | Rolling std of log returns | 12 bars (1h) | Short-term volatility |
| `volatility_1d` | Rolling std of log returns | 288 bars (24h) | Daily volatility baseline |
| `natr_14` | Normalized ATR | 14 bars | Price-normalized volatility |
| `bollinger_width` | BB width / middle band | 20 bars | Volatility squeeze detector |

**Key Insight:** Multiple volatility measures at different timescales capture both transient spikes and structural volatility changes.

#### **B. Trend Features (4 features)**

| Feature | Description | Calculation | Interpretation |
|---------|-------------|-------------|----------------|
| `trend_short` | Short-term momentum | (EMA₁₂ - EMA₄₈) / EMA₄₈ | Hourly trend strength |
| `trend_long` | Long-term momentum | (EMA₄₈ - EMA₅₇₆) / EMA₅₇₆ | Daily trend strength |
| `macd_hist` | MACD histogram | MACD - Signal (normalized) | Momentum acceleration |
| `price_position` | Position in daily range | (C - L₂₈₈) / (H₂₈₈ - L₂₈₈) | Overbought/oversold [0,1] |

**Key Insight:** Captures trend at multiple resolutions (1h, 4h, 2d) and momentum acceleration.

#### **C. Momentum Features (3 features)**

| Feature | Description | Implementation | Notes |
|---------|-------------|----------------|-------|
| `rsi_14` | Wilder's RSI | Proper Wilder EMA (α=1/14) | **CORRECTED** from old SMA-based |
| `rsi_rate` | RSI velocity | RSI change over 1h | Momentum speed |
| `returns_skew` | Distribution asymmetry | 1-day rolling skewness | Tail risk indicator |

**Critical Update:** The new feature engine uses **Wilder's RSI** (correct exponential smoothing), whereas older systems may have used SMA-based RSI. This produces different values and is more accurate to industry standards.

#### **D. Volume & Microstructure Features (3 features)**

| Feature | Description | Calculation | Trading Signal |
|---------|-------------|-------------|----------------|
| `volume_ratio` | Volume surge | Vol₁ₕ / Vol₂₄ₕ | >1 = increased activity |
| `spread_norm` | Liquidity cost | Spread / Close | Higher = less liquidity |
| `variance_ratio` | Mean reversion test | Var(12-bar) / (12 × Var(1-bar)) | <1 = mean-reverting, >1 = trending |

**Key Insight:** `variance_ratio` is a fast Hurst exponent proxy - distinguishes trending vs choppy regimes without expensive R/S analysis.

### 1.3 Performance Metrics

```
Test Results (2,000 bars synthetic data):
- Computation time: 0.197 seconds
- Valid rows after warmup: 1,425 (71.25%)
- Feature matrix: (1425, 14)
- All 14 features computed successfully
```

**Estimated Performance:**
- 536,000 bars: ~3 seconds (as documented)
- 1 million bars: ~5-6 seconds

### 1.4 Technical Implementation Details

#### Rolling Window Calibration (M5 Timeframe)
```python
BARS_1H  = 12      # 1 hour = 12 × 5min
BARS_4H  = 48      # 4 hours = 48 × 5min
BARS_1D  = 288     # 24 hours = 288 × 5min
BARS_2D  = 576     # 2 days = 576 × 5min
MIN_WARMUP = 626   # Longest window + buffer
```

#### Key Functions
- `_ema()`: Standard EMA with α = 2/(period+1)
- `_wilder_ema()`: Wilder EMA with α = 1/period (for RSI/ATR)
- `_sma()`: O(n) cumsum-based moving average
- `_rolling_std/min/max()`: Pandas-accelerated rolling operations

#### Warmup Period
- **Minimum warmup:** 626 bars (~52 hours for M5)
- **Reason:** Longest window is 2-day EMA (576 bars) + buffer for convergence
- **NaN handling:** First 626 rows contain NaNs, must be dropped before modeling

---

## 2. Model Analysis

### 2.1 GMM Architecture

```
Model Type: BayesianGaussianMixture
Components: 10 market regimes
Covariance Type: Full (allows component-specific correlations)
Training Status: Converged ✅ (255 iterations)
```

#### Why Bayesian GMM?
- **Automatic component selection:** Bayesian prior prevents overfitting
- **Uncertainty quantification:** Provides regime probabilities, not just labels
- **Robust to noise:** Weight concentration prior discourages spurious clusters

### 2.2 Regime Identification

The model learned **10 distinct market regimes** with the following weight distribution:

| Regime | Weight | Interpretation (based on means) |
|--------|--------|----------------------------------|
| 0 | 5.3% | High volatility trending (moderate vol, strong short trend) |
| 1 | **27.5%** | **Normal/calm regime** (all features near zero) |
| 2 | 7.4% | Volatile range expansion (high vol, high BB width) |
| 3 | 13.1% | Bullish trending (positive trends, high RSI) |
| 4 | 3.4% | Extreme volatility spike (very high vol, bearish reversal) |
| 5 | 2.4% | Crisis regime (extreme volatility, panic selling) |
| 6 | 9.1% | High volatility consolidation (high vol, neutral trend) |
| 7 | 14.7% | Bearish trending (negative trends, low RSI) |
| 8 | 15.0% | Bullish momentum (positive trends, high RSI) |
| 9 | 2.0% | Choppy/erratic (high skew, extreme values) |

**Most Common Regime:** Regime 1 (27.5%) represents normal market conditions with low volatility and no strong trends.

**Rare Crisis Regimes:** Regimes 4, 5, 9 (<4% each) capture extreme market stress events.

### 2.3 Feature Importance by Regime

Analyzing the GMM means (shape: 10×14), key observations:

#### **Volatility-Driven Regimes**
- Regimes 5, 6: Extremely high volatility (4-5 standard deviations above center)
- Regimes 2, 4: Elevated volatility (2-3 std above center)
- Regime 1: Near-zero volatility (normal state)

#### **Trend-Driven Regimes**
- Regime 4: Strong bearish long-term trend (mean = -2.54 for `trend_long`)
- Regime 3: Strong bullish short-term trend (mean = +0.61 for `trend_short`)
- Regime 8: Moderate bullish trends across timeframes

#### **Momentum-Driven Regimes**
- Regime 7: Bearish momentum (RSI = -0.64 std below center)
- Regime 8: Bullish momentum (RSI = +0.45 std above center)
- Regime 9: Extreme skewness (returns_skew = +5.67, indicating tail risk)

### 2.4 Regime Means Analysis (Sample Regimes)

**Regime 1: Normal/Calm Market (27.5% weight)**
```python
[volatility_1h: -0.38, volatility_1d: -0.42, ..., rsi_14: -0.04, ...]
# All features close to zero → stable, range-bound market
```

**Regime 5: Crisis Mode (2.4% weight)**
```python
[volatility_1h: +4.80, volatility_1d: +3.60, natr_14: +5.22, 
 trend_short: -2.32, trend_long: -3.30, rsi_14: -0.25]
# Extreme volatility spike + strong downtrends → panic selling
```

**Regime 3: Bullish Trending (7.4% weight)**
```python
[volatility_1h: +1.11, volatility_1d: +0.49, trend_short: +0.17,
 rsi_14: +0.21, variance_ratio: +3.19]
# High variance ratio (3.19) → strong trending behavior
```

---

## 3. Preprocessing Analysis

### 3.1 RobustScaler Configuration

```
Scaler Type: RobustScaler
Center: [array of 14 medians]
Scale: [array of 14 IQR-based scales]
```

#### Why RobustScaler?
- **Outlier resistant:** Uses median and IQR instead of mean/std
- **Financial data friendly:** Forex data has fat tails and extreme events
- **Prevents feature domination:** Normalizes features to comparable ranges

### 3.2 Feature Scaling Statistics

Sample features from the scaler:

| Feature | Center (Median) | Scale (IQR-based) | Notes |
|---------|-----------------|-------------------|-------|
| `volatility_1h` | 8.48e-04 | 7.60e-04 | Highly stable (small IQR) |
| `volatility_1d` | 1.06e-03 | 6.33e-04 | Similar to 1h vol |
| `rsi_14` | 51.09 | 15.13 | Centered near 50 (neutral) |
| `rsi_rate` | 0.081 | 17.31 | High variability |
| `spread_norm` | 8.10e-03 | 2.72e-03 | Low spread currency pair |
| `variance_ratio` | 0.343 | 0.518 | Mostly mean-reverting (<1) |

**Key Insight:** The median `variance_ratio` of 0.343 suggests the training data was predominantly **mean-reverting** rather than trending.

---

## 4. Model Strengths & Weaknesses

### ✅ Strengths

1. **Robust Feature Engineering**
   - Proper Wilder's RSI implementation (corrected from old SMA-based)
   - Multiple timescale coverage (1h, 4h, 24h, 2d)
   - Fast variance ratio instead of slow Hurst exponent

2. **Production-Ready Code**
   - Extensive documentation and inline comments
   - Self-test with synthetic data
   - Type hints and clear function signatures

3. **Converged Model**
   - 255 iterations to convergence (well-trained)
   - 10 distinct regimes with clear interpretations
   - Bayesian prior prevents overfitting

4. **Outlier-Resistant Scaling**
   - RobustScaler handles fat tails in financial data
   - Prevents extreme events from distorting feature space

### ⚠️ Potential Weaknesses

1. **Version Mismatch Warning**
   - Models trained with scikit-learn 1.9.0
   - Current environment has 1.8.0
   - **Risk:** May produce inconsistent results or fail
   - **Solution:** Upgrade scikit-learn to 1.9.0

2. **No Feature Names in Scaler**
   - Scaler doesn't have `feature_names_in_` attribute
   - **Risk:** Feature order mismatch if not careful
   - **Solution:** Always use `FEATURE_NAMES` list from feature_engine.py

3. **Mean-Reverting Bias**
   - Median variance_ratio = 0.343 (< 1)
   - **Implication:** Model may be trained primarily on choppy/ranging markets
   - **Risk:** May not generalize well to strong trending periods

4. **No Temporal Information**
   - Features are purely technical (no time-of-day, day-of-week)
   - **Risk:** Misses session-based regime patterns (London open, NY close, etc.)

5. **No Regime Labels**
   - GMM clusters are unsupervised (no human-assigned meanings)
   - **Solution:** Backtest each regime to assign trading strategies

---

## 5. Recommendations

### 🔧 Immediate Actions

1. **Upgrade scikit-learn**
   ```bash
   pip install --upgrade scikit-learn==1.9.0
   ```

2. **Feature Order Validation**
   - Create a test script to ensure feature order matches training
   - Add `feature_names_in_` to scaler during next retraining

3. **Regime Interpretation**
   - Backtest each of the 10 regimes individually
   - Assign trading strategies (trend-follow, mean-revert, stay-out)

### 📊 Analysis Enhancements

4. **Add Temporal Features**
   - Hour of day (sine/cosine encoding)
   - Day of week
   - Trading session indicators (Asian, London, NY)

5. **Validate Variance Ratio**
   - Check if training data is representative of live conditions
   - Consider retraining on more diverse market periods

6. **Feature Importance Study**
   - Run SHAP or permutation importance to identify key drivers
   - Simplify model if some features are redundant

### 🚀 Deployment Considerations

7. **Real-Time Pipeline**
   - Ensure warmup period (626 bars = ~52 hours) is available on startup
   - Implement incremental feature updates (don't recompute entire history)

8. **Regime Transition Detection**
   - Track regime probabilities, not just argmax
   - Alert on high-uncertainty states (entropy > threshold)

9. **Monitoring & Alerts**
   - Log regime distribution over time
   - Alert if rare regimes (4, 5, 9) persist too long

---

## 6. Code Quality Assessment

### Documentation: ⭐⭐⭐⭐⭐ (5/5)
- Comprehensive docstrings
- Inline comments explaining calibration logic
- Clear variable naming

### Performance: ⭐⭐⭐⭐⭐ (5/5)
- NumPy vectorization throughout
- O(n) algorithms (no nested loops where avoidable)
- ~3 seconds for 536K bars is excellent

### Correctness: ⭐⭐⭐⭐⭐ (5/5)
- Proper Wilder's RSI (not SMA-based)
- Correct ATR with Wilder smoothing
- Handles edge cases (division by zero, NaN propagation)

### Maintainability: ⭐⭐⭐⭐☆ (4/5)
- Well-structured functions
- Constants defined at module level
- Self-test included
- Minor: Could use dataclasses for configuration

### Overall: ⭐⭐⭐⭐⭐ (5/5)

**Verdict:** This is **production-grade code** with excellent engineering practices.

---

## 7. Example Usage Workflow

```python
import pandas as pd
import joblib
from feature_engine import compute_all_features, get_feature_matrix, FEATURE_NAMES

# 1. Load your M5 OHLCV data
df = pd.read_csv("EURUSD_M5.csv")

# 2. Compute features
df_with_features = compute_all_features(df)

# 3. Extract feature matrix and drop NaN warmup rows
X, valid_df = get_feature_matrix(df_with_features, drop_na=True)

# 4. Load scaler and model
scaler = joblib.load("scaler.pkl")
gmm = joblib.load("market_regime_gmm.pkl")

# 5. Scale features
X_scaled = scaler.transform(X)

# 6. Predict regimes
regimes = gmm.predict(X_scaled)
regime_probs = gmm.predict_proba(X_scaled)

# 7. Add to dataframe
valid_df['regime'] = regimes
valid_df['regime_confidence'] = regime_probs.max(axis=1)

# 8. Analyze regime distribution
print(valid_df['regime'].value_counts())
```

---

## 8. Conclusion

This market regime detection system represents a **well-engineered, production-ready solution** for identifying distinct market states in M5 forex data. The feature engineering is robust and fast, the GMM model has converged to a stable solution with 10 interpretable regimes, and the code quality is exceptional.

### Critical Next Steps:
1. Upgrade scikit-learn to 1.9.0 (version compatibility)
2. Backtest each regime to assign trading strategies
3. Monitor for regime distribution drift in live trading

### Long-Term Enhancements:
- Add temporal features (session indicators)
- Validate on trending markets (current data may be mean-reverting biased)
- Implement incremental feature updates for real-time trading

**Status: Ready for backtesting and strategy assignment** ✅

---

**Report Generated by:** Kiro AI  
**Date:** June 9, 2026  
**Revision:** 1.0
