# Regime Engine v2 — audit of the old detector and its replacement

October 2026. Data: Exness XAUUSDm M1, 2022-01-02 → 2026-10-09, resampled to M5 (337,920 bars).

## 1. What was wrong with the GMM detector

| # | Problem | Evidence |
|---|---------|----------|
| 1 | **Spread feature is broker-dependent.** The model was trained on a feed where gold spread ≈ 16 points; Exness quotes ≈ 200 points (3-digit pricing). | `spread_norm` sits ~28 robust-scaler units outside training range → **99.9 % of all bars** classified as "Extreme Vol Spike" (blocked). |
| 2 | **10 clusters, 8 labels.** `market_regime_gmm.pkl` has 10 components; the dashboard assumed 8 and clamped 8 and 9 to "Regime 8 – Bearish Trending". | 16 % of bars (spread neutralised) were clamped; component 8 is actually a mild *up*-move (up 70 % of the time). |
| 3 | **Names were hand-assigned and wrong.** Unsupervised clusters were never checked against what price did. | "Low Vol Bearish" is up over the prior 4h 86 % of the time (+163 bp/24h); "Extreme Vol Spike" is a sell-off; "Low Vol Bullish" follows a −110 bp day. "Bull" labels coincided with an up-move 51.9 % of the time, "bear" 51.5 % — no information. The directional filter therefore blocked buys in rallies. |
| 4 | **Flicker.** | 18.5 regime changes per day; 22 % of regimes lasted a single bar. |
| 5 | **Overconfident.** | Median confidence 99 % while being right ~36 % of the time. |
| 6 | Minor: forming bar used for live prediction; 800-bar window vs. 576-bar EMA warm-up. | ~97 % agreement with closed-bar / full-history labels — small next to 1–5. |

## 2. New detector

`src/python/regime_engine.py` — two scale-free axes on closed bars, each with hysteresis:

* **Volatility**: `d = ln(H/L) / median ln(H/L) at the same time of day over the previous 60 sessions`.
  `V` = mean d over 2h, `Vf` = over 1h. High: V ≥ 1.6 (exit < 1.3). Extreme: V ≥ 2.8 or Vf ≥ 3.5 (exit < 2.0).
* **Trend**: `Z = ln(C_t / C_t−6h) / sqrt(Σ r² over 6h)`. Up: Z ≥ +1.5 (exit < +0.6); down mirrored.
* `(vol state, trend state)` → regime ID 0–7 (same IDs and socket protocol as before).
* **Confidence** = calibrated probability from `models/regime_calibration.json`.

No price level, spread or tick volume is used, so it is broker- and instrument-agnostic.

## 3. How accuracy was measured

"Truth" is defined in hindsight, with fixed definitions chosen before tuning:

* volatility class from the **centred 4h** window: normal < 1.5 ≤ high < 2.5 ≤ extreme (× normal range for the time of day);
* trend class from the **centred 12h** window: Z ≥ +1 up, ≤ −1 down, else range.

The detector only sees the past. Its 8 thresholds were tuned on 2022–2024, and 2025–2026 was scored once.

## 4. Results

| Held-out 2025–26 | New v2 | Old GMM (live, Exness) | Old GMM (spread neutralised) | Always "Range" |
|---|---|---|---|---|
| Regime = hindsight regime | **63.0 %** | 3.8 % | 36.1 % | 53.7 % |
| Regime macro-F1 | **0.50** | 0.01 | 0.14 | 0.09 |
| Volatility state accuracy | **89.2 %** | 5.1 % | 78.2 % | 78.6 % |
| Trend direction right when a trend is called | **91.0 %** | 66 % | 45.6 % | – |
| Extreme-vol bars caught | **85 %** | 100 % (blocks 100 % of bars) | 15 % | 0 % |
| Bars wrongly put in a blocked regime | 3.5 % | 100 % | 6.1 % | 0 % |
| Regime changes / day | **5.2** | 0.06 | 16.0 | 0 |

Calibration (test): stated 45 % → 47 % right, 56 % → 57 %, 65 % → 65 %, 75 % → 74 %, 83 % → 79 %.

The same parameters and calibration were applied with no refit from 2023 on:

| Data | Regime acc. | Vol acc. | Trend dir. precision | Mean confidence | Always-Range |
|---|---|---|---|---|---|
| XAUUSDm M15 | 62.9 % | 88.9 % | 90.4 % | 64 % | 56.5 % |
| XAUUSDm H1 | 57.9 % | 85.5 % | 88.3 % | 63 % | 53.7 % |
| XAGUSDm M5 | 65.9 % | 90.0 % | 90.7 % | 65 % | 59.5 % |
| EURUSDm M5 | 66.5 % | 91.3 % | 89.9 % | 66 % | 63.1 % |
| US500m M5 | 63.4 % | 88.6 % | 88.6 % | 64 % | 53.2 % |

Live window (16,682 closed bars) vs. full history: 99.3 % identical regimes.

### What the regime tells you about the *future* (2025–26)

* Volatility: next-4h volatility is 1.06× normal after "normal", 1.66× after "high", 3.0× after "extreme". The vol axis is a genuine risk signal.
* Trend: the next 12h went up 55 % of the time after "up" and 51 % after "down". The trend state **describes** the current move accurately but does not forecast direction. The directional (counter-trend) filter is a style choice, not a proven edge.

## 5. Operating notes

* The dashboard now fetches `bars_needed(timeframe)` closed bars (≈16.7k on M5). It starts after 20 sessions; full accuracy needs 60.
* Confidence is honest now, typically 64 %, versus 99 % before. An EA "min confidence 50 %" setting will block about 23 % of bars, mostly near state boundaries. Lower it if that is not wanted.
* Recalibrate with your own data:
  `python src/python/calibrate_regime_engine.py --data <M1 or M5 parquet/csv> --tf 5 --train-end 2024-12-31`
* Tests: `python tests/test_regime_engine.py` (no-lookahead, scale/spread invariance, trend & spike detection).
