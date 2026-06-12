//+------------------------------------------------------------------+
//|          Combined HL-EPR Mean Reversion Sniper EA                |
//|  v2.2 — with Breakeven Stop Loss at 1:1 RR                      |
//|  Logic: Pivot High/Low + EMA crossover + PSAR + RSI + BB + ADX  |
//|  + Market Regime Detection + Trade Filters + Breakeven SL       |
//+------------------------------------------------------------------+
#property copyright "Converted from PineScript + Market Regime Features"
#property version   "2.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//=== INPUT GROUPS ================================================================

// --- Pivot Points ---
input group "=== Pivot Points High / Low ==="
input int    InpLeftLenH   = 10;    // Pivot High - Left Bars
input int    InpRightLenH  = 10;    // Pivot High - Right Bars
input int    InpLeftLenL   = 10;    // Pivot Low  - Left Bars
input int    InpRightLenL  = 10;    // Pivot Low  - Right Bars

// --- Swing Point Labels ---
input group "=== Swing Point Labels ==="
input bool   InpShowSwingLabels  = true;       // Show Swing Point Arrows & Labels
input color  InpPivotHighColor   = clrRed;     // Pivot High Arrow Color
input color  InpPivotLowColor    = clrLime;    // Pivot Low  Arrow Color
input int    InpLabelFontSize    = 8;          // Label Font Size
input int    InpArrowSize        = 2;          // Arrow Size (1-5)
input int    InpMaxSwingLabels   = 100;        // Max Labels to Keep on Chart

// --- EMA Settings ---
input group "=== EMA Settings ==="
input int    InpEmaFastLen = 5;     // Fast EMA Length
input int    InpEmaSlowLen = 15;    // Slow EMA Length

// --- PSAR Settings ---
input group "=== PSAR Settings ==="
input double InpSarStart   = 0.02;  // PSAR Start
input double InpSarInc     = 0.02;  // PSAR Increment
input double InpSarMax     = 0.20;  // PSAR Max Value

// --- RSI Settings ---
input group "=== RSI Settings (Mean Reversion) ==="
input int    InpRsiLen     = 7;     // RSI Length
input int    InpRsiOB      = 70;    // RSI Overbought
input int    InpRsiOS      = 30;    // RSI Oversold

// --- RSI Multi-Timeframe Filter ---
input group "=== RSI Multi-Timeframe Filter ==="
input bool            InpUseRsiFilter   = true;          // Enable RSI Multi-TF Filter
input ENUM_TIMEFRAMES InpRsiTf1         = PERIOD_H1;     // RSI Filter Timeframe 1
input ENUM_TIMEFRAMES InpRsiTf2         = PERIOD_H4;     // RSI Filter Timeframe 2
input int             InpRsiFilterLen   = 14;            // RSI Filter Length
input int             InpRsiFilterOB    = 70;            // RSI Filter Overbought Level
input int             InpRsiFilterOS    = 30;            // RSI Filter Oversold Level

// --- Macro Filter ---
input group "=== Macro Filter ==="
input ENUM_TIMEFRAMES InpMacroTf     = PERIOD_H1;  // Macro Timeframe
input int             InpMacroEmaLen = 200;          // Macro EMA Length
input bool            InpUseMacro    = true;          // Enable Macro Filter

// --- Volatility / ADX Filter ---
input group "=== Volatility Filter ==="
input int    InpBBLen        = 20;    // Bollinger Bands Length
input double InpBBMult       = 2.0;   // Bollinger Bands StdDev Multiplier
input int    InpAdxThreshold = 30;    // ADX Max Threshold (mean reversion needs low ADX)
input bool   InpUseAdx       = true;  // Enable ADX Filter

// --- Trade Management ---
input group "=== Trade Management ==="
input double InpLotSize          = 0.1;    // Lot Size
input bool   InpUseSwingPointSL  = true;   // Use Swing Point Stop Loss (else fixed pips)
input double InpSwingSlBufferPips = 5.0;   // Swing SL Buffer – extra pips beyond swing (safety margin)
input double InpRiskRewardRatio  = 2.0;    // Risk:Reward Ratio for Take Profit (e.g. 2 = 1:2)
input double InpStopLossPips     = 50.0;   // Fixed Stop Loss (pips) – used when swing SL is OFF
input bool   InpMoveToBreakeven  = true;   // Move SL to Breakeven at 1:1 RR
input double InpBreakevenBuffer  = 2.0;    // Breakeven Buffer (pips) – profit lock beyond entry
input int    InpMagicNumber      = 202406; // Magic Number
input int    InpSlippage         = 10;     // Max Slippage (points)

// --- Lookback for "was extreme" ---
input group "=== Mean Reversion Lookback ==="
input int    InpExtLookback  = 5;     // Bars since extreme condition (Pine: barssince <= 5)

// --- Market Regime Features ---
input group "=== Market Regime Detection ==="
input bool   InpLogRegime    = true;   // Log 14 Features on Trade Close
input int    InpFeatureBars  = 300;    // History Bars for Feature Calculation (min 300)

// --- Trade Quality Filter ---
enum ENUM_FILTER_MODE
{
   FILTER_OFF         = 0,  // No Filter (All Trades)
   FILTER_CONSERVATIVE = 1,  // Conservative (Price must be >50% of daily range)
   FILTER_BALANCED     = 2,  // Balanced (43% retention, +42.9% winrate) - RECOMMENDED
   FILTER_AGGRESSIVE   = 3   // Aggressive (32% retention, +48.0% winrate)
};

input group "=== Trade Quality Filter (Regime-Based) ==="
input ENUM_FILTER_MODE InpFilterMode = FILTER_BALANCED;  // Filter Mode

//=== GLOBAL HANDLES ==============================================================

int g_hEmaFast   = INVALID_HANDLE;
int g_hEmaSlow   = INVALID_HANDLE;
int g_hSar       = INVALID_HANDLE;
int g_hRsi       = INVALID_HANDLE;
int g_hBB        = INVALID_HANDLE;
int g_hAdx       = INVALID_HANDLE;
int g_hMacroEma  = INVALID_HANDLE;
int g_hRsiTf1    = INVALID_HANDLE;   // RSI filter timeframe 1
int g_hRsiTf2    = INVALID_HANDLE;   // RSI filter timeframe 2

CTrade g_trade;

//=== SWING POINT STATE ===========================================================

double   g_lastPivotHigh      = 0.0;   // Most recent confirmed pivot high price
double   g_lastPivotLow       = 0.0;   // Most recent confirmed pivot low price
datetime g_lastPivotHighTime  = 0;     // Bar time of last pivot high
datetime g_lastPivotLowTime   = 0;     // Bar time of last pivot low

// Track how many labels we've drawn so we can clean up old ones
int      g_labelCount         = 0;

//=== MARKET REGIME FEATURE NAMES =================================================

// 14 features from feature_engine.py (M5 timeframe calibrated)
string g_featureNames[14] = {
   "volatility_1h",      // 1-hour rolling volatility of log returns
   "volatility_1d",      // 1-day rolling volatility of log returns
   "natr_14",            // Normalized Average True Range (14-period)
   "bollinger_width",    // Bollinger Band width (20-period)
   "trend_short",        // Short-term trend: (EMA12 - EMA48) / EMA48
   "trend_long",         // Long-term trend: (EMA48 - EMA576) / EMA576
   "macd_hist",          // MACD histogram (12, 26, 9)
   "price_position",     // Price position in daily high-low range [0, 1]
   "rsi_14",             // Wilder's RSI (14-period, proper EMA)
   "rsi_rate",           // Rate of RSI change over 1 hour
   "returns_skew",       // Rolling skewness of returns (1-day)
   "volume_ratio",       // Tick volume surge ratio (1h / 1d)
   "spread_norm",        // Normalized bid-ask spread
   "variance_ratio"      // Variance ratio (trending vs mean-reverting)
};

// M5 Timeframe Constants (5-minute bars)
#define BARS_1H   12     // 12 × 5min = 1 hour
#define BARS_4H   48     // 48 × 5min = 4 hours
#define BARS_1D   288    // 288 × 5min = 24 hours
#define BARS_2D   576    // 576 × 5min = 2 days

//=== INIT ========================================================================

int OnInit()
{
   // Fast EMA
   g_hEmaFast = iMA(_Symbol, PERIOD_CURRENT, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEmaFast == INVALID_HANDLE) { Print("ERROR: Fast EMA handle"); return INIT_FAILED; }

   // Slow EMA
   g_hEmaSlow = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEmaSlow == INVALID_HANDLE) { Print("ERROR: Slow EMA handle"); return INIT_FAILED; }

   // Parabolic SAR
   g_hSar = iSAR(_Symbol, PERIOD_CURRENT, InpSarStart, InpSarMax);
   if(g_hSar == INVALID_HANDLE) { Print("ERROR: SAR handle"); return INIT_FAILED; }

   // RSI
   g_hRsi = iRSI(_Symbol, PERIOD_CURRENT, InpRsiLen, PRICE_CLOSE);
   if(g_hRsi == INVALID_HANDLE) { Print("ERROR: RSI handle"); return INIT_FAILED; }

   // Bollinger Bands
   g_hBB = iBands(_Symbol, PERIOD_CURRENT, InpBBLen, 0, InpBBMult, PRICE_CLOSE);
   if(g_hBB == INVALID_HANDLE) { Print("ERROR: BB handle"); return INIT_FAILED; }

   // ADX — buffer 0=ADX, 1=+DI, 2=-DI
   g_hAdx = iADX(_Symbol, PERIOD_CURRENT, 14);
   if(g_hAdx == INVALID_HANDLE) { Print("ERROR: ADX handle"); return INIT_FAILED; }

   // Macro EMA
   g_hMacroEma = iMA(_Symbol, InpMacroTf, InpMacroEmaLen, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hMacroEma == INVALID_HANDLE) { Print("ERROR: Macro EMA handle"); return INIT_FAILED; }

   // RSI Multi-Timeframe Filters
   if(InpUseRsiFilter)
   {
      g_hRsiTf1 = iRSI(_Symbol, InpRsiTf1, InpRsiFilterLen, PRICE_CLOSE);
      if(g_hRsiTf1 == INVALID_HANDLE) { Print("ERROR: RSI TF1 handle"); return INIT_FAILED; }

      g_hRsiTf2 = iRSI(_Symbol, InpRsiTf2, InpRsiFilterLen, PRICE_CLOSE);
      if(g_hRsiTf2 == INVALID_HANDLE) { Print("ERROR: RSI TF2 handle"); return INIT_FAILED; }

      Print("RSI Multi-TF Filter initialized: TF1=", EnumToString(InpRsiTf1),
            " TF2=", EnumToString(InpRsiTf2),
            " OB=", InpRsiFilterOB, " OS=", InpRsiFilterOS);
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Remove any leftover labels from a previous run
   RemoveAllSwingLabels();

   // Display filter mode information
   string filterInfo = "";
   switch(InpFilterMode)
   {
      case FILTER_OFF:
         filterInfo = "OFF (No filtering)";
         break;
      case FILTER_CONSERVATIVE:
         filterInfo = "CONSERVATIVE (Price >50% of daily range - upper half only)";
         break;
      case FILTER_BALANCED:
         filterInfo = "BALANCED (43% retention, ~43% winrate) ⭐ RECOMMENDED";
         break;
      case FILTER_AGGRESSIVE:
         filterInfo = "AGGRESSIVE (32% retention, ~48% winrate)";
         break;
      default:
         filterInfo = "UNKNOWN";
   }

   Print("========================================");
   Print("Combined HL-EPR EA v2.2 initialized");
   Print("SwingSL=", InpUseSwingPointSL, " | RR=1:", InpRiskRewardRatio);
   Print("Breakeven: ", InpMoveToBreakeven ? "ON (+" + DoubleToString(InpBreakevenBuffer, 1) + " pips)" : "OFF");
   Print("Trade Quality Filter: ", filterInfo);
   Print("========================================");
   return INIT_SUCCEEDED;
}

//=== DEINIT ======================================================================

void OnDeinit(const int reason)
{
   IndicatorRelease(g_hEmaFast);
   IndicatorRelease(g_hEmaSlow);
   IndicatorRelease(g_hSar);
   IndicatorRelease(g_hRsi);
   IndicatorRelease(g_hBB);
   IndicatorRelease(g_hAdx);
   IndicatorRelease(g_hMacroEma);
   IndicatorRelease(g_hRsiTf1);
   IndicatorRelease(g_hRsiTf2);

   // Clean up chart objects on removal (keep on chart-reattach for reference)
   if(reason == REASON_REMOVE)
      RemoveAllSwingLabels();
}

//=== UTILITY: safe buffer copy ===================================================

bool GetBuffer(int handle, int bufferIdx, int startPos, int count, double &arr[])
{
   ArraySetAsSeries(arr, true);
   int copied = CopyBuffer(handle, bufferIdx, startPos, count, arr);
   return (copied == count);
}

//=== SWING LABEL HELPERS =========================================================

// Prefix for all objects created by this EA so we can selectively clean them up
string ObjPrefix() { return "SWNG_" + IntegerToString(InpMagicNumber) + "_"; }

void RemoveAllSwingLabels()
{
   string prefix = ObjPrefix();
   int total = ObjectsTotal(0, -1, -1);
   // Iterate backwards so deletion doesn't shift indices
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
   g_labelCount = 0;
}

//--- Draw a pivot HIGH label: down-arrow above the bar + price text
void DrawPivotHighLabel(datetime barTime, double price)
{
   if(!InpShowSwingLabels) return;

   // Build unique object names (arrow + text)
   string arrowName = ObjPrefix() + "PH_ARR_" + IntegerToString((int)barTime);
   string textName  = ObjPrefix() + "PH_TXT_" + IntegerToString((int)barTime);

   // Arrow: down-pointing arrow placed slightly above the high
   double arrowPrice = price + 15 * _Point;   // small offset above bar tip

   if(!ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, arrowPrice))
   {
      // Object may already exist (re-attach scenario) — just move it
      ObjectMove(0, arrowName, 0, barTime, arrowPrice);
   }
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 234);  // WINGDINGS down arrow
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR,     InpPivotHighColor);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH,     InpArrowSize);
   ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR,    ANCHOR_BOTTOM);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN,    true);

   // Price text label
   string priceStr = "PH " + DoubleToString(price, _Digits);
   if(!ObjectCreate(0, textName, OBJ_TEXT, 0, barTime, arrowPrice + 8 * _Point))
      ObjectMove(0, textName, 0, barTime, arrowPrice + 8 * _Point);
   ObjectSetString (0, textName, OBJPROP_TEXT,      priceStr);
   ObjectSetInteger(0, textName, OBJPROP_COLOR,     InpPivotHighColor);
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE,  InpLabelFontSize);
   ObjectSetInteger(0, textName, OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, textName, OBJPROP_HIDDEN,    true);

   g_labelCount += 2;
   ChartRedraw(0);

   // Housekeeping: prune oldest labels if we exceed the cap
   if(g_labelCount > InpMaxSwingLabels * 2)
      PruneOldestSwingLabel();
}

//--- Draw a pivot LOW label: up-pointing arrow below the bar + price text
void DrawPivotLowLabel(datetime barTime, double price)
{
   if(!InpShowSwingLabels) return;

   string arrowName = ObjPrefix() + "PL_ARR_" + IntegerToString((int)barTime);
   string textName  = ObjPrefix() + "PL_TXT_" + IntegerToString((int)barTime);

   double arrowPrice = price - 15 * _Point;  // small offset below bar

   if(!ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, arrowPrice))
      ObjectMove(0, arrowName, 0, barTime, arrowPrice);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 233);  // WINGDINGS up arrow
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR,     InpPivotLowColor);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH,     InpArrowSize);
   ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR,    ANCHOR_TOP);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN,    true);

   string priceStr = "PL " + DoubleToString(price, _Digits);
   if(!ObjectCreate(0, textName, OBJ_TEXT, 0, barTime, arrowPrice - 8 * _Point))
      ObjectMove(0, textName, 0, barTime, arrowPrice - 8 * _Point);
   ObjectSetString (0, textName, OBJPROP_TEXT,      priceStr);
   ObjectSetInteger(0, textName, OBJPROP_COLOR,     InpPivotLowColor);
   ObjectSetInteger(0, textName, OBJPROP_FONTSIZE,  InpLabelFontSize);
   ObjectSetInteger(0, textName, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, textName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, textName, OBJPROP_HIDDEN,    true);

   g_labelCount += 2;
   ChartRedraw(0);

   if(g_labelCount > InpMaxSwingLabels * 2)
      PruneOldestSwingLabel();
}

//--- Remove the single oldest swing label pair to keep chart tidy
void PruneOldestSwingLabel()
{
   string prefix = ObjPrefix();
   datetime oldest = D'3000.01.01';
   string  oldestName = "";

   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) != 0) continue;

      datetime t = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME);
      if(t < oldest)
      {
         oldest     = t;
         oldestName = name;
      }
   }
   if(oldestName != "")
   {
      ObjectDelete(0, oldestName);
      g_labelCount--;
   }
}

//=== PIVOT HIGH/LOW DETECTION ====================================================

bool IsPivotHigh(const double &highs[], int offset, int leftLen, int rightLen)
{
   double candidate = highs[offset];
   for(int i = 1; i <= leftLen; i++)
      if(highs[offset + i] >= candidate) return false;
   for(int i = 1; i <= rightLen; i++)
      if(highs[offset - i] >= candidate) return false;
   return true;
}

bool IsPivotLow(const double &lows[], int offset, int leftLen, int rightLen)
{
   double candidate = lows[offset];
   for(int i = 1; i <= leftLen; i++)
      if(lows[offset + i] <= candidate) return false;
   for(int i = 1; i <= rightLen; i++)
      if(lows[offset - i] <= candidate) return false;
   return true;
}

//=== POSITION MANAGEMENT =========================================================

bool HasOpenPosition(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC)  == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE)   == posType)
            return true;
   }
   return false;
}

//=== STOP LOSS & TAKE PROFIT CALCULATION =========================================

// Returns the swing-point SL for a BUY order.
// SL = last pivot low  minus buffer pips.
// If no pivot low recorded yet, falls back to fixed pips.
double CalcBuySL(double entryPrice)
{
   double pipSize = _Point * 10;

   if(InpUseSwingPointSL && g_lastPivotLow > 0.0)
   {
      double sl = g_lastPivotLow - InpSwingSlBufferPips * pipSize;
      sl = NormalizeDouble(sl, _Digits);

      // Safety: ensure SL is actually below entry
      if(sl < entryPrice)
         return sl;

      // Pivot low is above entry (stale data) — fall through to fixed
      Print("WARNING: Swing Low SL (", sl, ") >= entry (", entryPrice,
            "). Falling back to fixed pip SL.");
   }

   // Fixed pip fallback
   return NormalizeDouble(entryPrice - InpStopLossPips * pipSize, _Digits);
}

// Returns the swing-point SL for a SELL order.
// SL = last pivot high plus buffer pips.
double CalcSellSL(double entryPrice)
{
   double pipSize = _Point * 10;

   if(InpUseSwingPointSL && g_lastPivotHigh > 0.0)
   {
      double sl = g_lastPivotHigh + InpSwingSlBufferPips * pipSize;
      sl = NormalizeDouble(sl, _Digits);

      if(sl > entryPrice)
         return sl;

      Print("WARNING: Swing High SL (", sl, ") <= entry (", entryPrice,
            "). Falling back to fixed pip SL.");
   }

   return NormalizeDouble(entryPrice + InpStopLossPips * pipSize, _Digits);
}

// Calculate TP from entry and SL using the selected Risk:Reward ratio.
double CalcTP(double entryPrice, double slPrice)
{
   double slDistance = MathAbs(entryPrice - slPrice);
   double tpDistance = slDistance * InpRiskRewardRatio;

   if(entryPrice > slPrice)                        // BUY
      return NormalizeDouble(entryPrice + tpDistance, _Digits);
   else                                             // SELL
      return NormalizeDouble(entryPrice - tpDistance, _Digits);
}

//=== MARKET REGIME FEATURE CALCULATIONS ==========================================

//--- Helper: Wilder's EMA (alpha = 1/period, used for RSI and ATR)
void WilderEMA(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, 0.0);
   
   double alpha = 1.0 / period;
   
   // Find first valid value
   int validStart = 0;
   while(validStart < size && src[validStart] == 0.0)
      validStart++;
   
   if(validStart + period > size)
      return;
   
   // Seed with SMA
   double sum = 0.0;
   for(int i = validStart; i < validStart + period; i++)
      sum += src[i];
   
   dst[validStart + period - 1] = sum / period;
   
   // Apply Wilder's smoothing
   for(int i = validStart + period; i < size; i++)
      dst[i] = alpha * src[i] + (1.0 - alpha) * dst[i - 1];
}

//--- Helper: Standard EMA (alpha = 2/(period+1))
void StandardEMA(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, 0.0);
   
   double alpha = 2.0 / (period + 1);
   
   // Seed with SMA
   double sum = 0.0;
   for(int i = 0; i < period && i < size; i++)
      sum += src[i];
   
   if(period <= size)
   {
      dst[period - 1] = sum / period;
      
      // Apply EMA
      for(int i = period; i < size; i++)
         dst[i] = alpha * src[i] + (1.0 - alpha) * dst[i - 1];
   }
}

//--- Helper: Simple Moving Average
void SimpleSMA(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, 0.0);
   
   for(int i = period - 1; i < size; i++)
   {
      double sum = 0.0;
      for(int j = 0; j < period; j++)
         sum += src[i - j];
      dst[i] = sum / period;
   }
}

//--- Helper: Rolling Standard Deviation
void RollingStd(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, 0.0);
   
   for(int i = period - 1; i < size; i++)
   {
      double mean = 0.0;
      for(int j = 0; j < period; j++)
         mean += src[i - j];
      mean /= period;
      
      double variance = 0.0;
      for(int j = 0; j < period; j++)
      {
         double diff = src[i - j] - mean;
         variance += diff * diff;
      }
      variance /= period;
      dst[i] = MathSqrt(variance);
   }
}

//--- Helper: Rolling Min
void RollingMin(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, DBL_MAX);
   
   for(int i = period - 1; i < size; i++)
   {
      double minVal = DBL_MAX;
      for(int j = 0; j < period; j++)
         minVal = MathMin(minVal, src[i - j]);
      dst[i] = minVal;
   }
}

//--- Helper: Rolling Max
void RollingMax(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, -DBL_MAX);
   
   for(int i = period - 1; i < size; i++)
   {
      double maxVal = -DBL_MAX;
      for(int j = 0; j < period; j++)
         maxVal = MathMax(maxVal, src[i - j]);
      dst[i] = maxVal;
   }
}

//--- Helper: Rolling Skewness
void RollingSkew(const double &src[], double &dst[], int period)
{
   int size = ArraySize(src);
   ArrayResize(dst, size);
   ArrayInitialize(dst, 0.0);
   
   for(int i = period - 1; i < size; i++)
   {
      // Calculate mean
      double mean = 0.0;
      for(int j = 0; j < period; j++)
         mean += src[i - j];
      mean /= period;
      
      // Calculate variance and skewness
      double m2 = 0.0, m3 = 0.0;
      for(int j = 0; j < period; j++)
      {
         double diff = src[i - j] - mean;
         m2 += diff * diff;
         m3 += diff * diff * diff;
      }
      m2 /= period;
      m3 /= period;
      
      double std = MathSqrt(m2);
      if(std > 1e-10)
         dst[i] = m3 / (std * std * std);
      else
         dst[i] = 0.0;
   }
}

//--- Feature: Wilder's RSI (correct implementation matching TradingView/MT5)
void ComputeWilderRSI(const double &close[], double &rsi[], int period)
{
   int size = ArraySize(close);
   ArrayResize(rsi, size);
   ArrayInitialize(rsi, 0.0);
   
   // Calculate price changes
   double gains[], losses[];
   ArrayResize(gains, size);
   ArrayResize(losses, size);
   ArrayInitialize(gains, 0.0);
   ArrayInitialize(losses, 0.0);
   
   for(int i = 1; i < size; i++)
   {
      double delta = close[i] - close[i - 1];
      if(delta > 0)
         gains[i] = delta;
      else
         losses[i] = -delta;
   }
   
   // Apply Wilder's smoothing
   double avgGain[], avgLoss[];
   WilderEMA(gains, avgGain, period);
   WilderEMA(losses, avgLoss, period);
   
   // Calculate RSI
   for(int i = period; i < size; i++)
   {
      if(avgLoss[i] > 1e-10)
      {
         double rs = avgGain[i] / avgLoss[i];
         rsi[i] = 100.0 - (100.0 / (1.0 + rs));
      }
      else
         rsi[i] = 100.0;
   }
}

//--- Feature: Average True Range (Wilder's smoothing)
void ComputeATR(const double &high[], const double &low[], const double &close[], 
                double &atr[], int period)
{
   int size = ArraySize(high);
   ArrayResize(atr, size);
   ArrayInitialize(atr, 0.0);
   
   double trueRange[];
   ArrayResize(trueRange, size);
   ArrayInitialize(trueRange, 0.0);
   
   // Calculate True Range
   trueRange[0] = high[0] - low[0];
   for(int i = 1; i < size; i++)
   {
      double tr1 = high[i] - low[i];
      double tr2 = MathAbs(high[i] - close[i - 1]);
      double tr3 = MathAbs(low[i] - close[i - 1]);
      trueRange[i] = MathMax(tr1, MathMax(tr2, tr3));
   }
   
   // Apply Wilder's EMA
   WilderEMA(trueRange, atr, period);
}

//--- Feature: Bollinger Band Width
void ComputeBollingerWidth(const double &close[], double &width[], int period, double numStd)
{
   int size = ArraySize(close);
   ArrayResize(width, size);
   ArrayInitialize(width, 0.0);
   
   double middle[], stdDev[];
   SimpleSMA(close, middle, period);
   RollingStd(close, stdDev, period);
   
   for(int i = period - 1; i < size; i++)
   {
      if(middle[i] > 0.0)
      {
         double upper = middle[i] + numStd * stdDev[i];
         double lower = middle[i] - numStd * stdDev[i];
         width[i] = (upper - lower) / middle[i];
      }
   }
}

//--- Feature: MACD Histogram (normalized)
void ComputeMACDHistogram(const double &close[], double &macdHist[], 
                          int fastPeriod, int slowPeriod, int signalPeriod)
{
   int size = ArraySize(close);
   ArrayResize(macdHist, size);
   ArrayInitialize(macdHist, 0.0);
   
   double emaFast[], emaSlow[];
   StandardEMA(close, emaFast, fastPeriod);
   StandardEMA(close, emaSlow, slowPeriod);
   
   // MACD Line
   double macdLine[];
   ArrayResize(macdLine, size);
   for(int i = 0; i < size; i++)
      macdLine[i] = emaFast[i] - emaSlow[i];
   
   // Signal Line (EMA of MACD)
   double signalLine[];
   StandardEMA(macdLine, signalLine, signalPeriod);
   
   // Histogram (normalized by price)
   for(int i = slowPeriod + signalPeriod; i < size; i++)
   {
      if(close[i] > 0.0)
         macdHist[i] = (macdLine[i] - signalLine[i]) / close[i];
   }
}

//--- Feature: Price Position in Range [0, 1]
void ComputePricePosition(const double &close[], const double &high[], 
                          const double &low[], double &position[], int period)
{
   int size = ArraySize(close);
   ArrayResize(position, size);
   ArrayInitialize(position, 0.5);
   
   double rollingHigh[], rollingLow[];
   RollingMax(high, rollingHigh, period);
   RollingMin(low, rollingLow, period);
   
   for(int i = period - 1; i < size; i++)
   {
      double range = rollingHigh[i] - rollingLow[i];
      if(range > 1e-10)
         position[i] = (close[i] - rollingLow[i]) / range;
      else
         position[i] = 0.5;
   }
}

//--- Feature: Variance Ratio (trending vs mean-reverting)
void ComputeVarianceRatio(const double &logReturns[], double &vr[], 
                          int shortPeriod, int longPeriod)
{
   int size = ArraySize(logReturns);
   ArrayResize(vr, size);
   ArrayInitialize(vr, 1.0);
   
   // q-period returns (sum of log returns)
   double qReturns[];
   ArrayResize(qReturns, size);
   ArrayInitialize(qReturns, 0.0);
   
   for(int i = shortPeriod - 1; i < size; i++)
   {
      double sum = 0.0;
      for(int j = 0; j < shortPeriod; j++)
         sum += logReturns[i - j];
      qReturns[i] = sum;
   }
   
   // Rolling variance of 1-period and q-period returns
   double var1[], varQ[];
   RollingStd(logReturns, var1, longPeriod);
   RollingStd(qReturns, varQ, longPeriod / shortPeriod);
   
   // Variance ratio
   for(int i = longPeriod; i < size; i++)
   {
      double v1 = var1[i] * var1[i];
      if(v1 > 1e-20)
      {
         double vq = varQ[i] * varQ[i];
         vr[i] = vq / (shortPeriod * v1);
      }
   }
}

//--- MASTER FUNCTION: Compute all 14 features and return as array
bool ComputeAllFeatures(double &features[])
{
   ArrayResize(features, 14);
   ArrayInitialize(features, 0.0);
   
   int barsNeeded = MathMax(InpFeatureBars, BARS_2D + 50);
   
   // Load price data
   double open[], high[], low[], close[];
   long tickVol[];
   int spread[];  // CopySpread returns int[], not long[]
   
   ArraySetAsSeries(open, false);
   ArraySetAsSeries(high, false);
   ArraySetAsSeries(low, false);
   ArraySetAsSeries(close, false);
   ArraySetAsSeries(tickVol, false);
   ArraySetAsSeries(spread, false);
   
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, barsNeeded, open) < barsNeeded)
      return false;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, barsNeeded, high) < barsNeeded)
      return false;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, barsNeeded, low) < barsNeeded)
      return false;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, barsNeeded, close) < barsNeeded)
      return false;
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 0, barsNeeded, tickVol) < barsNeeded)
      return false;
   if(CopySpread(_Symbol, PERIOD_CURRENT, 0, barsNeeded, spread) < barsNeeded)
      return false;
   
   int size = ArraySize(close);
   
   // Convert tick volume and spread to double
   double tickVolDbl[], spreadDbl[];
   ArrayResize(tickVolDbl, size);
   ArrayResize(spreadDbl, size);
   for(int i = 0; i < size; i++)
   {
      tickVolDbl[i] = (double)tickVol[i];
      spreadDbl[i] = (double)spread[i] * _Point;  // Convert to price units
   }
   
   // Calculate log returns
   double logReturns[], pctReturns[];
   ArrayResize(logReturns, size);
   ArrayResize(pctReturns, size);
   ArrayInitialize(logReturns, 0.0);
   ArrayInitialize(pctReturns, 0.0);
   
   for(int i = 1; i < size; i++)
   {
      if(close[i - 1] > 0.0)
      {
         logReturns[i] = MathLog(close[i] / close[i - 1]);
         pctReturns[i] = (close[i] - close[i - 1]) / close[i - 1];
      }
   }
   
   //--- 1. VOLATILITY FEATURES ---
   
   // 1a. volatility_1h
   double vol1h[];
   RollingStd(logReturns, vol1h, BARS_1H);
   features[0] = vol1h[size - 1];
   
   // 1b. volatility_1d
   double vol1d[];
   RollingStd(logReturns, vol1d, BARS_1D);
   features[1] = vol1d[size - 1];
   
   // 1c. natr_14 (Normalized ATR)
   double atr[];
   ComputeATR(high, low, close, atr, 14);
   features[2] = (close[size - 1] > 0.0) ? atr[size - 1] / close[size - 1] : 0.0;
   
   // 1d. bollinger_width
   double bbWidth[];
   ComputeBollingerWidth(close, bbWidth, 20, 2.0);
   features[3] = bbWidth[size - 1];
   
   //--- 2. TREND FEATURES ---
   
   // 2a. trend_short: (EMA12 - EMA48) / EMA48
   double ema12[], ema48[];
   StandardEMA(close, ema12, BARS_1H);
   StandardEMA(close, ema48, BARS_4H);
   features[4] = (ema48[size - 1] > 0.0) ? 
                 (ema12[size - 1] - ema48[size - 1]) / ema48[size - 1] : 0.0;
   
   // 2b. trend_long: (EMA48 - EMA576) / EMA576
   double ema576[];
   StandardEMA(close, ema576, BARS_2D);
   features[5] = (ema576[size - 1] > 0.0) ? 
                 (ema48[size - 1] - ema576[size - 1]) / ema576[size - 1] : 0.0;
   
   // 2c. macd_hist (normalized)
   double macdHist[];
   ComputeMACDHistogram(close, macdHist, 12, 26, 9);
   features[6] = macdHist[size - 1];
   
   // 2d. price_position [0, 1]
   double pricePos[];
   ComputePricePosition(close, high, low, pricePos, BARS_1D);
   features[7] = pricePos[size - 1];
   
   //--- 3. MOMENTUM FEATURES ---
   
   // 3a. rsi_14 (Wilder's RSI)
   double rsi14[];
   ComputeWilderRSI(close, rsi14, 14);
   features[8] = rsi14[size - 1];
   
   // 3b. rsi_rate (RSI change over 1 hour)
   features[9] = (size > BARS_1H) ? rsi14[size - 1] - rsi14[size - 1 - BARS_1H] : 0.0;
   
   // 3c. returns_skew (1-day window)
   double returnSkew[];
   RollingSkew(pctReturns, returnSkew, BARS_1D);
   features[10] = returnSkew[size - 1];
   
   //--- 4. VOLUME & MICROSTRUCTURE FEATURES ---
   
   // 4a. volume_ratio (1h / 1d average tick volume)
   double volShort[], volLong[];
   SimpleSMA(tickVolDbl, volShort, BARS_1H);
   SimpleSMA(tickVolDbl, volLong, BARS_1D);
   features[11] = (volLong[size - 1] > 1e-10) ? 
                  volShort[size - 1] / volLong[size - 1] : 1.0;
   
   // 4b. spread_norm (normalized spread)
   features[12] = (close[size - 1] > 0.0) ? 
                  spreadDbl[size - 1] / close[size - 1] : 0.0;
   
   // 4c. variance_ratio (trending vs mean-reverting)
   double varRatio[];
   ComputeVarianceRatio(logReturns, varRatio, BARS_1H, BARS_1D);
   features[13] = varRatio[size - 1];
   
   return true;
}

//--- Log all 14 features to the journal
void LogMarketRegimeFeatures(string tradeType, double entryPrice, double exitPrice, 
                              double profit, string exitReason)
{
   if(!InpLogRegime)
      return;
   
   double features[];
   if(!ComputeAllFeatures(features))
   {
      Print("⚠️ Failed to compute market regime features");
      return;
   }
   
   Print("═══════════════════════════════════════════════════════════════");
   Print("🎯 TRADE CLOSED | ", tradeType, " | ", exitReason);
   Print("   Entry: ", entryPrice, " | Exit: ", exitPrice, " | Profit: ", 
         DoubleToString(profit, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("───────────────────────────────────────────────────────────────");
   Print("📊 MARKET REGIME FEATURES (14 indicators):");
   Print("───────────────────────────────────────────────────────────────");
   
   // Volatility Features
   Print("💨 VOLATILITY:");
   Print("   volatility_1h     = ", DoubleToString(features[0], 6));
   Print("   volatility_1d     = ", DoubleToString(features[1], 6));
   Print("   natr_14           = ", DoubleToString(features[2], 6));
   Print("   bollinger_width   = ", DoubleToString(features[3], 6));
   
   // Trend Features
   Print("📈 TREND:");
   Print("   trend_short       = ", DoubleToString(features[4], 6));
   Print("   trend_long        = ", DoubleToString(features[5], 6));
   Print("   macd_hist         = ", DoubleToString(features[6], 6));
   Print("   price_position    = ", DoubleToString(features[7], 4));
   
   // Momentum Features
   Print("⚡ MOMENTUM:");
   Print("   rsi_14            = ", DoubleToString(features[8], 2));
   Print("   rsi_rate          = ", DoubleToString(features[9], 4));
   Print("   returns_skew      = ", DoubleToString(features[10], 4));
   
   // Volume & Microstructure
   Print("📦 VOLUME & MICROSTRUCTURE:");
   Print("   volume_ratio      = ", DoubleToString(features[11], 4));
   Print("   spread_norm       = ", DoubleToString(features[12], 6));
   Print("   variance_ratio    = ", DoubleToString(features[13], 4));
   
   Print("═══════════════════════════════════════════════════════════════");
}

//=== RSI MULTI-TIMEFRAME FILTER ==================================================

// Check if BUY trades are allowed based on RSI multi-timeframe filter
// Returns true if allowed, false if blocked
// Blocks BUY if ANY timeframe RSI is in overbought zone
bool CheckRsiFilterForBuy(double &rsiTf1Val, double &rsiTf2Val)
{
   if(!InpUseRsiFilter)
   {
      rsiTf1Val = 0.0;
      rsiTf2Val = 0.0;
      return true;  // Filter disabled, allow trade
   }

   double rsiTf1Arr[], rsiTf2Arr[];
   ArraySetAsSeries(rsiTf1Arr, true);
   ArraySetAsSeries(rsiTf2Arr, true);

   // Get current RSI values from both timeframes
   if(CopyBuffer(g_hRsiTf1, 0, 0, 2, rsiTf1Arr) < 2)
   {
      Print("ERROR: Failed to copy RSI TF1 buffer");
      return false;
   }
   if(CopyBuffer(g_hRsiTf2, 0, 0, 2, rsiTf2Arr) < 2)
   {
      Print("ERROR: Failed to copy RSI TF2 buffer");
      return false;
   }

   rsiTf1Val = rsiTf1Arr[0];
   rsiTf2Val = rsiTf2Arr[0];

   // Block BUY if ANY timeframe is overbought
   if(rsiTf1Val >= InpRsiFilterOB)
   {
      Print("⛔ BUY BLOCKED | RSI Filter TF1 (", EnumToString(InpRsiTf1), 
            ") = ", DoubleToString(rsiTf1Val, 2), " >= ", InpRsiFilterOB, " (Overbought)");
      return false;
   }

   if(rsiTf2Val >= InpRsiFilterOB)
   {
      Print("⛔ BUY BLOCKED | RSI Filter TF2 (", EnumToString(InpRsiTf2), 
            ") = ", DoubleToString(rsiTf2Val, 2), " >= ", InpRsiFilterOB, " (Overbought)");
      return false;
   }

   // All checks passed, allow BUY
   Print("✅ BUY ALLOWED | RSI Filter: TF1 (", EnumToString(InpRsiTf1), 
         ") = ", DoubleToString(rsiTf1Val, 2),
         " | TF2 (", EnumToString(InpRsiTf2), 
         ") = ", DoubleToString(rsiTf2Val, 2), " | Both below OB level");

   return true;
}

// Check if SELL trades are allowed based on RSI multi-timeframe filter
// Returns true if allowed, false if blocked
// Blocks SELL if ANY timeframe RSI is in oversold zone
bool CheckRsiFilterForSell(double &rsiTf1Val, double &rsiTf2Val)
{
   if(!InpUseRsiFilter)
   {
      rsiTf1Val = 0.0;
      rsiTf2Val = 0.0;
      return true;  // Filter disabled, allow trade
   }

   double rsiTf1Arr[], rsiTf2Arr[];
   ArraySetAsSeries(rsiTf1Arr, true);
   ArraySetAsSeries(rsiTf2Arr, true);

   // Get current RSI values from both timeframes
   if(CopyBuffer(g_hRsiTf1, 0, 0, 2, rsiTf1Arr) < 2)
   {
      Print("ERROR: Failed to copy RSI TF1 buffer");
      return false;
   }
   if(CopyBuffer(g_hRsiTf2, 0, 0, 2, rsiTf2Arr) < 2)
   {
      Print("ERROR: Failed to copy RSI TF2 buffer");
      return false;
   }

   rsiTf1Val = rsiTf1Arr[0];
   rsiTf2Val = rsiTf2Arr[0];

   // Block SELL if ANY timeframe is oversold
   if(rsiTf1Val <= InpRsiFilterOS)
   {
      Print("⛔ SELL BLOCKED | RSI Filter TF1 (", EnumToString(InpRsiTf1), 
            ") = ", DoubleToString(rsiTf1Val, 2), " <= ", InpRsiFilterOS, " (Oversold)");
      return false;
   }

   if(rsiTf2Val <= InpRsiFilterOS)
   {
      Print("⛔ SELL BLOCKED | RSI Filter TF2 (", EnumToString(InpRsiTf2), 
            ") = ", DoubleToString(rsiTf2Val, 2), " <= ", InpRsiFilterOS, " (Oversold)");
      return false;
   }

   // All checks passed, allow SELL
   Print("✅ SELL ALLOWED | RSI Filter: TF1 (", EnumToString(InpRsiTf1), 
         ") = ", DoubleToString(rsiTf1Val, 2),
         " | TF2 (", EnumToString(InpRsiTf2), 
         ") = ", DoubleToString(rsiTf2Val, 2), " | Both above OS level");

   return true;
}

//=== TRADE QUALITY FILTER (Regime-Based Feature Filter) =========================

// Check if trade meets quality criteria based on market regime features
// Returns true if trade passes filter, false if blocked
bool PassesRegimeFilter(const double &features[])
{
   // If filter is OFF, allow all trades
   if(InpFilterMode == FILTER_OFF)
      return true;

   // Feature indices (from g_featureNames array)
   // 0: volatility_1h,  1: volatility_1d,  2: natr_14,         3: bollinger_width
   // 4: trend_short,    5: trend_long,     6: macd_hist,       7: price_position
   // 8: rsi_14,         9: rsi_rate,       10: returns_skew,   11: volume_ratio
   // 12: spread_norm,   13: variance_ratio

   double rsi14          = features[8];
   double pricePosition  = features[7];
   double bollingerWidth = features[3];
   double trendShort     = features[4];
   double varianceRatio  = features[13];

   string reason = "";
   bool passed = false;

   switch(InpFilterMode)
   {
      case FILTER_CONSERVATIVE:
         // Conservative: Top 2 features
         // - RSI_14 > 28.72
         // - price_position > 0.5 (price must be above midpoint of daily range)
         passed = (rsi14 > 28.72 && pricePosition > 0.5);
         
         if(!passed)
         {
            reason = StringFormat("CONSERVATIVE filter: RSI14=%.2f (need >28.72) | PricePos=%.3f (need >0.50)",
                                 rsi14, pricePosition);
         }
         else
         {
            reason = StringFormat("CONSERVATIVE ✓: RSI14=%.2f | PricePos=%.3f",
                                 rsi14, pricePosition);
         }
         break;

      case FILTER_BALANCED:
         // Balanced: Top 3 features (43% retention, 42.9% winrate) - RECOMMENDED
         // - RSI_14 > 28.72
         // - price_position > 0.10
         // - bollinger_width > 0.0039
         passed = (rsi14 > 28.72 && 
                   pricePosition > 0.10 && 
                   bollingerWidth > 0.0039);
         
         if(!passed)
         {
            reason = StringFormat("BALANCED filter: RSI14=%.2f (>28.72?) | PricePos=%.3f (>0.10?) | BBWidth=%.5f (>0.0039?)",
                                 rsi14, pricePosition, bollingerWidth);
         }
         else
         {
            reason = StringFormat("BALANCED ✓: RSI14=%.2f | PricePos=%.3f | BBWidth=%.5f",
                                 rsi14, pricePosition, bollingerWidth);
         }
         break;

      case FILTER_AGGRESSIVE:
         // Aggressive: Top 5 features (32% retention, 48.0% winrate)
         // - RSI_14 > 28.72
         // - price_position > 0.10
         // - bollinger_width > 0.0039
         // - trend_short > -0.0015
         // - variance_ratio > 0.25
         passed = (rsi14 > 28.72 && 
                   pricePosition > 0.10 && 
                   bollingerWidth > 0.0039 &&
                   trendShort > -0.0015 &&
                   varianceRatio > 0.25);
         
         if(!passed)
         {
            reason = StringFormat("AGGRESSIVE filter: RSI14=%.2f (>28.72?) | PricePos=%.3f (>0.10?) | BBWidth=%.5f (>0.0039?) | TrendShort=%.6f (>-0.0015?) | VarRatio=%.3f (>0.25?)",
                                 rsi14, pricePosition, bollingerWidth, trendShort, varianceRatio);
         }
         else
         {
            reason = StringFormat("AGGRESSIVE ✓: RSI14=%.2f | PricePos=%.3f | BBWidth=%.5f | TrendShort=%.6f | VarRatio=%.3f",
                                 rsi14, pricePosition, bollingerWidth, trendShort, varianceRatio);
         }
         break;

      default:
         passed = true;
         reason = "Unknown filter mode - allowing trade";
         break;
   }

   if(!passed)
   {
      Print("⛔ TRADE BLOCKED | ", reason);
   }
   else
   {
      Print("✅ TRADE ALLOWED | ", reason);
   }

   return passed;
}

//=== BREAKEVEN MANAGEMENT ========================================================

// Move stop loss to breakeven when trade reaches 1:1 risk-reward ratio
void ManageBreakeven()
{
   CPositionInfo posInfo;
   double pipSize = _Point * 10;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!posInfo.SelectByTicket(ticket))
         continue;
      
      // Only manage our positions
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber)
         continue;
      
      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double currentTP = posInfo.TakeProfit();
      double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Calculate risk distance (entry to current SL)
      double riskDistance = MathAbs(openPrice - currentSL);
      
      // Skip if SL is already at or beyond breakeven
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         // For BUY: Check if SL is already at/above entry
         if(currentSL >= openPrice)
            continue;
         
         // Check if price has moved 1:1 (risk distance above entry)
         double breakevenTrigger = openPrice + riskDistance;
         
         if(currentPrice >= breakevenTrigger)
         {
            // Move SL to breakeven + buffer
            double newSL = openPrice + (InpBreakevenBuffer * pipSize);
            newSL = NormalizeDouble(newSL, _Digits);
            
            // Ensure new SL is better than current SL
            if(newSL > currentSL)
            {
               if(g_trade.PositionModify(ticket, newSL, currentTP))
               {
                  Print("✅ BUY Breakeven | Ticket=", ticket, 
                        " | Entry=", openPrice,
                        " | Old SL=", currentSL,
                        " | New SL=", newSL, " (BE+", InpBreakevenBuffer, " pips)",
                        " | Current Price=", currentPrice,
                        " | Profit Locked=", DoubleToString((newSL - openPrice) / pipSize, 1), " pips");
               }
               else
               {
                  Print("⚠ Failed to move BUY to breakeven: ", g_trade.ResultRetcodeDescription());
               }
            }
         }
      }
      else // SELL position
      {
         // For SELL: Check if SL is already at/below entry
         if(currentSL <= openPrice && currentSL > 0)
            continue;
         
         // Check if price has moved 1:1 (risk distance below entry)
         double breakevenTrigger = openPrice - riskDistance;
         
         if(currentPrice <= breakevenTrigger)
         {
            // Move SL to breakeven - buffer
            double newSL = openPrice - (InpBreakevenBuffer * pipSize);
            newSL = NormalizeDouble(newSL, _Digits);
            
            // Ensure new SL is better than current SL (lower for SELL)
            if(newSL < currentSL || currentSL == 0)
            {
               if(g_trade.PositionModify(ticket, newSL, currentTP))
               {
                  Print("✅ SELL Breakeven | Ticket=", ticket, 
                        " | Entry=", openPrice,
                        " | Old SL=", currentSL,
                        " | New SL=", newSL, " (BE-", InpBreakevenBuffer, " pips)",
                        " | Current Price=", currentPrice,
                        " | Profit Locked=", DoubleToString((openPrice - newSL) / pipSize, 1), " pips");
               }
               else
               {
                  Print("⚠ Failed to move SELL to breakeven: ", g_trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}

//=== MAIN TICK ===================================================================

void OnTick()
{
   // Only act on new bar to match Pine bar-close logic
   static datetime lastBar = 0;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == lastBar) return;
   lastBar = currentBar;

   //--- How many bars we need ---
   int maxLen    = MathMax(InpLeftLenH + InpRightLenH, InpLeftLenL + InpRightLenL) + 10;
   int barsNeeded = MathMax(maxLen, InpExtLookback + InpBBLen + 5);
   barsNeeded = MathMax(barsNeeded, InpMacroEmaLen + 5);

   //--- Load price arrays ---
   double highArr[], lowArr[], closeArr[];
   ArraySetAsSeries(highArr,  true);
   ArraySetAsSeries(lowArr,   true);
   ArraySetAsSeries(closeArr, true);

   int copiedH = CopyHigh (_Symbol, PERIOD_CURRENT, 0, barsNeeded, highArr);
   int copiedL = CopyLow  (_Symbol, PERIOD_CURRENT, 0, barsNeeded, lowArr);
   int copiedC = CopyClose(_Symbol, PERIOD_CURRENT, 0, barsNeeded, closeArr);
   if(copiedH < barsNeeded || copiedL < barsNeeded || copiedC < barsNeeded)
   { Print("Not enough bars yet."); return; }

   //--- Swing Point Detection (check the confirmed pivot at bar[rightLen]) ---
   // The confirmed pivot sits at bar index = rightLen (it has rightLen bars to its right)
   int pivotIdxH = InpRightLenH;
   int pivotIdxL = InpRightLenL;

   bool pivotHigh = IsPivotHigh(highArr, pivotIdxH, InpLeftLenH, InpRightLenH);
   bool pivotLow  = IsPivotLow (lowArr,  pivotIdxL, InpLeftLenL, InpRightLenL);

   // Retrieve bar time for labelling
   if(pivotHigh)
   {
      datetime pivotHighTime = iTime(_Symbol, PERIOD_CURRENT, pivotIdxH);
      double   pivotHighPrice = highArr[pivotIdxH];

      // Only update & draw if this is a NEW pivot high we haven't logged yet
      if(pivotHighTime != g_lastPivotHighTime)
      {
         g_lastPivotHigh     = pivotHighPrice;
         g_lastPivotHighTime = pivotHighTime;

         DrawPivotHighLabel(pivotHighTime, pivotHighPrice);
         Print("✦ Pivot HIGH | Price=", pivotHighPrice,
               " | Time=", TimeToString(pivotHighTime));
      }
   }

   if(pivotLow)
   {
      datetime pivotLowTime  = iTime(_Symbol, PERIOD_CURRENT, pivotIdxL);
      double   pivotLowPrice = lowArr[pivotIdxL];

      if(pivotLowTime != g_lastPivotLowTime)
      {
         g_lastPivotLow     = pivotLowPrice;
         g_lastPivotLowTime = pivotLowTime;

         DrawPivotLowLabel(pivotLowTime, pivotLowPrice);
         Print("✦ Pivot LOW  | Price=", pivotLowPrice,
               " | Time=", TimeToString(pivotLowTime));
      }
   }

   //--- EMA Fast & Slow ---
   double emaFastArr[], emaSlowArr[];
   if(!GetBuffer(g_hEmaFast, 0, 0, 3, emaFastArr)) return;
   if(!GetBuffer(g_hEmaSlow, 0, 0, 3, emaSlowArr)) return;

   double emaFast1 = emaFastArr[1], emaFast2 = emaFastArr[2];
   double emaSlow1 = emaSlowArr[1], emaSlow2 = emaSlowArr[2];

   bool crossOver  = (emaFast2 <= emaSlow2) && (emaFast1 > emaSlow1);
   bool crossUnder = (emaFast2 >= emaSlow2) && (emaFast1 < emaSlow1);

   //--- PSAR ---
   double sarArr[];
   if(!GetBuffer(g_hSar, 0, 0, 3, sarArr)) return;
   double sar1    = sarArr[1];
   bool psarBull  = (sar1 < closeArr[1]);
   bool psarBear  = (sar1 > closeArr[1]);

   //--- RSI ---
   double rsiArr[];
   if(!GetBuffer(g_hRsi, 0, 0, InpExtLookback + 3, rsiArr)) return;

   //--- Bollinger Bands ---
   double bbUpperArr[], bbLowerArr[];
   if(!GetBuffer(g_hBB, 1, 0, InpExtLookback + 3, bbUpperArr)) return;
   if(!GetBuffer(g_hBB, 2, 0, InpExtLookback + 3, bbLowerArr)) return;

   bool wasExtOS = false, wasExtOB = false;
   for(int k = 1; k <= InpExtLookback; k++)
   {
      if((lowArr[k]  <= bbLowerArr[k]) || (rsiArr[k] <= InpRsiOS)) wasExtOS = true;
      if((highArr[k] >= bbUpperArr[k]) || (rsiArr[k] >= InpRsiOB)) wasExtOB = true;
   }

   //--- ADX Filter ---
   double adxArr[];
   if(!GetBuffer(g_hAdx, 0, 0, 3, adxArr)) return;
   double adxVal = adxArr[1];
   bool adxOk    = !InpUseAdx || (adxVal < InpAdxThreshold);

   //--- Macro Filter ---
   double macroEmaArr[], macroPriceArr[];
   ArraySetAsSeries(macroEmaArr,   true);
   ArraySetAsSeries(macroPriceArr, true);
   if(CopyBuffer(g_hMacroEma, 0, 0, 3, macroEmaArr)   < 3) return;
   if(CopyClose(_Symbol, InpMacroTf, 0, 3, macroPriceArr) < 3) return;

   double macroEma1   = macroEmaArr[1];
   double macroPrice1 = macroPriceArr[0];

   bool macroOkBull = !InpUseMacro || (macroPrice1 > macroEma1);
   bool macroOkBear = !InpUseMacro || (macroPrice1 < macroEma1);

   //--- Final Signal Logic ---
   bool buySig  = crossOver  && psarBull && wasExtOS && adxOk && macroOkBull;
   bool sellSig = crossUnder && psarBear && wasExtOB && adxOk && macroOkBear;

   //--- Trade Execution ---
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySig && !HasOpenPosition(POSITION_TYPE_BUY))
   {
      // Check RSI Multi-Timeframe Filter for BUY
      double rsiTf1Val = 0.0, rsiTf2Val = 0.0;
      if(!CheckRsiFilterForBuy(rsiTf1Val, rsiTf2Val))
      {
         // Trade blocked by RSI filter - log already printed in function
         return;
      }

      // Check Regime-Based Trade Quality Filter
      if(InpFilterMode != FILTER_OFF)
      {
         double regimeFeatures[];
         if(ComputeAllFeatures(regimeFeatures))
         {
            if(!PassesRegimeFilter(regimeFeatures))
            {
               // Trade blocked by regime filter - log already printed in function
               return;
            }
         }
         else
         {
            Print("⚠ WARNING: Could not compute regime features, allowing trade anyway");
         }
      }

      double sl = CalcBuySL(ask);
      double tp = CalcTP(ask, sl);
      double slPips = MathAbs(ask - sl) / (_Point * 10);
      double tpPips = MathAbs(tp  - ask) / (_Point * 10);

      Print("BUY Signal | SwingSL=", InpUseSwingPointSL,
            " | LastPivotLow=",  g_lastPivotLow,
            " | SL=", sl, " (", DoubleToString(slPips, 1), " pips)",
            " | TP=", tp, " (", DoubleToString(tpPips, 1), " pips)",
            " | RR=1:", InpRiskRewardRatio,
            " | Filter=", EnumToString(InpFilterMode));

      if(g_trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "EPR Buy | RR1:" +
                     DoubleToString(InpRiskRewardRatio, 1)))
         Print("BUY opened. ADX=", adxVal, " macroPrice=", macroPrice1, " macroEMA=", macroEma1);
      else
         Print("BUY failed: ", g_trade.ResultRetcodeDescription());
   }

   if(sellSig && !HasOpenPosition(POSITION_TYPE_SELL))
   {
      // Check RSI Multi-Timeframe Filter for SELL
      double rsiTf1Val = 0.0, rsiTf2Val = 0.0;
      if(!CheckRsiFilterForSell(rsiTf1Val, rsiTf2Val))
      {
         // Trade blocked by RSI filter - log already printed in function
         return;
      }

      // Check Regime-Based Trade Quality Filter
      if(InpFilterMode != FILTER_OFF)
      {
         double regimeFeatures[];
         if(ComputeAllFeatures(regimeFeatures))
         {
            if(!PassesRegimeFilter(regimeFeatures))
            {
               // Trade blocked by regime filter - log already printed in function
               return;
            }
         }
         else
         {
            Print("⚠ WARNING: Could not compute regime features, allowing trade anyway");
         }
      }

      double sl = CalcSellSL(bid);
      double tp = CalcTP(bid, sl);
      double slPips = MathAbs(sl  - bid) / (_Point * 10);
      double tpPips = MathAbs(bid - tp)  / (_Point * 10);

      Print("SELL Signal | SwingSL=", InpUseSwingPointSL,
            " | LastPivotHigh=", g_lastPivotHigh,
            " | SL=", sl, " (", DoubleToString(slPips, 1), " pips)",
            " | TP=", tp, " (", DoubleToString(tpPips, 1), " pips)",
            " | RR=1:", InpRiskRewardRatio,
            " | Filter=", EnumToString(InpFilterMode));

      if(g_trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "EPR Sell | RR1:" +
                      DoubleToString(InpRiskRewardRatio, 1)))
         Print("SELL opened. ADX=", adxVal, " macroPrice=", macroPrice1, " macroEMA=", macroEma1);
      else
         Print("SELL failed: ", g_trade.ResultRetcodeDescription());
   }

   //--- Breakeven Management ---
   if(InpMoveToBreakeven)
      ManageBreakeven();
}

//=== END OF FILE =================================================================

//=== TRADE TRANSACTION HANDLER (Monitor Trade Closures) =========================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // We only care about deal events (actual trade executions)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   
   // Get deal information
   ulong dealTicket = trans.deal;
   if(dealTicket == 0)
      return;
   
   // Check if this is our EA's trade
   if(!HistoryDealSelect(dealTicket))
      return;
   
   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealMagic != InpMagicNumber)
      return;
   
   // Only process EXIT deals (closing trades)
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT)
      return;
   
   // Get deal details
   ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   double dealProfit       = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double dealPrice        = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   ulong posTicket         = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   
   // Get position entry price from history
   double entryPrice = 0.0;
   string tradeType = "";
   string exitReason = "Unknown";
   
   // Select position from history to get entry details
   if(HistorySelectByPosition(posTicket))
   {
      // Find the entry deal for this position
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         
         ulong posTick = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         if(posTick != posTicket) continue;
         
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
         {
            entryPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
            break;
         }
      }
   }
   
   // Determine trade type from deal type
   if(dealType == DEAL_TYPE_BUY)
      tradeType = "SELL (Exit Long)";
   else if(dealType == DEAL_TYPE_SELL)
      tradeType = "BUY (Exit Short)";
   else
      return;  // Not a position close
   
   // Determine exit reason
   string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
   if(StringFind(comment, "tp") >= 0 || StringFind(comment, "TP") >= 0)
      exitReason = "Take Profit";
   else if(StringFind(comment, "sl") >= 0 || StringFind(comment, "SL") >= 0)
      exitReason = "Stop Loss";
   else
      exitReason = "Manual/Other";
   
   // Log the market regime features at the time of closure
   LogMarketRegimeFeatures(tradeType, entryPrice, dealPrice, dealProfit, exitReason);
}

//=================================================================================
