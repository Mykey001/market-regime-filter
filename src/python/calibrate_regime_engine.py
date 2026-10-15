"""
Calibrate and validate the Market Regime Engine v2.

Writes models/regime_calibration.json (confidence tables) and prints how
often each detected regime agrees with what the market did in hindsight.

Hindsight truth (fixed definitions, never tuned):
  volatility : mean d over the CENTRED 4h window around the bar
               normal < 1.5 <= high < 2.5 <= extreme
  trend      : Z over the CENTRED 12h window around the bar
               up >= +1, down <= -1, otherwise range
(d and Z are defined in regime_engine.py.)

Usage:
  python calibrate_regime_engine.py --data XAUUSD_M1.parquet --train-end 2024-12-31
  python calibrate_regime_engine.py --data XAUUSD_M5.csv --tf 5 --no-write

Accepted data: parquet/CSV with time + OHLC columns (MT5 export <DATE>/<TIME>,
'time', or 'ts' with o/h/l/c). Finer bars are resampled to --tf minutes.
"""

import argparse
import json
import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regime_engine as RE  # noqa: E402

VOL_TRUTH_MIN = 240
TREND_TRUTH_MIN = 720
VOL_EDGES = [0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.4, 2.8, 3.5]
TREND_EDGES = [-3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
MIN_BIN = 200


# ------------------------------------------------------------------
# Data loading
# ------------------------------------------------------------------
def load_bars(path, tf_minutes=5):
    df = pd.read_parquet(path) if path.lower().endswith(".parquet") else pd.read_csv(path, sep=None, engine="python")
    df.columns = [c.lower().strip().replace("<", "").replace(">", "") for c in df.columns]
    df = df.rename(columns={"o": "open", "h": "high", "l": "low", "c": "close", "ts": "time"})
    if "date" in df.columns and "time" in df.columns:
        t = pd.to_datetime(df["date"].astype(str) + " " + df["time"].astype(str))
    elif "time" in df.columns:
        t = pd.to_datetime(df["time"], unit="s") if np.issubdtype(df["time"].dtype, np.number) else pd.to_datetime(df["time"])
    else:
        raise ValueError("No time column found")
    df = df[["open", "high", "low", "close"]].astype(float).set_index(pd.DatetimeIndex(t)).sort_index()
    step = RE._infer_tf_minutes(df.index)
    if step < tf_minutes:
        g = df.resample(f"{tf_minutes}min", label="left", closed="left")
        df = pd.DataFrame({"open": g["open"].first(), "high": g["high"].max(),
                           "low": g["low"].min(), "close": g["close"].last()}).dropna()
    return df


# ------------------------------------------------------------------
# Hindsight truth
# ------------------------------------------------------------------
def _centred(x, w):
    """Mean of x over the w bars centred on each bar (needs future bars)."""
    m = RE._roll_mean(np.asarray(x, float), w)
    return pd.Series(m).shift(-(w // 2)).values


def hindsight_truth(bars, series, tf_minutes):
    g = np.log(bars["high"].values / bars["low"].values)
    # d exactly as the engine defines it
    slot = bars.index.hour * 60 + bars.index.minute
    med = (pd.Series(g, index=np.arange(len(g))).groupby(np.asarray(slot))
           .transform(lambda x: x.rolling(RE.REF_DAYS, min_periods=RE.MIN_REF_DAYS).median().shift(1)).values)
    with np.errstate(divide="ignore", invalid="ignore"):
        d = g / np.where(med > 1e-9, med, np.nan)
    wv = RE.bars_for(VOL_TRUTH_MIN, tf_minutes)
    vc = _centred(d, wv)

    lc = np.log(bars["close"].values)
    r2 = np.r_[np.nan, np.diff(lc)] ** 2
    wt = RE.bars_for(TREND_TRUTH_MIN, tf_minutes, floor=6)
    h = wt // 2
    lcs = pd.Series(lc)
    rs = pd.Series(RE._roll_mean(r2, wt) * wt).shift(-h).values
    with np.errstate(divide="ignore", invalid="ignore"):
        zc = (lcs.shift(-h) - lcs.shift(wt - h)).values / np.sqrt(rs)

    # forward-looking versions (next 4h vol, next 12h move) for usefulness checks
    vf = pd.Series(RE._roll_mean(d, wv)).shift(-wv).values
    with np.errstate(divide="ignore", invalid="ignore"):
        zf = (lcs.shift(-wt) - lcs).values / np.sqrt(pd.Series(RE._roll_mean(r2, wt) * wt).shift(-wt).values)

    t = pd.DataFrame({"Vc": vc, "Zc": zc, "Vf": vf, "Zf": zf}, index=bars.index)
    t["vol_true"] = np.select([t.Vc >= 2.5, t.Vc >= 1.5], [2, 1], 0)
    t["trend_true"] = np.select([t.Zc >= 1.0, t.Zc <= -1.0], [1, -1], 0)
    t["valid"] = ~(np.isnan(vc) | np.isnan(zc)) & (series["regime_id"].values >= 0)
    return t


def regime_true(t):
    return np.array([RE.REGIME_OF[(int(a), int(b))] for a, b in zip(t.vol_true, t.trend_true)])


# ------------------------------------------------------------------
# Calibration tables
# ------------------------------------------------------------------
def _table(states, scores, truth, classes, edges):
    bins = np.searchsorted(edges, scores, side="right")
    out = {"edges": edges, "bins": {}, "state": {}}
    for s in np.unique(states):
        m = states == s
        out["state"][str(int(s))] = [float(np.mean(truth[m] == c)) for c in classes]
        for b in np.unique(bins[m]):
            mb = m & (bins == b)
            if mb.sum() >= MIN_BIN:
                out["bins"][f"{int(s)}|{int(b)}"] = [float(np.mean(truth[mb] == c)) for c in classes]
    return out


def fit_calibration(series, truth, mask):
    s, t = series[mask], truth[mask]
    return {
        "engine_version": RE.ENGINE_VERSION,
        "n_bars": int(mask.sum()),
        "period": [str(s.index[0]), str(s.index[-1])],
        "vol": _table(s.vol_state.values, s.vol_ratio.values, t.vol_true.values, [0, 1, 2], VOL_EDGES),
        "trend": _table(s.trend_state.values, s.trend_z.values, t.trend_true.values, [-1, 0, 1], TREND_EDGES),
    }


# ------------------------------------------------------------------
# Evaluation
# ------------------------------------------------------------------
def _f1(pred, true, classes):
    f = []
    for c in classes:
        tp = np.sum((pred == c) & (true == c))
        f.append(2 * tp / max(2 * tp + np.sum((pred == c) & (true != c)) + np.sum((pred != c) & (true == c)), 1))
    return float(np.mean(f))


def changes_per_day(lab, tf_minutes):
    lab = np.asarray(lab)
    return float(np.sum(lab[1:] != lab[:-1]) / (len(lab) * tf_minutes / 1440))


def evaluate(series, truth, mask, tf_minutes, calib=None, label=""):
    s, t = series[mask], truth[mask]
    vs, ts = s.vol_state.values, s.trend_state.values
    vt, tt = t.vol_true.values, t.trend_true.values
    rid, rtrue = s.regime_id.values, regime_true(t)
    trending = ts != 0
    res = {
        "label": label, "bars": int(mask.sum()),
        "regime_acc": float(np.mean(rid == rtrue)),
        "vol_acc": float(np.mean(vs == vt)), "vol_f1": _f1(vs, vt, [0, 1, 2]),
        "trend_acc": float(np.mean(ts == tt)), "trend_f1": _f1(ts, tt, [-1, 0, 1]),
        "trend_dir_precision": float(np.mean(np.sign(t.Zc.values[trending]) == ts[trending])) if trending.any() else np.nan,
        "trend_coverage": float(np.mean(trending)),
        "changes_per_day": changes_per_day(rid, tf_minutes),
        "truth_changes_per_day": changes_per_day(rtrue, tf_minutes),
    }
    if calib is not None:
        conf = confidence_array(s, calib)
        bins = pd.cut(conf, [0, .3, .4, .5, .6, .7, .8, .9, 1.0])
        res["calibration"] = (pd.DataFrame({"conf": conf, "hit": rid == rtrue})
                              .groupby(bins, observed=True)
                              .agg(n=("hit", "size"), mean_conf=("conf", "mean"), hit_rate=("hit", "mean"))
                              .round(3))
        res["mean_confidence"] = float(conf.mean())
    return res


def confidence_array(s, calib):
    """Vectorised RE.detect_regime confidence for every row of a series."""
    def axis(table, states, scores, classes):
        b = np.searchsorted(table["edges"], scores, side="right")
        out = np.empty((len(states), len(classes)))
        for k, (st, bi) in enumerate(zip(states, b)):
            out[k] = table["bins"].get(f"{st}|{bi}", table["state"][str(st)])
        return out
    pv = axis(calib["vol"], s.vol_state.values, s.vol_ratio.values, [0, 1, 2])
    pt = axis(calib["trend"], s.trend_state.values, s.trend_z.values, [-1, 0, 1])
    probs = np.zeros((len(s), 8))
    for vi, vs in enumerate((0, 1, 2)):
        for ti, ts in enumerate((-1, 0, 1)):
            probs[:, RE.REGIME_OF[(vs, ts)]] += pv[:, vi] * pt[:, ti]
    probs /= probs.sum(1, keepdims=True)
    return probs[np.arange(len(s)), s.regime_id.values]


def print_eval(res):
    print(f"\n--- {res['label']}  ({res['bars']:,} bars)")
    for k in ("regime_acc", "vol_acc", "vol_f1", "trend_acc", "trend_f1", "trend_dir_precision",
              "trend_coverage", "changes_per_day", "truth_changes_per_day", "mean_confidence"):
        if k in res:
            print(f"  {k:24s} {res[k]:.3f}")
    if "calibration" in res:
        print("  confidence calibration (stated confidence vs actual hit rate):")
        print(res["calibration"].to_string().replace("\n", "\n    "))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--tf", type=int, default=5)
    ap.add_argument("--train-end", default="2024-12-31")
    ap.add_argument("--out", default=RE._CALIB_PATH)
    ap.add_argument("--no-write", action="store_true")
    a = ap.parse_args()

    bars = load_bars(a.data, a.tf)
    print(f"{len(bars):,} bars  {bars.index[0]} -> {bars.index[-1]}  (M{a.tf})")
    series = RE.compute_regime_series(bars, a.tf)
    truth = hindsight_truth(bars, series, a.tf)
    train = truth.valid.values & (bars.index <= pd.Timestamp(a.train_end) + pd.Timedelta(days=1))
    test = truth.valid.values & (bars.index > pd.Timestamp(a.train_end) + pd.Timedelta(days=1))

    calib = fit_calibration(series, truth, train)
    if not a.no_write:
        with open(a.out, "w") as f:
            json.dump(calib, f, indent=1)
        print(f"calibration written -> {a.out}")
    print_eval(evaluate(series, truth, train, a.tf, calib, "TRAIN (calibration period)"))
    if test.any():
        print_eval(evaluate(series, truth, test, a.tf, calib, "TEST (held out)"))


if __name__ == "__main__":
    main()
