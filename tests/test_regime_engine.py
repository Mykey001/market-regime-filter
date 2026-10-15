"""
Tests for the Market Regime Engine v2 (src/python/regime_engine.py).

Run:  python tests/test_regime_engine.py      (or: pytest tests/test_regime_engine.py)
No MT5 connection needed - uses synthetic M5 bars.
"""
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src", "python"))
import regime_engine as RE  # noqa: E402


def synthetic_m5(sessions=70, seed=0):
    """Random-walk M5 bars, 23h sessions on weekdays, with an intraday volatility cycle."""
    rng = np.random.default_rng(seed)
    days = pd.bdate_range("2025-01-06", periods=sessions)
    idx = pd.DatetimeIndex(np.concatenate([d + pd.to_timedelta(np.arange(0, 23 * 60, 5), "min") for d in days]))
    hour = idx.hour.values
    sigma = 0.0006 * (1.0 + 0.8 * np.exp(-((hour - 14) ** 2) / 8.0))     # busier mid-session
    r = rng.normal(0, sigma)
    close = 2000.0 * np.exp(np.cumsum(r))
    opn = np.r_[close[0], close[:-1]]
    wick = np.abs(rng.normal(0, sigma * 0.6)) * close
    high = np.maximum(opn, close) + wick
    low = np.minimum(opn, close) - wick
    return pd.DataFrame({"open": opn, "high": high, "low": low, "close": close,
                         "tick_volume": rng.integers(50, 500, len(idx)), "spread": 20}, index=idx)


def _append(df, n, drift=0.0, vol_mult=1.0, seed=1):
    rng = np.random.default_rng(seed)
    step = pd.Timedelta(minutes=5)
    idx = pd.date_range(df.index[-1] + step, periods=n, freq=step)
    r = drift + rng.normal(0, 0.0006 * vol_mult, n)
    close = df["close"].iloc[-1] * np.exp(np.cumsum(r))
    opn = np.r_[df["close"].iloc[-1], close[:-1]]
    wick = np.abs(rng.normal(0, 0.0004 * vol_mult, n)) * close
    new = pd.DataFrame({"open": opn, "high": np.maximum(opn, close) + wick,
                        "low": np.minimum(opn, close) - wick, "close": close,
                        "tick_volume": 100, "spread": 20}, index=idx)
    return pd.concat([df, new])


def test_random_walk_is_mostly_quiet_range():
    s = RE.compute_regime_series(synthetic_m5(), 5)
    s = s[s.regime_id >= 0]
    assert (s.vol_state == 0).mean() > 0.85
    assert (s.regime_id == 1).mean() > 0.55


def test_no_lookahead():
    df = synthetic_m5(sessions=40)
    full = RE.compute_regime_series(df, 5)
    for cut in (len(df) - 3000, len(df) - 700, len(df) - 1):
        part = RE.compute_regime_series(df.iloc[:cut + 1], 5)
        pd.testing.assert_frame_equal(part, full.iloc[:cut + 1])


def test_price_scale_and_spread_invariance():
    df = synthetic_m5(sessions=40)
    a = RE.compute_regime_series(df, 5)
    scaled = df.copy()
    scaled[["open", "high", "low", "close"]] *= 7.3
    scaled["spread"] = 999999
    b = RE.compute_regime_series(scaled, 5)
    assert (a.regime_id.values == b.regime_id.values).all()
    np.testing.assert_allclose(a.trend_z.values, b.trend_z.values, equal_nan=True, atol=1e-9)


def test_detects_uptrend_and_downtrend():
    base = synthetic_m5(sessions=40)
    up = RE.detect_regime(_append(base, 96, drift=+0.0004), 5)
    assert up["trend_state"] == "up" and up["direction"] == "bullish"
    dn = RE.detect_regime(_append(base, 96, drift=-0.0004), 5)
    assert dn["trend_state"] == "down" and dn["direction"] == "bearish"


def test_detects_volatility_spike():
    r = RE.detect_regime(_append(synthetic_m5(sessions=40), 24, vol_mult=6.0), 5)
    assert r["vol_state"] == "extreme"
    assert r["regime_id"] in (4, 5)
    assert not RE.REGIMES[r["regime_id"]]["allow"]


def test_output_contract():
    r = RE.detect_regime(synthetic_m5(sessions=40), 5)
    assert 0 <= r["regime_id"] <= 7
    assert len(r["probabilities"]) == 8
    assert abs(r["probabilities"].sum() - 1.0) < 1e-9
    assert 0.0 < r["confidence"] <= 100.0


def test_insufficient_history_raises():
    try:
        RE.detect_regime(synthetic_m5(sessions=3), 5)
    except ValueError as e:
        assert "Not enough history" in str(e)
    else:
        raise AssertionError("expected ValueError")


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"\nAll {len(tests)} tests passed.")
