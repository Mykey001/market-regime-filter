//+------------------------------------------------------------------+
//|                                      HedgeGridMartingaleBot.mq5 |
//|                                 Production-Grade Trading Bot     |
//|                               Enhanced with Market Regime v2.3   |
//+------------------------------------------------------------------+
#property copyright "Advanced Trading System v2.3"
#property link      ""
#property version   "2.30"
#property strict

#include "MarketRegimeFeatures.mqh"

//--- Input Parameters
input group "=== Initial Position Settings ==="
input bool     AutoCalculateLotSize = true;         // Auto-Calculate Initial Lot (Based on Balance)
input double   ManualLotSize = 0.01;                // Manual Lot Size (if Auto = false)
input double   RiskPercentPerCycle = 2.0;           // Risk % per Cycle (for Auto Lot)
input int      MagicNumber = 123456;                // Magic Number

input group "=== ATR Grid Settings ==="
input int      ATR_Period = 14;                     // ATR Period
input double   ATR_Multiplier = 1.0;                // ATR Multiplier for Grid Spacing
input bool     AutoCalculateGridDistance = true;    // Auto-Calculate Grid Distance
input double   ManualMinGridDistancePoints = 100;  // Manual Min Grid Distance (Points)
input double   ManualMaxGridDistancePoints = 1000; // Manual Max Grid Distance (Points)
input int      MaxGridLevels = 10;                  // Maximum Grid Levels

input group "=== Martingale Settings ==="
input double   MartingaleMultiplier = 2.0;          // Martingale Multiplier
input bool     AutoCalculateMaxLot = true;          // Auto-Calculate Max Lot (Based on Broker)
input double   ManualMaxLotSize = 10.0;             // Manual Max Lot Size

input group "=== Basket Profit Settings ==="
input bool     UseDollarTP = true;                  // Use Dollar-Based TP (false = Pip-Based)
input double   BasketProfitDollar = 10.0;           // Basket Profit Target (Dollar)
input double   BasketProfitPips = 50.0;             // Basket Profit Target (Pips)

input group "=== Risk Management ==="
input double   MaxDrawdownDollar = 1000.0;          // Max Basket Drawdown (Dollar) - 0 = Disabled
input bool     EnableTrailing = false;               // Enable Trailing Basket Profit
input double   TrailingStartDollar = 5.0;           // Trailing Start (Dollar)
input double   TrailingStepDollar = 2.0;            // Trailing Step (Dollar)

input group "=== Trading Hours ==="
input bool     UseTradingHours = false;             // Enable Trading Hours Filter
input int      StartHour = 0;                       // Start Hour
input int      EndHour = 23;                        // End Hour

input group "=== ADX Trend Filter ==="
input bool     UseADXFilter = true;                 // Enable ADX Trend Filter
input int      ADX_Period = 14;                     // ADX Period
input double   MaxADX_ForEntry = 25.0;              // Max ADX for New Cycle (Ranging Market)
input double   MaxADX_ForGrid = 30.0;               // Max ADX for Grid Expansion

input group "=== Spread Filter ==="
input bool     UseSpreadFilter = true;              // Enable Spread Filter
input double   MaxSpreadMultiplier = 2.0;           // Max Spread Multiplier (vs Average)
input int      SpreadAveragePeriod = 20;            // Spread Average Period (bars)
input int      MaxSpreadPoints = 50;                // Max Absolute Spread (Points) - 0 = Use Multiplier Only

input group "=== Market Regime Features (v2.3) ==="
input bool     InpLogRegime = true;                 // Log Market Regime Features
input int      InpFeatureBars = 300;                // History Bars for Feature Calculation

input group "=== Market Regime Filters ==="
input bool     UseRegimeFilter = true;              // Enable Market Regime Filter
input double   MinReturnsSkew = 0.299;              // Minimum Returns Skew (Entry Filter)
input double   MinVolumeRatio = 1.375;              // Minimum Volume Ratio (Entry Filter)

//--- Global Variables
int atrHandle;
int adxHandle;
double atrBuffer[];
double adxBuffer[];
double plusDIBuffer[];
double minusDIBuffer[];
double spreadHistory[];
int spreadHistoryIndex = 0;
double lastBuyPrice = 0;
double lastSellPrice = 0;
int buyGridLevel = 0;
int sellGridLevel = 0;
bool cycleActive = false;
double highestBasketProfit = 0;
double trailingThreshold = 0;

//--- Dynamic Broker Settings
double InitialLotSize = 0.01;
double MinGridDistancePoints = 100;
double MaxGridDistancePoints = 1000;
double MaxLotSize = 10.0;
double brokerMinLot = 0.01;
double brokerMaxLot = 100.0;
double brokerLotStep = 0.01;
int brokerStopLevel = 0;
int brokerSpread = 0;
int brokerDigits = 5;
string brokerName = "";
double tickValue = 0;
double tickSize = 0;
ENUM_ORDER_TYPE_FILLING fillingMode = ORDER_FILLING_FOK;

//--- Structure for position tracking
struct PositionInfo {
    ulong ticket;
    double lots;
    double openPrice;
    ENUM_POSITION_TYPE type;
    int gridLevel;
};

PositionInfo buyPositions[];
PositionInfo sellPositions[];

//=== MARKET REGIME FEATURE NAMES (v2.3) ==========================================

// M5 Timeframe Constants (5-minute bars)
#define BARS_1H   12     // 12 × 5min = 1 hour
#define BARS_4H   48     // 48 × 5min = 4 hours
#define BARS_1D   288    // 288 × 5min = 24 hours
#define BARS_2D   576    // 576 × 5min = 2 days

// 22 features from feature_engine.py (M5 timeframe calibrated) - Enhanced v2.3
string g_featureNames[22] = {
   // Original 14 features
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
   "variance_ratio",     // Variance ratio (trending vs mean-reverting)
   // NEW: Advanced Regime Features (8) - v2.3
   "range_expansion",    // True Range expansion/contraction ratio
   "momentum_strength",  // Absolute momentum magnitude (rate of change)
   "volume_price_corr",  // Volume-price correlation (12-bar)
   "intrabar_pressure",  // (Close-Low)/(High-Low) buying pressure [0,1]
   "volatility_regime",  // Volatility percentile rank (relative positioning)
   "trend_consistency",  // EMA alignment strength (3 EMAs agreement)
   "price_acceleration", // Second derivative of price (change in momentum)
   "volume_surprise"     // Volume deviation from norm (z-score)
};

// Cycle tracking for features
double g_cycleStartPrice = 0;
datetime g_cycleStartTime = 0;

//=== MARKET REGIME FEATURE COMPUTATION (v2.3) ====================================

//--- MASTER FUNCTION: Compute all 22 features and return as array (v2.3 Enhanced)
bool ComputeAllFeatures(double &features[])
{
   ArrayResize(features, 22);
   ArrayInitialize(features, 0.0);
   
   int barsNeeded = MathMax(InpFeatureBars, BARS_2D + 50);
   
   // Load price data
   double open[], high[], low[], close[];
   long tickVol[];
   int spread[];
   
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
      spreadDbl[i] = (double)spread[i] * _Point;
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
   
   //--- 1. VOLATILITY FEATURES (Original 4) ---
   
   double vol1h[];
   RollingStd(logReturns, vol1h, BARS_1H);
   features[0] = vol1h[size - 1];
   
   double vol1d[];
   RollingStd(logReturns, vol1d, BARS_1D);
   features[1] = vol1d[size - 1];
   
   double atr[];
   ComputeATR(high, low, close, atr, 14);
   features[2] = (close[size - 1] > 0.0) ? atr[size - 1] / close[size - 1] : 0.0;
   
   double bbWidth[];
   ComputeBollingerWidth(close, bbWidth, 20, 2.0);
   features[3] = bbWidth[size - 1];
   
   //--- 2. TREND FEATURES (Original 4) ---
   
   double ema12[], ema48[];
   StandardEMA(close, ema12, BARS_1H);
   StandardEMA(close, ema48, BARS_4H);
   features[4] = (ema48[size - 1] > 0.0) ? 
                 (ema12[size - 1] - ema48[size - 1]) / ema48[size - 1] : 0.0;
   
   double ema576[];
   StandardEMA(close, ema576, BARS_2D);
   features[5] = (ema576[size - 1] > 0.0) ? 
                 (ema48[size - 1] - ema576[size - 1]) / ema576[size - 1] : 0.0;
   
   double macdHist[];
   ComputeMACDHistogram(close, macdHist, 12, 26, 9);
   features[6] = macdHist[size - 1];
   
   double pricePos[];
   ComputePricePosition(close, high, low, pricePos, BARS_1D);
   features[7] = pricePos[size - 1];
   
   //--- 3. MOMENTUM FEATURES (Original 3) ---
   
   double rsi14[];
   ComputeWilderRSI(close, rsi14, 14);
   features[8] = rsi14[size - 1];
   
   features[9] = (size > BARS_1H) ? rsi14[size - 1] - rsi14[size - 1 - BARS_1H] : 0.0;
   
   double returnSkew[];
   RollingSkew(pctReturns, returnSkew, BARS_1D);
   features[10] = returnSkew[size - 1];
   
   //--- 4. VOLUME & MICROSTRUCTURE FEATURES (Original 3) ---
   
   double volShort[], volLong[];
   SimpleSMA(tickVolDbl, volShort, BARS_1H);
   SimpleSMA(tickVolDbl, volLong, BARS_1D);
   features[11] = (volLong[size - 1] > 1e-10) ? 
                  volShort[size - 1] / volLong[size - 1] : 1.0;
   
   features[12] = (close[size - 1] > 0.0) ? 
                  spreadDbl[size - 1] / close[size - 1] : 0.0;
   
   double varRatio[];
   ComputeVarianceRatio(logReturns, varRatio, BARS_1H, BARS_1D);
   features[13] = varRatio[size - 1];
   
   //--- 5. NEW ADVANCED REGIME FEATURES (8) v2.3 ---
   
   double rangeExp[];
   ComputeRangeExpansion(high, low, close, rangeExp, 14);
   features[14] = rangeExp[size - 1];
   
   double momStrength[];
   ComputeMomentumStrength(close, momStrength, BARS_1H);
   features[15] = momStrength[size - 1];
   
   double volPriceCorr[];
   ComputeVolumePriceCorr(close, tickVolDbl, volPriceCorr, BARS_1H);
   features[16] = volPriceCorr[size - 1];
   
   features[17] = ComputeIntrabarPressure(high, low, close, size - 1);
   
   double volRegime[];
   ComputeVolatilityRegime(vol1d, volRegime, BARS_1D);
   features[18] = volRegime[size - 1];
   
   double trendConsist[];
   ComputeTrendConsistency(close, trendConsist, BARS_1H, BARS_4H, BARS_1D);
   features[19] = trendConsist[size - 1];
   
   double priceAccel[];
   ComputePriceAcceleration(close, priceAccel, 5);
   features[20] = priceAccel[size - 1];
   
   double volSurprise[];
   ComputeVolumeSurprise(tickVolDbl, volSurprise, BARS_1D);
   features[21] = volSurprise[size - 1];
   
   return true;
}

//--- Log features at BASKET OPEN (cycle start) - v2.3
void LogMarketRegimeFeaturesAtOpen(double avgPrice)
{
   if(!InpLogRegime)
      return;
   
   double features[];
   if(!ComputeAllFeatures(features))
   {
      Print("⚠️ Failed to compute market regime features at basket open");
      return;
   }
   
   Print("═══════════════════════════════════════════════════════════════");
   Print("🚀 BASKET OPENED | Avg Price: ", avgPrice);
   Print("───────────────────────────────────────────────────────────────");
   Print("📊 MARKET REGIME FEATURES (22 indicators) - AT OPEN:");
   Print("───────────────────────────────────────────────────────────────");
   
   Print("💨 VOLATILITY:");
   Print("   volatility_1h     = ", DoubleToString(features[0], 6));
   Print("   volatility_1d     = ", DoubleToString(features[1], 6));
   Print("   natr_14           = ", DoubleToString(features[2], 6));
   Print("   bollinger_width   = ", DoubleToString(features[3], 6));
   
   Print("📈 TREND:");
   Print("   trend_short       = ", DoubleToString(features[4], 6));
   Print("   trend_long        = ", DoubleToString(features[5], 6));
   Print("   macd_hist         = ", DoubleToString(features[6], 6));
   Print("   price_position    = ", DoubleToString(features[7], 4));
   
   Print("⚡ MOMENTUM:");
   Print("   rsi_14            = ", DoubleToString(features[8], 2));
   Print("   rsi_rate          = ", DoubleToString(features[9], 4));
   Print("   returns_skew      = ", DoubleToString(features[10], 4));
   
   Print("📦 VOLUME & MICROSTRUCTURE:");
   Print("   volume_ratio      = ", DoubleToString(features[11], 4));
   Print("   spread_norm       = ", DoubleToString(features[12], 6));
   Print("   variance_ratio    = ", DoubleToString(features[13], 4));
   
   Print("🔥 ADVANCED REGIME (NEW):");
   Print("   range_expansion   = ", DoubleToString(features[14], 4));
   Print("   momentum_strength = ", DoubleToString(features[15], 6));
   Print("   volume_price_corr = ", DoubleToString(features[16], 4));
   Print("   intrabar_pressure = ", DoubleToString(features[17], 4));
   Print("   volatility_regime = ", DoubleToString(features[18], 4));
   Print("   trend_consistency = ", DoubleToString(features[19], 6));
   Print("   price_acceleration= ", DoubleToString(features[20], 6));
   Print("   volume_surprise   = ", DoubleToString(features[21], 4));
   
   Print("═══════════════════════════════════════════════════════════════");
}

//--- Log features at BASKET CLOSE - v2.3
void LogMarketRegimeFeaturesAtClose(double avgPrice, double totalProfit, string closeReason)
{
   if(!InpLogRegime)
      return;
   
   double features[];
   if(!ComputeAllFeatures(features))
   {
      Print("⚠️ Failed to compute market regime features at basket close");
      return;
   }
   
   Print("═══════════════════════════════════════════════════════════════");
   Print("🎯 BASKET CLOSED | ", closeReason);
   Print("   Avg Price: ", avgPrice, " | Profit: ", DoubleToString(totalProfit, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("───────────────────────────────────────────────────────────────");
   Print("📊 MARKET REGIME FEATURES (22 indicators) - AT CLOSE:");
   Print("───────────────────────────────────────────────────────────────");
   
   Print("💨 VOLATILITY:");
   Print("   volatility_1h     = ", DoubleToString(features[0], 6));
   Print("   volatility_1d     = ", DoubleToString(features[1], 6));
   Print("   natr_14           = ", DoubleToString(features[2], 6));
   Print("   bollinger_width   = ", DoubleToString(features[3], 6));
   
   Print("📈 TREND:");
   Print("   trend_short       = ", DoubleToString(features[4], 6));
   Print("   trend_long        = ", DoubleToString(features[5], 6));
   Print("   macd_hist         = ", DoubleToString(features[6], 6));
   Print("   price_position    = ", DoubleToString(features[7], 4));
   
   Print("⚡ MOMENTUM:");
   Print("   rsi_14            = ", DoubleToString(features[8], 2));
   Print("   rsi_rate          = ", DoubleToString(features[9], 4));
   Print("   returns_skew      = ", DoubleToString(features[10], 4));
   
   Print("📦 VOLUME & MICROSTRUCTURE:");
   Print("   volume_ratio      = ", DoubleToString(features[11], 4));
   Print("   spread_norm       = ", DoubleToString(features[12], 6));
   Print("   variance_ratio    = ", DoubleToString(features[13], 4));
   
   Print("🔥 ADVANCED REGIME (NEW):");
   Print("   range_expansion   = ", DoubleToString(features[14], 4));
   Print("   momentum_strength = ", DoubleToString(features[15], 6));
   Print("   volume_price_corr = ", DoubleToString(features[16], 4));
   Print("   intrabar_pressure = ", DoubleToString(features[17], 4));
   Print("   volatility_regime = ", DoubleToString(features[18], 4));
   Print("   trend_consistency = ", DoubleToString(features[19], 6));
   Print("   price_acceleration= ", DoubleToString(features[20], 6));
   Print("   volume_surprise   = ", DoubleToString(features[21], 4));
   
   Print("═══════════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Get broker information
    LoadBrokerSettings();
    
    // Display broker information
    PrintBrokerInfo();
    
    // Initialize dynamic parameters
    InitializeDynamicParameters();
    
    // Initialize ATR indicator
    atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
    if(atrHandle == INVALID_HANDLE) {
        Print("Failed to create ATR indicator");
        return(INIT_FAILED);
    }
    
    // Initialize ADX indicator
    adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
    if(adxHandle == INVALID_HANDLE) {
        Print("Failed to create ADX indicator");
        return(INIT_FAILED);
    }
    
    ArraySetAsSeries(atrBuffer, true);
    ArraySetAsSeries(adxBuffer, true);
    ArraySetAsSeries(plusDIBuffer, true);
    ArraySetAsSeries(minusDIBuffer, true);
    
    // Initialize spread history array
    ArrayResize(spreadHistory, SpreadAveragePeriod);
    ArrayInitialize(spreadHistory, 0);
    
    Print("=== HedgeGridMartingaleBot Initialized ===");
    Print("Symbol: ", _Symbol);
    Print("Initial Lot: ", InitialLotSize, " (", (AutoCalculateLotSize ? "Auto" : "Manual"), ")");
    Print("ATR Period: ", ATR_Period);
    Print("ATR Multiplier: ", ATR_Multiplier);
    Print("Grid Distance: ", MinGridDistancePoints, "-", MaxGridDistancePoints, " points (", (AutoCalculateGridDistance ? "Auto" : "Manual"), ")");
    Print("Martingale Multiplier: ", MartingaleMultiplier);
    Print("Max Grid Levels: ", MaxGridLevels);
    Print("Max Lot Size: ", MaxLotSize, " (", (AutoCalculateMaxLot ? "Auto" : "Manual"), ")");
    Print("Basket Profit Target: ", UseDollarTP ? DoubleToString(BasketProfitDollar, 2) + " $" : DoubleToString(BasketProfitPips, 1) + " pips");
    Print("--- Filters ---");
    Print("ADX Filter: ", UseADXFilter ? "ENABLED" : "DISABLED", UseADXFilter ? " | Max ADX Entry: " + DoubleToString(MaxADX_ForEntry, 1) : "");
    Print("Spread Filter: ", UseSpreadFilter ? "ENABLED" : "DISABLED", UseSpreadFilter ? " | Max Multiplier: " + DoubleToString(MaxSpreadMultiplier, 1) + "x" : "");
    Print("Regime Filter: ", UseRegimeFilter ? "ENABLED" : "DISABLED", UseRegimeFilter ? " | Min Skew: " + DoubleToString(MinReturnsSkew, 3) + " | Min Vol Ratio: " + DoubleToString(MinVolumeRatio, 3) : "");
    Print("==========================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    
    if(adxHandle != INVALID_HANDLE)
        IndicatorRelease(adxHandle);
    
    Print("=== HedgeGridMartingaleBot Stopped ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check if trading is allowed
    if(!IsTradeAllowed()) {
        return;
    }
    
    // Check trading hours
    if(UseTradingHours && !IsWithinTradingHours()) {
        return;
    }
    
    // Update spread history
    UpdateSpreadHistory();
    
    // Update position arrays
    UpdatePositionArrays();
    
    // Check if we need to start a new cycle
    if(!cycleActive) {
        StartNewCycle();
        return;
    }
    
    // Calculate basket metrics
    double basketProfit = CalculateBasketProfit();
    double basketPips = CalculateBasketPips();
    
    // Check for basket take profit
    if(CheckBasketTakeProfit(basketProfit, basketPips)) {
        CloseAllPositions();
        ResetCycle();
        return;
    }
    
    // Check for maximum drawdown
    if(MaxDrawdownDollar > 0 && basketProfit < -MaxDrawdownDollar) {
        Print("Max Drawdown Reached! Closing all positions.");
        CloseAllPositions();
        ResetCycle();
        return;
    }
    
    // Update trailing stop
    if(EnableTrailing) {
        UpdateTrailingStop(basketProfit);
    }
    
    // Check for grid opportunities
    CheckAndOpenGridPositions();
}

//+------------------------------------------------------------------+
//| Start a new trading cycle                                        |
//+------------------------------------------------------------------+
void StartNewCycle() {
    // Check ADX filter for new cycle
    if(UseADXFilter && !CheckADXFilter(true)) {
        return; // Market too trending, skip cycle start
    }
    
    // Check spread filter
    if(UseSpreadFilter && !CheckSpreadFilter()) {
        return; // Spread too wide, skip cycle start
    }
    
    // Check market regime filter (Returns Skew & Volume Ratio)
    if(UseRegimeFilter && !CheckRegimeFilter(true)) {
        return; // Market regime conditions not met, skip cycle start
    }
    
    Print("=== Starting New Cycle ===");
    Print("Market Conditions: PASSED (All filters OK)");
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Open initial Buy position
    ulong buyTicket = OpenPosition(ORDER_TYPE_BUY, InitialLotSize, 0);
    if(buyTicket > 0) {
        lastBuyPrice = ask;
        buyGridLevel = 0;
        Print("Initial Buy opened at ", ask, " | Ticket: ", buyTicket);
    }
    
    // Open initial Sell position
    ulong sellTicket = OpenPosition(ORDER_TYPE_SELL, InitialLotSize, 0);
    if(sellTicket > 0) {
        lastSellPrice = bid;
        sellGridLevel = 0;
        Print("Initial Sell opened at ", bid, " | Ticket: ", sellTicket);
    }
    
    if(buyTicket > 0 && sellTicket > 0) {
        cycleActive = true;
        highestBasketProfit = 0;
        trailingThreshold = 0;
        
        // Calculate average price for basket
        double avgPrice = (ask + bid) / 2.0;
        g_cycleStartPrice = avgPrice;
        g_cycleStartTime = TimeCurrent();
        
        Print("Cycle activated successfully");
        
        // Log market regime features at basket open
        LogMarketRegimeFeaturesAtOpen(avgPrice);
    }
}

//+------------------------------------------------------------------+
//| Open a new position                                              |
//+------------------------------------------------------------------+
ulong OpenPosition(ENUM_ORDER_TYPE orderType, double lots, int gridLevel) {
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    double price = (orderType == ORDER_TYPE_BUY) ? 
                   SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                   SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeLots(lots);
    request.type = orderType;
    request.price = price;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "Grid_L" + IntegerToString(gridLevel);
    request.type_filling = fillingMode;  // Use detected filling mode
    
    // Try to send order
    if(!OrderSend(request, result)) {
        Print("OrderSend failed: ", GetLastError(), " | ", result.comment);
        
        // If filling mode failed, try alternative mode
        if(result.retcode == TRADE_RETCODE_INVALID_FILL) {
            Print("Trying alternative filling mode...");
            
            // If FOK failed, try IOC
            if(fillingMode == ORDER_FILLING_FOK) {
                request.type_filling = ORDER_FILLING_IOC;
                if(OrderSend(request, result)) {
                    if(result.retcode == TRADE_RETCODE_DONE) {
                        fillingMode = ORDER_FILLING_IOC; // Update global setting
                        Print("Success with IOC filling mode");
                        return result.order;
                    }
                }
            }
            // If IOC failed, try FOK
            else if(fillingMode == ORDER_FILLING_IOC) {
                request.type_filling = ORDER_FILLING_FOK;
                if(OrderSend(request, result)) {
                    if(result.retcode == TRADE_RETCODE_DONE) {
                        fillingMode = ORDER_FILLING_FOK; // Update global setting
                        Print("Success with FOK filling mode");
                        return result.order;
                    }
                }
            }
        }
        
        return 0;
    }
    
    if(result.retcode != TRADE_RETCODE_DONE) {
        Print("Trade failed: ", result.retcode, " | ", result.comment);
        return 0;
    }
    
    return result.order;
}

//+------------------------------------------------------------------+
//| Update position arrays                                           |
//+------------------------------------------------------------------+
void UpdatePositionArrays() {
    ArrayFree(buyPositions);
    ArrayFree(sellPositions);
    
    int buyCount = 0;
    int sellCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        
        PositionInfo pos;
        pos.ticket = ticket;
        pos.lots = PositionGetDouble(POSITION_VOLUME);
        pos.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        pos.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Extract grid level from comment
        string comment = PositionGetString(POSITION_COMMENT);
        pos.gridLevel = ExtractGridLevel(comment);
        
        if(pos.type == POSITION_TYPE_BUY) {
            ArrayResize(buyPositions, buyCount + 1);
            buyPositions[buyCount] = pos;
            buyCount++;
        } else {
            ArrayResize(sellPositions, sellCount + 1);
            sellPositions[sellCount] = pos;
            sellCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Extract grid level from comment                                  |
//+------------------------------------------------------------------+
int ExtractGridLevel(string comment) {
    int pos = StringFind(comment, "Grid_L");
    if(pos >= 0) {
        string levelStr = StringSubstr(comment, pos + 6);
        return (int)StringToInteger(levelStr);
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Check and open grid positions                                    |
//+------------------------------------------------------------------+
void CheckAndOpenGridPositions() {
    // Check ADX filter for grid expansion (more lenient than cycle start)
    if(UseADXFilter && !CheckADXFilter(false)) {
        return; // Market too trending, pause grid expansion
    }
    
    // Check spread filter before opening any grid position
    if(UseSpreadFilter && !CheckSpreadFilter()) {
        return; // Spread too wide, pause grid expansion
    }
    
    // Check market regime filter for grid expansion
    if(UseRegimeFilter && !CheckRegimeFilter(false)) {
        return; // Market regime conditions not met, pause grid expansion
    }
    
    double currentATR = GetCurrentATR();
    if(currentATR <= 0) return;
    
    double gridDistance = CalculateGridDistance(currentATR);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check Buy grid
    if(ArraySize(buyPositions) > 0) {
        double lowestBuyPrice = GetLowestBuyPrice();
        int currentBuyLevel = GetHighestGridLevel(buyPositions);
        
        if(currentBuyLevel < MaxGridLevels && 
           ask <= lowestBuyPrice - gridDistance) {
            
            double newLots = CalculateMartingaleLots(currentBuyLevel + 1);
            ulong ticket = OpenPosition(ORDER_TYPE_BUY, newLots, currentBuyLevel + 1);
            
            if(ticket > 0) {
                Print("Grid Buy Level ", currentBuyLevel + 1, " opened at ", ask, 
                      " | Lots: ", newLots, " | Distance: ", (lowestBuyPrice - ask) / _Point, " points");
            }
        }
    }
    
    // Check Sell grid
    if(ArraySize(sellPositions) > 0) {
        double highestSellPrice = GetHighestSellPrice();
        int currentSellLevel = GetHighestGridLevel(sellPositions);
        
        if(currentSellLevel < MaxGridLevels && 
           bid >= highestSellPrice + gridDistance) {
            
            double newLots = CalculateMartingaleLots(currentSellLevel + 1);
            ulong ticket = OpenPosition(ORDER_TYPE_SELL, newLots, currentSellLevel + 1);
            
            if(ticket > 0) {
                Print("Grid Sell Level ", currentSellLevel + 1, " opened at ", bid, 
                      " | Lots: ", newLots, " | Distance: ", (bid - highestSellPrice) / _Point, " points");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate grid distance based on ATR                             |
//+------------------------------------------------------------------+
double CalculateGridDistance(double atr) {
    double distance = atr * ATR_Multiplier;
    
    // Convert to points and apply min/max filters
    double distancePoints = distance / _Point;
    
    if(distancePoints < MinGridDistancePoints)
        distancePoints = MinGridDistancePoints;
    
    if(distancePoints > MaxGridDistancePoints)
        distancePoints = MaxGridDistancePoints;
    
    return distancePoints * _Point;
}

//+------------------------------------------------------------------+
//| Calculate martingale lot size                                    |
//+------------------------------------------------------------------+
double CalculateMartingaleLots(int level) {
    double lots = InitialLotSize * MathPow(MartingaleMultiplier, level);
    
    if(lots > MaxLotSize)
        lots = MaxLotSize;
    
    return NormalizeLots(lots);
}

//+------------------------------------------------------------------+
//| Get current ATR value                                            |
//+------------------------------------------------------------------+
double GetCurrentATR() {
    if(CopyBuffer(atrHandle, 0, 0, 2, atrBuffer) < 2) {
        Print("Failed to copy ATR buffer");
        return 0;
    }
    return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Calculate total basket profit in dollars                         |
//+------------------------------------------------------------------+
double CalculateBasketProfit() {
    double totalProfit = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        
        totalProfit += PositionGetDouble(POSITION_PROFIT);
        totalProfit += PositionGetDouble(POSITION_SWAP);
    }
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Calculate basket profit in pips                                  |
//+------------------------------------------------------------------+
double CalculateBasketPips() {
    double totalPips = 0;
    double pipValue = GetPipValue();
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double lots = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        double priceDiff = (type == POSITION_TYPE_BUY) ? 
                          (currentPrice - openPrice) : 
                          (openPrice - currentPrice);
        
        totalPips += (priceDiff / pipValue) * lots;
    }
    
    return totalPips;
}

//+------------------------------------------------------------------+
//| Get pip value for the symbol                                     |
//+------------------------------------------------------------------+
double GetPipValue() {
    string symbol = _Symbol;
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // JPY pairs (3 digits)
    if(digits == 3 || StringFind(symbol, "JPY") > 0) {
        return 0.01;
    }
    // Standard forex pairs (5 digits)
    else if(digits == 5) {
        return 0.0001;
    }
    // Metals, indices, crypto
    else if(digits == 2) {
        return 0.01;
    }
    else if(digits == 4) {
        return 0.0001;
    }
    
    // Default
    return MathPow(10, -digits);
}

//+------------------------------------------------------------------+
//| Check if basket take profit is reached                           |
//+------------------------------------------------------------------+
bool CheckBasketTakeProfit(double basketProfit, double basketPips) {
    if(UseDollarTP) {
        if(basketProfit >= BasketProfitDollar) {
            Print("=== Basket Take Profit Reached ===");
            Print("Target: $", BasketProfitDollar, " | Achieved: $", basketProfit);
            return true;
        }
    } else {
        if(basketPips >= BasketProfitPips) {
            Print("=== Basket Take Profit Reached ===");
            Print("Target: ", BasketProfitPips, " pips | Achieved: ", basketPips, " pips");
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update trailing stop                                             |
//+------------------------------------------------------------------+
void UpdateTrailingStop(double basketProfit) {
    if(basketProfit >= TrailingStartDollar) {
        if(basketProfit > highestBasketProfit) {
            highestBasketProfit = basketProfit;
            trailingThreshold = highestBasketProfit - TrailingStepDollar;
        }
        
        if(trailingThreshold > 0 && basketProfit <= trailingThreshold) {
            Print("=== Trailing Stop Triggered ===");
            Print("Highest Profit: $", highestBasketProfit, " | Current: $", basketProfit);
            CloseAllPositions();
            ResetCycle();
        }
    }
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    Print("=== Closing All Positions ===");
    
    // Calculate final basket profit before closing
    double finalProfit = CalculateBasketProfit();
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double avgPrice = (ask + bid) / 2.0;
    
    int closed = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.volume = PositionGetDouble(POSITION_VOLUME);
        request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                       ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = (request.type == ORDER_TYPE_SELL) ? 
                       SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        request.deviation = 10;
        request.magic = MagicNumber;
        request.type_filling = fillingMode;
        
        if(OrderSend(request, result)) {
            if(result.retcode == TRADE_RETCODE_DONE) {
                closed++;
                Print("Position closed: ", ticket);
            } else {
                Print("Failed to close position ", ticket, ": ", result.retcode, " | ", result.comment);
            }
        } else {
            Print("OrderSend failed for closing ", ticket, ": ", GetLastError());
        }
    }
    
    Print("Total positions closed: ", closed);
    
    // Log market regime features at basket close
    string closeReason = (finalProfit >= BasketProfitDollar) ? "Take Profit" : 
                        (finalProfit < -MaxDrawdownDollar) ? "Max Drawdown" : "Manual/Other";
    LogMarketRegimeFeaturesAtClose(avgPrice, finalProfit, closeReason);
}

//+------------------------------------------------------------------+
//| Reset cycle variables                                            |
//+------------------------------------------------------------------+
void ResetCycle() {
    Print("=== Resetting Cycle ===");
    
    cycleActive = false;
    lastBuyPrice = 0;
    lastSellPrice = 0;
    buyGridLevel = 0;
    sellGridLevel = 0;
    highestBasketProfit = 0;
    trailingThreshold = 0;
    
    ArrayFree(buyPositions);
    ArrayFree(sellPositions);
    
    Print("Cycle reset complete. Ready for new cycle.");
}

//+------------------------------------------------------------------+
//| Get lowest buy price                                             |
//+------------------------------------------------------------------+
double GetLowestBuyPrice() {
    if(ArraySize(buyPositions) == 0) return 0;
    
    double lowest = buyPositions[0].openPrice;
    for(int i = 1; i < ArraySize(buyPositions); i++) {
        if(buyPositions[i].openPrice < lowest)
            lowest = buyPositions[i].openPrice;
    }
    return lowest;
}

//+------------------------------------------------------------------+
//| Get highest sell price                                           |
//+------------------------------------------------------------------+
double GetHighestSellPrice() {
    if(ArraySize(sellPositions) == 0) return 0;
    
    double highest = sellPositions[0].openPrice;
    for(int i = 1; i < ArraySize(sellPositions); i++) {
        if(sellPositions[i].openPrice > highest)
            highest = sellPositions[i].openPrice;
    }
    return highest;
}

//+------------------------------------------------------------------+
//| Get highest grid level from position array                       |
//+------------------------------------------------------------------+
int GetHighestGridLevel(PositionInfo &positions[]) {
    if(ArraySize(positions) == 0) return -1;
    
    int highest = positions[0].gridLevel;
    for(int i = 1; i < ArraySize(positions); i++) {
        if(positions[i].gridLevel > highest)
            highest = positions[i].gridLevel;
    }
    return highest;
}

//+------------------------------------------------------------------+
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double NormalizeLots(double lots) {
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(lots < minLot) lots = minLot;
    if(lots > maxLot) lots = maxLot;
    
    lots = MathRound(lots / lotStep) * lotStep;
    
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(StartHour <= EndHour) {
        return (dt.hour >= StartHour && dt.hour <= EndHour);
    } else {
        return (dt.hour >= StartHour || dt.hour <= EndHour);
    }
}

//+------------------------------------------------------------------+
//| Check if trading is allowed                                      |
//+------------------------------------------------------------------+
bool IsTradeAllowed() {
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        return false;
    }
    
    if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) {
        return false;
    }
    
    if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Load broker settings dynamically                                 |
//+------------------------------------------------------------------+
void LoadBrokerSettings() {
    // Get symbol properties
    brokerMinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    brokerMaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    brokerLotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    brokerStopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    brokerSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    brokerDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    // Get broker/server name
    brokerName = AccountInfoString(ACCOUNT_COMPANY);
    
    // Detect and set the appropriate filling mode
    fillingMode = GetFillingMode();
}

//+------------------------------------------------------------------+
//| Detect the appropriate filling mode for the symbol              |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode() {
    // Get symbol filling modes
    int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    
    // Check supported filling modes in order of preference
    // FOK (Fill or Kill) - preferred for most brokers
    if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
        Print("Filling Mode: FOK (Fill or Kill)");
        return ORDER_FILLING_FOK;
    }
    // IOC (Immediate or Cancel) - common for ECN brokers and crypto
    else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
        Print("Filling Mode: IOC (Immediate or Cancel)");
        return ORDER_FILLING_IOC;
    }
    
    // Default fallback to FOK
    Print("Filling Mode: FOK (Default Fallback)");
    return ORDER_FILLING_FOK;
}

//+------------------------------------------------------------------+
//| Print broker information                                         |
//+------------------------------------------------------------------+
void PrintBrokerInfo() {
    Print("========== BROKER INFORMATION ==========");
    Print("Broker: ", brokerName);
    Print("Account Type: ", AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "LIVE");
    Print("Symbol: ", _Symbol);
    Print("Digits: ", brokerDigits);
    Print("Min Lot: ", brokerMinLot);
    Print("Max Lot: ", brokerMaxLot);
    Print("Lot Step: ", brokerLotStep);
    Print("Stop Level: ", brokerStopLevel, " points");
    Print("Current Spread: ", brokerSpread, " points");
    Print("Tick Value: ", tickValue);
    Print("Tick Size: ", tickSize);
    Print("Point Value: ", _Point);
    
    // Print filling modes
    int filling = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    string fillingModes = "Supported Filling Modes: ";
    if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) fillingModes += "FOK ";
    if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) fillingModes += "IOC ";
    Print(fillingModes);
    
    Print("Leverage: 1:", AccountInfoInteger(ACCOUNT_LEVERAGE));
    Print("Balance: ", AccountInfoDouble(ACCOUNT_BALANCE), " ", AccountInfoString(ACCOUNT_CURRENCY));
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Initialize dynamic parameters based on broker settings           |
//+------------------------------------------------------------------+
void InitializeDynamicParameters() {
    // Auto-calculate initial lot size
    if(AutoCalculateLotSize) {
        InitialLotSize = CalculateOptimalLotSize();
        Print("Auto-calculated Initial Lot: ", InitialLotSize);
    } else {
        InitialLotSize = ManualLotSize;
        // Ensure it's within broker limits
        if(InitialLotSize < brokerMinLot) {
            InitialLotSize = brokerMinLot;
            Print("WARNING: Manual lot adjusted to broker minimum: ", InitialLotSize);
        }
        if(InitialLotSize > brokerMaxLot) {
            InitialLotSize = brokerMaxLot;
            Print("WARNING: Manual lot adjusted to broker maximum: ", InitialLotSize);
        }
    }
    
    // Auto-calculate max lot size
    if(AutoCalculateMaxLot) {
        // Set to broker max or reasonable limit based on account
        double accountBasedMaxLot = CalculateMaxLotBasedOnAccount();
        MaxLotSize = MathMin(brokerMaxLot, accountBasedMaxLot);
        Print("Auto-calculated Max Lot: ", MaxLotSize);
    } else {
        MaxLotSize = ManualMaxLotSize;
        if(MaxLotSize > brokerMaxLot) {
            MaxLotSize = brokerMaxLot;
            Print("WARNING: Max lot adjusted to broker maximum: ", MaxLotSize);
        }
    }
    
    // Auto-calculate grid distances
    if(AutoCalculateGridDistance) {
        CalculateDynamicGridDistances();
        Print("Auto-calculated Grid Distance: ", MinGridDistancePoints, "-", MaxGridDistancePoints, " points");
    } else {
        MinGridDistancePoints = ManualMinGridDistancePoints;
        MaxGridDistancePoints = ManualMaxGridDistancePoints;
        
        // Ensure minimum distance respects broker's stop level
        if(brokerStopLevel > 0 && MinGridDistancePoints < brokerStopLevel * 2) {
            MinGridDistancePoints = brokerStopLevel * 2;
            Print("WARNING: Min grid distance adjusted to respect stop level: ", MinGridDistancePoints);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate optimal lot size based on account balance              |
//+------------------------------------------------------------------+
double CalculateOptimalLotSize() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPercentPerCycle / 100.0);
    
    // Calculate based on potential drawdown
    // Estimate: MaxGridLevels with martingale can create significant exposure
    double totalLotsAtMaxGrid = 0;
    for(int i = 0; i <= MaxGridLevels; i++) {
        totalLotsAtMaxGrid += MathPow(MartingaleMultiplier, i);
    }
    
    // Conservative calculation: divide risk by potential total exposure
    double calculatedLot = riskAmount / (totalLotsAtMaxGrid * 1000 * tickValue);
    
    // Apply broker constraints
    calculatedLot = NormalizeLots(calculatedLot);
    
    // Ensure minimum
    if(calculatedLot < brokerMinLot) {
        calculatedLot = brokerMinLot;
    }
    
    // Conservative cap for safety
    double conservativeMax = balance / 10000; // Very conservative
    if(calculatedLot > conservativeMax) {
        calculatedLot = NormalizeLots(conservativeMax);
    }
    
    return calculatedLot;
}

//+------------------------------------------------------------------+
//| Calculate maximum lot size based on account                      |
//+------------------------------------------------------------------+
double CalculateMaxLotBasedOnAccount() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    // Calculate based on margin requirements
    double marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
    if(marginRequired == 0) marginRequired = 1000; // Default fallback
    
    // Max lot that doesn't exceed 50% of free margin
    double maxByMargin = (freeMargin * 0.5) / marginRequired;
    
    // Max lot based on balance (conservative)
    double maxByBalance = balance / 1000;
    
    // Take the smaller value and normalize
    double calculatedMax = MathMin(maxByMargin, maxByBalance);
    calculatedMax = NormalizeLots(calculatedMax);
    
    // Ensure reasonable limits
    if(calculatedMax < 0.1) calculatedMax = 0.1;
    if(calculatedMax > 50.0) calculatedMax = 50.0;
    
    return calculatedMax;
}

//+------------------------------------------------------------------+
//| Calculate dynamic grid distances based on symbol volatility      |
//+------------------------------------------------------------------+
void CalculateDynamicGridDistances() {
    // Get current ATR
    double currentATR = GetCurrentATR();
    if(currentATR <= 0) {
        // Fallback to percentage of price
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        currentATR = price * 0.001; // 0.1% of price as fallback
    }
    
    // Convert ATR to points
    double atrPoints = currentATR / _Point;
    
    // Set minimum to ATR * 0.5 or broker stop level (whichever is higher)
    MinGridDistancePoints = MathMax(atrPoints * 0.5, brokerStopLevel * 2);
    
    // Ensure minimum is reasonable (at least 10 points or 2x spread)
    MinGridDistancePoints = MathMax(MinGridDistancePoints, MathMax(10, brokerSpread * 2));
    
    // Set maximum to ATR * 3
    MaxGridDistancePoints = atrPoints * 3;
    
    // Ensure max is at least 2x min
    if(MaxGridDistancePoints < MinGridDistancePoints * 2) {
        MaxGridDistancePoints = MinGridDistancePoints * 2;
    }
    
    // Round to nice numbers
    MinGridDistancePoints = MathRound(MinGridDistancePoints / 10) * 10;
    MaxGridDistancePoints = MathRound(MaxGridDistancePoints / 10) * 10;
}

//+------------------------------------------------------------------+
//| Check ADX filter for trend detection                             |
//+------------------------------------------------------------------+
bool CheckADXFilter(bool isNewCycle) {
    // Copy ADX buffers
    if(CopyBuffer(adxHandle, 0, 0, 3, adxBuffer) < 3) {
        Print("Failed to copy ADX buffer");
        return true; // Allow trade if indicator fails (fail-safe)
    }
    
    if(CopyBuffer(adxHandle, 1, 0, 3, plusDIBuffer) < 3) {
        Print("Failed to copy +DI buffer");
        return true;
    }
    
    if(CopyBuffer(adxHandle, 2, 0, 3, minusDIBuffer) < 3) {
        Print("Failed to copy -DI buffer");
        return true;
    }
    
    double currentADX = adxBuffer[0];
    double previousADX = adxBuffer[1];
    double plusDI = plusDIBuffer[0];
    double minusDI = minusDIBuffer[0];
    
    // Use stricter threshold for new cycle, more lenient for grid expansion
    double adxThreshold = isNewCycle ? MaxADX_ForEntry : MaxADX_ForGrid;
    
    // Check if ADX is below threshold (indicating ranging market)
    if(currentADX > adxThreshold) {
        if(isNewCycle) {
            Print("ADX Filter: Market too trending for new cycle. ADX: ", 
                  DoubleToString(currentADX, 2), " > ", DoubleToString(adxThreshold, 2));
        }
        return false;
    }
    
    // Additional check: ADX should not be rapidly rising (prevents entering before breakout)
    double adxChange = currentADX - previousADX;
    if(adxChange > 3.0 && currentADX > adxThreshold * 0.8) {
        if(isNewCycle) {
            Print("ADX Filter: ADX rising too fast. Change: +", DoubleToString(adxChange, 2));
        }
        return false;
    }
    
    // Log successful filter pass for new cycles
    if(isNewCycle) {
        Print("ADX Filter: PASSED - Ranging market detected. ADX: ", DoubleToString(currentADX, 2),
              " | +DI: ", DoubleToString(plusDI, 2), " | -DI: ", DoubleToString(minusDI, 2));
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update spread history for averaging                              |
//+------------------------------------------------------------------+
void UpdateSpreadHistory() {
    // Get current spread in points
    long currentSpreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    
    // Update circular buffer
    spreadHistory[spreadHistoryIndex] = (double)currentSpreadPoints;
    spreadHistoryIndex = (spreadHistoryIndex + 1) % SpreadAveragePeriod;
}

//+------------------------------------------------------------------+
//| Check spread filter                                              |
//+------------------------------------------------------------------+
bool CheckSpreadFilter() {
    // Get current spread
    long currentSpreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    
    // Check absolute maximum if set
    if(MaxSpreadPoints > 0 && currentSpreadPoints > MaxSpreadPoints) {
        Print("Spread Filter: BLOCKED - Spread too high. Current: ", currentSpreadPoints, 
              " points > Max: ", MaxSpreadPoints, " points");
        return false;
    }
    
    // Calculate average spread from history
    double averageSpread = 0;
    int validCount = 0;
    
    for(int i = 0; i < SpreadAveragePeriod; i++) {
        if(spreadHistory[i] > 0) {
            averageSpread += spreadHistory[i];
            validCount++;
        }
    }
    
    if(validCount > 0) {
        averageSpread = averageSpread / validCount;
    } else {
        // No history yet, use current as baseline
        averageSpread = (double)currentSpreadPoints;
    }
    
    // Check if current spread exceeds multiplier threshold
    double maxAllowedSpread = averageSpread * MaxSpreadMultiplier;
    
    if(currentSpreadPoints > maxAllowedSpread) {
        Print("Spread Filter: BLOCKED - Spread spike detected. Current: ", currentSpreadPoints, 
              " points | Average: ", DoubleToString(averageSpread, 1), 
              " | Max Allowed: ", DoubleToString(maxAllowedSpread, 1), " points");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get current ADX value (utility function)                         |
//+------------------------------------------------------------------+
double GetCurrentADX() {
    if(CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) < 1) {
        return 0;
    }
    return adxBuffer[0];
}

//+------------------------------------------------------------------+
//| Check market regime filter (Returns Skew & Volume Ratio)         |
//+------------------------------------------------------------------+
bool CheckRegimeFilter(bool isNewCycle) {
    // Compute all market features
    double features[];
    if(!ComputeAllFeatures(features)) {
        Print("⚠️ Failed to compute market regime features for filter check");
        return true; // Allow trade if computation fails (fail-safe)
    }
    
    // Extract the features we need:
    // features[10] = returns_skew
    // features[11] = volume_ratio
    double returnsSkew = features[10];
    double volumeRatio = features[11];
    
    // Check if conditions are met
    bool skewPass = returnsSkew > MinReturnsSkew;
    bool volRatioPass = volumeRatio > MinVolumeRatio;
    
    // Both conditions must pass
    if(!skewPass || !volRatioPass) {
        if(isNewCycle) {
            Print("Regime Filter: BLOCKED - Conditions not met");
            Print("   Returns Skew: ", DoubleToString(returnsSkew, 4), 
                  (skewPass ? " ✅ PASS" : " ❌ FAIL"), " (Min: ", DoubleToString(MinReturnsSkew, 3), ")");
            Print("   Volume Ratio: ", DoubleToString(volumeRatio, 4), 
                  (volRatioPass ? " ✅ PASS" : " ❌ FAIL"), " (Min: ", DoubleToString(MinVolumeRatio, 3), ")");
        }
        return false;
    }
    
    // Log successful filter pass for new cycles
    if(isNewCycle) {
        Print("Regime Filter: ✅ PASSED");
        Print("   Returns Skew: ", DoubleToString(returnsSkew, 4), " > ", DoubleToString(MinReturnsSkew, 3));
        Print("   Volume Ratio: ", DoubleToString(volumeRatio, 4), " > ", DoubleToString(MinVolumeRatio, 3));
    }
    
    return true;
}
//+------------------------------------------------------------------+
