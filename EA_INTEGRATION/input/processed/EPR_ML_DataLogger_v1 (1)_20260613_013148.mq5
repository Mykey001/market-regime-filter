//+------------------------------------------------------------------+
//|              EPR_ML_DataLogger_v1.mq5                            |
//|  Collects ML training data from the HL-EPR Mean Reversion EA     |
//|                                                                    |
//|  Outputs (written to MT5 terminal common\Files folder):           |
//|    EPR_signals_raw.csv  — one row per resolved trade             |
//|    EPR_signals_norm.csv — z-score normalised copy on EA stop     |
//|                                                                    |
//|  Trade resolution strategy:                                        |
//|    • Strategy Tester / InpExecuteTrades=false:                    |
//|        Simulates trades bar-by-bar; SL wins if same-bar conflict  |
//|    • InpExecuteTrades=true (live/demo):                           |
//|        Opens real orders; OnTradeTransaction captures close price  |
//+------------------------------------------------------------------+
#property copyright "EPR ML DataLogger v1.0"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//=============================================================================
//  INPUTS — mirrors the main EA exactly, plus logger-specific group
//=============================================================================

input group "=== Pivot Points High / Low ==="
input int    InpLeftLenH         = 10;   // Pivot High - left bars
input int    InpRightLenH        = 10;   // Pivot High - right bars
input int    InpLeftLenL         = 10;   // Pivot Low  - left bars
input int    InpRightLenL        = 10;   // Pivot Low  - right bars

input group "=== EMA Settings ==="
input int    InpEmaFastLen       = 5;    // Fast EMA length
input int    InpEmaSlowLen       = 15;   // Slow EMA length

input group "=== PSAR Settings ==="
input double InpSarStart         = 0.02;
input double InpSarInc           = 0.02;
input double InpSarMax           = 0.20;

input group "=== RSI Settings ==="
input int    InpRsiLen           = 7;
input int    InpRsiOB            = 70;   // Overbought threshold
input int    InpRsiOS            = 30;   // Oversold threshold

input group "=== Macro Filter ==="
input ENUM_TIMEFRAMES InpMacroTf     = PERIOD_H1;
input int             InpMacroEmaLen = 200;
input bool            InpUseMacro    = true;

input group "=== Volatility / ADX Filter ==="
input int    InpBBLen            = 20;
input double InpBBMult           = 2.0;
input int    InpAdxThreshold     = 30;
input bool   InpUseAdx           = true;

input group "=== Trade Management ==="
input bool   InpUseSwingPointSL   = true;
input double InpSwingSlBufferPips = 5.0;
input double InpRiskRewardRatio   = 2.0;
input double InpStopLossPips      = 50.0;
input int    InpMagicNumber       = 202407; // different from main EA
input int    InpSlippage          = 10;
input double InpLotSize           = 0.1;    // used only when InpExecuteTrades=true

input group "=== Mean Reversion Lookback ==="
input int    InpExtLookback      = 5;

input group "=== ML Data Logger ==="
input bool   InpExecuteTrades    = false;           // Open real orders (else simulate)
input string InpRawCSV           = "EPR_signals_raw.csv";
input string InpNormCSV          = "EPR_signals_norm.csv";
input int    InpMaxBuffer        = 10000;            // Max completed trades to buffer
input int    InpMaxPending       = 300;              // Max simultaneous simulated trades
input int    InpServerUtcOffset  = 2;               // Server UTC offset hours (for sessions)

//=============================================================================
//  FEATURE INDEX CONSTANTS
//  These are the column indices in STradeRecord.f[].
//  Any change here MUST be reflected in CSV_HEADER below.
//=============================================================================

#define FEAT_N            26    // total feature count

// ── Momentum ──────────────────────────────────────
#define F_RSI             0     // RSI(7) value at signal bar
#define F_EMA_FAST        1     // Fast EMA absolute value
#define F_EMA_SLOW        2     // Slow EMA absolute value
#define F_EMA_SPREAD_PCT  3     // (ema_fast - ema_slow) / close * 100  [signed]
#define F_PSAR_DIST_PCT   4     // (close - psar) / close * 100  [+: price above psar]

// ── Volatility / band position ────────────────────
#define F_BB_PERCENTB     5     // (close - lower_band) / band_width,  clipped [0,1]
#define F_BB_WIDTH_PCT    6     // band_width / middle_band * 100  (volatility proxy)

// ── Trend strength ────────────────────────────────
#define F_ADX             7     // ADX(14)
#define F_PLUS_DI         8     // +DI
#define F_MINUS_DI        9     // -DI

// ── Pattern timing ────────────────────────────────
#define F_BARS_SINCE_EXT  10    // bars since last RSI/BB extreme (1 = last bar)

// ── Structure / swing levels ──────────────────────
#define F_PIVOT_H_DIST    11    // (pivot_high - close) / close * 100  [+ = PH above close]
#define F_PIVOT_L_DIST    12    // (close - pivot_low)  / close * 100  [+ = close above PL]

// ── Macro context ─────────────────────────────────
#define F_MACRO_DIST_PCT  13    // (close - H1_EMA200) / H1_EMA200 * 100  [signed]

// ── Normalised volatility ─────────────────────────
#define F_ATR_PCT         14    // ATR(14) / close * 100

// ── Time / session ────────────────────────────────
#define F_HOUR            15    // UTC hour 0-23 (derived from server time - offset)
#define F_DOW             16    // Day of week: 1=Mon .. 5=Fri
#define F_SES_LONDON      17    // 1 if London session active  (07:00–16:00 UTC)
#define F_SES_NY          18    // 1 if NY session active      (12:00–21:00 UTC)
#define F_SES_OVERLAP     19    // 1 if London–NY overlap      (12:00–16:00 UTC)

// ── Trade geometry ────────────────────────────────
#define F_SL_PIPS         20    // Stop loss distance in pips
#define F_TP_PIPS         21    // Take profit distance in pips
#define F_RR_ACTUAL       22    // TP_pips / SL_pips  (realised R:R at entry)
#define F_ENTRY_PRICE     23    // Entry price
#define F_SL_PRICE        24    // Stop loss price
#define F_TP_PRICE        25    // Take profit price

//=============================================================================
//  CSV HEADER  — must stay in sync with feature constants and WriteRawRow()
//=============================================================================

static const string CSV_HEADER =
   "signal_id,direction,signal_time,"
   "rsi,ema_fast,ema_slow,ema_spread_pct,psar_dist_pct,"
   "bb_percentb,bb_width_pct,"
   "adx,plus_di,minus_di,"
   "bars_since_extreme,"
   "pivot_high_dist_pct,pivot_low_dist_pct,"
   "macro_dist_pct,atr_pct,"
   "hour_utc,day_of_week,"
   "session_london,session_ny,session_overlap,"
   "sl_pips,tp_pips,rr_actual,"
   "entry_price,sl_price,tp_price,"
   "outcome,r_multiple,bars_held,close_price,close_time\n";

//=============================================================================
//  TRADE RECORD STRUCT
//  Allocated once per signal; outcome fields filled on trade close.
//=============================================================================

struct STradeRecord
{
   int      signal_id;
   int      direction;       //  1 = BUY,  -1 = SELL
   datetime signal_time;     // bar time that generated the signal
   double   f[FEAT_N];       // feature vector

   ulong    ticket;          // position ticket (0 = pure simulation)
   bool     closed;          // true once outcome is known

   // ── Outcome fields (filled on close) ───────────────────────────────────
   int      outcome;         //  1 = TP hit,  0 = SL hit,  -1 = still open
   double   r_multiple;      // signed realized R: +2.0 means "gained 2×risk"
   int      bars_held;       // number of bars from signal to close
   double   close_price;
   datetime close_time;
};

//=============================================================================
//  NORMALIZATION STATS STRUCT  (computed once over the full completed buffer)
//=============================================================================

struct SFeatStats
{
   double mean;
   double std_dev;
};

//=============================================================================
//  GLOBAL INDICATOR HANDLES
//=============================================================================

int g_hEmaFast  = INVALID_HANDLE;
int g_hEmaSlow  = INVALID_HANDLE;
int g_hSar      = INVALID_HANDLE;
int g_hRsi      = INVALID_HANDLE;
int g_hBB       = INVALID_HANDLE;
int g_hAdx      = INVALID_HANDLE;
int g_hMacroEma = INVALID_HANDLE;
int g_hAtr      = INVALID_HANDLE;

CTrade g_trade;

//=============================================================================
//  SWING STATE  (same as original EA)
//=============================================================================

double   g_lastPivotHigh     = 0.0;
double   g_lastPivotLow      = 0.0;
datetime g_lastPivotHighTime = 0;
datetime g_lastPivotLowTime  = 0;

//=============================================================================
//  LOGGER STATE
//=============================================================================

int          g_nextSignalId    = 0;
int          g_rawFileHandle   = INVALID_HANDLE;

STradeRecord g_pending[];        // trades awaiting resolution
int          g_pendingCount    = 0;

STradeRecord g_completed[];      // completed trades (for normalisation)
int          g_completedCount  = 0;

//=============================================================================
//  SECTION 1 — UTILITY HELPERS
//=============================================================================

//----  Safe indicator buffer copy -----------------------------------------
bool GetBuf(int handle, int bufIdx, int start, int count, double &arr[])
{
   ArraySetAsSeries(arr, true);
   return (CopyBuffer(handle, bufIdx, start, count, arr) == count);
}

//----  Pip size for this instrument ----------------------------------------
double PipSize() { return _Point * 10.0; }

//=============================================================================
//  SECTION 2 — PIVOT DETECTION  (identical to main EA)
//=============================================================================

bool IsPivotHigh(const double &h[], int idx, int left, int right)
{
   double c = h[idx];
   for(int i = 1; i <= left;  i++) if(h[idx + i] >= c) return false;
   for(int i = 1; i <= right; i++) if(h[idx - i] >= c) return false;
   return true;
}

bool IsPivotLow(const double &l[], int idx, int left, int right)
{
   double c = l[idx];
   for(int i = 1; i <= left;  i++) if(l[idx + i] <= c) return false;
   for(int i = 1; i <= right; i++) if(l[idx - i] <= c) return false;
   return true;
}

//=============================================================================
//  SECTION 3 — SL / TP CALCULATION  (identical to main EA)
//=============================================================================

double CalcBuySL(double entry)
{
   double pip = PipSize();
   if(InpUseSwingPointSL && g_lastPivotLow > 0.0)
   {
      double sl = NormalizeDouble(g_lastPivotLow - InpSwingSlBufferPips * pip, _Digits);
      if(sl < entry) return sl;
      Print("WARN: swing SL (", sl, ") >= entry (", entry, ") — using fixed pips");
   }
   return NormalizeDouble(entry - InpStopLossPips * pip, _Digits);
}

double CalcSellSL(double entry)
{
   double pip = PipSize();
   if(InpUseSwingPointSL && g_lastPivotHigh > 0.0)
   {
      double sl = NormalizeDouble(g_lastPivotHigh + InpSwingSlBufferPips * pip, _Digits);
      if(sl > entry) return sl;
      Print("WARN: swing SL (", sl, ") <= entry (", entry, ") — using fixed pips");
   }
   return NormalizeDouble(entry + InpStopLossPips * pip, _Digits);
}

double CalcTP(double entry, double sl)
{
   double dist = MathAbs(entry - sl) * InpRiskRewardRatio;
   return (entry > sl)
      ? NormalizeDouble(entry + dist, _Digits)
      : NormalizeDouble(entry - dist, _Digits);
}

//=============================================================================
//  SECTION 4 — SESSION DETECTION  (UTC-based)
//=============================================================================

void CalcSessionFlags(datetime serverTime,
                      int &outHourUTC,
                      int &outLondon,
                      int &outNY,
                      int &outOverlap)
{
   MqlDateTime mdt;
   TimeToStruct(serverTime, mdt);

   outHourUTC = ((mdt.hour - InpServerUtcOffset) % 24 + 24) % 24;
   outLondon  = (outHourUTC >=  7 && outHourUTC < 16) ? 1 : 0;
   outNY      = (outHourUTC >= 12 && outHourUTC < 21) ? 1 : 0;
   outOverlap = (outHourUTC >= 12 && outHourUTC < 16) ? 1 : 0;
}

//=============================================================================
//  SECTION 5 — POSITION MANAGEMENT  (identical to main EA)
//=============================================================================

bool HasOpenPosition(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString (POSITION_SYMBOL) != _Symbol)         continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)  continue;
      if(PositionGetInteger(POSITION_TYPE)   == posType) return true;
   }
   return false;
}

//=============================================================================
//  SECTION 6 — FEATURE EXTRACTION
//  Fills rec.f[] from indicator state at bar[1] (last closed bar).
//  Returns false if any indicator data is unavailable.
//=============================================================================

bool ExtractFeatures(const double &highArr[],
                     const double &lowArr[],
                     const double &closeArr[],
                     datetime      signalBarTime,
                     double        entryPrice,
                     double        slPrice,
                     double        tpPrice,
                     int           direction,
                     STradeRecord &rec)
{
   //──────────────────────────────────────────────────────────────────────────
   // Convenience: bar[1] prices
   //──────────────────────────────────────────────────────────────────────────
   const double cl = closeArr[1];
   const double hi = highArr[1];
   const double lo = lowArr[1];
   const double pip = PipSize();

   if(cl <= 0.0) { Print("ExtractFeatures: close price is zero"); return false; }

   //──────────────────────────────────────────────────────────────────────────
   // RSI
   //──────────────────────────────────────────────────────────────────────────
   double rsiArr[];
   if(!GetBuf(g_hRsi, 0, 0, InpExtLookback + 3, rsiArr)) return false;
   rec.f[F_RSI] = rsiArr[1];

   //──────────────────────────────────────────────────────────────────────────
   // EMA
   //──────────────────────────────────────────────────────────────────────────
   double emaFArr[], emaSArr[];
   if(!GetBuf(g_hEmaFast, 0, 0, 3, emaFArr)) return false;
   if(!GetBuf(g_hEmaSlow, 0, 0, 3, emaSArr)) return false;

   rec.f[F_EMA_FAST]       = emaFArr[1];
   rec.f[F_EMA_SLOW]       = emaSArr[1];
   rec.f[F_EMA_SPREAD_PCT] = (emaFArr[1] - emaSArr[1]) / cl * 100.0;

   //──────────────────────────────────────────────────────────────────────────
   // PSAR
   //──────────────────────────────────────────────────────────────────────────
   double sarArr[];
   if(!GetBuf(g_hSar, 0, 0, 3, sarArr)) return false;
   // Positive  → price is above PSAR (bullish)
   // Negative  → price is below PSAR (bearish)
   rec.f[F_PSAR_DIST_PCT] = (cl - sarArr[1]) / cl * 100.0;

   //──────────────────────────────────────────────────────────────────────────
   // Bollinger Bands  (buffer 0=mid, 1=upper, 2=lower)
   //──────────────────────────────────────────────────────────────────────────
   double bbMidArr[], bbUpArr[], bbLoArr[];
   if(!GetBuf(g_hBB, 0, 0, InpExtLookback + 3, bbMidArr)) return false;
   if(!GetBuf(g_hBB, 1, 0, InpExtLookback + 3, bbUpArr))  return false;
   if(!GetBuf(g_hBB, 2, 0, InpExtLookback + 3, bbLoArr))  return false;

   double bw = bbUpArr[1] - bbLoArr[1];
   // %B: 0 = at lower band, 1 = at upper band; clipped to avoid extreme outliers
   rec.f[F_BB_PERCENTB]  = (bw > 1e-10)
      ? MathMax(-0.5, MathMin(1.5, (cl - bbLoArr[1]) / bw))
      : 0.5;
   rec.f[F_BB_WIDTH_PCT] = (bbMidArr[1] > 0.0) ? (bw / bbMidArr[1] * 100.0) : 0.0;

   //──────────────────────────────────────────────────────────────────────────
   // ADX  (buffer 0=ADX, 1=+DI, 2=-DI)
   //──────────────────────────────────────────────────────────────────────────
   double adxArr[], plusDiArr[], minusDiArr[];
   if(!GetBuf(g_hAdx, 0, 0, 3, adxArr))     return false;
   if(!GetBuf(g_hAdx, 1, 0, 3, plusDiArr))  return false;
   if(!GetBuf(g_hAdx, 2, 0, 3, minusDiArr)) return false;

   rec.f[F_ADX]      = adxArr[1];
   rec.f[F_PLUS_DI]  = plusDiArr[1];
   rec.f[F_MINUS_DI] = minusDiArr[1];

   //──────────────────────────────────────────────────────────────────────────
   // Bars since extreme condition (1 = just happened, InpExtLookback+1 = not found)
   //──────────────────────────────────────────────────────────────────────────
   int barsSince = InpExtLookback + 1;
   for(int k = 1; k <= InpExtLookback; k++)
   {
      bool isExtreme = (direction == 1)
         ? ((lowArr[k] <= bbLoArr[k]) || (rsiArr[k] <= (double)InpRsiOS))
         : ((highArr[k] >= bbUpArr[k]) || (rsiArr[k] >= (double)InpRsiOB));
      if(isExtreme) { barsSince = k; break; }
   }
   rec.f[F_BARS_SINCE_EXT] = (double)barsSince;

   //──────────────────────────────────────────────────────────────────────────
   // Pivot distances
   //   F_PIVOT_H_DIST > 0  → pivot high is above close (price approaching from below)
   //   F_PIVOT_L_DIST > 0  → close is above pivot low (price has bounced off support)
   //──────────────────────────────────────────────────────────────────────────
   rec.f[F_PIVOT_H_DIST] = (g_lastPivotHigh > 0.0)
      ? ((g_lastPivotHigh - cl) / cl * 100.0) : 0.0;
   rec.f[F_PIVOT_L_DIST] = (g_lastPivotLow > 0.0)
      ? ((cl - g_lastPivotLow) / cl * 100.0) : 0.0;

   //──────────────────────────────────────────────────────────────────────────
   // Macro EMA (H1 EMA200)
   //──────────────────────────────────────────────────────────────────────────
   double macroArr[];
   ArraySetAsSeries(macroArr, true);
   if(CopyBuffer(g_hMacroEma, 0, 0, 3, macroArr) < 3) return false;
   rec.f[F_MACRO_DIST_PCT] = (macroArr[1] > 0.0)
      ? ((cl - macroArr[1]) / macroArr[1] * 100.0) : 0.0;

   //──────────────────────────────────────────────────────────────────────────
   // ATR(14) — normalised as percentage of close
   //──────────────────────────────────────────────────────────────────────────
   double atrArr[];
   if(!GetBuf(g_hAtr, 0, 0, 3, atrArr)) return false;
   rec.f[F_ATR_PCT] = atrArr[1] / cl * 100.0;

   //──────────────────────────────────────────────────────────────────────────
   // Time and session flags
   //──────────────────────────────────────────────────────────────────────────
   MqlDateTime mdt;
   TimeToStruct(signalBarTime, mdt);

   int utcH, london, ny, overlap;
   CalcSessionFlags(signalBarTime, utcH, london, ny, overlap);

   rec.f[F_HOUR]        = (double)utcH;
   rec.f[F_DOW]         = (double)MathMax(1, MathMin(5, mdt.day_of_week)); // clamp to Mon-Fri
   rec.f[F_SES_LONDON]  = (double)london;
   rec.f[F_SES_NY]      = (double)ny;
   rec.f[F_SES_OVERLAP] = (double)overlap;

   //──────────────────────────────────────────────────────────────────────────
   // Trade geometry
   //──────────────────────────────────────────────────────────────────────────
   double slPips = MathAbs(entryPrice - slPrice) / pip;
   double tpPips = MathAbs(tpPrice    - entryPrice) / pip;

   rec.f[F_SL_PIPS]     = slPips;
   rec.f[F_TP_PIPS]     = tpPips;
   rec.f[F_RR_ACTUAL]   = (slPips > 0.0) ? (tpPips / slPips) : 0.0;
   rec.f[F_ENTRY_PRICE] = entryPrice;
   rec.f[F_SL_PRICE]    = slPrice;
   rec.f[F_TP_PRICE]    = tpPrice;

   return true;
}

//=============================================================================
//  SECTION 7 — CSV WRITER
//  Writes one complete row (features + outcome) to the raw file.
//  Called only after outcome is known to avoid partial rows.
//=============================================================================

void WriteRawRow(const STradeRecord &r)
{
   if(g_rawFileHandle == INVALID_HANDLE) return;

   string row = IntegerToString(r.signal_id)  + ","
              + IntegerToString(r.direction)   + ","
              + TimeToString(r.signal_time, TIME_DATE | TIME_SECONDS) + ",";

   // Feature columns (F_RSI through F_TP_PRICE)
   for(int i = 0; i < FEAT_N; i++)
      row += DoubleToString(r.f[i], 6) + ",";

   // Outcome columns
   row += IntegerToString(r.outcome)   + ","
        + DoubleToString(r.r_multiple, 4) + ","
        + IntegerToString(r.bars_held) + ","
        + DoubleToString(r.close_price, _Digits) + ","
        + TimeToString(r.close_time, TIME_DATE | TIME_SECONDS) + "\n";

   FileWriteString(g_rawFileHandle, row);
   FileFlush(g_rawFileHandle);   // flush after every row so partial runs are usable
}

//=============================================================================
//  SECTION 8 — NORMALISED CSV WRITER
//  Called from OnDeinit with the full completed[] buffer.
//  Strategy:
//    Continuous features  → z-score: (x - mean) / std, clipped to ±4σ
//    Categorical/binary   → pass through unchanged
//    Outcome fields       → pass through unchanged
//=============================================================================

// Returns true for features that should NOT be z-scored
bool IsCategorical(int fi)
{
   return (fi == F_HOUR ||
           fi == F_DOW  ||
           fi == F_SES_LONDON  ||
           fi == F_SES_NY      ||
           fi == F_SES_OVERLAP);
}

void WriteNormalisedCSV()
{
   if(g_completedCount < 5)
   {
      Print("NormWriter: only ", g_completedCount,
            " completed trades — need ≥5 for normalisation. Skipping norm CSV.");
      return;
   }

   //──────────────────────────────────────────────────────────────────────────
   // 1. Compute per-feature mean and std over all completed trades
   //──────────────────────────────────────────────────────────────────────────
   SFeatStats stats[FEAT_N];
   for(int fi = 0; fi < FEAT_N; fi++)
   {
      if(IsCategorical(fi)) { stats[fi].mean = 0.0; stats[fi].std_dev = 1.0; continue; }

      double sum = 0.0;
      for(int i = 0; i < g_completedCount; i++)
         sum += g_completed[i].f[fi];
      double mean = sum / (double)g_completedCount;

      double ss = 0.0;
      for(int i = 0; i < g_completedCount; i++)
      {
         double d = g_completed[i].f[fi] - mean;
         ss += d * d;
      }
      double std = (ss > 0.0) ? MathSqrt(ss / (double)g_completedCount) : 1.0;
      if(std < 1e-10) std = 1.0;   // guard constant-value features

      stats[fi].mean    = mean;
      stats[fi].std_dev = std;
   }

   //──────────────────────────────────────────────────────────────────────────
   // 2. Open output file and write header
   //──────────────────────────────────────────────────────────────────────────
   int fh = FileOpen(InpNormCSV,
                     FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
   {
      Print("NormWriter: cannot open '", InpNormCSV, "' error=", GetLastError());
      return;
   }

   FileWriteString(fh, CSV_HEADER);

   //──────────────────────────────────────────────────────────────────────────
   // 3. Write one row per completed trade
   //──────────────────────────────────────────────────────────────────────────
   for(int i = 0; i < g_completedCount; i++)
   {
      STradeRecord r = g_completed[i];   // local copy — MQL5 forbids const-ref to array element

      string row = IntegerToString(r.signal_id) + ","
                 + IntegerToString(r.direction)  + ","
                 + TimeToString(r.signal_time, TIME_DATE | TIME_SECONDS) + ",";

      for(int fi = 0; fi < FEAT_N; fi++)
      {
         double val;
         if(IsCategorical(fi))
         {
            val = r.f[fi];
         }
         else
         {
            val = (r.f[fi] - stats[fi].mean) / stats[fi].std_dev;
            val = MathMax(-4.0, MathMin(4.0, val));   // clip outliers
         }
         row += DoubleToString(val, 6) + ",";
      }

      row += IntegerToString(r.outcome)      + ","
           + DoubleToString(r.r_multiple, 4) + ","
           + IntegerToString(r.bars_held)    + ","
           + DoubleToString(r.close_price, _Digits) + ","
           + TimeToString(r.close_time, TIME_DATE | TIME_SECONDS) + "\n";

      FileWriteString(fh, row);
   }

   FileClose(fh);

   Print("NormWriter: wrote ", g_completedCount,
         " rows to '", InpNormCSV, "'");

   // Log feature statistics for inspection
   string statLog = "Feature z-score parameters:\n";
   string featureNames[] = {
      "rsi","ema_fast","ema_slow","ema_spread_pct","psar_dist_pct",
      "bb_percentb","bb_width_pct","adx","plus_di","minus_di",
      "bars_since_extreme","pivot_high_dist_pct","pivot_low_dist_pct",
      "macro_dist_pct","atr_pct","hour_utc","dow",
      "session_london","session_ny","session_overlap",
      "sl_pips","tp_pips","rr_actual","entry_price","sl_price","tp_price"
   };
   for(int fi = 0; fi < FEAT_N; fi++)
   {
      if(!IsCategorical(fi))
         Print("  ", featureNames[fi],
               "  mean=", DoubleToString(stats[fi].mean, 4),
               "  std=",  DoubleToString(stats[fi].std_dev, 4));
   }
}

//=============================================================================
//  SECTION 9 — FINALISE RECORD
//  Shared logic called by both simulated and real close paths.
//=============================================================================

void FinaliseRecord(STradeRecord &r,
                    int           outcome,
                    double        closePrice,
                    datetime      closeTime)
{
   r.outcome     = outcome;
   r.close_price = closePrice;
   r.close_time  = closeTime;
   r.closed      = true;

   // R-multiple: how many multiples of SL distance did we gain/lose?
   double entry   = r.f[F_ENTRY_PRICE];
   double slDist  = MathAbs(entry - r.f[F_SL_PRICE]);
   double realized = (double)r.direction * (closePrice - entry);
   r.r_multiple   = (slDist > 0.0) ? (realized / slDist) : 0.0;

   // Bars held from signal to close
   r.bars_held = (int)MathMax(0,
      iBarShift(_Symbol, PERIOD_CURRENT, r.signal_time));

   WriteRawRow(r);

   // Buffer for normalisation
   if(g_completedCount < InpMaxBuffer)
   {
      ArrayResize(g_completed, g_completedCount + 1, InpMaxBuffer);
      g_completed[g_completedCount++] = r;
   }
   else
      Print("WARN: completed buffer full (", InpMaxBuffer, ") — dropping oldest data.");

   Print("■ Signal #", r.signal_id,
         " | ", (r.direction == 1 ? "BUY" : "SELL"),
         " | ", (outcome == 1 ? "TP ✓" : "SL ✗"),
         " | R=",      DoubleToString(r.r_multiple, 2),
         " | Bars=",   r.bars_held,
         " | Total completed: ", g_completedCount);
}

//=============================================================================
//  SECTION 10 — SIMULATED TRADE OUTCOME CHECK
//  Runs on every new bar using confirmed OHLC of bar[1].
//  BUY:  SL if low[1] ≤ slPrice, TP if high[1] ≥ tpPrice
//  SELL: SL if high[1] ≥ slPrice, TP if low[1] ≤ tpPrice
//  If both SL and TP breach on the same bar → SL wins (conservative).
//=============================================================================

void CheckSimulatedOutcomes(const double &highArr[], const double &lowArr[])
{
   const double barHigh = highArr[1];
   const double barLow  = lowArr[1];
   const datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);

   for(int i = 0; i < g_pendingCount; i++)
   {
      if(g_pending[i].closed) continue;
      if(g_pending[i].ticket != 0) continue;   // real-order path handles these

      const double sl  = g_pending[i].f[F_SL_PRICE];
      const double tp  = g_pending[i].f[F_TP_PRICE];
      const int    dir = g_pending[i].direction;

      bool slHit = (dir ==  1) ? (barLow  <= sl) : (barHigh >= sl);
      bool tpHit = (dir ==  1) ? (barHigh >= tp) : (barLow  <= tp);

      if(!slHit && !tpHit) continue;

      // SL wins on same-bar conflict (conservative assumption)
      int    outcome    = (slHit) ? 0 : 1;
      double closePrice = (slHit) ? sl : tp;

      FinaliseRecord(g_pending[i], outcome, closePrice, barTime);
   }

   // ── Compact pending array: remove closed records ─────────────────────────
   int keep = 0;
   for(int i = 0; i < g_pendingCount; i++)
      if(!g_pending[i].closed)
         g_pending[keep++] = g_pending[i];
   g_pendingCount = keep;
}

//=============================================================================
//  OnInit
//=============================================================================

int OnInit()
{
   //──────────────────────────────────────────────────────────────────────────
   // Create all indicator handles
   //──────────────────────────────────────────────────────────────────────────
   g_hEmaFast  = iMA (_Symbol, PERIOD_CURRENT, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   g_hEmaSlow  = iMA (_Symbol, PERIOD_CURRENT, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   g_hSar      = iSAR(_Symbol, PERIOD_CURRENT, InpSarStart, InpSarMax);
   g_hRsi      = iRSI(_Symbol, PERIOD_CURRENT, InpRsiLen, PRICE_CLOSE);
   g_hBB       = iBands(_Symbol, PERIOD_CURRENT, InpBBLen, 0, InpBBMult, PRICE_CLOSE);
   g_hAdx      = iADX(_Symbol, PERIOD_CURRENT, 14);
   g_hMacroEma = iMA (_Symbol, InpMacroTf, InpMacroEmaLen, 0, MODE_EMA, PRICE_CLOSE);
   g_hAtr      = iATR(_Symbol, PERIOD_CURRENT, 14);

   // Validate all handles
   int    handles[] = {g_hEmaFast, g_hEmaSlow, g_hSar, g_hRsi,
                       g_hBB, g_hAdx, g_hMacroEma, g_hAtr};
   string names[]   = {"EmaFast","EmaSlow","SAR","RSI",
                       "BB","ADX","MacroEMA","ATR(14)"};
   for(int i = 0; i < 8; i++)
      if(handles[i] == INVALID_HANDLE)
         { Print("ERROR: failed to create handle for ", names[i]); return INIT_FAILED; }

   //──────────────────────────────────────────────────────────────────────────
   // Trade object setup (only used when InpExecuteTrades=true)
   //──────────────────────────────────────────────────────────────────────────
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   //──────────────────────────────────────────────────────────────────────────
   // Allocate arrays
   //──────────────────────────────────────────────────────────────────────────
   ArrayResize(g_pending,   InpMaxPending);
   ArrayResize(g_completed, 0);
   g_pendingCount   = 0;
   g_completedCount = 0;

   //──────────────────────────────────────────────────────────────────────────
   // Open raw CSV (FILE_COMMON → terminal\common\Files folder)
   //──────────────────────────────────────────────────────────────────────────
   g_rawFileHandle = FileOpen(InpRawCSV,
                              FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON,
                              ',');
   if(g_rawFileHandle == INVALID_HANDLE)
   {
      Print("ERROR: cannot open raw CSV '", InpRawCSV,
            "' — error=", GetLastError());
      return INIT_FAILED;
   }

   FileWriteString(g_rawFileHandle, CSV_HEADER);
   FileFlush(g_rawFileHandle);

   Print("EPR_ML_DataLogger ready.");
   Print("  Mode: ", (InpExecuteTrades ? "REAL ORDERS" : "SIMULATION"));
   Print("  Raw CSV  : ", InpRawCSV);
   Print("  Norm CSV : ", InpNormCSV, "  (written on stop)");

   return INIT_SUCCEEDED;
}

//=============================================================================
//  OnDeinit
//=============================================================================

void OnDeinit(const int reason)
{
   if(g_rawFileHandle != INVALID_HANDLE)
   {
      FileFlush(g_rawFileHandle);
      FileClose(g_rawFileHandle);
      g_rawFileHandle = INVALID_HANDLE;
   }

   // Write normalised CSV using all buffered completed trades
   WriteNormalisedCSV();

   // Release indicator handles
   int handles[] = {g_hEmaFast, g_hEmaSlow, g_hSar, g_hRsi,
                    g_hBB, g_hAdx, g_hMacroEma, g_hAtr};
   for(int i = 0; i < 8; i++)
      if(handles[i] != INVALID_HANDLE)
         IndicatorRelease(handles[i]);

   Print("EPR_ML_DataLogger stopped. ",
         "Completed trades logged: ", g_completedCount, " | ",
         "Pending (unresolved): ",    g_pendingCount);
}

//=============================================================================
//  OnTick — main loop
//=============================================================================

void OnTick()
{
   //──────────────────────────────────────────────────────────────────────────
   // Gate on new bar (bar-close logic only, matching original EA)
   //──────────────────────────────────────────────────────────────────────────
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   //──────────────────────────────────────────────────────────────────────────
   // Determine bar count needed for all indicators
   //──────────────────────────────────────────────────────────────────────────
   int pivotDepth = MathMax(InpLeftLenH + InpRightLenH,
                            InpLeftLenL + InpRightLenL) + 10;
   int barsNeeded = MathMax(MathMax(pivotDepth,
                                    InpExtLookback + InpBBLen + 5),
                            InpMacroEmaLen + 5);

   //──────────────────────────────────────────────────────────────────────────
   // Load OHLC arrays (as-series: index 0=current forming bar, 1=last closed)
   //──────────────────────────────────────────────────────────────────────────
   double highArr[], lowArr[], closeArr[];
   ArraySetAsSeries(highArr,  true);
   ArraySetAsSeries(lowArr,   true);
   ArraySetAsSeries(closeArr, true);

   if(CopyHigh (_Symbol, PERIOD_CURRENT, 0, barsNeeded, highArr)  < barsNeeded ||
      CopyLow  (_Symbol, PERIOD_CURRENT, 0, barsNeeded, lowArr)   < barsNeeded ||
      CopyClose(_Symbol, PERIOD_CURRENT, 0, barsNeeded, closeArr) < barsNeeded)
   { Print("Not enough bars (need ", barsNeeded, "). Waiting..."); return; }

   //──────────────────────────────────────────────────────────────────────────
   // Step 1: Check simulated trade outcomes using bar[1] OHLC
   //──────────────────────────────────────────────────────────────────────────
   CheckSimulatedOutcomes(highArr, lowArr);

   //──────────────────────────────────────────────────────────────────────────
   // Step 2: Update swing points (same logic as main EA)
   //──────────────────────────────────────────────────────────────────────────
   if(IsPivotHigh(highArr, InpRightLenH, InpLeftLenH, InpRightLenH))
   {
      datetime t = iTime(_Symbol, PERIOD_CURRENT, InpRightLenH);
      if(t != g_lastPivotHighTime)
      {
         g_lastPivotHigh     = highArr[InpRightLenH];
         g_lastPivotHighTime = t;
      }
   }
   if(IsPivotLow(lowArr, InpRightLenL, InpLeftLenL, InpRightLenL))
   {
      datetime t = iTime(_Symbol, PERIOD_CURRENT, InpRightLenL);
      if(t != g_lastPivotLowTime)
      {
         g_lastPivotLow     = lowArr[InpRightLenL];
         g_lastPivotLowTime = t;
      }
   }

   //──────────────────────────────────────────────────────────────────────────
   // Step 3: Compute all signal conditions (identical to main EA)
   //──────────────────────────────────────────────────────────────────────────

   // ── EMA crossover ──────────────────────────────────────────────────────
   double emaFArr[], emaSArr[];
   if(!GetBuf(g_hEmaFast, 0, 0, 3, emaFArr)) return;
   if(!GetBuf(g_hEmaSlow, 0, 0, 3, emaSArr)) return;

   bool crossOver  = (emaFArr[2] <= emaSArr[2]) && (emaFArr[1] > emaSArr[1]);
   bool crossUnder = (emaFArr[2] >= emaSArr[2]) && (emaFArr[1] < emaSArr[1]);

   // ── PSAR ───────────────────────────────────────────────────────────────
   double sarArr[];
   if(!GetBuf(g_hSar, 0, 0, 3, sarArr)) return;
   bool psarBull = (sarArr[1] < closeArr[1]);
   bool psarBear = (sarArr[1] > closeArr[1]);

   // ── RSI + Bollinger extremes in lookback window ─────────────────────────
   double rsiArr[], bbUpArr[], bbLoArr[];
   if(!GetBuf(g_hRsi, 0, 0, InpExtLookback + 3, rsiArr)) return;
   if(!GetBuf(g_hBB,  1, 0, InpExtLookback + 3, bbUpArr)) return;
   if(!GetBuf(g_hBB,  2, 0, InpExtLookback + 3, bbLoArr)) return;

   bool wasExtOS = false, wasExtOB = false;
   for(int k = 1; k <= InpExtLookback; k++)
   {
      if((lowArr[k]  <= bbLoArr[k]) || (rsiArr[k] <= (double)InpRsiOS)) wasExtOS = true;
      if((highArr[k] >= bbUpArr[k]) || (rsiArr[k] >= (double)InpRsiOB)) wasExtOB = true;
   }

   // ── ADX filter ─────────────────────────────────────────────────────────
   double adxArr[];
   if(!GetBuf(g_hAdx, 0, 0, 3, adxArr)) return;
   bool adxOk = (!InpUseAdx) || (adxArr[1] < (double)InpAdxThreshold);

   // ── Macro filter ───────────────────────────────────────────────────────
   double macroEmaArr[], macroPriceArr[];
   ArraySetAsSeries(macroEmaArr,   true);
   ArraySetAsSeries(macroPriceArr, true);
   if(CopyBuffer(g_hMacroEma, 0, 0, 3, macroEmaArr)        < 3) return;
   if(CopyClose(_Symbol, InpMacroTf, 0, 3, macroPriceArr)  < 3) return;

   bool macroOkBull = (!InpUseMacro) || (macroPriceArr[0] > macroEmaArr[1]);
   bool macroOkBear = (!InpUseMacro) || (macroPriceArr[0] < macroEmaArr[1]);

   // ── Final signal ───────────────────────────────────────────────────────
   bool buySig  = crossOver  && psarBull && wasExtOS && adxOk && macroOkBull;
   bool sellSig = crossUnder && psarBear && wasExtOB && adxOk && macroOkBear;

   if(!buySig && !sellSig) return;

   //──────────────────────────────────────────────────────────────────────────
   // Step 4: Signal fired — build trade record and extract features
   //──────────────────────────────────────────────────────────────────────────
   if(g_pendingCount >= InpMaxPending)
   {
      Print("WARN: pending buffer full (", InpMaxPending, "). Signal skipped.");
      return;
   }

   const int    dir   = buySig ? 1 : -1;
   const double entry = buySig
      ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
      : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double sl    = buySig ? CalcBuySL(entry) : CalcSellSL(entry);
   const double tp    = CalcTP(entry, sl);

   // Basic sanity check before investing CPU in feature extraction
   if(dir ==  1 && sl >= entry) { Print("Invalid BUY SL — skipping."); return; }
   if(dir == -1 && sl <= entry) { Print("Invalid SELL SL — skipping."); return; }

   // ── Populate record ─────────────────────────────────────────────────────
   STradeRecord rec;
   ZeroMemory(rec);
   rec.signal_id   = ++g_nextSignalId;
   rec.direction   = dir;
   rec.signal_time = iTime(_Symbol, PERIOD_CURRENT, 1); // bar[1] = signal bar
   rec.ticket      = 0;
   rec.closed      = false;
   rec.outcome     = -1;

   if(!ExtractFeatures(highArr, lowArr, closeArr,
                       rec.signal_time, entry, sl, tp, dir, rec))
   {
      Print("Feature extraction failed for signal #", rec.signal_id, " — skipping.");
      return;
   }

   // ── Add to pending buffer ───────────────────────────────────────────────
   g_pending[g_pendingCount++] = rec;

   // ── Optionally open a real order ────────────────────────────────────────
   if(InpExecuteTrades)
   {
      string comment = "EPR_Log#" + IntegerToString(rec.signal_id);
      bool   opened  = false;

      if(dir ==  1 && !HasOpenPosition(POSITION_TYPE_BUY))
         opened = g_trade.Buy(InpLotSize, _Symbol, entry, sl, tp, comment);
      else if(dir == -1 && !HasOpenPosition(POSITION_TYPE_SELL))
         opened = g_trade.Sell(InpLotSize, _Symbol, entry, sl, tp, comment);

      if(opened)
         g_pending[g_pendingCount - 1].ticket = g_trade.ResultOrder();
      else if(dir == 1 || dir == -1)
         Print("Order open failed: ", g_trade.ResultRetcodeDescription());
   }

   Print("► Signal #", rec.signal_id,
         " | ", (dir == 1 ? "BUY" : "SELL"),
         " | RSI=",      DoubleToString(rec.f[F_RSI], 1),
         " | %B=",       DoubleToString(rec.f[F_BB_PERCENTB], 3),
         " | ADX=",      DoubleToString(rec.f[F_ADX], 1),
         " | PSAR%=",    DoubleToString(rec.f[F_PSAR_DIST_PCT], 3),
         " | SL pips=",  DoubleToString(rec.f[F_SL_PIPS], 1),
         " | Pending: ", g_pendingCount);
}

//=============================================================================
//  OnTradeTransaction — real-order close tracking
//  Only active when InpExecuteTrades=true.
//=============================================================================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest      &req,
                        const MqlTradeResult       &result)
{
   if(!InpExecuteTrades) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString (trans.deal, DEAL_SYMBOL) != _Symbol)          return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC)  != InpMagicNumber)   return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY)  != DEAL_ENTRY_OUT)   return;

   const ulong    posId      = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   const double   closePrice = HistoryDealGetDouble (trans.deal, DEAL_PRICE);
   const datetime closeTime  = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

   // ── Find the matching pending record by position ticket ─────────────────
   for(int i = 0; i < g_pendingCount; i++)
   {
      if(g_pending[i].ticket != posId) continue;
      if(g_pending[i].closed)          continue;

      const double tp = g_pending[i].f[F_TP_PRICE];
      const double sl = g_pending[i].f[F_SL_PRICE];

      // Classify outcome by proximity to SL vs TP
      int outcome = (MathAbs(closePrice - tp) < MathAbs(closePrice - sl)) ? 1 : 0;

      FinaliseRecord(g_pending[i], outcome, closePrice, closeTime);

      // Compact pending after this close
      int keep = 0;
      for(int j = 0; j < g_pendingCount; j++)
         if(!g_pending[j].closed)
            g_pending[keep++] = g_pending[j];
      g_pendingCount = keep;

      return;
   }
}

//+------------------------------------------------------------------+
//  END OF FILE
//+------------------------------------------------------------------+
