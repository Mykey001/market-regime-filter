"""
Market Regime Engine v2
=======================
Replaces the Bayesian-GMM detector (market_regime_gmm.pkl + scaler.pkl).

Why it was replaced (audit on Exness XAUUSDm M5, 2022-01 -> 2026-10):
  * The GMM has 10 components but the system assumed 8; components 8 and 9
    (16% of bars) were clamped to "Regime 8 - Bearish Trending".
  * Regime names/directions were assigned by hand and do not match what the
    clusters contain (e.g. "Low Vol Bearish" is up 86% of the time over the
    prior 4h). Bull/bear labels agreed with the real move ~51% of the time.
  * The spread feature is broker-dependent: on a 3-digit gold feed it sits
    ~28 scaler units outside the training range and 99.9% of bars land in
    "Extreme Vol Spike".
  * Labels flickered ~18 times per day.

How regimes are detected now
----------------------------
Two independent, scale-free axes (no price level, spread or tick volume, so
the same thresholds work for any broker / instrument):

  Volatility  d_t = ln(H/L) / median ln(H/L) at the same time of day over the
              previous REF_DAYS sessions (1.0 = normal for this hour).
              V   = mean d over the last 2h,  Vf = mean d over the last 1h.
              normal -> HIGH when V >= 1.6 (back below 1.3)
              any    -> EXTREME when V >= 2.8 or Vf >= 3.5 (back below 2.0)

  Trend       Z = ln(C_t / C_{t-6h}) / sqrt(sum of squared returns over 6h)
              (net move measured in units of the path's own noise; a random
              walk gives Z ~ N(0,1)).
              range -> UP when Z >= +1.5 (back below +0.6), mirror for DOWN.

The hysteresis bands make each state persist instead of flickering.
The two axes combine into the 8 regime IDs used by the EA protocol.

Confidence is an empirical hit-rate: models/regime_calibration.json stores,
per detected state and score bin, how often the hindsight truth agreed on the
calibration data (see calibrate_regime_engine.py). If the file is missing a
margin-based fallback is used.

Only CLOSED bars must be passed in (drop the forming bar).
"""

import json
import os

import numpy as np
import pandas as pd

ENGINE_VERSION = "2.0"

# ------------------------------------------------------------------
# Parameters (tuned on XAUUSDm M5 2022-2024, tested on 2025-2026)
# ------------------------------------------------------------------
REF_DAYS = 60            # seasonal volatility reference (sessions)
MIN_REF_DAYS = 20        # minimum sessions before the reference is usable
VOL_WINDOW_MIN = 120     # V  : 2h
VOL_FAST_MIN = 60        # Vf : 1h
TREND_WINDOW_MIN = 360   # Z  : 6h

HI_IN, HI_OUT = 1.6, 1.3
EX_IN, EX_OUT, EX_FAST = 2.8, 2.0, 3.5
TR_IN, TR_OUT = 1.5, 0.6

# vol state: 0 normal, 1 high, 2 extreme | trend state: -1 down, 0 range, +1 up
VOL_STATES = {0: "normal", 1: "high", 2: "extreme"}
TREND_STATES = {-1: "down", 0: "range", 1: "up"}

# Regime IDs are kept 0-7 so the EA socket protocol is unchanged.
REGIMES = {
    0: {"name": "Bullish Trend",        "direction": "bullish", "allow": True},
    1: {"name": "Range / Consolidation", "direction": "neutral", "allow": True},
    2: {"name": "High Vol Bearish",     "direction": "bearish", "allow": False},
    3: {"name": "Bearish Trend",        "direction": "bearish", "allow": True},
    4: {"name": "Extreme Vol Spike",    "direction": "neutral", "allow": False},
    5: {"name": "Crash / Crisis",       "direction": "bearish", "allow": False},
    6: {"name": "High Vol Choppy",      "direction": "neutral", "allow": True},
    7: {"name": "High Vol Bullish",     "direction": "bullish", "allow": True},
}

# (vol_state, trend_state) -> regime id
REGIME_OF = {
    (0, 1): 0, (0, 0): 1, (0, -1): 3,
    (1, 1): 7, (1, 0): 6, (1, -1): 2,
    (2, 1): 4, (2, 0): 4, (2, -1): 5,
}

_CALIB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "models", "regime_calibration.json")
_calib_cache = {}


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
def bars_for(minutes, tf_minutes, floor=3):
    return max(int(round(minutes / tf_minutes)), floor)


def required_bars(tf_minutes):
    """Bars to fetch so the seasonal reference is fully populated."""
    per_session = int(round(1380 / tf_minutes))   # ~23h trading day
    return REF_DAYS * per_session + bars_for(TREND_WINDOW_MIN, tf_minutes) + 50


def _infer_tf_minutes(index):
    if not isinstance(index, pd.DatetimeIndex) or len(index) < 3:
        return 5
    step = pd.Series(index).diff().dropna().dt.total_seconds().median() / 60.0
    return max(int(round(step)), 1)


def _roll_mean(x, w):
    """Trailing mean over w bars, ignoring NaNs; NaN if under half are valid."""
    x = np.asarray(x, dtype=np.float64)
    valid = ~np.isnan(x)
    c = np.cumsum(np.r_[0.0, np.where(valid, x, 0.0)])
    n = np.cumsum(np.r_[0, valid.astype(np.int64)])
    out = np.full(len(x), np.nan)
    if len(x) >= w:
        k = n[w:] - n[:-w]
        with np.errstate(divide="ignore", invalid="ignore"):
            out[w - 1:] = np.where(k >= max(1, w / 2), (c[w:] - c[:-w]) / k, np.nan)
    return out


def _hysteresis_trend(z):
    out = np.zeros(len(z), dtype=np.int8)
    s = 0
    for i, v in enumerate(z):
        if v == v:
            if s == 1 and v < TR_OUT:
                s = 0
            elif s == -1 and v > -TR_OUT:
                s = 0
            if s == 0:
                if v >= TR_IN:
                    s = 1
                elif v <= -TR_IN:
                    s = -1
        out[i] = s
    return out


def _hysteresis_vol(v, vf):
    out = np.zeros(len(v), dtype=np.int8)
    s = 0
    for i in range(len(v)):
        a, f = v[i], vf[i]
        if a == a:
            if s == 2 and a < EX_OUT and not (f >= EX_FAST):
                s = 1
            if s == 1 and a < HI_OUT:
                s = 0
            if a >= EX_IN or f >= EX_FAST:
                s = 2
            elif s == 0 and a >= HI_IN:
                s = 1
        out[i] = s
    return out


# ------------------------------------------------------------------
# Core computation
# ------------------------------------------------------------------
def _ohlc(df):
    cols = {c.lower().strip().replace("<", "").replace(">", ""): c for c in df.columns}
    out = pd.DataFrame({k: df[cols[k]].astype(float).values for k in ("open", "high", "low", "close")})
    if "time" in cols and not isinstance(df.index, pd.DatetimeIndex):
        out.index = pd.to_datetime(df[cols["time"]].values)
    else:
        out.index = df.index
    return out


def compute_regime_series(df, tf_minutes=None):
    """Compute regime scores and states for every bar.

    Args:
        df: closed OHLC bars, oldest first, with a DatetimeIndex or a 'time'
            column. Any extra columns are ignored.
        tf_minutes: bar size; inferred from the timestamps if omitted.

    Returns:
        DataFrame indexed by time with close, vol_ratio (V), vol_ratio_fast (Vf),
        trend_z (Z), vol_state, trend_state, regime_id. Rows before the
        seasonal reference is ready have NaN scores and regime_id = -1.
    """
    bars = _ohlc(df)
    if tf_minutes is None:
        tf_minutes = _infer_tf_minutes(bars.index)

    high, low, close = bars["high"].values, bars["low"].values, bars["close"].values
    g = np.log(np.maximum(high, 1e-12) / np.maximum(low, 1e-12))

    # seasonal (time-of-day) baseline: median range at the same clock time
    # over the previous REF_DAYS sessions, excluding the current bar
    idx = bars.index
    slot = idx.hour * 60 + idx.minute if isinstance(idx, pd.DatetimeIndex) else np.zeros(len(g))
    base = (pd.Series(g, index=np.arange(len(g)))
            .groupby(np.asarray(slot))
            .transform(lambda x: x.rolling(REF_DAYS, min_periods=MIN_REF_DAYS).median().shift(1))
            .values)
    with np.errstate(divide="ignore", invalid="ignore"):
        d = g / np.where(base > 1e-9, base, np.nan)

    v = _roll_mean(d, bars_for(VOL_WINDOW_MIN, tf_minutes))
    vf = _roll_mean(d, bars_for(VOL_FAST_MIN, tf_minutes))

    lc = np.log(close)
    r = np.r_[np.nan, np.diff(lc)]
    w = bars_for(TREND_WINDOW_MIN, tf_minutes, floor=6)
    rv = np.sqrt(_roll_mean(r ** 2, w) * w)
    net = lc - np.r_[np.full(w, np.nan), lc[:-w]] if len(lc) > w else np.full(len(lc), np.nan)
    with np.errstate(divide="ignore", invalid="ignore"):
        z = np.where(rv > 0, net / rv, 0.0)
    z[np.isnan(net) | np.isnan(rv)] = np.nan

    vs = _hysteresis_vol(v, vf)
    ts = _hysteresis_trend(z)
    rid = np.array([REGIME_OF[(int(a), int(b))] for a, b in zip(vs, ts)], dtype=np.int64)
    ready = ~(np.isnan(v) | np.isnan(z))
    rid[~ready] = -1

    return pd.DataFrame({
        "close": close, "vol_ratio": v, "vol_ratio_fast": vf, "trend_z": z,
        "vol_state": vs, "trend_state": ts, "regime_id": rid,
    }, index=bars.index)


# ------------------------------------------------------------------
# Confidence / probabilities
# ------------------------------------------------------------------
def load_calibration(path=_CALIB_PATH):
    if path in _calib_cache:
        return _calib_cache[path]
    calib = None
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                calib = json.load(f)
        except Exception:
            calib = None
    _calib_cache[path] = calib
    return calib


def _lookup(table, state, score):
    """Return P(true class) list for a detected state and score."""
    edges = table["edges"]
    b = int(np.searchsorted(edges, score, side="right"))
    key = f"{state}|{b}"
    if key in table["bins"]:
        return table["bins"][key]
    return table["state"][str(state)]


def _fallback_axis(classes, state, margin):
    # margin >= 0 means comfortably inside the detected state
    p_state = 1.0 / (1.0 + np.exp(-2.0 * margin)) * 0.5 + 0.45
    rest = (1.0 - p_state) / (len(classes) - 1)
    return [p_state if c == state else rest for c in classes]


def axis_probabilities(row, calib=None):
    """P(true vol class 0/1/2) and P(true trend class -1/0/1) for one bar."""
    vs, ts = int(row["vol_state"]), int(row["trend_state"])
    v, z = float(row["vol_ratio"]), float(row["trend_z"])
    if calib is not None:
        pv = _lookup(calib["vol"], vs, v)
        pt = _lookup(calib["trend"], ts, z)
    else:
        vm = {0: HI_IN - v, 1: min(v - HI_OUT, EX_IN - v), 2: v - EX_OUT}[vs]
        tm = {1: z - TR_OUT, -1: -TR_OUT - z, 0: TR_IN - abs(z)}[ts]
        pv = _fallback_axis([0, 1, 2], vs, vm)
        pt = _fallback_axis([-1, 0, 1], ts, tm)
    return np.asarray(pv, float), np.asarray(pt, float)


def regime_probabilities(pv, pt):
    probs = np.zeros(8)
    for vi, vs in enumerate((0, 1, 2)):
        for ti, ts in enumerate((-1, 0, 1)):
            probs[REGIME_OF[(vs, ts)]] += pv[vi] * pt[ti]
    s = probs.sum()
    return probs / s if s > 0 else probs


# ------------------------------------------------------------------
# Public API used by the dashboard
# ------------------------------------------------------------------
def detect_regime(df, tf_minutes=None, calib_path=_CALIB_PATH):
    """Detect the current regime from closed bars.

    Returns dict: regime_id, regime_name, direction, confidence (0-100),
    probabilities (len 8), vol_state, trend_state, scores, series.
    """
    series = compute_regime_series(df, tf_minutes)
    ready = series[series["regime_id"] >= 0]
    if len(ready) == 0:
        tf = tf_minutes or _infer_tf_minutes(series.index)
        raise ValueError(
            f"Not enough history for regime detection: need about {required_bars(tf)} "
            f"closed bars ({REF_DAYS} sessions), got {len(series)}.")
    last = ready.iloc[-1]
    calib = load_calibration(calib_path)
    pv, pt = axis_probabilities(last, calib)
    probs = regime_probabilities(pv, pt)
    rid = int(last["regime_id"])
    return {
        "regime_id": rid,
        "regime_name": REGIMES[rid]["name"],
        "direction": REGIMES[rid]["direction"],
        "confidence": float(probs[rid] * 100.0),
        "probabilities": probs,
        "vol_state": VOL_STATES[int(last["vol_state"])],
        "trend_state": TREND_STATES[int(last["trend_state"])],
        "scores": {
            "vol_ratio_2h": float(last["vol_ratio"]),
            "vol_ratio_1h": float(last["vol_ratio_fast"]),
            "trend_z_6h": float(last["trend_z"]),
            "p_vol_state": float(pv[int(last["vol_state"])]),
            "p_trend_state": float(pt[int(last["trend_state"]) + 1]),
        },
        "time": ready.index[-1],
        "price": float(last["close"]),
        "series": ready,
        "calibrated": calib is not None,
    }
