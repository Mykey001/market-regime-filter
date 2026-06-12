//+------------------------------------------------------------------+
//|                                               HybridGridBot.mq5  |
//|                        High-Frequency Scalping Grid Bot          |
//|                     Hybrid Grid + Trend Filter + Async Execution |
//+------------------------------------------------------------------+
#property copyright "HybridGridBot"
#property link      ""
#property version   "1.1"
#property strict

#include "RegimeFilterLib.mqh"  // ML Regime Filter Integration

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// Grid Settings
input double   GridStepPoints = 100;           // Grid step in points
input double   InitialLotSize = 0.01;          // Starting lot size
input double   MartingaleMultiplier = 1.5;     // Lot multiplier per level
input int      MaxGridLevels = 10;             // Maximum grid positions

// Profit Settings
input double   TargetProfitUSD = 5.0;          // Basket profit target ($)

// Risk Settings
input double   MaxDrawdownPercent = 20.0;      // Max drawdown before stop (%)
input int      DrawdownSleepMinutes = 60;      // Sleep time after max drawdown (minutes)

// QQE Indicator Settings (Primary Trend Filter)
input int      QQE_RSI_Period = 14;            // RSI period for QQE calculation
input int      QQE_Smoothing = 5;              // Wilders smoothing factor
input double   QQE_ATR_Multiplier = 4.236;     // ATR multiplier for trailing bands
input double   QQE_MidlineThreshold = 5.0;     // Threshold around 50 mid-line (no trade zone)
input bool     QQE_EnableEarlyExit = true;     // Enable early exit on QQE reversal
input double   QQE_ReversalThreshold = 10.0;   // QQE movement toward 50 to trigger warning (%)

// RSIH Settings (Ehlers Hann-Windowed RSI - TASC Jan 2022)
input bool     UseRSIH = true;                 // Use RSIH instead of standard RSI
input int      RSIH_Period = 14;               // RSIH calculation period

// ADX Smoothed Settings (Range/Trend Strength Filter)
input bool     UseADXFilter = true;            // Enable ADX filter for entries
input int      ADX_Period = 14;                // ADX calculation period
input int      ADX_Smoothing = 5;              // ADX smoothing period (SMA)
input double   ADX_MaxThreshold = 20.0;        // Maximum ADX for entry (low volatility/range)

// TMA Slope Settings (Secondary/Optional Confirmation)
input bool     UseTMAConfirmation = false;     // Use TMA as secondary filter
input int      TMA_Period = 20;                // TMA calculation period
input double   TMA_SlopeThreshold = 0.0001;    // Minimum slope for signal

// Support/Resistance Zone Settings
input bool     UseSRZones = true;              // Enable S/R zone bias
input int      SR_LookbackBars = 100;          // Bars to look back for S/R detection
input int      SR_TouchCount = 2;              // Minimum touches to confirm zone
input double   SR_ZoneWidth = 50;              // Zone width in points
input double   SR_BuyBias = 0.7;               // Buy probability near support (0.5-1.0)
input double   SR_SellBias = 0.7;              // Sell probability near resistance (0.5-1.0)
input double   SR_MixRatio = 0.3;              // Counter-trend mix ratio (0.0-0.5)

// Order Flow & Order Book Settings
input bool     UseOrderFlow = true;            // Enable Order Flow analysis
input int      OrderBookDepth = 10;            // Number of order book levels to analyze
input int      DeltaVolumePeriod = 100;        // Period for cumulative delta calculation
input double   ImbalanceThreshold = 0.3;       // Minimum imbalance to consider significant (0-1)
input double   PressureWeight_VWOI = 0.4;      // Weight for Volume-Weighted Imbalance
input double   PressureWeight_Delta = 0.4;     // Weight for Delta Volume
input double   PressureWeight_Absorption = 0.2;// Weight for Absorption Rate
input int      ImbalanceEMA_Period = 100;      // EMA period for imbalance momentum
input double   MinPressureIndex = 0.2;         // Minimum pressure index to allow entry

// Fibonacci Retracement Settings
input bool     UseFibonacci = true;              // Enable Fibonacci filter
input int      Fib_SwingLookback = 50;           // Bars to look back for swing detection
input int      Fib_MinSwingBars = 5;             // Minimum bars between swings
input bool     Fib_AnchorGridLevels = true;      // Anchor grid to Fib levels
input bool     Fib_BlockBeyond786 = true;        // Block entries beyond 78.6% level
input double   Fib_EntryZoneMin = 38.2;          // Minimum Fib level for entry (%)
input double   Fib_EntryZoneMax = 78.6;          // Maximum Fib level for entry (%)
input bool     Fib_ShowOnChart = true;           // Draw Fib levels on chart

// System Settings
input int      MagicNumber = 123456;           // Unique identifier
input bool     ShowBasketOnChart = true;       // Display basket profit on chart

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+

struct GridPosition
{
    ulong              ticket;      // Position ticket
    double             lotSize;     // Position volume
    double             openPrice;   // Entry price
    int                gridLevel;   // Grid level (1, 2, 3...)
    ENUM_POSITION_TYPE type;        // Buy or Sell
};

struct GridState
{
    GridPosition       positions[];  // Array of tracked positions
    int                currentLevel; // Current grid depth
    double             lastGridPrice;// Price of last grid entry
    bool               isActive;     // Grid currently running
    ENUM_POSITION_TYPE direction;    // Buy or Sell grid
};

// QQE Indicator State
struct QQEState
{
    double qqeLine;           // Current QQE line value (smoothed RSI)
    double qqeLinePrev;       // Previous QQE line value
    double trailingBandUp;    // Upper trailing band
    double trailingBandDown;  // Lower trailing band
    double smoothedATR;       // Smoothed ATR for band calculation
    double rsiATR;            // ATR of RSI values
    int    signal;            // Current signal: 1=Bullish, -1=Bearish, 0=Neutral
    int    biasedSignal;      // Signal after S/R zone bias applied
    int    histogram;         // Histogram color: 1=Blue(Buy), -1=Red(Sell)
    bool   crossedBandUp;     // QQE crossed above upper band
    bool   crossedBandDown;   // QQE crossed below lower band
    double rsihValue;         // Current RSIH value (Ehlers Hann-windowed RSI)
    double rsihPrev;          // Previous RSIH value for momentum detection
};

// ADX Indicator State
struct ADXState
{
    double adxValue;          // Current ADX value (smoothed)
    double plusDI;            // Current +DI value
    double minusDI;           // Current -DI value
    bool   allowEntry;        // True if ADX < threshold (range condition)
};

// Support/Resistance Zone State
struct SRZoneState
{
    double supportLevel;      // Detected support price level
    double resistanceLevel;   // Detected resistance price level
    double supportStrength;   // Support zone strength (touch count)
    double resistanceStrength;// Resistance zone strength (touch count)
    bool   nearSupport;       // Price is near support zone
    bool   nearResistance;    // Price is near resistance zone
    int    zoneBias;          // Current zone bias: 1=Buy bias, -1=Sell bias, 0=Neutral
};

// Order Book Level
struct OrderBookLevel
{
    double price;             // Price level
    double volume;            // Volume at this level
    int    levelIndex;        // Distance from best bid/ask (1, 2, 3...)
};

// Order Flow State
struct OrderFlowState
{
    // Order Book Data
    OrderBookLevel bidLevels[10];     // Bid side depth (up to 10 levels)
    OrderBookLevel askLevels[10];     // Ask side depth (up to 10 levels)
    int            bidLevelCount;     // Number of valid bid levels
    int            askLevelCount;     // Number of valid ask levels
    
    // Imbalance Metrics
    double staticImbalance;           // Simple bid/ask volume imbalance (-1 to +1)
    double volumeWeightedImbalance;   // VWOI: Distance-weighted imbalance
    double imbalanceMomentum;         // Change in imbalance vs EMA
    double imbalanceEMA;              // EMA of imbalance for momentum calculation
    
    // Delta Volume (Executed Aggression)
    double cumulativeDelta;           // Running sum of buy - sell market orders
    double normalizedDelta;           // Delta / Total Volume
    double lastTradePrice;            // Last trade price for delta calculation
    double totalVolume;               // Total volume for normalization
    
    // Absorption Rate
    double bidAbsorptionRate;         // Rate of bid liquidity depletion
    double askAbsorptionRate;         // Rate of ask liquidity depletion
    double prevBidLevel1Volume;       // Previous volume at best bid
    double prevAskLevel1Volume;       // Previous volume at best ask
    datetime lastAbsorptionUpdate;    // Last time absorption was calculated
    
    // Composite Metrics
    double pressureIndex;             // Combined pressure indicator
    double adjustedImbalance;         // Imbalance adjusted for spread
    int    marketDirection;           // Who is winning: 1=Buyers, -1=Sellers, 0=Neutral
    
    // Spread Normalization
    double currentSpread;             // Current bid-ask spread
    double atr14;                     // ATR(14) for spread normalization
    
    // Signal
    bool   allowBuy;                  // Order flow allows buy entry
    bool   allowSell;                 // Order flow allows sell entry
};

// Fibonacci State
struct FibonacciState
{
    // Swing Points
    double swingHigh;              // Last significant swing high
    double swingLow;               // Last significant swing low
    datetime swingHighTime;        // Time of swing high
    datetime swingLowTime;         // Time of swing low
    int swingHighBar;              // Bar index of swing high
    int swingLowBar;               // Bar index of swing low
    
    // Fibonacci Levels (calculated from swing range)
    double fib_0;                  // 0% (swing extreme)
    double fib_236;                // 23.6% retracement
    double fib_382;                // 38.2% retracement
    double fib_50;                 // 50% retracement
    double fib_618;                // 61.8% retracement
    double fib_786;                // 78.6% retracement
    double fib_100;                // 100% (opposite swing)
    
    // Extension Levels
    double fib_1272;               // 127.2% extension
    double fib_1618;               // 161.8% extension
    
    // State
    bool isValid;                  // Fib levels are valid
    bool isUptrend;                // True if retracing from high, false if from low
    double currentFibLevel;        // Current price as Fib % (0-100)
    bool inEntryZone;              // Price is in valid entry zone
    bool beyondSafetyLevel;        // Price beyond 78.6% (danger zone)
    
    // Grid Anchoring
    double gridLevel1Price;        // Fib-anchored grid level 1
    double gridLevel2Price;        // Fib-anchored grid level 2
    double gridLevel3Price;        // Fib-anchored grid level 3
    double gridLevel4Price;        // Fib-anchored grid level 4
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+

GridState g_gridState;              // Main grid state
QQEState  g_qqeState;               // QQE indicator state
ADXState  g_adxState;               // ADX indicator state
SRZoneState g_srState;              // Support/Resistance zone state
OrderFlowState g_orderFlowState;    // Order flow and order book state
FibonacciState g_fibState;          // Fibonacci state
double    g_peakEquity;             // Peak equity for drawdown calculation
bool      g_emergencyStop;          // Emergency stop flag
datetime  g_sleepUntil;             // Sleep until this time after drawdown hit
bool      g_pendingRetry;           // Pending order retry flag
MqlTradeRequest g_retryRequest;     // Request to retry
bool      g_isSleeping;             // Sleep mode after drawdown hit
datetime  g_sleepStartTime;         // When sleep period started
int       g_drawdownSleepMinutes;   // Validated sleep duration

// Order Flow validated parameters
bool   g_useOrderFlow;
int    g_orderBookDepth;
int    g_deltaVolumePeriod;
double g_imbalanceThreshold;
double g_pressureWeightVWOI;
double g_pressureWeightDelta;
double g_pressureWeightAbsorption;
int    g_imbalanceEMAPeriod;
double g_minPressureIndex;

// Default parameter values for validation
const double DEFAULT_GRID_STEP = 100;
const double DEFAULT_LOT_SIZE = 0.01;
const double DEFAULT_MARTINGALE = 1.5;
const int    DEFAULT_MAX_LEVELS = 10;
const double DEFAULT_TARGET_PROFIT = 5.0;
const double DEFAULT_MAX_DRAWDOWN = 20.0;
const int    DEFAULT_DRAWDOWN_SLEEP = 60;
const int    DEFAULT_TMA_PERIOD = 20;
const double DEFAULT_TMA_THRESHOLD = 0.0001;

// QQE Default parameter values
const int    DEFAULT_QQE_RSI_PERIOD = 14;
const int    DEFAULT_QQE_SMOOTHING = 5;
const double DEFAULT_QQE_ATR_MULT = 4.236;
const double DEFAULT_QQE_MIDLINE_THRESHOLD = 5.0;
const double DEFAULT_QQE_REVERSAL_THRESHOLD = 10.0;

// RSIH Default parameter values
const int    DEFAULT_RSIH_PERIOD = 14;

// ADX Default parameter values
const int    DEFAULT_ADX_PERIOD = 14;
const int    DEFAULT_ADX_SMOOTHING = 5;
const double DEFAULT_ADX_MAX_THRESHOLD = 20.0;

// S/R Zone Default parameter values
const int    DEFAULT_SR_LOOKBACK = 100;
const int    DEFAULT_SR_TOUCH_COUNT = 2;
const double DEFAULT_SR_ZONE_WIDTH = 50;
const double DEFAULT_SR_BUY_BIAS = 0.7;
const double DEFAULT_SR_SELL_BIAS = 0.7;
const double DEFAULT_SR_MIX_RATIO = 0.3;

// Order Flow Default parameter values
const int    DEFAULT_ORDER_BOOK_DEPTH = 10;
const int    DEFAULT_DELTA_VOLUME_PERIOD = 100;
const double DEFAULT_IMBALANCE_THRESHOLD = 0.3;
const double DEFAULT_PRESSURE_WEIGHT_VWOI = 0.4;
const double DEFAULT_PRESSURE_WEIGHT_DELTA = 0.4;
const double DEFAULT_PRESSURE_WEIGHT_ABSORPTION = 0.2;
const int    DEFAULT_IMBALANCE_EMA_PERIOD = 100;
const double DEFAULT_MIN_PRESSURE_INDEX = 0.2;

// Validated parameters (after bounds checking)
double g_gridStepPoints;
double g_initialLotSize;
double g_martingaleMultiplier;
int    g_maxGridLevels;
double g_targetProfitUSD;
double g_maxDrawdownPercent;
int    g_tmaPeriod;
double g_tmaSlopeThreshold;
bool   g_useTMAConfirmation;

// Validated QQE parameters
int    g_qqeRSIPeriod;
int    g_qqeSmoothing;
double g_qqeATRMultiplier;
double g_qqeMidlineThreshold;
bool   g_qqeEnableEarlyExit;
double g_qqeReversalThreshold;

// Validated RSIH parameters
bool   g_useRSIH;
int    g_rsihPeriod;

// Validated ADX parameters
bool   g_useADXFilter;
int    g_adxPeriod;
int    g_adxSmoothing;
double g_adxMaxThreshold;

// Validated S/R Zone parameters
bool   g_useSRZones;
int    g_srLookbackBars;
int    g_srTouchCount;
double g_srZoneWidth;
double g_srBuyBias;
double g_srSellBias;
double g_srMixRatio;

// Validated Fibonacci parameters
bool   g_useFibonacci;
int    g_fibSwingLookback;
int    g_fibMinSwingBars;
bool   g_fibAnchorGridLevels;
bool   g_fibBlockBeyond786;
double g_fibEntryZoneMin;
double g_fibEntryZoneMax;
bool   g_fibShowOnChart;

//+------------------------------------------------------------------+
//| Fibonacci Functions                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Find Last Swing High                                              |
//+------------------------------------------------------------------+

// ==================== ML Regime Filter Settings ====================
input bool     EnableRegimeFilter = true;      // Enable ML regime filter
input string   RegimeFilterHost = "127.0.0.1"; // Python GUI host  
input int      RegimeFilterPort = 9090;        // Python GUI port
// ====================================================================

bool FindSwingHigh(double &price, datetime &time, int &barIndex)
{
    int minBars = g_fibMinSwingBars;
    double highestHigh = 0;
    int highestBar = -1;
    
    for(int i = minBars; i < g_fibSwingLookback; i++)
    {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        bool isSwingHigh = true;
        
        // Check if this is a local high (higher than neighbors)
        for(int j = 1; j <= minBars; j++)
        {
            if(i - j < 0) continue;
            if(high <= iHigh(_Symbol, PERIOD_CURRENT, i - j) ||
               high <= iHigh(_Symbol, PERIOD_CURRENT, i + j))
            {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh && high > highestHigh)
        {
            highestHigh = high;
            highestBar = i;
        }
    }
    
    if(highestBar >= 0)
    {
        price = highestHigh;
        time = iTime(_Symbol, PERIOD_CURRENT, highestBar);
        barIndex = highestBar;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Find Last Swing Low                                               |
//+------------------------------------------------------------------+
bool FindSwingLow(double &price, datetime &time, int &barIndex)
{
    int minBars = g_fibMinSwingBars;
    double lowestLow = DBL_MAX;
    int lowestBar = -1;
    
    for(int i = minBars; i < g_fibSwingLookback; i++)
    {
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        bool isSwingLow = true;
        
        // Check if this is a local low (lower than neighbors)
        for(int j = 1; j <= minBars; j++)
        {
            if(i - j < 0) continue;
            if(low >= iLow(_Symbol, PERIOD_CURRENT, i - j) ||
               low >= iLow(_Symbol, PERIOD_CURRENT, i + j))
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow && low < lowestLow)
        {
            lowestLow = low;
            lowestBar = i;
        }
    }
    
    if(lowestBar >= 0)
    {
        price = lowestLow;
        time = iTime(_Symbol, PERIOD_CURRENT, lowestBar);
        barIndex = lowestBar;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Initialize Fibonacci State                                        |
//+------------------------------------------------------------------+
void InitializeFibonacci()
{
    g_fibState.swingHigh = 0;
    g_fibState.swingLow = 0;
    g_fibState.swingHighTime = 0;
    g_fibState.swingLowTime = 0;
    g_fibState.swingHighBar = 0;
    g_fibState.swingLowBar = 0;
    g_fibState.isValid = false;
    g_fibState.isUptrend = false;
    g_fibState.currentFibLevel = 0;
    g_fibState.inEntryZone = false;
    g_fibState.beyondSafetyLevel = false;
    
    // Initial calculation
    if(g_useFibonacci)
        UpdateFibonacciLevels();
}

//+------------------------------------------------------------------+
//| Update Fibonacci Levels                                           |
//+------------------------------------------------------------------+
void UpdateFibonacciLevels()
{
    // Find swing points
    double swingHigh, swingLow;
    datetime swingHighTime, swingLowTime;
    int swingHighBar, swingLowBar;
    
    bool foundHigh = FindSwingHigh(swingHigh, swingHighTime, swingHighBar);
    bool foundLow = FindSwingLow(swingLow, swingLowTime, swingLowBar);
    
    if(!foundHigh || !foundLow)
    {
        g_fibState.isValid = false;
        return;
    }
    
    // Store swing points
    g_fibState.swingHigh = swingHigh;
    g_fibState.swingLow = swingLow;
    g_fibState.swingHighTime = swingHighTime;
    g_fibState.swingLowTime = swingLowTime;
    g_fibState.swingHighBar = swingHighBar;
    g_fibState.swingLowBar = swingLowBar;
    
    // Determine trend direction (which swing is more recent)
    g_fibState.isUptrend = (swingHighBar < swingLowBar);
    
    double range = swingHigh - swingLow;
    
    if(g_fibState.isUptrend)
    {
        // Retracing from high (bearish retracement in uptrend)
        g_fibState.fib_0 = swingHigh;
        g_fibState.fib_100 = swingLow;
        g_fibState.fib_236 = swingHigh - (range * 0.236);
        g_fibState.fib_382 = swingHigh - (range * 0.382);
        g_fibState.fib_50 = swingHigh - (range * 0.50);
        g_fibState.fib_618 = swingHigh - (range * 0.618);
        g_fibState.fib_786 = swingHigh - (range * 0.786);
        
        // Extensions
        g_fibState.fib_1272 = swingHigh + (range * 0.272);
        g_fibState.fib_1618 = swingHigh + (range * 0.618);
    }
    else
    {
        // Retracing from low (bullish retracement in downtrend)
        g_fibState.fib_0 = swingLow;
        g_fibState.fib_100 = swingHigh;
        g_fibState.fib_236 = swingLow + (range * 0.236);
        g_fibState.fib_382 = swingLow + (range * 0.382);
        g_fibState.fib_50 = swingLow + (range * 0.50);
        g_fibState.fib_618 = swingLow + (range * 0.618);
        g_fibState.fib_786 = swingLow + (range * 0.786);
        
        // Extensions
        g_fibState.fib_1272 = swingLow - (range * 0.272);
        g_fibState.fib_1618 = swingLow - (range * 0.618);
    }
    
    g_fibState.isValid = true;
    
    // Calculate current Fib level
    CalculateCurrentFibLevel();
    
    // Anchor grid levels if enabled
    if(g_fibAnchorGridLevels)
        AnchorGridLevelsToFib();
}

//+------------------------------------------------------------------+
//| Calculate Current Fibonacci Level (where price is now)            |
//+------------------------------------------------------------------+
void CalculateCurrentFibLevel()
{
    if(!g_fibState.isValid)
        return;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double range = g_fibState.swingHigh - g_fibState.swingLow;
    
    if(range == 0)
    {
        g_fibState.currentFibLevel = 0;
        return;
    }
    
    if(g_fibState.isUptrend)
    {
        // Calculate % retracement from high
        g_fibState.currentFibLevel = ((g_fibState.swingHigh - currentPrice) / range) * 100.0;
    }
    else
    {
        // Calculate % retracement from low
        g_fibState.currentFibLevel = ((currentPrice - g_fibState.swingLow) / range) * 100.0;
    }
    
    // Check if in entry zone
    g_fibState.inEntryZone = (g_fibState.currentFibLevel >= g_fibEntryZoneMin &&
                               g_fibState.currentFibLevel <= g_fibEntryZoneMax);
    
    // Check if beyond safety level
    g_fibState.beyondSafetyLevel = (g_fibState.currentFibLevel > 78.6);
}

//+------------------------------------------------------------------+
//| Anchor Grid Levels to Fibonacci Prices                            |
//+------------------------------------------------------------------+
void AnchorGridLevelsToFib()
{
    if(!g_fibState.isValid)
        return;
    
    // Anchor grid levels to key Fib retracement levels
    if(g_fibState.isUptrend)
    {
        // For uptrend retracement (buy setups)
        g_fibState.gridLevel1Price = g_fibState.fib_382;
        g_fibState.gridLevel2Price = g_fibState.fib_50;
        g_fibState.gridLevel3Price = g_fibState.fib_618;
        g_fibState.gridLevel4Price = g_fibState.fib_786;
    }
    else
    {
        // For downtrend retracement (sell setups)
        g_fibState.gridLevel1Price = g_fibState.fib_382;
        g_fibState.gridLevel2Price = g_fibState.fib_50;
        g_fibState.gridLevel3Price = g_fibState.fib_618;
        g_fibState.gridLevel4Price = g_fibState.fib_786;
    }
}

//+------------------------------------------------------------------+
//| Get Grid Entry Price (Fib-anchored or distance-based)             |
//+------------------------------------------------------------------+
double GetGridEntryPrice(int gridLevel)
{
    // If Fib anchoring is enabled and valid, use Fib levels
    if(g_useFibonacci && g_fibAnchorGridLevels && g_fibState.isValid)
    {
        switch(gridLevel)
        {
            case 1: return g_fibState.gridLevel1Price;
            case 2: return g_fibState.gridLevel2Price;
            case 3: return g_fibState.gridLevel3Price;
            case 4: return g_fibState.gridLevel4Price;
            default: break;
        }
    }
    
    return 0; // 0 means use current market price
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels on Chart                                    |
//+------------------------------------------------------------------+
void DrawFibonacciLevels()
{
    if(!g_fibShowOnChart || !g_fibState.isValid)
    {
        ObjectDelete(0, "Fib_0");
        ObjectDelete(0, "Fib_236");
        ObjectDelete(0, "Fib_382");
        ObjectDelete(0, "Fib_50");
        ObjectDelete(0, "Fib_618");
        ObjectDelete(0, "Fib_786");
        ObjectDelete(0, "Fib_100");
        return;
    }
    
    datetime currentTime = TimeCurrent();
    datetime futureTime = currentTime + PeriodSeconds(PERIOD_CURRENT) * 50;
    
    CreateFibLine("Fib_0", g_fibState.fib_0, "0.0%", clrRed, STYLE_SOLID, 2, currentTime, futureTime);
    CreateFibLine("Fib_236", g_fibState.fib_236, "23.6%", clrGray, STYLE_DOT, 1, currentTime, futureTime);
    CreateFibLine("Fib_382", g_fibState.fib_382, "38.2%", clrYellow, STYLE_DASH, 1, currentTime, futureTime);
    CreateFibLine("Fib_50", g_fibState.fib_50, "50.0%", clrWhite, STYLE_SOLID, 2, currentTime, futureTime);
    CreateFibLine("Fib_618", g_fibState.fib_618, "61.8%", clrYellow, STYLE_DASH, 1, currentTime, futureTime);
    CreateFibLine("Fib_786", g_fibState.fib_786, "78.6%", clrOrange, STYLE_DASH, 1, currentTime, futureTime);
    CreateFibLine("Fib_100", g_fibState.fib_100, "100.0%", clrLime, STYLE_SOLID, 2, currentTime, futureTime);
}

//+------------------------------------------------------------------+
//| Create Fibonacci Line on Chart                                    |
//+------------------------------------------------------------------+
void CreateFibLine(string name, double price, string label, color clr, 
                   ENUM_LINE_STYLE style, int width, datetime time1, datetime time2)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_TREND, 0, time1, price, time2, price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, style);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
        ObjectSetString(0, name, OBJPROP_TEXT, label);
    }
    else
    {
        ObjectMove(0, name, 0, time1, price);
        ObjectMove(0, name, 1, time2, price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    
    // ===== ML Regime Filter Initialization =====
    if(EnableRegimeFilter)
    {
        Print("=== Initializing ML Regime Filter ===");
        if(RF_InitRegimeFilter(RegimeFilterHost, RegimeFilterPort, EnableRegimeFilter))
        {
            Print("ML Regime Filter: Successfully connected to Python GUI");
        }
        else
        {
            Print("ML Regime Filter: Failed to connect - operating in bypass mode");
        }
    }
    else
    {
        Print("ML Regime Filter: DISABLED by user settings");
    }
    // ===========================================

    // Validate and set parameters
    ValidateParameters();
    
    // Initialize grid state
    InitializeGrid();
    
    // Initialize QQE state
    InitializeQQE();
    
    // Initialize ADX state
    InitializeADX();
    
    // Initialize S/R Zone state
    InitializeSRZones();
    
    // Initialize Fibonacci state
    if(g_useFibonacci)
    {
        InitializeFibonacci();
        Print("Fibonacci retracement filter initialized");
    }
    
    // Initialize Order Flow state
    if(g_useOrderFlow)
    {
        InitializeOrderFlow();
        
        // Subscribe to Market Depth (Order Book) events
        if(!MarketBookAdd(_Symbol))
        {
            Print("WARNING: Failed to subscribe to Market Depth for ", _Symbol);
            Print("Order Flow analysis will be limited. Check if broker provides Level 2 data.");
            g_useOrderFlow = false;
        }
        else
        {
            Print("Successfully subscribed to Market Depth for ", _Symbol);
        }
    }
    
    // Initialize equity tracking
    g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_emergencyStop = false;
    g_sleepUntil = 0;
    g_pendingRetry = false;
    g_isSleeping = false;
    g_sleepStartTime = 0;
    
    // Validate sleep duration
    if(DrawdownSleepMinutes < 1 || DrawdownSleepMinutes > 1440)
    {
        g_drawdownSleepMinutes = DEFAULT_DRAWDOWN_SLEEP;
        Print("WARNING: Invalid DrawdownSleepMinutes, using default: ", DEFAULT_DRAWDOWN_SLEEP);
    }
    else
        g_drawdownSleepMinutes = DrawdownSleepMinutes;
    
    // Rebuild state from existing positions (for restart recovery)
    RebuildStateFromPositions();
    
    // Log configuration
    LogConfiguration();
    
    Print("HybridGridBot initialized successfully with QQE trend filter and Order Flow analysis");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    
    // ML Regime Filter Cleanup
    if(EnableRegimeFilter)
    {
        RF_DeinitRegimeFilter();
        Print("ML Regime Filter: Shut down");
    }

    // Unsubscribe from Market Depth if subscribed
    if(g_useOrderFlow)
    {
        MarketBookRelease(_Symbol);
        Print("Unsubscribed from Market Depth");
    }
    
    // Clean up chart objects
    ObjectDelete(0, "BasketProfit");
    ObjectDelete(0, "DrawdownLabel");
    ObjectDelete(0, "GridLevelLabel");
    ObjectDelete(0, "TargetLabel");
    ObjectDelete(0, "SlopeLabel");
    ObjectDelete(0, "QQELabel");
    ObjectDelete(0, "QQEHistogram");
    ObjectDelete(0, "RSIHLabel");
    ObjectDelete(0, "ADXLabel");
    ObjectDelete(0, "SleepLabel");
    ObjectDelete(0, "SRZoneLabel");
    ObjectDelete(0, "SRBiasLabel");
    ObjectDelete(0, "OrderFlowLabel");
    ObjectDelete(0, "ImbalanceLabel");
    ObjectDelete(0, "DeltaLabel");
    ObjectDelete(0, "PressureLabel");
    ObjectDelete(0, "FibTrendLabel");
    ObjectDelete(0, "FibLevelLabel");
    ObjectDelete(0, "FibZoneLabel");
    ObjectDelete(0, "Fib_0");
    ObjectDelete(0, "Fib_236");
    ObjectDelete(0, "Fib_382");
    ObjectDelete(0, "Fib_50");
    ObjectDelete(0, "Fib_618");
    ObjectDelete(0, "Fib_786");
    ObjectDelete(0, "Fib_100");
    ObjectDelete(0, "FibTrendLabel");
    ObjectDelete(0, "FibLevelLabel");
    ObjectDelete(0, "FibZoneLabel");
    ObjectDelete(0, "Fib_0");
    ObjectDelete(0, "Fib_236");
    ObjectDelete(0, "Fib_382");
    ObjectDelete(0, "Fib_50");
    ObjectDelete(0, "Fib_618");
    ObjectDelete(0, "Fib_786");
    ObjectDelete(0, "Fib_100");
    
    string reasonText;
    switch(reason)
    {
        case REASON_PROGRAM:     reasonText = "EA removed"; break;
        case REASON_REMOVE:      reasonText = "EA removed from chart"; break;
        case REASON_RECOMPILE:   reasonText = "EA recompiled"; break;
        case REASON_CHARTCHANGE: reasonText = "Symbol/timeframe changed"; break;
        case REASON_CHARTCLOSE:  reasonText = "Chart closed"; break;
        case REASON_PARAMETERS:  reasonText = "Parameters changed"; break;
        case REASON_ACCOUNT:     reasonText = "Account changed"; break;
        case REASON_TEMPLATE:    reasonText = "Template applied"; break;
        case REASON_INITFAILED:  reasonText = "Init failed"; break;
        case REASON_CLOSE:       reasonText = "Terminal closed"; break;
        default:                 reasonText = "Unknown"; break;
    }
    
    Print("HybridGridBot deinitialized. Reason: ", reasonText);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    
    // Update ML Regime Filter
    if(EnableRegimeFilter)
    {
        RF_UpdateRegimeFilter();
    }

    // Periodic status logging (every 5 minutes)
    static datetime lastStatusLog = 0;
    if(TimeCurrent() - lastStatusLog > 300)
    {
        LogPeriodicStatus();
        lastStatusLog = TimeCurrent();
    }
    
    // 1. Check emergency stop flag first
    if(g_emergencyStop)
    {
        // Bot is stopped - do nothing until manual reset
        return;
    }
    
    // 2. Check if in sleep mode after drawdown hit
    if(g_isSleeping)
    {
        datetime currentTime = TimeCurrent();
        int sleepSeconds = g_drawdownSleepMinutes * 60;
        
        if(currentTime - g_sleepStartTime >= sleepSeconds)
        {
            // Sleep period ended - reinitialize and resume trading
            Print("========================================");
            Print("SLEEP PERIOD ENDED");
            Print("========================================");
            Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
            Print("Sleep Duration: ", g_drawdownSleepMinutes, " minutes");
            Print("Reinitializing trades...");
            Print("========================================");
            
            g_isSleeping = false;
            g_sleepStartTime = 0;
            
            // Reset peak equity to current equity for fresh drawdown tracking
            g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            
            // Reset grid state for fresh start
            ResetGridState();
            
            // Reinitialize QQE state
            InitializeQQE();
            
            // Reinitialize ADX state
            InitializeADX();
            
            // Reinitialize S/R zones
            InitializeSRZones();
            
            // Reinitialize Order Flow
            if(g_useOrderFlow)
                InitializeOrderFlow();
            
            Print("Bot reinitialized and ready to trade");
        }
        else
        {
            // Still sleeping - update chart display with remaining time
            if(ShowBasketOnChart)
            {
                int remainingSeconds = sleepSeconds - (int)(currentTime - g_sleepStartTime);
                int remainingMinutes = remainingSeconds / 60;
                int remainingSecs = remainingSeconds % 60;
                string sleepText = "SLEEPING: " + IntegerToString(remainingMinutes) + "m " + 
                                   IntegerToString(remainingSecs) + "s remaining";
                CreateOrUpdateLabel("SleepLabel", sleepText, 10, 190, clrOrange);
                ChartRedraw(0);
            }
            return;
        }
    }
    else
    {
        // Remove sleep label if not sleeping
        ObjectDelete(0, "SleepLabel");
    }
    
    // 3. Handle pending retry if any
    if(g_pendingRetry)
    {
        MqlTradeResult result;
        if(OrderSendAsync(g_retryRequest, result))
        {
            Print("Retry order sent - Request ID: ", result.request_id);
        }
        g_pendingRetry = false;
    }
    
    // 4. Calculate QQE indicator on each tick
    CalculateQQE();
    
    // 4a. Calculate ADX indicator on each tick
    if(g_useADXFilter)
    {
        CalculateADX();
    }
    
    // 4b. Update S/R zones and apply bias to QQE signal
    if(g_useSRZones)
    {
        UpdateSRZones();
        ApplySRBiasToQQE();
    }
    
    // 4c. Update Fibonacci levels periodically
    if(g_useFibonacci)
    {
        static datetime lastFibUpdate = 0;
        datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
        
        // Recalculate Fib levels every new bar
        if(currentBar != lastFibUpdate)
        {
            UpdateFibonacciLevels();
            if(g_fibShowOnChart)
                DrawFibonacciLevels();
            lastFibUpdate = currentBar;
        }
        else
        {
            // Update current Fib level on every tick
            CalculateCurrentFibLevel();
        }
    }
    
    // 4d. Update Order Flow metrics on tick (OnBookEvent handles order book updates)
    if(g_useOrderFlow)
    {
        UpdateOrderFlowOnTick();
    }
    
    // 5. Update peak equity tracking
    UpdatePeakEquity();
    
    // 6. Check drawdown limit
    if(CheckDrawdownLimit())
    {
        return; // Sleep mode triggered
    }
    
    // 7. Check QQE early warning (log warning if trend reversing)
    CheckQQEEarlyWarning();
    
    // 8. Check QQE emergency exit (close basket if QQE crosses 50 opposite direction)
    if(CheckQQEEmergencyExit())
    {
        Print("QQE Emergency Exit triggered - closing all positions");
        CloseAllPositionsAsync();
        return;
    }
    
    // 9. Check basket profit target
    if(CheckProfitTarget())
    {
        return; // Closing basket
    }
    
    // 10. Manage grid (add levels or start new grid)
    ManageGrid();
    
    // 11. Update chart display if enabled
    if(ShowBasketOnChart)
    {
        UpdateChartDisplay();
    }
}

//+------------------------------------------------------------------+
//| OnBookEvent - Order Book Change Handler                           |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
{
    if(symbol != _Symbol || !g_useOrderFlow)
        return;
    
    // Update order book data and calculate imbalances
    UpdateOrderBookData();
    CalculateOrderBookImbalances();
    CalculateAbsorptionRates();
    CalculateCompositePressure();
    DetermineMarketDirection();
}

//+------------------------------------------------------------------+
//| Log Periodic Status (Every 5 Minutes)                             |
//+------------------------------------------------------------------+
void LogPeriodicStatus()
{
    Print("========================================");
    Print("PERIODIC STATUS UPDATE");
    Print("========================================");
    Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("----------------------------------------");
    Print("GRID STATUS:");
    Print("  Active: ", g_gridState.isActive ? "Yes" : "No");
    if(g_gridState.isActive)
    {
        Print("  Direction: ", EnumToString(g_gridState.direction));
        Print("  Level: ", g_gridState.currentLevel, "/", g_maxGridLevels);
        Print("  Positions: ", ArraySize(g_gridState.positions));
        Print("  Basket P/L: $", DoubleToString(CalculateBasketProfit(), 2));
    }
    Print("----------------------------------------");
    Print("ACCOUNT:");
    Print("  Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("  Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("  Drawdown: ", DoubleToString(CalculateDrawdown(), 2), "%");
    Print("----------------------------------------");
    LogAllIndicatorStates();
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Handle deal additions (position opened)
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        // Check if this deal belongs to our bot
        if(trans.symbol == _Symbol)
        {
            ulong dealTicket = trans.deal;
            if(dealTicket > 0 && HistoryDealSelect(dealTicket))
            {
                long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
                if(dealMagic == MagicNumber)
                {
                    ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                    
                    if(entry == DEAL_ENTRY_IN)
                    {
                        // Position opened - add to tracking
                        HandlePositionOpened(dealTicket);
                    }
                    else if(entry == DEAL_ENTRY_OUT)
                    {
                        // Position closed - remove from tracking
                        HandlePositionClosed(trans.position);
                    }
                }
            }
        }
    }
    
    // Handle order request results
    if(trans.type == TRADE_TRANSACTION_REQUEST)
    {
        if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
        {
            HandleOrderError(result.retcode, request);
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Position Opened Event                                      |
//+------------------------------------------------------------------+
void HandlePositionOpened(ulong dealTicket)
{
    if(!HistoryDealSelect(dealTicket))
        return;
    
    ulong positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
    
    // Find the position ticket
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_IDENTIFIER) == positionId)
            {
                // Create position record
                GridPosition pos;
                pos.ticket = ticket;
                pos.lotSize = PositionGetDouble(POSITION_VOLUME);
                pos.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                pos.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                string comment = PositionGetString(POSITION_COMMENT);
                pos.gridLevel = ExtractGridLevel(comment);
                
                // Add to tracked positions
                int size = ArraySize(g_gridState.positions);
                ArrayResize(g_gridState.positions, size + 1);
                g_gridState.positions[size] = pos;
                
                // Update grid state
                g_gridState.isActive = true;
                g_gridState.direction = pos.type;
                g_gridState.currentLevel = pos.gridLevel;
                g_gridState.lastGridPrice = pos.openPrice;
                
                LogTrade("OPEN", pos);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Handle Position Closed Event                                      |
//+------------------------------------------------------------------+
void HandlePositionClosed(ulong positionId)
{
    // Find and remove from tracked positions
    for(int i = ArraySize(g_gridState.positions) - 1; i >= 0; i--)
    {
        if(g_gridState.positions[i].ticket == positionId)
        {
            GridPosition closedPos = g_gridState.positions[i];
            
            // Remove from array
            for(int j = i; j < ArraySize(g_gridState.positions) - 1; j++)
            {
                g_gridState.positions[j] = g_gridState.positions[j + 1];
            }
            ArrayResize(g_gridState.positions, ArraySize(g_gridState.positions) - 1);
            
            Print("Position closed and removed from tracking: ", positionId);
            break;
        }
    }
    
    // Check if all positions are closed
    if(ArraySize(g_gridState.positions) == 0)
    {
        ResetGridState();
    }
}

//+------------------------------------------------------------------+
//| Handle Order Error                                                |
//+------------------------------------------------------------------+
void HandleOrderError(int errorCode, const MqlTradeRequest& request)
{
    Print("Order error: ", errorCode, " - ", ErrorDescription(errorCode));
    
    switch(errorCode)
    {
        case TRADE_RETCODE_REQUOTE:
            // Queue for retry on next tick
            g_pendingRetry = true;
            g_retryRequest = request;
            break;
            
        case TRADE_RETCODE_NO_MONEY:
            Print("CRITICAL: Insufficient margin - stopping grid");
            g_gridState.isActive = false;
            g_emergencyStop = true;
            break;
            
        case TRADE_RETCODE_MARKET_CLOSED:
            Print("Market closed - will retry when open");
            break;
            
        default:
            Print("Unhandled error - will retry once");
            g_pendingRetry = true;
            g_retryRequest = request;
    }
}

//+------------------------------------------------------------------+
//| Reset Grid State After All Positions Closed                       |
//+------------------------------------------------------------------+
void ResetGridState()
{
    ArrayResize(g_gridState.positions, 0);
    g_gridState.currentLevel = 0;
    g_gridState.lastGridPrice = 0;
    g_gridState.isActive = false;
    
    Print("Grid state reset - ready for new basket");
}

//+------------------------------------------------------------------+
//| Log Trade Action with Full Market Conditions                      |
//+------------------------------------------------------------------+
void LogTrade(string action, const GridPosition& pos)
{
    Print("========================================");
    Print("TRADE ACTION: ", action);
    Print("========================================");
    Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("Symbol: ", _Symbol);
    Print("Direction: ", EnumToString(pos.type));
    Print("Lot Size: ", pos.lotSize);
    Print("Open Price: ", pos.openPrice);
    Print("Grid Level: ", pos.gridLevel);
    Print("Ticket: ", pos.ticket);
    Print("----------------------------------------");
    Print("MARKET CONDITIONS AT TRADE:");
    Print("----------------------------------------");
    Print("Current Bid: ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
    Print("Current Ask: ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
    Print("Spread: ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), " points");
    Print("----------------------------------------");
    LogAllIndicatorStates();
    Print("----------------------------------------");
    Print("GRID STATE:");
    Print("----------------------------------------");
    Print("Grid Active: ", g_gridState.isActive ? "Yes" : "No");
    Print("Grid Direction: ", EnumToString(g_gridState.direction));
    Print("Current Level: ", g_gridState.currentLevel, "/", g_maxGridLevels);
    Print("Last Grid Price: ", g_gridState.lastGridPrice);
    Print("Total Positions: ", ArraySize(g_gridState.positions));
    Print("Basket P/L: $", DoubleToString(CalculateBasketProfit(), 2));
    Print("----------------------------------------");
    Print("ACCOUNT STATE:");
    Print("----------------------------------------");
    Print("Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("Peak Equity: $", DoubleToString(g_peakEquity, 2));
    Print("Drawdown: ", DoubleToString(CalculateDrawdown(), 2), "%");
    Print("Free Margin: $", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Log All Indicator States                                          |
//+------------------------------------------------------------------+
void LogAllIndicatorStates()
{
    Print("QQE INDICATOR:");
    Print("  QQE Line: ", DoubleToString(g_qqeState.qqeLine, 2));
    Print("  QQE Previous: ", DoubleToString(g_qqeState.qqeLinePrev, 2));
    Print("  Upper Band: ", DoubleToString(g_qqeState.trailingBandUp, 2));
    Print("  Lower Band: ", DoubleToString(g_qqeState.trailingBandDown, 2));
    Print("  Smoothed ATR: ", DoubleToString(g_qqeState.smoothedATR, 2));
    Print("  Signal: ", g_qqeState.signal == 1 ? "BUY" : (g_qqeState.signal == -1 ? "SELL" : "NEUTRAL"));
    Print("  Biased Signal: ", g_qqeState.biasedSignal == 1 ? "BUY" : (g_qqeState.biasedSignal == -1 ? "SELL" : "NEUTRAL"));
    Print("  Histogram: ", g_qqeState.histogram == 1 ? "RISING" : "FALLING");
    Print("  Distance from 50: ", DoubleToString(MathAbs(g_qqeState.qqeLine - 50), 2));
    
    if(g_useRSIH)
    {
        Print("RSIH INDICATOR:");
        Print("  RSIH Value: ", DoubleToString(g_qqeState.rsihValue, 2));
        Print("  RSIH Previous: ", DoubleToString(g_qqeState.rsihPrev, 2));
        Print("  RSIH Momentum: ", g_qqeState.rsihValue > g_qqeState.rsihPrev ? "RISING" : "FALLING");
    }
    
    if(g_useADXFilter)
    {
        Print("ADX INDICATOR:");
        Print("  ADX Value: ", DoubleToString(g_adxState.adxValue, 2));
        Print("  +DI: ", DoubleToString(g_adxState.plusDI, 2));
        Print("  -DI: ", DoubleToString(g_adxState.minusDI, 2));
        Print("  State: ", g_adxState.allowEntry ? "RANGE (Entry Allowed)" : "TREND (Entry Blocked)");
        Print("  Threshold: ", DoubleToString(g_adxMaxThreshold, 2));
    }
    
    if(g_useSRZones)
    {
        Print("S/R ZONES:");
        Print("  Support Level: ", g_srState.supportLevel > 0 ? DoubleToString(g_srState.supportLevel, _Digits) : "None");
        Print("  Support Strength: ", g_srState.supportStrength);
        Print("  Resistance Level: ", g_srState.resistanceLevel > 0 ? DoubleToString(g_srState.resistanceLevel, _Digits) : "None");
        Print("  Resistance Strength: ", g_srState.resistanceStrength);
        Print("  Near Support: ", g_srState.nearSupport ? "Yes" : "No");
        Print("  Near Resistance: ", g_srState.nearResistance ? "Yes" : "No");
        Print("  Zone Bias: ", g_srState.zoneBias == 1 ? "BUY" : (g_srState.zoneBias == -1 ? "SELL" : "NEUTRAL"));
    }
    
    if(g_useOrderFlow)
    {
        Print("ORDER FLOW:");
        Print("  Market Direction: ", g_orderFlowState.marketDirection == 1 ? "BUYERS WINNING" : 
              (g_orderFlowState.marketDirection == -1 ? "SELLERS WINNING" : "NEUTRAL"));
        Print("  Static Imbalance: ", DoubleToString(g_orderFlowState.staticImbalance, 3));
        Print("  VWOI: ", DoubleToString(g_orderFlowState.volumeWeightedImbalance, 3));
        Print("  Imbalance Momentum: ", DoubleToString(g_orderFlowState.imbalanceMomentum, 3));
        Print("  Cumulative Delta: ", DoubleToString(g_orderFlowState.cumulativeDelta, 2));
        Print("  Normalized Delta: ", DoubleToString(g_orderFlowState.normalizedDelta, 3));
        Print("  Bid Absorption: ", DoubleToString(g_orderFlowState.bidAbsorptionRate, 2));
        Print("  Ask Absorption: ", DoubleToString(g_orderFlowState.askAbsorptionRate, 2));
        Print("  Pressure Index: ", DoubleToString(g_orderFlowState.pressureIndex, 3));
        Print("  Adjusted Imbalance: ", DoubleToString(g_orderFlowState.adjustedImbalance, 3));
        Print("  Allow Buy: ", g_orderFlowState.allowBuy ? "YES" : "NO");
        Print("  Allow Sell: ", g_orderFlowState.allowSell ? "YES" : "NO");
        Print("  Bid Levels: ", g_orderFlowState.bidLevelCount);
        Print("  Ask Levels: ", g_orderFlowState.askLevelCount);
    }
    
    if(g_useTMAConfirmation)
    {
        double slope = GetTMASlope();
        Print("TMA INDICATOR:");
        Print("  TMA Slope: ", DoubleToString(slope, 6));
        Print("  Slope Direction: ", slope > g_tmaSlopeThreshold ? "UP" : (slope < -g_tmaSlopeThreshold ? "DOWN" : "FLAT"));
        Print("  Threshold: ", DoubleToString(g_tmaSlopeThreshold, 6));
    }
    
    if(g_useFibonacci && g_fibState.isValid)
    {
        Print("FIBONACCI LEVELS:");
        Print("  Swing High: ", DoubleToString(g_fibState.swingHigh, _Digits), 
              " (Bar ", g_fibState.swingHighBar, ")");
        Print("  Swing Low: ", DoubleToString(g_fibState.swingLow, _Digits), 
              " (Bar ", g_fibState.swingLowBar, ")");
        Print("  Trend: ", g_fibState.isUptrend ? "Uptrend (retracing from high)" : "Downtrend (retracing from low)");
        Print("  Current Fib Level: ", DoubleToString(g_fibState.currentFibLevel, 2), "%");
        Print("  In Entry Zone: ", g_fibState.inEntryZone ? "YES" : "NO");
        Print("  Beyond 78.6%: ", g_fibState.beyondSafetyLevel ? "YES" : "NO");
        Print("  Fib 38.2%: ", DoubleToString(g_fibState.fib_382, _Digits));
        Print("  Fib 50.0%: ", DoubleToString(g_fibState.fib_50, _Digits));
        Print("  Fib 61.8%: ", DoubleToString(g_fibState.fib_618, _Digits));
        Print("  Fib 78.6%: ", DoubleToString(g_fibState.fib_786, _Digits));
        
        if(g_fibAnchorGridLevels)
        {
            Print("  Grid Level 1 Price: ", DoubleToString(g_fibState.gridLevel1Price, _Digits));
            Print("  Grid Level 2 Price: ", DoubleToString(g_fibState.gridLevel2Price, _Digits));
            Print("  Grid Level 3 Price: ", DoubleToString(g_fibState.gridLevel3Price, _Digits));
            Print("  Grid Level 4 Price: ", DoubleToString(g_fibState.gridLevel4Price, _Digits));
        }
    }
}

//+------------------------------------------------------------------+
//| Log Entry Conditions Check                                        |
//+------------------------------------------------------------------+
void LogEntryConditions(ENUM_POSITION_TYPE direction, bool canOpen)
{
    Print("========================================");
    Print("ENTRY CONDITIONS CHECK");
    Print("========================================");
    Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("Requested Direction: ", EnumToString(direction));
    Print("Can Open: ", canOpen ? "YES" : "NO");
    Print("----------------------------------------");
    LogAllIndicatorStates();
    Print("----------------------------------------");
    Print("FILTER RESULTS:");
    Print("----------------------------------------");
    
    int qqeSignal = GetQQESignal();
    Print("QQE Filter: ", qqeSignal == 0 ? "BLOCKED (Neutral)" : 
          (direction == POSITION_TYPE_BUY && qqeSignal == 1) || (direction == POSITION_TYPE_SELL && qqeSignal == -1) ? "PASSED" : "BLOCKED (Wrong Direction)");
    
    if(g_useADXFilter)
    {
        Print("ADX Filter: ", g_adxState.allowEntry ? "PASSED (Range)" : "BLOCKED (Trend)");
    }
    
    if(g_useTMAConfirmation)
    {
        double slope = GetTMASlope();
        bool tmaPass = false;
        if(direction == POSITION_TYPE_BUY && slope > g_tmaSlopeThreshold)
            tmaPass = true;
        if(direction == POSITION_TYPE_SELL && slope < -g_tmaSlopeThreshold)
            tmaPass = true;
        Print("TMA Filter: ", tmaPass ? "PASSED" : "BLOCKED");
    }
    
    if(g_useOrderFlow)
    {
        bool orderFlowPass = false;
        if(direction == POSITION_TYPE_BUY && g_orderFlowState.allowBuy)
            orderFlowPass = true;
        if(direction == POSITION_TYPE_SELL && g_orderFlowState.allowSell)
            orderFlowPass = true;
        Print("Order Flow Filter: ", orderFlowPass ? "PASSED" : "BLOCKED");
        Print("  Market Direction: ", g_orderFlowState.marketDirection == 1 ? "BUYERS" : 
              (g_orderFlowState.marketDirection == -1 ? "SELLERS" : "NEUTRAL"));
        Print("  Pressure Index: ", DoubleToString(g_orderFlowState.pressureIndex, 3));
    }
    
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Calculate Basket Profit (Sum of All Position Profits)             |
//+------------------------------------------------------------------+
double CalculateBasketProfit()
{
    double totalProfit = 0;
    
    int count = ArraySize(g_gridState.positions);
    for(int i = 0; i < count; i++)
    {
        ulong ticket = g_gridState.positions[i].ticket;
        if(PositionSelectByTicket(ticket))
        {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
            totalProfit += PositionGetDouble(POSITION_SWAP);
        }
    }
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Check Profit Target and Close if Reached                          |
//+------------------------------------------------------------------+
bool CheckProfitTarget()
{
    if(!g_gridState.isActive || ArraySize(g_gridState.positions) == 0)
        return false;
    
    double basketProfit = CalculateBasketProfit();
    
    if(basketProfit >= g_targetProfitUSD)
    {
        Print("========================================");
        Print("PROFIT TARGET REACHED!");
        Print("========================================");
        Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
        Print("Basket Profit: $", DoubleToString(basketProfit, 2));
        Print("Target: $", DoubleToString(g_targetProfitUSD, 2));
        Print("Grid Direction: ", EnumToString(g_gridState.direction));
        Print("Grid Levels Used: ", g_gridState.currentLevel, "/", g_maxGridLevels);
        Print("Total Positions: ", ArraySize(g_gridState.positions));
        Print("----------------------------------------");
        LogAllIndicatorStates();
        Print("----------------------------------------");
        Print("POSITION DETAILS:");
        for(int i = 0; i < ArraySize(g_gridState.positions); i++)
        {
            if(PositionSelectByTicket(g_gridState.positions[i].ticket))
            {
                Print("  Level ", g_gridState.positions[i].gridLevel, 
                      ": Ticket=", g_gridState.positions[i].ticket,
                      ", Lots=", g_gridState.positions[i].lotSize,
                      ", Open=", g_gridState.positions[i].openPrice,
                      ", P/L=$", DoubleToString(PositionGetDouble(POSITION_PROFIT), 2));
            }
        }
        Print("========================================");
        
        CloseAllPositionsAsync();
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update Peak Equity (Monotonically Non-Decreasing)                 |
//+------------------------------------------------------------------+
void UpdatePeakEquity()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(currentEquity > g_peakEquity)
    {
        g_peakEquity = currentEquity;
    }
}

//+------------------------------------------------------------------+
//| Calculate Current Drawdown Percentage                             |
//+------------------------------------------------------------------+
double CalculateDrawdown()
{
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(g_peakEquity <= 0)
        return 0;
    
    // Drawdown = (Peak - Current) / Peak * 100
    double drawdown = ((g_peakEquity - currentEquity) / g_peakEquity) * 100.0;
    
    return MathMax(0, drawdown);
}

//+------------------------------------------------------------------+
//| Check Drawdown Limit and Trigger Sleep Mode if Exceeded           |
//+------------------------------------------------------------------+
bool CheckDrawdownLimit()
{
    double drawdown = CalculateDrawdown();
    
    // Warning when approaching limit (within 5%)
    if(drawdown >= (g_maxDrawdownPercent - 5.0) && drawdown < g_maxDrawdownPercent)
    {
        static datetime lastWarning = 0;
        if(TimeCurrent() - lastWarning > 60) // Warn once per minute
        {
            Print("========================================");
            Print("DRAWDOWN WARNING!");
            Print("========================================");
            Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
            Print("Current Drawdown: ", DoubleToString(drawdown, 2), "%");
            Print("Max Allowed: ", DoubleToString(g_maxDrawdownPercent, 2), "%");
            Print("Peak Equity: $", DoubleToString(g_peakEquity, 2));
            Print("Current Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
            Print("Basket P/L: $", DoubleToString(CalculateBasketProfit(), 2));
            Print("========================================");
            lastWarning = TimeCurrent();
        }
    }
    
    // Sleep mode if limit exceeded
    if(drawdown >= g_maxDrawdownPercent)
    {
        Print("========================================");
        Print("MAX DRAWDOWN HIT - ENTERING SLEEP MODE");
        Print("========================================");
        Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
        Print("Drawdown: ", DoubleToString(drawdown, 2), "%");
        Print("Max Allowed: ", DoubleToString(g_maxDrawdownPercent, 2), "%");
        Print("Peak Equity: $", DoubleToString(g_peakEquity, 2));
        Print("Current Equity: $", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
        Print("Sleep Duration: ", g_drawdownSleepMinutes, " minutes");
        Print("----------------------------------------");
        LogAllIndicatorStates();
        Print("----------------------------------------");
        Print("CLOSING ALL POSITIONS:");
        for(int i = 0; i < ArraySize(g_gridState.positions); i++)
        {
            if(PositionSelectByTicket(g_gridState.positions[i].ticket))
            {
                Print("  Level ", g_gridState.positions[i].gridLevel, 
                      ": Ticket=", g_gridState.positions[i].ticket,
                      ", P/L=$", DoubleToString(PositionGetDouble(POSITION_PROFIT), 2));
            }
        }
        Print("========================================");
        
        CloseAllPositionsAsync();
        
        // Enter sleep mode instead of permanent stop
        g_isSleeping = true;
        g_sleepStartTime = TimeCurrent();
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Manage Grid - Check for New Level or Start New Grid               |
//+------------------------------------------------------------------+
void ManageGrid()
{
    // If no active grid, try to start one
    if(!g_gridState.isActive)
    {
        TryStartNewGrid();
        return;
    }
    
    // Check if we can add another level
    if(g_gridState.currentLevel >= g_maxGridLevels)
    {
        // Max levels reached - just wait for profit target or drawdown
        return;
    }
    
    double currentPrice = GetCurrentPrice(g_gridState.direction);
    
    // Check if using Fib-anchored levels
    if(g_useFibonacci && g_fibAnchorGridLevels && g_fibState.isValid)
    {
        int nextLevel = g_gridState.currentLevel + 1;
        double targetPrice = GetGridEntryPrice(nextLevel);
        
        if(targetPrice > 0)
        {
            // Check if price has reached the Fib level
            bool shouldAddLevel = false;
            
            if(g_gridState.direction == POSITION_TYPE_BUY)
            {
                // For buy grid, add level when price drops to Fib level
                shouldAddLevel = (currentPrice <= targetPrice);
            }
            else
            {
                // For sell grid, add level when price rises to Fib level
                shouldAddLevel = (currentPrice >= targetPrice);
            }
            
            if(shouldAddLevel)
            {
                Print("Adding Fib-anchored grid level ", nextLevel, " at ", targetPrice);
                AddGridLevel();
            }
            return;
        }
    }
    
    // Traditional distance-based grid logic
    double priceMove = 0;
    
    if(g_gridState.direction == POSITION_TYPE_BUY)
    {
        // For buy grid, price moving DOWN triggers new level
        priceMove = g_gridState.lastGridPrice - currentPrice;
    }
    else
    {
        // For sell grid, price moving UP triggers new level
        priceMove = currentPrice - g_gridState.lastGridPrice;
    }
    
    // Convert to points
    double moveInPoints = priceMove / _Point;
    
    if(moveInPoints >= g_gridStepPoints)
    {
        // Time to add a new grid level
        AddGridLevel();
    }
}

//+------------------------------------------------------------------+
//| Try to Start a New Grid                                           |
//+------------------------------------------------------------------+
void TryStartNewGrid()
{
    // Determine direction based on QQE signal
    int qqeSignal = GetQQESignal();
    
    // Check if we have a valid signal
    if(qqeSignal == 0)
    {
        static datetime lastNeutralLog = 0;
        if(TimeCurrent() - lastNeutralLog > 300) // Log every 5 minutes
        {
            Print("No trade signal - QQE in neutral zone (", DoubleToString(g_qqeState.qqeLine, 2), ")");
            lastNeutralLog = TimeCurrent();
        }
        return; // No signal - stay out (QQE in neutral zone)
    }
    
    ENUM_POSITION_TYPE direction;
    ENUM_ORDER_TYPE orderType;
    
    if(qqeSignal == 1)
    {
        direction = POSITION_TYPE_BUY;
        orderType = ORDER_TYPE_BUY;
    }
    else
    {
        direction = POSITION_TYPE_SELL;
        orderType = ORDER_TYPE_SELL;
    }
    
    // Check if direction is permitted (includes optional TMA confirmation)
    bool canOpen = CanOpenNewGrid(direction);
    
    // Log entry conditions check
    static datetime lastConditionLog = 0;
    if(!canOpen && TimeCurrent() - lastConditionLog > 60) // Log every minute when blocked
    {
        LogEntryConditions(direction, canOpen);
        lastConditionLog = TimeCurrent();
    }
    
    if(!canOpen)
        return;
    
    // Log pre-trade conditions
    Print("========================================");
    Print("STARTING NEW GRID");
    Print("========================================");
    Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("Direction: ", EnumToString(direction));
    Print("QQE Signal: ", qqeSignal == 1 ? "BUY" : "SELL");
    Print("----------------------------------------");
    LogAllIndicatorStates();
    Print("========================================");
    
    // Calculate lot size for first level
    double lots = CalculateLotSize(1);
    
    // Open first position
    if(OpenPositionAsync(orderType, lots, 1))
    {
        g_gridState.direction = direction;
        g_gridState.lastGridPrice = GetCurrentPrice(direction);
        Print("New ", EnumToString(direction), " grid initiated based on QQE signal");
    }
}

//+------------------------------------------------------------------+
//| Add a New Grid Level                                              |
//+------------------------------------------------------------------+
void AddGridLevel()
{
    int newLevel = g_gridState.currentLevel + 1;
    
    if(newLevel > g_maxGridLevels)
    {
        Print("Max grid levels reached: ", g_maxGridLevels);
        return;
    }
    
    // Log pre-add conditions
    Print("========================================");
    Print("ADDING GRID LEVEL");
    Print("========================================");
    Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
    Print("New Level: ", newLevel, "/", g_maxGridLevels);
    Print("Current Grid Direction: ", EnumToString(g_gridState.direction));
    Print("Last Grid Price: ", g_gridState.lastGridPrice);
    Print("Current Price: ", GetCurrentPrice(g_gridState.direction));
    Print("Price Movement: ", DoubleToString((g_gridState.lastGridPrice - GetCurrentPrice(g_gridState.direction)) / _Point, 2), " points");
    Print("----------------------------------------");
    LogAllIndicatorStates();
    Print("========================================");
    
    // Calculate lot size for new level
    double lots = CalculateLotSize(newLevel);
    
    // Determine order type
    ENUM_ORDER_TYPE orderType;
    if(g_gridState.direction == POSITION_TYPE_BUY)
        orderType = ORDER_TYPE_BUY;
    else
        orderType = ORDER_TYPE_SELL;
    
    // Open new position
    if(OpenPositionAsync(orderType, lots, newLevel))
    {
        Print("Grid level ", newLevel, " added with ", lots, " lots");
    }
}

//+------------------------------------------------------------------+
//| Get Current Price Based on Position Type                          |
//+------------------------------------------------------------------+
double GetCurrentPrice(ENUM_POSITION_TYPE posType)
{
    if(posType == POSITION_TYPE_BUY)
        return SymbolInfoDouble(_Symbol, SYMBOL_BID); // Exit price for buy
    else
        return SymbolInfoDouble(_Symbol, SYMBOL_ASK); // Exit price for sell
}

//+------------------------------------------------------------------+
//| Update Chart Display                                              |
//+------------------------------------------------------------------+
void UpdateChartDisplay()
{
    double basketProfit = CalculateBasketProfit();
    double drawdown = CalculateDrawdown();
    int gridLevel = g_gridState.currentLevel;
    string direction = g_gridState.isActive ? EnumToString(g_gridState.direction) : "NONE";
    
    // Basket Profit Label
    string profitText = "Basket P/L: $" + DoubleToString(basketProfit, 2);
    color profitColor = basketProfit >= 0 ? clrLime : clrRed;
    CreateOrUpdateLabel("BasketProfit", profitText, 10, 30, profitColor);
    
    // Drawdown Label
    string ddText = "Drawdown: " + DoubleToString(drawdown, 2) + "% / " + 
                    DoubleToString(g_maxDrawdownPercent, 2) + "%";
    color ddColor = drawdown < (g_maxDrawdownPercent - 5) ? clrWhite : clrOrange;
    if(drawdown >= g_maxDrawdownPercent) ddColor = clrRed;
    CreateOrUpdateLabel("DrawdownLabel", ddText, 10, 50, ddColor);
    
    // Grid Level Label
    string gridText = "Grid: " + direction + " L" + IntegerToString(gridLevel) + 
                      "/" + IntegerToString(g_maxGridLevels) + 
                      " (" + IntegerToString(ArraySize(g_gridState.positions)) + " pos)";
    CreateOrUpdateLabel("GridLevelLabel", gridText, 10, 70, clrYellow);
    
    // Target Label
    string targetText = "Target: $" + DoubleToString(g_targetProfitUSD, 2);
    CreateOrUpdateLabel("TargetLabel", targetText, 10, 90, clrAqua);
    
    // QQE Line Label
    double qqeLine = GetQQELine();
    int qqeSignal = GetQQESignal();
    string signalText = (qqeSignal == 1) ? "BUY" : ((qqeSignal == -1) ? "SELL" : "NEUTRAL");
    string qqeText = "QQE: " + DoubleToString(qqeLine, 2) + " [" + signalText + "]";
    color qqeColor = (qqeSignal == 1) ? clrLime : ((qqeSignal == -1) ? clrRed : clrGray);
    CreateOrUpdateLabel("QQELabel", qqeText, 10, 110, qqeColor);
    
    // QQE Histogram Label (momentum direction)
    string histText = "Momentum: " + ((g_qqeState.histogram == 1) ? "RISING" : "FALLING");
    color histColor = (g_qqeState.histogram == 1) ? clrDodgerBlue : clrOrangeRed;
    CreateOrUpdateLabel("QQEHistogram", histText, 10, 130, histColor);
    
    // RSIH Label (only if RSIH is enabled)
    if(g_useRSIH)
    {
        string rsihText = "RSIH: " + DoubleToString(g_qqeState.rsihValue, 2);
        color rsihColor = (g_qqeState.rsihValue > 0) ? clrLime : 
                          ((g_qqeState.rsihValue < 0) ? clrRed : clrGray);
        CreateOrUpdateLabel("RSIHLabel", rsihText, 10, 150, rsihColor);
    }
    else
    {
        ObjectDelete(0, "RSIHLabel");
    }
    
    // ADX Label (only if ADX filter is enabled)
    if(g_useADXFilter)
    {
        string adxText = "ADX: " + DoubleToString(g_adxState.adxValue, 2) + 
                         " [" + (g_adxState.allowEntry ? "RANGE" : "TREND") + "]";
        color adxColor = g_adxState.allowEntry ? clrLime : clrOrange;
        CreateOrUpdateLabel("ADXLabel", adxText, 10, 170, adxColor);
    }
    else
    {
        ObjectDelete(0, "ADXLabel");
    }
    
    // S/R Zone Labels (only if S/R zones are enabled)
    if(g_useSRZones)
    {
        string srText = "S/R: " + GetSRZoneInfo();
        CreateOrUpdateLabel("SRZoneLabel", srText, 10, 190, clrWhite);
        
        string biasText = "Zone Bias: ";
        color biasColor = clrGray;
        if(g_srState.nearSupport)
        {
            biasText += "NEAR SUPPORT (Buy Bias)";
            biasColor = clrLime;
        }
        else if(g_srState.nearResistance)
        {
            biasText += "NEAR RESISTANCE (Sell Bias)";
            biasColor = clrRed;
        }
        else
        {
            biasText += "NEUTRAL";
        }
        CreateOrUpdateLabel("SRBiasLabel", biasText, 10, 210, biasColor);
    }
    else
    {
        ObjectDelete(0, "SRZoneLabel");
        ObjectDelete(0, "SRBiasLabel");
    }
    
    // Order Flow Labels (only if Order Flow is enabled)
    int yOffset = g_useSRZones ? 230 : 190;
    
    if(g_useOrderFlow)
    {
        // Market Direction
        string directionText = "Market: ";
        color directionColor = clrGray;
        if(g_orderFlowState.marketDirection == 1)
        {
            directionText += "BUYERS WINNING";
            directionColor = clrLime;
        }
        else if(g_orderFlowState.marketDirection == -1)
        {
            directionText += "SELLERS WINNING";
            directionColor = clrRed;
        }
        else
        {
            directionText += "NEUTRAL";
        }
        CreateOrUpdateLabel("OrderFlowLabel", directionText, 10, yOffset, directionColor);
        
        // Imbalance
        string imbalanceText = "Imbalance: " + DoubleToString(g_orderFlowState.volumeWeightedImbalance, 3) +
                               " (Mom: " + DoubleToString(g_orderFlowState.imbalanceMomentum, 3) + ")";
        color imbalanceColor = g_orderFlowState.volumeWeightedImbalance > 0 ? clrLime : 
                               (g_orderFlowState.volumeWeightedImbalance < 0 ? clrRed : clrGray);
        CreateOrUpdateLabel("ImbalanceLabel", imbalanceText, 10, yOffset + 20, imbalanceColor);
        
        // Delta Volume
        string deltaText = "Delta: " + DoubleToString(g_orderFlowState.cumulativeDelta, 0) +
                           " (Norm: " + DoubleToString(g_orderFlowState.normalizedDelta, 3) + ")";
        color deltaColor = g_orderFlowState.normalizedDelta > 0 ? clrLime : 
                           (g_orderFlowState.normalizedDelta < 0 ? clrRed : clrGray);
        CreateOrUpdateLabel("DeltaLabel", deltaText, 10, yOffset + 40, deltaColor);
        
        // Pressure Index
        string pressureText = "Pressure: " + DoubleToString(g_orderFlowState.pressureIndex, 3);
        color pressureColor = g_orderFlowState.pressureIndex > g_minPressureIndex ? clrLime : 
                              (g_orderFlowState.pressureIndex < -g_minPressureIndex ? clrRed : clrGray);
        CreateOrUpdateLabel("PressureLabel", pressureText, 10, yOffset + 60, pressureColor);
        
        yOffset += 80;
    }
    else
    {
        ObjectDelete(0, "OrderFlowLabel");
        ObjectDelete(0, "ImbalanceLabel");
        ObjectDelete(0, "DeltaLabel");
        ObjectDelete(0, "PressureLabel");
    }
    
    // Fibonacci Labels (only if Fibonacci is enabled)
    if(g_useFibonacci && g_fibState.isValid)
    {
        string fibTrendText = "Fib: " + (g_fibState.isUptrend ? "Uptrend Retrace" : "Downtrend Retrace");
        CreateOrUpdateLabel("FibTrendLabel", fibTrendText, 10, yOffset, clrWhite);
        
        string fibLevelText = "Fib Level: " + DoubleToString(g_fibState.currentFibLevel, 1) + "%";
        color fibLevelColor = g_fibState.inEntryZone ? clrLime : clrOrange;
        if(g_fibState.beyondSafetyLevel) fibLevelColor = clrRed;
        CreateOrUpdateLabel("FibLevelLabel", fibLevelText, 10, yOffset + 20, fibLevelColor);
        
        string fibZoneText = "Entry Zone: " + (g_fibState.inEntryZone ? "YES" : "NO");
        CreateOrUpdateLabel("FibZoneLabel", fibZoneText, 10, yOffset + 40, 
                           g_fibState.inEntryZone ? clrLime : clrGray);
        
        yOffset += 60;
    }
    else if(g_useFibonacci)
    {
        CreateOrUpdateLabel("FibTrendLabel", "Fib: Calculating...", 10, yOffset, clrGray);
        yOffset += 20;
    }
    else
    {
        ObjectDelete(0, "FibTrendLabel");
        ObjectDelete(0, "FibLevelLabel");
        ObjectDelete(0, "FibZoneLabel");
    }
    
    // TMA Slope Label (only if TMA confirmation is enabled)
    if(g_useTMAConfirmation)
    {
        double slope = GetTMASlope();
        string slopeText = "TMA Slope: " + DoubleToString(slope, 6);
        color slopeColor = slope > g_tmaSlopeThreshold ? clrLime : 
                           (slope < -g_tmaSlopeThreshold ? clrRed : clrGray);
        CreateOrUpdateLabel("SlopeLabel", slopeText, 10, yOffset, slopeColor);
        yOffset += 20;
    }
    else
    {
        ObjectDelete(0, "SlopeLabel");
    }
    
    // Fibonacci Labels (only if Fibonacci is enabled)
    if(g_useFibonacci && g_fibState.isValid)
    {
        string fibTrendText = "Fib: " + (g_fibState.isUptrend ? "Uptrend Retrace" : "Downtrend Retrace");
        CreateOrUpdateLabel("FibTrendLabel", fibTrendText, 10, yOffset, clrWhite);
        
        string fibLevelText = "Fib Level: " + DoubleToString(g_fibState.currentFibLevel, 1) + "%";
        color fibLevelColor = g_fibState.inEntryZone ? clrLime : clrOrange;
        if(g_fibState.beyondSafetyLevel) fibLevelColor = clrRed;
        CreateOrUpdateLabel("FibLevelLabel", fibLevelText, 10, yOffset + 20, fibLevelColor);
        
        string fibZoneText = "Entry Zone: " + (g_fibState.inEntryZone ? "YES" : "NO");
        CreateOrUpdateLabel("FibZoneLabel", fibZoneText, 10, yOffset + 40, 
                           g_fibState.inEntryZone ? clrLime : clrGray);
    }
    else if(g_useFibonacci)
    {
        CreateOrUpdateLabel("FibTrendLabel", "Fib: Calculating...", 10, yOffset, clrGray);
    }
    else
    {
        ObjectDelete(0, "FibTrendLabel");
        ObjectDelete(0, "FibLevelLabel");
        ObjectDelete(0, "FibZoneLabel");
    }
    
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Create or Update Chart Label                                      |
//+------------------------------------------------------------------+
void CreateOrUpdateLabel(string name, string text, int x, int y, color clr)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }
    
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Log Error with Description                                        |
//+------------------------------------------------------------------+
void LogError(string context, int errorCode)
{
    Print("ERROR [", context, "]: Code ", errorCode, " - ", ErrorDescription(errorCode));
}

//+------------------------------------------------------------------+
//| Log General Message                                               |
//+------------------------------------------------------------------+
void LogMessage(string message)
{
    Print(TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", message);
}

//+------------------------------------------------------------------+
//| Parameter Validation                                              |
//+------------------------------------------------------------------+
void ValidateParameters()
{
    // Grid Step
    if(GridStepPoints <= 0)
    {
        g_gridStepPoints = DEFAULT_GRID_STEP;
        Print("WARNING: Invalid GridStepPoints, using default: ", DEFAULT_GRID_STEP);
    }
    else
        g_gridStepPoints = GridStepPoints;
    
    // Initial Lot Size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(InitialLotSize < minLot || InitialLotSize > maxLot)
    {
        g_initialLotSize = MathMax(minLot, DEFAULT_LOT_SIZE);
        Print("WARNING: Invalid InitialLotSize, using: ", g_initialLotSize);
    }
    else
        g_initialLotSize = InitialLotSize;
    
    // Martingale Multiplier
    if(MartingaleMultiplier < 1.0 || MartingaleMultiplier > 10.0)
    {
        g_martingaleMultiplier = DEFAULT_MARTINGALE;
        Print("WARNING: Invalid MartingaleMultiplier, using default: ", DEFAULT_MARTINGALE);
    }
    else
        g_martingaleMultiplier = MartingaleMultiplier;
    
    // Max Grid Levels
    if(MaxGridLevels < 1 || MaxGridLevels > 100)
    {
        g_maxGridLevels = DEFAULT_MAX_LEVELS;
        Print("WARNING: Invalid MaxGridLevels, using default: ", DEFAULT_MAX_LEVELS);
    }
    else
        g_maxGridLevels = MaxGridLevels;
    
    // Target Profit
    if(TargetProfitUSD <= 0)
    {
        g_targetProfitUSD = DEFAULT_TARGET_PROFIT;
        Print("WARNING: Invalid TargetProfitUSD, using default: ", DEFAULT_TARGET_PROFIT);
    }
    else
        g_targetProfitUSD = TargetProfitUSD;
    
    // Max Drawdown
    if(MaxDrawdownPercent <= 0 || MaxDrawdownPercent > 100)
    {
        g_maxDrawdownPercent = DEFAULT_MAX_DRAWDOWN;
        Print("WARNING: Invalid MaxDrawdownPercent, using default: ", DEFAULT_MAX_DRAWDOWN);
    }
    else
        g_maxDrawdownPercent = MaxDrawdownPercent;
    
    // TMA Period
    if(TMA_Period < 2 || TMA_Period > 500)
    {
        g_tmaPeriod = DEFAULT_TMA_PERIOD;
        Print("WARNING: Invalid TMA_Period, using default: ", DEFAULT_TMA_PERIOD);
    }
    else
        g_tmaPeriod = TMA_Period;
    
    // TMA Slope Threshold
    if(TMA_SlopeThreshold < 0)
    {
        g_tmaSlopeThreshold = DEFAULT_TMA_THRESHOLD;
        Print("WARNING: Invalid TMA_SlopeThreshold, using default: ", DEFAULT_TMA_THRESHOLD);
    }
    else
        g_tmaSlopeThreshold = TMA_SlopeThreshold;
    
    // Use TMA Confirmation
    g_useTMAConfirmation = UseTMAConfirmation;
    
    // QQE RSI Period (2-100)
    if(QQE_RSI_Period < 2 || QQE_RSI_Period > 100)
    {
        g_qqeRSIPeriod = DEFAULT_QQE_RSI_PERIOD;
        Print("WARNING: Invalid QQE_RSI_Period, using default: ", DEFAULT_QQE_RSI_PERIOD);
    }
    else
        g_qqeRSIPeriod = QQE_RSI_Period;
    
    // QQE Smoothing (1-50)
    if(QQE_Smoothing < 1 || QQE_Smoothing > 50)
    {
        g_qqeSmoothing = DEFAULT_QQE_SMOOTHING;
        Print("WARNING: Invalid QQE_Smoothing, using default: ", DEFAULT_QQE_SMOOTHING);
    }
    else
        g_qqeSmoothing = QQE_Smoothing;
    
    // QQE ATR Multiplier (0.1-10.0)
    if(QQE_ATR_Multiplier < 0.1 || QQE_ATR_Multiplier > 10.0)
    {
        g_qqeATRMultiplier = DEFAULT_QQE_ATR_MULT;
        Print("WARNING: Invalid QQE_ATR_Multiplier, using default: ", DEFAULT_QQE_ATR_MULT);
    }
    else
        g_qqeATRMultiplier = QQE_ATR_Multiplier;
    
    // QQE Midline Threshold (0-25)
    if(QQE_MidlineThreshold < 0 || QQE_MidlineThreshold > 25)
    {
        g_qqeMidlineThreshold = DEFAULT_QQE_MIDLINE_THRESHOLD;
        Print("WARNING: Invalid QQE_MidlineThreshold, using default: ", DEFAULT_QQE_MIDLINE_THRESHOLD);
    }
    else
        g_qqeMidlineThreshold = QQE_MidlineThreshold;
    
    // QQE Enable Early Exit
    g_qqeEnableEarlyExit = QQE_EnableEarlyExit;
    
    // QQE Reversal Threshold
    if(QQE_ReversalThreshold < 0 || QQE_ReversalThreshold > 100)
    {
        g_qqeReversalThreshold = DEFAULT_QQE_REVERSAL_THRESHOLD;
        Print("WARNING: Invalid QQE_ReversalThreshold, using default: ", DEFAULT_QQE_REVERSAL_THRESHOLD);
    }
    else
        g_qqeReversalThreshold = QQE_ReversalThreshold;
    
    // RSIH Settings
    g_useRSIH = UseRSIH;
    
    // RSIH Period (2-100)
    if(RSIH_Period < 2 || RSIH_Period > 100)
    {
        g_rsihPeriod = DEFAULT_RSIH_PERIOD;
        Print("WARNING: Invalid RSIH_Period, using default: ", DEFAULT_RSIH_PERIOD);
    }
    else
        g_rsihPeriod = RSIH_Period;
    
    // ADX Settings
    g_useADXFilter = UseADXFilter;
    
    // ADX Period (5-100)
    if(ADX_Period < 5 || ADX_Period > 100)
    {
        g_adxPeriod = DEFAULT_ADX_PERIOD;
        Print("WARNING: Invalid ADX_Period, using default: ", DEFAULT_ADX_PERIOD);
    }
    else
        g_adxPeriod = ADX_Period;
    
    // ADX Smoothing (1-50)
    if(ADX_Smoothing < 1 || ADX_Smoothing > 50)
    {
        g_adxSmoothing = DEFAULT_ADX_SMOOTHING;
        Print("WARNING: Invalid ADX_Smoothing, using default: ", DEFAULT_ADX_SMOOTHING);
    }
    else
        g_adxSmoothing = ADX_Smoothing;
    
    // ADX Max Threshold (5-50)
    if(ADX_MaxThreshold < 5 || ADX_MaxThreshold > 50)
    {
        g_adxMaxThreshold = DEFAULT_ADX_MAX_THRESHOLD;
        Print("WARNING: Invalid ADX_MaxThreshold, using default: ", DEFAULT_ADX_MAX_THRESHOLD);
    }
    else
        g_adxMaxThreshold = ADX_MaxThreshold;
    
    // S/R Zone Settings
    g_useSRZones = UseSRZones;
    
    // S/R Lookback Bars (20-500)
    if(SR_LookbackBars < 20 || SR_LookbackBars > 500)
    {
        g_srLookbackBars = DEFAULT_SR_LOOKBACK;
        Print("WARNING: Invalid SR_LookbackBars, using default: ", DEFAULT_SR_LOOKBACK);
    }
    else
        g_srLookbackBars = SR_LookbackBars;
    
    // S/R Touch Count (1-10)
    if(SR_TouchCount < 1 || SR_TouchCount > 10)
    {
        g_srTouchCount = DEFAULT_SR_TOUCH_COUNT;
        Print("WARNING: Invalid SR_TouchCount, using default: ", DEFAULT_SR_TOUCH_COUNT);
    }
    else
        g_srTouchCount = SR_TouchCount;
    
    // S/R Zone Width (10-200 points)
    if(SR_ZoneWidth < 10 || SR_ZoneWidth > 200)
    {
        g_srZoneWidth = DEFAULT_SR_ZONE_WIDTH;
        Print("WARNING: Invalid SR_ZoneWidth, using default: ", DEFAULT_SR_ZONE_WIDTH);
    }
    else
        g_srZoneWidth = SR_ZoneWidth;
    
    // S/R Buy Bias (0.5-1.0)
    if(SR_BuyBias < 0.5 || SR_BuyBias > 1.0)
    {
        g_srBuyBias = DEFAULT_SR_BUY_BIAS;
        Print("WARNING: Invalid SR_BuyBias, using default: ", DEFAULT_SR_BUY_BIAS);
    }
    else
        g_srBuyBias = SR_BuyBias;
    
    // S/R Sell Bias (0.5-1.0)
    if(SR_SellBias < 0.5 || SR_SellBias > 1.0)
    {
        g_srSellBias = DEFAULT_SR_SELL_BIAS;
        Print("WARNING: Invalid SR_SellBias, using default: ", DEFAULT_SR_SELL_BIAS);
    }
    else
        g_srSellBias = SR_SellBias;
    
    // S/R Mix Ratio (0.0-0.5)
    if(SR_MixRatio < 0.0 || SR_MixRatio > 0.5)
    {
        g_srMixRatio = DEFAULT_SR_MIX_RATIO;
        Print("WARNING: Invalid SR_MixRatio, using default: ", DEFAULT_SR_MIX_RATIO);
    }
    else
        g_srMixRatio = SR_MixRatio;
    
    // Validate Order Flow parameters
    ValidateOrderFlowParameters();
    
    // Validate Fibonacci parameters
    ValidateFibonacciParameters();
}

//+------------------------------------------------------------------+
//| Initialize Grid State                                             |
//+------------------------------------------------------------------+
void InitializeGrid()
{
    ArrayResize(g_gridState.positions, 0);
    g_gridState.currentLevel = 0;
    g_gridState.lastGridPrice = 0;
    g_gridState.isActive = false;
    g_gridState.direction = POSITION_TYPE_BUY;
}

//+------------------------------------------------------------------+
//| Rebuild State From Existing Positions                             |
//+------------------------------------------------------------------+
void RebuildStateFromPositions()
{
    // Placeholder - will be fully implemented in Task 8
    int totalPositions = PositionsTotal();
    
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                // Found a position belonging to this bot
                GridPosition pos;
                pos.ticket = ticket;
                pos.lotSize = PositionGetDouble(POSITION_VOLUME);
                pos.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                pos.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                
                // Extract grid level from comment if possible
                string comment = PositionGetString(POSITION_COMMENT);
                pos.gridLevel = ExtractGridLevel(comment);
                
                // Add to tracked positions
                int size = ArraySize(g_gridState.positions);
                ArrayResize(g_gridState.positions, size + 1);
                g_gridState.positions[size] = pos;
                
                // Update grid state
                if(!g_gridState.isActive)
                {
                    g_gridState.isActive = true;
                    g_gridState.direction = pos.type;
                }
                
                if(pos.gridLevel > g_gridState.currentLevel)
                {
                    g_gridState.currentLevel = pos.gridLevel;
                    g_gridState.lastGridPrice = pos.openPrice;
                }
            }
        }
    }
    
    if(g_gridState.isActive)
    {
        Print("Rebuilt grid state: ", ArraySize(g_gridState.positions), 
              " positions, Level ", g_gridState.currentLevel);
    }
}

//+------------------------------------------------------------------+
//| Extract Grid Level from Comment                                   |
//+------------------------------------------------------------------+
int ExtractGridLevel(string comment)
{
    // Comment format: "HybridGrid_L1", "HybridGrid_L2", etc.
    int pos = StringFind(comment, "_L");
    if(pos >= 0)
    {
        string levelStr = StringSubstr(comment, pos + 2);
        return (int)StringToInteger(levelStr);
    }
    return 1; // Default to level 1 if not found
}

//+------------------------------------------------------------------+
//| Log Configuration                                                 |
//+------------------------------------------------------------------+
void LogConfiguration()
{
    Print("=== HybridGridBot Configuration ===");
    Print("Symbol: ", _Symbol);
    Print("Grid Step: ", g_gridStepPoints, " points");
    Print("Initial Lot: ", g_initialLotSize);
    Print("Martingale: ", g_martingaleMultiplier, "x");
    Print("Max Levels: ", g_maxGridLevels);
    Print("Target Profit: $", g_targetProfitUSD);
    Print("Max Drawdown: ", g_maxDrawdownPercent, "%");
    Print("Drawdown Sleep: ", g_drawdownSleepMinutes, " minutes");
    Print("--- QQE Settings (Primary Filter) ---");
    Print("QQE RSI Period: ", g_qqeRSIPeriod);
    Print("QQE Smoothing: ", g_qqeSmoothing);
    Print("QQE ATR Multiplier: ", g_qqeATRMultiplier);
    Print("QQE Midline Threshold: ", g_qqeMidlineThreshold);
    Print("QQE Early Exit: ", g_qqeEnableEarlyExit ? "Enabled" : "Disabled");
    Print("QQE Reversal Threshold: ", g_qqeReversalThreshold, "%");
    Print("--- RSIH Settings (Ehlers Hann-Windowed RSI) ---");
    Print("Use RSIH: ", g_useRSIH ? "Yes" : "No");
    Print("RSIH Period: ", g_rsihPeriod);
    Print("--- ADX Settings (Range/Trend Filter) ---");
    Print("Use ADX Filter: ", g_useADXFilter ? "Yes" : "No");
    Print("ADX Period: ", g_adxPeriod);
    Print("ADX Smoothing: ", g_adxSmoothing);
    Print("ADX Max Threshold: ", g_adxMaxThreshold);
    Print("--- TMA Settings (Secondary Filter) ---");
    Print("Use TMA Confirmation: ", g_useTMAConfirmation ? "Yes" : "No");
    Print("TMA Period: ", g_tmaPeriod);
    Print("TMA Threshold: ", g_tmaSlopeThreshold);
    Print("--- S/R Zone Settings ---");
    Print("Use S/R Zones: ", g_useSRZones ? "Yes" : "No");
    Print("S/R Lookback Bars: ", g_srLookbackBars);
    Print("S/R Touch Count: ", g_srTouchCount);
    Print("S/R Zone Width: ", g_srZoneWidth, " points");
    Print("S/R Buy Bias: ", g_srBuyBias);
    Print("S/R Sell Bias: ", g_srSellBias);
    Print("S/R Mix Ratio: ", g_srMixRatio);
    Print("--- Fibonacci Settings ---");
    Print("Use Fibonacci: ", g_useFibonacci ? "Yes" : "No");
    Print("Fib Swing Lookback: ", g_fibSwingLookback);
    Print("Fib Min Swing Bars: ", g_fibMinSwingBars);
    Print("Fib Anchor Grid Levels: ", g_fibAnchorGridLevels ? "Yes" : "No");
    Print("Fib Block Beyond 78.6%: ", g_fibBlockBeyond786 ? "Yes" : "No");
    Print("Fib Entry Zone: ", g_fibEntryZoneMin, "% - ", g_fibEntryZoneMax, "%");
    Print("Fib Show On Chart: ", g_fibShowOnChart ? "Yes" : "No");
    Print("Magic Number: ", MagicNumber);
    Print("===================================");
}

//+------------------------------------------------------------------+
//| Calculate Simple Moving Average                                   |
//+------------------------------------------------------------------+
double CalculateSMA(int period, int shift)
{
    double sum = 0;
    for(int i = 0; i < period; i++)
    {
        sum += iClose(_Symbol, PERIOD_CURRENT, shift + i);
    }
    return sum / period;
}

//+------------------------------------------------------------------+
//| Calculate Triangular Moving Average (Double-Smoothed SMA)         |
//+------------------------------------------------------------------+
double CalculateTMA(int shift)
{
    // TMA is a double-smoothed SMA
    // First, calculate SMA values, then smooth them again
    int halfPeriod = g_tmaPeriod / 2 + 1;
    
    double sum = 0;
    for(int i = 0; i < halfPeriod; i++)
    {
        sum += CalculateSMA(halfPeriod, shift + i);
    }
    return sum / halfPeriod;
}

//+------------------------------------------------------------------+
//| Get TMA Slope Value                                               |
//+------------------------------------------------------------------+
double GetTMASlope()
{
    double tma_current = CalculateTMA(0);
    double tma_previous = CalculateTMA(1);
    
    // Calculate slope normalized by point value
    return (tma_current - tma_previous) / _Point;
}

//+------------------------------------------------------------------+
//| Calculate RSI (Relative Strength Index)                           |
//+------------------------------------------------------------------+
double CalculateRSI(int period, int shift)
{
    double gains = 0;
    double losses = 0;
    
    for(int i = 0; i < period; i++)
    {
        double close_current = iClose(_Symbol, PERIOD_CURRENT, shift + i);
        double close_previous = iClose(_Symbol, PERIOD_CURRENT, shift + i + 1);
        double change = close_current - close_previous;
        
        if(change > 0)
            gains += change;
        else
            losses += MathAbs(change);
    }
    
    double avgGain = gains / period;
    double avgLoss = losses / period;
    
    if(avgLoss == 0)
        return 100.0;
    
    double rs = avgGain / avgLoss;
    double rsi = 100.0 - (100.0 / (1.0 + rs));
    
    return rsi;
}

//+------------------------------------------------------------------+
//| Calculate RSIH - Ehlers Hann-Windowed RSI (TASC Jan 2022)         |
//| Smoother RSI with zero mean using Hann windowing                  |
//| Eliminates need for additional filtering due to inherent smoothing|
//+------------------------------------------------------------------+
double CalculateRSIH(int period, int shift)
{
    // Hann-windowed price changes
    double hannGains = 0;
    double hannLosses = 0;
    double weightSum = 0;
    
    for(int i = 0; i < period; i++)
    {
        double close_current = iClose(_Symbol, PERIOD_CURRENT, shift + i);
        double close_previous = iClose(_Symbol, PERIOD_CURRENT, shift + i + 1);
        double change = close_current - close_previous;
        
        // Hann window coefficient: 0.5 * (1 - cos(2*PI*i/period))
        // This creates a smooth bell-shaped weighting
        double hannCoeff = 0.5 * (1.0 - MathCos(2.0 * M_PI * i / period));
        
        if(change > 0)
            hannGains += change * hannCoeff;
        else
            hannLosses += MathAbs(change) * hannCoeff;
        
        weightSum += hannCoeff;
    }
    
    // Normalize by weight sum
    if(weightSum > 0)
    {
        hannGains /= weightSum;
        hannLosses /= weightSum;
    }
    
    // Calculate RSIH with zero-mean adjustment
    // Standard RSI formula but with Hann-weighted values
    if(hannLosses == 0)
    {
        if(hannGains == 0)
            return 0.0;  // Zero mean when no movement
        return 50.0;     // Centered at 50 for pure gains
    }
    
    double rs = hannGains / hannLosses;
    
    // RSIH formula: produces zero-mean oscillator (-50 to +50 range)
    // This is the key difference from standard RSI
    double rsih = 50.0 * (rs - 1.0) / (rs + 1.0);
    
    return rsih;
}

//+------------------------------------------------------------------+
//| Get RSI Value (Standard or RSIH based on settings)                |
//+------------------------------------------------------------------+
double GetRSIValue(int period, int shift)
{
    if(g_useRSIH)
    {
        // RSIH returns -50 to +50, convert to 0-100 scale for QQE compatibility
        double rsih = CalculateRSIH(g_rsihPeriod, shift);
        return rsih + 50.0;  // Shift to 0-100 range
    }
    else
    {
        return CalculateRSI(period, shift);
    }
}

//+------------------------------------------------------------------+
//| Wilders Smoothing (EMA-like smoothing)                            |
//+------------------------------------------------------------------+
double WildersSmoothing(double currentValue, double previousSmoothed, int period)
{
    if(previousSmoothed == 0)
        return currentValue;
    return previousSmoothed + (currentValue - previousSmoothed) / period;
}

//+------------------------------------------------------------------+
//| Calculate ATR of RSI values                                       |
//+------------------------------------------------------------------+
double CalculateRSI_ATR(int period)
{
    double sum = 0;
    double prevRSI = CalculateRSI(g_qqeRSIPeriod, period);
    
    for(int i = 0; i < period; i++)
    {
        double currentRSI = CalculateRSI(g_qqeRSIPeriod, i);
        sum += MathAbs(currentRSI - prevRSI);
        prevRSI = currentRSI;
    }
    
    return sum / period;
}

//+------------------------------------------------------------------+
//| Update QQE Trailing Bands                                         |
//+------------------------------------------------------------------+
void UpdateTrailingBands(double bandDistance)
{
    double newBandUp = g_qqeState.qqeLine + bandDistance;
    double newBandDown = g_qqeState.qqeLine - bandDistance;
    
    // Trailing logic - bands only move in favorable direction
    if(g_qqeState.qqeLine > g_qqeState.trailingBandUp || g_qqeState.trailingBandUp == 0)
        g_qqeState.trailingBandUp = newBandUp;
    else if(newBandUp < g_qqeState.trailingBandUp)
        g_qqeState.trailingBandUp = newBandUp;
    
    if(g_qqeState.qqeLine < g_qqeState.trailingBandDown || g_qqeState.trailingBandDown == 0)
        g_qqeState.trailingBandDown = newBandDown;
    else if(newBandDown > g_qqeState.trailingBandDown)
        g_qqeState.trailingBandDown = newBandDown;
}

//+------------------------------------------------------------------+
//| Initialize QQE State                                              |
//+------------------------------------------------------------------+
void InitializeQQE()
{
    g_qqeState.qqeLine = 50.0;
    g_qqeState.qqeLinePrev = 50.0;
    g_qqeState.trailingBandUp = 0;
    g_qqeState.trailingBandDown = 0;
    g_qqeState.smoothedATR = 0;
    g_qqeState.rsiATR = 0;
    g_qqeState.signal = 0;
    g_qqeState.biasedSignal = 0;
    g_qqeState.histogram = 0;
    g_qqeState.crossedBandUp = false;
    g_qqeState.crossedBandDown = false;
    g_qqeState.rsihValue = 0;
    g_qqeState.rsihPrev = 0;
}

//+------------------------------------------------------------------+
//| Calculate QQE Indicator                                           |
//+------------------------------------------------------------------+
void CalculateQQE()
{
    // Step 1: Calculate RSI (standard or RSIH based on settings)
    double rsi = GetRSIValue(g_qqeRSIPeriod, 0);
    
    // Store raw RSIH value for display/analysis
    if(g_useRSIH)
    {
        g_qqeState.rsihPrev = g_qqeState.rsihValue;
        g_qqeState.rsihValue = CalculateRSIH(g_rsihPeriod, 0);
    }
    
    // Step 2: Apply Wilders smoothing to RSI (first smoothing)
    g_qqeState.qqeLinePrev = g_qqeState.qqeLine;
    g_qqeState.qqeLine = WildersSmoothing(rsi, g_qqeState.qqeLine, g_qqeSmoothing);
    
    // Step 3: Calculate ATR of the smoothed RSI
    double rsiATR = CalculateRSI_ATR(g_qqeSmoothing);
    
    // Step 4: Apply Wilders smoothing to ATR (second smoothing)
    g_qqeState.smoothedATR = WildersSmoothing(rsiATR, g_qqeState.smoothedATR, g_qqeSmoothing);
    
    // Step 5: Calculate trailing bands
    double bandDistance = g_qqeState.smoothedATR * g_qqeATRMultiplier;
    UpdateTrailingBands(bandDistance);
    
    // Step 6: Determine signal based on QQE line vs 50 mid-line
    int prevSignal = g_qqeState.signal;
    if(g_qqeState.qqeLine > 50 + g_qqeMidlineThreshold)
        g_qqeState.signal = 1;   // Bullish
    else if(g_qqeState.qqeLine < 50 - g_qqeMidlineThreshold)
        g_qqeState.signal = -1;  // Bearish
    else
        g_qqeState.signal = 0;   // Neutral (no trade zone)
    
    // Log signal changes
    if(prevSignal != g_qqeState.signal)
    {
        Print("========================================");
        Print("QQE SIGNAL CHANGE");
        Print("========================================");
        Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
        Print("Previous Signal: ", prevSignal == 1 ? "BUY" : (prevSignal == -1 ? "SELL" : "NEUTRAL"));
        Print("New Signal: ", g_qqeState.signal == 1 ? "BUY" : (g_qqeState.signal == -1 ? "SELL" : "NEUTRAL"));
        Print("QQE Line: ", DoubleToString(g_qqeState.qqeLine, 2));
        Print("QQE Previous: ", DoubleToString(g_qqeState.qqeLinePrev, 2));
        Print("Distance from 50: ", DoubleToString(MathAbs(g_qqeState.qqeLine - 50), 2));
        Print("Threshold: ", DoubleToString(g_qqeMidlineThreshold, 2));
        Print("========================================");
    }
    
    // Step 7: Update histogram color
    g_qqeState.histogram = (g_qqeState.qqeLine > g_qqeState.qqeLinePrev) ? 1 : -1;
    
    // Step 8: Check for band crossings (momentum burst signals)
    g_qqeState.crossedBandUp = (g_qqeState.qqeLinePrev <= g_qqeState.trailingBandUp && 
                                g_qqeState.qqeLine > g_qqeState.trailingBandUp);
    g_qqeState.crossedBandDown = (g_qqeState.qqeLinePrev >= g_qqeState.trailingBandDown && 
                                  g_qqeState.qqeLine < g_qqeState.trailingBandDown);
    
    // Log band crossings
    if(g_qqeState.crossedBandUp)
    {
        Print("QQE BAND CROSS: Crossed ABOVE upper band at ", DoubleToString(g_qqeState.trailingBandUp, 2));
    }
    if(g_qqeState.crossedBandDown)
    {
        Print("QQE BAND CROSS: Crossed BELOW lower band at ", DoubleToString(g_qqeState.trailingBandDown, 2));
    }
}

//+------------------------------------------------------------------+
//| Get QQE Signal for Trade Direction                                |
//+------------------------------------------------------------------+
int GetQQESignal()
{
    // Return biased signal if S/R zones are enabled
    if(g_useSRZones)
        return g_qqeState.biasedSignal;
    return g_qqeState.signal;  // 1=Buy, -1=Sell, 0=No trade
}

//+------------------------------------------------------------------+
//| Get QQE Line Value                                                |
//+------------------------------------------------------------------+
double GetQQELine()
{
    return g_qqeState.qqeLine;
}

//+------------------------------------------------------------------+
//| Check QQE Early Warning                                           |
//+------------------------------------------------------------------+
bool CheckQQEEarlyWarning()
{
    if(!g_gridState.isActive)
        return false;
    
    double distanceFrom50 = MathAbs(g_qqeState.qqeLine - 50);
    double prevDistanceFrom50 = MathAbs(g_qqeState.qqeLinePrev - 50);
    
    // Warning if QQE is moving back toward 50
    if(distanceFrom50 < prevDistanceFrom50 && prevDistanceFrom50 > 0)
    {
        double movementPercent = ((prevDistanceFrom50 - distanceFrom50) / prevDistanceFrom50) * 100;
        
        if(movementPercent >= g_qqeReversalThreshold)
        {
            Print("WARNING: QQE curving back toward 50 mid-line. Potential trend reversal. Movement: ", 
                  DoubleToString(movementPercent, 2), "%");
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check QQE Emergency Exit                                          |
//+------------------------------------------------------------------+
bool CheckQQEEmergencyExit()
{
    if(!g_gridState.isActive || !g_qqeEnableEarlyExit)
        return false;
    
    // Check if QQE crossed 50 in opposite direction of grid
    if(g_gridState.direction == POSITION_TYPE_BUY)
    {
        // Buy grid - exit if QQE crosses below 50
        if(g_qqeState.qqeLinePrev >= 50 && g_qqeState.qqeLine < 50)
        {
            Print("========================================");
            Print("QQE EMERGENCY EXIT TRIGGERED!");
            Print("========================================");
            Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
            Print("Reason: QQE crossed below 50 while Buy grid active");
            Print("QQE Previous: ", DoubleToString(g_qqeState.qqeLinePrev, 2));
            Print("QQE Current: ", DoubleToString(g_qqeState.qqeLine, 2));
            Print("Grid Direction: BUY");
            Print("Current Basket P/L: $", DoubleToString(CalculateBasketProfit(), 2));
            Print("----------------------------------------");
            LogAllIndicatorStates();
            Print("========================================");
            return true;
        }
    }
    else
    {
        // Sell grid - exit if QQE crosses above 50
        if(g_qqeState.qqeLinePrev <= 50 && g_qqeState.qqeLine > 50)
        {
            Print("========================================");
            Print("QQE EMERGENCY EXIT TRIGGERED!");
            Print("========================================");
            Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
            Print("Reason: QQE crossed above 50 while Sell grid active");
            Print("QQE Previous: ", DoubleToString(g_qqeState.qqeLinePrev, 2));
            Print("QQE Current: ", DoubleToString(g_qqeState.qqeLine, 2));
            Print("Grid Direction: SELL");
            Print("Current Basket P/L: $", DoubleToString(CalculateBasketProfit(), 2));
            Print("----------------------------------------");
            LogAllIndicatorStates();
            Print("========================================");
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if New Grid Can Be Opened Based on QQE (and optionally TMA) |
//+------------------------------------------------------------------+
bool CanOpenNewGrid(ENUM_POSITION_TYPE direction)
{
    // If grid is already active, allow management regardless of trend
    if(g_gridState.isActive)
        return true;
    
    // Primary filter: QQE
    int qqeSignal = GetQQESignal();
    
    if(qqeSignal == 0)
        return false;  // In neutral zone - no new grids
    
    bool qqeAllows = false;
    if(direction == POSITION_TYPE_BUY && qqeSignal == 1)
        qqeAllows = true;
    if(direction == POSITION_TYPE_SELL && qqeSignal == -1)
        qqeAllows = true;
    
    if(!qqeAllows)
        return false;
    
    // Order Flow filter: Check if order flow supports the direction
    if(g_useOrderFlow)
    {
        bool orderFlowAllows = false;
        
        if(direction == POSITION_TYPE_BUY && g_orderFlowState.allowBuy)
            orderFlowAllows = true;
        if(direction == POSITION_TYPE_SELL && g_orderFlowState.allowSell)
            orderFlowAllows = true;
        
        if(!orderFlowAllows)
        {
            static datetime lastOrderFlowLog = 0;
            if(TimeCurrent() - lastOrderFlowLog > 60)
            {
                Print("Order Flow filter blocking ", EnumToString(direction), " entry");
                Print("  Market Direction: ", g_orderFlowState.marketDirection == 1 ? "BUYERS" : 
                      (g_orderFlowState.marketDirection == -1 ? "SELLERS" : "NEUTRAL"));
                Print("  Pressure Index: ", DoubleToString(g_orderFlowState.pressureIndex, 3));
                Print("  Allow Buy: ", g_orderFlowState.allowBuy ? "YES" : "NO");
                Print("  Allow Sell: ", g_orderFlowState.allowSell ? "YES" : "NO");
                lastOrderFlowLog = TimeCurrent();
            }
            return false;
        }
    }
    
    // Fibonacci filter: Check if price is in valid Fib zone
    if(g_useFibonacci && g_fibState.isValid)
    {
        // Block entries beyond 78.6% if safety filter enabled
        if(g_fibBlockBeyond786 && g_fibState.beyondSafetyLevel)
        {
            static datetime lastFibSafetyLog = 0;
            if(TimeCurrent() - lastFibSafetyLog > 60)
            {
                Print("Fibonacci safety filter blocking entry - beyond 78.6% level");
                Print("  Current Fib Level: ", DoubleToString(g_fibState.currentFibLevel, 2), "%");
                Print("  Price: ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
                lastFibSafetyLog = TimeCurrent();
            }
            return false;
        }
        
        // Only allow entries in valid Fib entry zone
        if(!g_fibState.inEntryZone)
        {
            static datetime lastFibZoneLog = 0;
            if(TimeCurrent() - lastFibZoneLog > 60)
            {
                Print("Fibonacci filter blocking entry - not in entry zone");
                Print("  Current Fib Level: ", DoubleToString(g_fibState.currentFibLevel, 2), "%");
                Print("  Entry Zone: ", g_fibEntryZoneMin, "% - ", g_fibEntryZoneMax, "%");
                lastFibZoneLog = TimeCurrent();
            }
            return false;
        }
        
        // Check direction alignment
        bool fibAllows = false;
        if(direction == POSITION_TYPE_BUY && !g_fibState.isUptrend)
            fibAllows = true;  // Buy when retracing from low (bullish)
        if(direction == POSITION_TYPE_SELL && g_fibState.isUptrend)
            fibAllows = true;  // Sell when retracing from high (bearish)
        
        if(!fibAllows)
        {
            static datetime lastFibDirectionLog = 0;
            if(TimeCurrent() - lastFibDirectionLog > 60)
            {
                Print("Fibonacci filter blocking entry - wrong direction");
                Print("  Requested: ", EnumToString(direction));
                Print("  Fib Trend: ", g_fibState.isUptrend ? "Uptrend (sell retracement)" : "Downtrend (buy retracement)");
                lastFibDirectionLog = TimeCurrent();
            }
            return false;
        }
    }
    
    // ADX filter: Only allow entries when ADX < threshold (range condition)
    // BUT: If ADX state hasn't changed for a while, allow entry anyway
    if(g_useADXFilter)
    {
        static bool lastADXState = false;
        static int unchangedBars = 0;
        static datetime lastBarTime = 0;
        
        datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
        
        // Count how many bars ADX state has remained the same
        if(currentBarTime != lastBarTime)
        {
            if(g_adxState.allowEntry == lastADXState)
                unchangedBars++;
            else
            {
                unchangedBars = 0;
                lastADXState = g_adxState.allowEntry;
            }
            lastBarTime = currentBarTime;
        }
        
        // If ADX state hasn't changed for 10+ bars, ignore ADX filter
        if(unchangedBars < 10)
        {
            if(!g_adxState.allowEntry)
            {
                // ADX too high - strong trend, avoid grid entries
                Print("ADX filter blocking entry: ADX=", DoubleToString(g_adxState.adxValue, 2), 
                      " (unchanged for ", unchangedBars, " bars)");
                return false;
            }
        }
        else
        {
            Print("ADX filter bypassed: State unchanged for ", unchangedBars, " bars");
        }
    }
    
    // Secondary filter: TMA (optional)
    if(g_useTMAConfirmation)
    {
        double slope = GetTMASlope();
        
        if(MathAbs(slope) < g_tmaSlopeThreshold)
            return false;  // TMA in neutral zone
        
        if(direction == POSITION_TYPE_BUY && slope <= g_tmaSlopeThreshold)
            return false;  // TMA doesn't confirm buy
        
        if(direction == POSITION_TYPE_SELL && slope >= -g_tmaSlopeThreshold)
            return false;  // TMA doesn't confirm sell
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Permitted Grid Direction Based on QQE                         |
//+------------------------------------------------------------------+
ENUM_POSITION_TYPE GetPermittedDirection()
{
    int qqeSignal = GetQQESignal();
    
    if(qqeSignal == 1)
        return POSITION_TYPE_BUY;
    else if(qqeSignal == -1)
        return POSITION_TYPE_SELL;
    
    // Return current direction if in neutral zone (no new grids allowed)
    return g_gridState.direction;
}

//+------------------------------------------------------------------+
//| Initialize S/R Zone State                                         |
//+------------------------------------------------------------------+
void InitializeSRZones()
{
    g_srState.supportLevel = 0;
    g_srState.resistanceLevel = 0;
    g_srState.supportStrength = 0;
    g_srState.resistanceStrength = 0;
    g_srState.nearSupport = false;
    g_srState.nearResistance = false;
    g_srState.zoneBias = 0;
    
    // Initial S/R detection
    if(g_useSRZones)
        DetectSRZones();
}

//+------------------------------------------------------------------+
//| Detect Support and Resistance Zones                               |
//+------------------------------------------------------------------+
void DetectSRZones()
{
    double zoneWidthPrice = g_srZoneWidth * _Point;
    
    // Arrays to store potential S/R levels
    double swingLows[];
    double swingHighs[];
    ArrayResize(swingLows, 0);
    ArrayResize(swingHighs, 0);
    
    // Find swing highs and lows
    for(int i = 2; i < g_srLookbackBars - 2; i++)
    {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        
        // Check for swing high (higher than neighbors)
        if(high > iHigh(_Symbol, PERIOD_CURRENT, i-1) &&
           high > iHigh(_Symbol, PERIOD_CURRENT, i-2) &&
           high > iHigh(_Symbol, PERIOD_CURRENT, i+1) &&
           high > iHigh(_Symbol, PERIOD_CURRENT, i+2))
        {
            int size = ArraySize(swingHighs);
            ArrayResize(swingHighs, size + 1);
            swingHighs[size] = high;
        }
        
        // Check for swing low (lower than neighbors)
        if(low < iLow(_Symbol, PERIOD_CURRENT, i-1) &&
           low < iLow(_Symbol, PERIOD_CURRENT, i-2) &&
           low < iLow(_Symbol, PERIOD_CURRENT, i+1) &&
           low < iLow(_Symbol, PERIOD_CURRENT, i+2))
        {
            int size = ArraySize(swingLows);
            ArrayResize(swingLows, size + 1);
            swingLows[size] = low;
        }
    }
    
    // Find strongest support zone (most touches)
    double bestSupport = 0;
    int bestSupportTouches = 0;
    
    for(int i = 0; i < ArraySize(swingLows); i++)
    {
        int touches = CountTouchesInZone(swingLows[i], zoneWidthPrice, swingLows);
        if(touches >= g_srTouchCount && touches > bestSupportTouches)
        {
            bestSupportTouches = touches;
            bestSupport = swingLows[i];
        }
    }
    
    // Find strongest resistance zone (most touches)
    double bestResistance = 0;
    int bestResistanceTouches = 0;
    
    for(int i = 0; i < ArraySize(swingHighs); i++)
    {
        int touches = CountTouchesInZone(swingHighs[i], zoneWidthPrice, swingHighs);
        if(touches >= g_srTouchCount && touches > bestResistanceTouches)
        {
            bestResistanceTouches = touches;
            bestResistance = swingHighs[i];
        }
    }
    
    // Update state
    g_srState.supportLevel = bestSupport;
    g_srState.resistanceLevel = bestResistance;
    g_srState.supportStrength = bestSupportTouches;
    g_srState.resistanceStrength = bestResistanceTouches;
}

//+------------------------------------------------------------------+
//| Count Touches Within a Zone                                       |
//+------------------------------------------------------------------+
int CountTouchesInZone(double level, double zoneWidth, double &levels[])
{
    int count = 0;
    for(int i = 0; i < ArraySize(levels); i++)
    {
        if(MathAbs(levels[i] - level) <= zoneWidth)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Update S/R Zones and Check Proximity                              |
//+------------------------------------------------------------------+
void UpdateSRZones()
{
    static datetime lastUpdate = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    // Recalculate S/R zones every new bar
    if(currentBar != lastUpdate)
    {
        DetectSRZones();
        lastUpdate = currentBar;
    }
    
    // Check current price proximity to zones
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double zoneWidthPrice = g_srZoneWidth * _Point;
    
    g_srState.nearSupport = false;
    g_srState.nearResistance = false;
    g_srState.zoneBias = 0;
    
    // Check if near support
    if(g_srState.supportLevel > 0)
    {
        double distToSupport = currentPrice - g_srState.supportLevel;
        if(distToSupport >= 0 && distToSupport <= zoneWidthPrice * 2)
        {
            g_srState.nearSupport = true;
            g_srState.zoneBias = 1;  // Buy bias near support
        }
    }
    
    // Check if near resistance
    if(g_srState.resistanceLevel > 0)
    {
        double distToResistance = g_srState.resistanceLevel - currentPrice;
        if(distToResistance >= 0 && distToResistance <= zoneWidthPrice * 2)
        {
            g_srState.nearResistance = true;
            g_srState.zoneBias = -1;  // Sell bias near resistance
        }
    }
    
    // If near both (tight range), use QQE direction
    if(g_srState.nearSupport && g_srState.nearResistance)
    {
        g_srState.zoneBias = 0;  // Let QQE decide
    }
}

//+------------------------------------------------------------------+
//| Apply S/R Zone Bias to QQE Signal                                 |
//+------------------------------------------------------------------+
void ApplySRBiasToQQE()
{
    // Start with raw QQE signal
    g_qqeState.biasedSignal = g_qqeState.signal;
    
    // If QQE is neutral, no bias can help
    if(g_qqeState.signal == 0)
        return;
    
    // Apply zone bias
    if(g_srState.nearSupport && g_srState.zoneBias == 1)
    {
        // Near support - bias toward buys
        if(g_qqeState.signal == 1)
        {
            // QQE already bullish - strong buy signal
            g_qqeState.biasedSignal = 1;
        }
        else if(g_qqeState.signal == -1)
        {
            // QQE bearish but near support - apply mix logic
            // Use random to mix in some counter-trend trades
            double rand = MathRand() / 32767.0;
            if(rand < g_srBuyBias)
            {
                // Override to buy (support bounce expected)
                g_qqeState.biasedSignal = 1;
            }
            else if(rand < g_srBuyBias + g_srMixRatio)
            {
                // Allow the sell (catch breakdown)
                g_qqeState.biasedSignal = -1;
            }
            else
            {
                // Stay neutral
                g_qqeState.biasedSignal = 0;
            }
        }
    }
    else if(g_srState.nearResistance && g_srState.zoneBias == -1)
    {
        // Near resistance - bias toward sells
        if(g_qqeState.signal == -1)
        {
            // QQE already bearish - strong sell signal
            g_qqeState.biasedSignal = -1;
        }
        else if(g_qqeState.signal == 1)
        {
            // QQE bullish but near resistance - apply mix logic
            double rand = MathRand() / 32767.0;
            if(rand < g_srSellBias)
            {
                // Override to sell (resistance rejection expected)
                g_qqeState.biasedSignal = -1;
            }
            else if(rand < g_srSellBias + g_srMixRatio)
            {
                // Allow the buy (catch breakout)
                g_qqeState.biasedSignal = 1;
            }
            else
            {
                // Stay neutral
                g_qqeState.biasedSignal = 0;
            }
        }
    }
    // If not near any zone, use raw QQE signal (already set above)
}

//+------------------------------------------------------------------+
//| Get S/R Zone Info String for Display                              |
//+------------------------------------------------------------------+
string GetSRZoneInfo()
{
    string info = "";
    
    if(g_srState.supportLevel > 0)
        info += "S:" + DoubleToString(g_srState.supportLevel, _Digits) + 
                "(" + IntegerToString((int)g_srState.supportStrength) + ")";
    
    if(g_srState.resistanceLevel > 0)
    {
        if(info != "") info += " | ";
        info += "R:" + DoubleToString(g_srState.resistanceLevel, _Digits) + 
                "(" + IntegerToString((int)g_srState.resistanceStrength) + ")";
    }
    
    if(info == "") info = "No zones detected";
    
    return info;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size for Grid Level (Martingale)                    |
//+------------------------------------------------------------------+
double CalculateLotSize(int gridLevel)
{
    // Formula: InitialLotSize * (MartingaleMultiplier ^ (gridLevel - 1))
    double lots = g_initialLotSize * MathPow(g_martingaleMultiplier, gridLevel - 1);
    
    // Normalize to broker requirements
    lots = NormalizeLotSize(lots);
    
    return lots;
}

//+------------------------------------------------------------------+
//| Normalize Lot Size to Broker Requirements                         |
//+------------------------------------------------------------------+
double NormalizeLotSize(double lots)
{
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Clamp to min/max
    lots = MathMax(minLot, lots);
    lots = MathMin(maxLot, lots);
    
    // Round to lot step
    lots = MathFloor(lots / lotStep) * lotStep;
    
    // Final normalization
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Open Position Asynchronously                                      |
//+------------------------------------------------------------------+
bool OpenPositionAsync(ENUM_ORDER_TYPE orderType, double lots, int gridLevel)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    // Fill request structure
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = orderType;
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = "HybridGrid_L" + IntegerToString(gridLevel);
    
    // Set price based on order type
    if(orderType == ORDER_TYPE_BUY)
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    else
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Send order asynchronously
    bool sent = OrderSendAsync(request, result);
    
    if(sent)
    {
        Print("Order sent async - Request ID: ", result.request_id, 
              ", Type: ", EnumToString(orderType), 
              ", Lots: ", lots, 
              ", Level: ", gridLevel);
    }
    else
    {
        int error = GetLastError();
        Print("OrderSendAsync failed - Error: ", error, " - ", ErrorDescription(error));
        
        // Store for retry
        g_pendingRetry = true;
        g_retryRequest = request;
    }
    
    return sent;
}

//+------------------------------------------------------------------+
//| Close Position Asynchronously                                     |
//+------------------------------------------------------------------+
bool ClosePositionAsync(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
    {
        Print("Position not found for close: ", ticket);
        return false;
    }
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.position = ticket;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.deviation = 10;
    request.magic = MagicNumber;
    
    // Reverse the position type to close
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    if(posType == POSITION_TYPE_BUY)
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }
    else
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }
    
    bool sent = OrderSendAsync(request, result);
    
    if(sent)
    {
        Print("Close order sent async - Request ID: ", result.request_id, 
              ", Ticket: ", ticket);
    }
    else
    {
        Print("Close OrderSendAsync failed - Error: ", GetLastError());
    }
    
    return sent;
}

//+------------------------------------------------------------------+
//| Close All Positions Asynchronously                                |
//+------------------------------------------------------------------+
void CloseAllPositionsAsync()
{
    int count = ArraySize(g_gridState.positions);
    Print("Closing all positions - Count: ", count);
    
    for(int i = 0; i < count; i++)
    {
        ClosePositionAsync(g_gridState.positions[i].ticket);
    }
}

//+------------------------------------------------------------------+
//| Initialize ADX State                                              |
//+------------------------------------------------------------------+
void InitializeADX()
{
    g_adxState.adxValue = 0;
    g_adxState.plusDI = 0;
    g_adxState.minusDI = 0;
    g_adxState.allowEntry = false;
}

//+------------------------------------------------------------------+
//| Calculate True Range                                              |
//+------------------------------------------------------------------+
double CalculateTrueRange(int shift)
{
    double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double low = iLow(_Symbol, PERIOD_CURRENT, shift);
    double prevClose = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
    
    double tr1 = high - low;
    double tr2 = MathAbs(high - prevClose);
    double tr3 = MathAbs(low - prevClose);
    
    return MathMax(tr1, MathMax(tr2, tr3));
}

//+------------------------------------------------------------------+
//| Calculate Directional Movement                                    |
//+------------------------------------------------------------------+
void CalculateDirectionalMovement(int shift, double &plusDM, double &minusDM)
{
    double highCurrent = iHigh(_Symbol, PERIOD_CURRENT, shift);
    double highPrev = iHigh(_Symbol, PERIOD_CURRENT, shift + 1);
    double lowCurrent = iLow(_Symbol, PERIOD_CURRENT, shift);
    double lowPrev = iLow(_Symbol, PERIOD_CURRENT, shift + 1);
    
    double upMove = highCurrent - highPrev;
    double downMove = lowPrev - lowCurrent;
    
    plusDM = 0;
    minusDM = 0;
    
    if(upMove > downMove && upMove > 0)
        plusDM = upMove;
    
    if(downMove > upMove && downMove > 0)
        minusDM = downMove;
}

//+------------------------------------------------------------------+
//| Calculate ADX Indicator with Smoothing                            |
//+------------------------------------------------------------------+
void CalculateADX()
{
    // Step 1: Calculate DX values for multiple bars
    double dxValues[];
    ArrayResize(dxValues, g_adxPeriod + g_adxSmoothing);
    
    for(int i = 0; i < g_adxPeriod + g_adxSmoothing; i++)
    {
        // Calculate TR, +DM, -DM for this bar
        double sumTR = 0;
        double sumPlusDM = 0;
        double sumMinusDM = 0;
        
        // Sum over the ADX period
        for(int j = 0; j < g_adxPeriod; j++)
        {
            int shift = i + j;
            sumTR += CalculateTrueRange(shift);
            
            double plusDM, minusDM;
            CalculateDirectionalMovement(shift, plusDM, minusDM);
            sumPlusDM += plusDM;
            sumMinusDM += minusDM;
        }
        
        // Calculate +DI and -DI
        double plusDI = 0;
        double minusDI = 0;
        
        if(sumTR > 0)
        {
            plusDI = 100.0 * sumPlusDM / sumTR;
            minusDI = 100.0 * sumMinusDM / sumTR;
        }
        
        // Calculate DX
        double diSum = plusDI + minusDI;
        if(diSum > 0)
        {
            double diDiff = MathAbs(plusDI - minusDI);
            dxValues[i] = 100.0 * diDiff / diSum;
        }
        else
        {
            dxValues[i] = 0;
        }
        
        // Store current +DI and -DI for display
        if(i == 0)
        {
            g_adxState.plusDI = plusDI;
            g_adxState.minusDI = minusDI;
        }
    }
    
    // Step 2: Apply SMA smoothing to DX values to get ADX
    double adxSum = 0;
    for(int i = 0; i < g_adxSmoothing; i++)
    {
        adxSum += dxValues[i];
    }
    
    double prevADXValue = g_adxState.adxValue;
    g_adxState.adxValue = adxSum / g_adxSmoothing;
    
    // Determine if entry is allowed (ADX < threshold = range/low volatility)
    bool prevAllowEntry = g_adxState.allowEntry;
    g_adxState.allowEntry = (g_adxState.adxValue < g_adxMaxThreshold);
    
    // Log ADX state changes
    if(prevAllowEntry != g_adxState.allowEntry)
    {
        Print("========================================");
        Print("ADX STATE CHANGE");
        Print("========================================");
        Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
        Print("Previous State: ", prevAllowEntry ? "RANGE (Entry Allowed)" : "TREND (Entry Blocked)");
        Print("New State: ", g_adxState.allowEntry ? "RANGE (Entry Allowed)" : "TREND (Entry Blocked)");
        Print("ADX Value: ", DoubleToString(g_adxState.adxValue, 2));
        Print("Previous ADX: ", DoubleToString(prevADXValue, 2));
        Print("Threshold: ", DoubleToString(g_adxMaxThreshold, 2));
        Print("+DI: ", DoubleToString(g_adxState.plusDI, 2));
        Print("-DI: ", DoubleToString(g_adxState.minusDI, 2));
        Print("========================================");
    }
}

//+------------------------------------------------------------------+
//| Get Error Description                                             |
//+------------------------------------------------------------------+
string ErrorDescription(int errorCode)
{
    switch(errorCode)
    {
        case TRADE_RETCODE_REQUOTE:       return "Requote";
        case TRADE_RETCODE_REJECT:        return "Request rejected";
        case TRADE_RETCODE_CANCEL:        return "Request canceled";
        case TRADE_RETCODE_PLACED:        return "Order placed";
        case TRADE_RETCODE_DONE:          return "Request completed";
        case TRADE_RETCODE_DONE_PARTIAL:  return "Partial execution";
        case TRADE_RETCODE_ERROR:         return "Request processing error";
        case TRADE_RETCODE_TIMEOUT:       return "Request timeout";
        case TRADE_RETCODE_INVALID:       return "Invalid request";
        case TRADE_RETCODE_INVALID_VOLUME:return "Invalid volume";
        case TRADE_RETCODE_INVALID_PRICE: return "Invalid price";
        case TRADE_RETCODE_NO_MONEY:      return "Insufficient funds";
        case TRADE_RETCODE_MARKET_CLOSED: return "Market closed";
        case TRADE_RETCODE_TRADE_DISABLED:return "Trading disabled";
        default:                          return "Unknown error";
    }
}

//+------------------------------------------------------------------+
//| Initialize Order Flow State                                       |
//+------------------------------------------------------------------+
void InitializeOrderFlow()
{
    // Reset all order flow metrics
    g_orderFlowState.bidLevelCount = 0;
    g_orderFlowState.askLevelCount = 0;
    
    for(int i = 0; i < 10; i++)
    {
        g_orderFlowState.bidLevels[i].price = 0;
        g_orderFlowState.bidLevels[i].volume = 0;
        g_orderFlowState.bidLevels[i].levelIndex = i + 1;
        
        g_orderFlowState.askLevels[i].price = 0;
        g_orderFlowState.askLevels[i].volume = 0;
        g_orderFlowState.askLevels[i].levelIndex = i + 1;
    }
    
    g_orderFlowState.staticImbalance = 0;
    g_orderFlowState.volumeWeightedImbalance = 0;
    g_orderFlowState.imbalanceMomentum = 0;
    g_orderFlowState.imbalanceEMA = 0;
    
    g_orderFlowState.cumulativeDelta = 0;
    g_orderFlowState.normalizedDelta = 0;
    g_orderFlowState.lastTradePrice = 0;
    g_orderFlowState.totalVolume = 0;
    
    g_orderFlowState.bidAbsorptionRate = 0;
    g_orderFlowState.askAbsorptionRate = 0;
    g_orderFlowState.prevBidLevel1Volume = 0;
    g_orderFlowState.prevAskLevel1Volume = 0;
    g_orderFlowState.lastAbsorptionUpdate = TimeCurrent();
    
    g_orderFlowState.pressureIndex = 0;
    g_orderFlowState.adjustedImbalance = 0;
    g_orderFlowState.marketDirection = 0;
    
    g_orderFlowState.currentSpread = 0;
    g_orderFlowState.atr14 = CalculateATR(14, 0);
    
    g_orderFlowState.allowBuy = true;
    g_orderFlowState.allowSell = true;
    
    Print("Order Flow state initialized");
}

//+------------------------------------------------------------------+
//| Update Order Book Data from Market Depth                          |
//+------------------------------------------------------------------+
void UpdateOrderBookData()
{
    MqlBookInfo book[];
    
    if(!MarketBookGet(_Symbol, book))
    {
        Print("Failed to get Market Book data");
        return;
    }
    
    // Reset counters
    g_orderFlowState.bidLevelCount = 0;
    g_orderFlowState.askLevelCount = 0;
    
    // Parse order book levels
    for(int i = 0; i < ArraySize(book) && i < g_orderBookDepth; i++)
    {
        if(book[i].type == BOOK_TYPE_BUY || book[i].type == BOOK_TYPE_BUY_MARKET)
        {
            // Bid side
            if(g_orderFlowState.bidLevelCount < 10)
            {
                int idx = g_orderFlowState.bidLevelCount;
                g_orderFlowState.bidLevels[idx].price = book[i].price;
                g_orderFlowState.bidLevels[idx].volume = book[i].volume_real;
                g_orderFlowState.bidLevels[idx].levelIndex = idx + 1;
                g_orderFlowState.bidLevelCount++;
            }
        }
        else if(book[i].type == BOOK_TYPE_SELL || book[i].type == BOOK_TYPE_SELL_MARKET)
        {
            // Ask side
            if(g_orderFlowState.askLevelCount < 10)
            {
                int idx = g_orderFlowState.askLevelCount;
                g_orderFlowState.askLevels[idx].price = book[i].price;
                g_orderFlowState.askLevels[idx].volume = book[i].volume_real;
                g_orderFlowState.askLevels[idx].levelIndex = idx + 1;
                g_orderFlowState.askLevelCount++;
            }
        }
    }
    
    // Update spread
    if(g_orderFlowState.bidLevelCount > 0 && g_orderFlowState.askLevelCount > 0)
    {
        g_orderFlowState.currentSpread = g_orderFlowState.askLevels[0].price - 
                                          g_orderFlowState.bidLevels[0].price;
    }
}

//+------------------------------------------------------------------+
//| Calculate Order Book Imbalances                                   |
//+------------------------------------------------------------------+
void CalculateOrderBookImbalances()
{
    // 1. Static Order Book Imbalance (SOBI)
    double totalBidVolume = 0;
    double totalAskVolume = 0;
    
    for(int i = 0; i < g_orderFlowState.bidLevelCount; i++)
        totalBidVolume += g_orderFlowState.bidLevels[i].volume;
    
    for(int i = 0; i < g_orderFlowState.askLevelCount; i++)
        totalAskVolume += g_orderFlowState.askLevels[i].volume;
    
    double totalVolume = totalBidVolume + totalAskVolume;
    if(totalVolume > 0)
    {
        g_orderFlowState.staticImbalance = (totalBidVolume - totalAskVolume) / totalVolume;
    }
    else
    {
        g_orderFlowState.staticImbalance = 0;
    }
    
    // 2. Volume-Weighted Order Book Imbalance (VWOI)
    // Weight by proximity: closer levels have more impact
    double weightedBidSum = 0;
    double weightedAskSum = 0;
    
    for(int i = 0; i < g_orderFlowState.bidLevelCount; i++)
    {
        double weight = 1.0 / (i + 1);  // Level 1 = weight 1.0, Level 2 = 0.5, etc.
        weightedBidSum += g_orderFlowState.bidLevels[i].volume * weight;
    }
    
    for(int i = 0; i < g_orderFlowState.askLevelCount; i++)
    {
        double weight = 1.0 / (i + 1);
        weightedAskSum += g_orderFlowState.askLevels[i].volume * weight;
    }
    
    double weightedTotal = weightedBidSum + weightedAskSum;
    if(weightedTotal > 0)
    {
        g_orderFlowState.volumeWeightedImbalance = (weightedBidSum - weightedAskSum) / weightedTotal;
    }
    else
    {
        g_orderFlowState.volumeWeightedImbalance = 0;
    }
    
    // 3. Imbalance Momentum (current vs EMA)
    // Update EMA of imbalance
    double alpha = 2.0 / (g_imbalanceEMAPeriod + 1);
    if(g_orderFlowState.imbalanceEMA == 0)
        g_orderFlowState.imbalanceEMA = g_orderFlowState.volumeWeightedImbalance;
    else
        g_orderFlowState.imbalanceEMA = alpha * g_orderFlowState.volumeWeightedImbalance + 
                                         (1 - alpha) * g_orderFlowState.imbalanceEMA;
    
    g_orderFlowState.imbalanceMomentum = g_orderFlowState.volumeWeightedImbalance - 
                                          g_orderFlowState.imbalanceEMA;
    
    // 4. Bid-Ask Spread Normalization
    if(g_orderFlowState.atr14 > 0)
    {
        double spreadFactor = 1.0 - (g_orderFlowState.currentSpread / g_orderFlowState.atr14);
        spreadFactor = MathMax(0, MathMin(1.0, spreadFactor));  // Clamp to [0, 1]
        g_orderFlowState.adjustedImbalance = g_orderFlowState.volumeWeightedImbalance * spreadFactor;
    }
    else
    {
        g_orderFlowState.adjustedImbalance = g_orderFlowState.volumeWeightedImbalance;
    }
}

//+------------------------------------------------------------------+
//| Update Order Flow Metrics on Tick (Delta Volume)                  |
//+------------------------------------------------------------------+
void UpdateOrderFlowOnTick()
{
    // Update ATR for spread normalization
    g_orderFlowState.atr14 = CalculateATR(14, 0);
    
    // Track delta volume (executed aggression)
    MqlTick lastTick;
    if(!SymbolInfoTick(_Symbol, lastTick))
        return;
    
    double currentPrice = lastTick.last;
    double currentVolume = (double)lastTick.volume;
    
    if(g_orderFlowState.lastTradePrice > 0)
    {
        // Determine if trade was buyer or seller initiated
        if(currentPrice > g_orderFlowState.lastTradePrice)
        {
            // Buyer initiated (aggressive buy)
            g_orderFlowState.cumulativeDelta += currentVolume;
        }
        else if(currentPrice < g_orderFlowState.lastTradePrice)
        {
            // Seller initiated (aggressive sell)
            g_orderFlowState.cumulativeDelta -= currentVolume;
        }
        // If price unchanged, don't update delta
    }
    
    g_orderFlowState.lastTradePrice = currentPrice;
    g_orderFlowState.totalVolume += currentVolume;
    
    // Normalize delta by total volume
    if(g_orderFlowState.totalVolume > 0)
    {
        g_orderFlowState.normalizedDelta = g_orderFlowState.cumulativeDelta / 
                                            g_orderFlowState.totalVolume;
    }
    
    // Reset cumulative metrics periodically (every DeltaVolumePeriod ticks)
    static int tickCount = 0;
    tickCount++;
    if(tickCount >= g_deltaVolumePeriod)
    {
        g_orderFlowState.cumulativeDelta = 0;
        g_orderFlowState.totalVolume = 0;
        tickCount = 0;
    }
}

//+------------------------------------------------------------------+
//| Calculate Absorption Rates                                        |
//+------------------------------------------------------------------+
void CalculateAbsorptionRates()
{
    datetime currentTime = TimeCurrent();
    double timeDelta = (double)(currentTime - g_orderFlowState.lastAbsorptionUpdate);
    
    if(timeDelta < 1)
        return;  // Need at least 1 second between updates
    
    // Calculate bid absorption (how fast bid liquidity is being consumed)
    if(g_orderFlowState.bidLevelCount > 0)
    {
        double currentBidVolume = g_orderFlowState.bidLevels[0].volume;
        double volumeChange = g_orderFlowState.prevBidLevel1Volume - currentBidVolume;
        
        if(g_orderFlowState.prevBidLevel1Volume > 0)
        {
            g_orderFlowState.bidAbsorptionRate = volumeChange / timeDelta;
        }
        
        g_orderFlowState.prevBidLevel1Volume = currentBidVolume;
    }
    
    // Calculate ask absorption (how fast ask liquidity is being consumed)
    if(g_orderFlowState.askLevelCount > 0)
    {
        double currentAskVolume = g_orderFlowState.askLevels[0].volume;
        double volumeChange = g_orderFlowState.prevAskLevel1Volume - currentAskVolume;
        
        if(g_orderFlowState.prevAskLevel1Volume > 0)
        {
            g_orderFlowState.askAbsorptionRate = volumeChange / timeDelta;
        }
        
        g_orderFlowState.prevAskLevel1Volume = currentAskVolume;
    }
    
    g_orderFlowState.lastAbsorptionUpdate = currentTime;
}

//+------------------------------------------------------------------+
//| Calculate Composite Pressure Index                                |
//+------------------------------------------------------------------+
void CalculateCompositePressure()
{
    // Composite Pressure = w1*VWOI + w2*NormalizedDelta + w3*AbsorptionRate
    
    // Normalize absorption rate to [-1, 1] range
    double maxAbsorption = MathMax(MathAbs(g_orderFlowState.bidAbsorptionRate), 
                                    MathAbs(g_orderFlowState.askAbsorptionRate));
    double normalizedAbsorption = 0;
    
    if(maxAbsorption > 0)
    {
        // Positive if bid absorption > ask absorption (sellers overpowering)
        // Negative if ask absorption > bid absorption (buyers overpowering)
        normalizedAbsorption = (g_orderFlowState.bidAbsorptionRate - 
                                g_orderFlowState.askAbsorptionRate) / maxAbsorption;
    }
    
    // Calculate weighted pressure index
    g_orderFlowState.pressureIndex = 
        g_pressureWeightVWOI * g_orderFlowState.volumeWeightedImbalance +
        g_pressureWeightDelta * g_orderFlowState.normalizedDelta +
        g_pressureWeightAbsorption * normalizedAbsorption;
    
    // Clamp to [-1, 1]
    g_orderFlowState.pressureIndex = MathMax(-1.0, MathMin(1.0, g_orderFlowState.pressureIndex));
}

//+------------------------------------------------------------------+
//| Determine Market Direction (Who is Winning)                       |
//+------------------------------------------------------------------+
void DetermineMarketDirection()
{
    int prevDirection = g_orderFlowState.marketDirection;
    
    // Use pressure index to determine direction
    if(g_orderFlowState.pressureIndex > g_imbalanceThreshold)
    {
        g_orderFlowState.marketDirection = 1;  // Buyers winning
        g_orderFlowState.allowBuy = true;
        g_orderFlowState.allowSell = false;
    }
    else if(g_orderFlowState.pressureIndex < -g_imbalanceThreshold)
    {
        g_orderFlowState.marketDirection = -1;  // Sellers winning
        g_orderFlowState.allowBuy = false;
        g_orderFlowState.allowSell = true;
    }
    else
    {
        g_orderFlowState.marketDirection = 0;  // Neutral
        
        // In neutral zone, check if pressure index meets minimum threshold
        if(MathAbs(g_orderFlowState.pressureIndex) >= g_minPressureIndex)
        {
            // Allow both directions if there's some pressure
            g_orderFlowState.allowBuy = (g_orderFlowState.pressureIndex > 0);
            g_orderFlowState.allowSell = (g_orderFlowState.pressureIndex < 0);
        }
        else
        {
            // Too neutral - block both
            g_orderFlowState.allowBuy = false;
            g_orderFlowState.allowSell = false;
        }
    }
    
    // Log direction changes
    if(prevDirection != g_orderFlowState.marketDirection)
    {
        Print("========================================");
        Print("ORDER FLOW DIRECTION CHANGE");
        Print("========================================");
        Print("Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
        Print("Previous: ", prevDirection == 1 ? "BUYERS" : (prevDirection == -1 ? "SELLERS" : "NEUTRAL"));
        Print("New: ", g_orderFlowState.marketDirection == 1 ? "BUYERS" : 
              (g_orderFlowState.marketDirection == -1 ? "SELLERS" : "NEUTRAL"));
        Print("Pressure Index: ", DoubleToString(g_orderFlowState.pressureIndex, 3));
        Print("VWOI: ", DoubleToString(g_orderFlowState.volumeWeightedImbalance, 3));
        Print("Normalized Delta: ", DoubleToString(g_orderFlowState.normalizedDelta, 3));
        Print("========================================");
    }
}

//+------------------------------------------------------------------+
//| Calculate ATR for Spread Normalization                            |
//+------------------------------------------------------------------+
double CalculateATR(int period, int shift)
{
    double sum = 0;
    for(int i = shift; i < shift + period; i++)
    {
        sum += CalculateTrueRange(i);
    }
    return sum / period;
}

//+------------------------------------------------------------------+
//| Validate Order Flow Parameters                                    |
//+------------------------------------------------------------------+
void ValidateOrderFlowParameters()
{
    g_useOrderFlow = UseOrderFlow;
    
    // Order Book Depth (1-10)
    if(OrderBookDepth < 1 || OrderBookDepth > 10)
    {
        g_orderBookDepth = DEFAULT_ORDER_BOOK_DEPTH;
        Print("WARNING: Invalid OrderBookDepth, using default: ", DEFAULT_ORDER_BOOK_DEPTH);
    }
    else
        g_orderBookDepth = OrderBookDepth;
    
    // Delta Volume Period (10-1000)
    if(DeltaVolumePeriod < 10 || DeltaVolumePeriod > 1000)
    {
        g_deltaVolumePeriod = DEFAULT_DELTA_VOLUME_PERIOD;
        Print("WARNING: Invalid DeltaVolumePeriod, using default: ", DEFAULT_DELTA_VOLUME_PERIOD);
    }
    else
        g_deltaVolumePeriod = DeltaVolumePeriod;
    
    // Imbalance Threshold (0-1)
    if(ImbalanceThreshold < 0 || ImbalanceThreshold > 1)
    {
        g_imbalanceThreshold = DEFAULT_IMBALANCE_THRESHOLD;
        Print("WARNING: Invalid ImbalanceThreshold, using default: ", DEFAULT_IMBALANCE_THRESHOLD);
    }
    else
        g_imbalanceThreshold = ImbalanceThreshold;
    
    // Pressure Weights (must sum to ~1.0)
    double weightSum = PressureWeight_VWOI + PressureWeight_Delta + PressureWeight_Absorption;
    if(weightSum < 0.9 || weightSum > 1.1)
    {
        Print("WARNING: Pressure weights don't sum to 1.0, normalizing...");
        g_pressureWeightVWOI = DEFAULT_PRESSURE_WEIGHT_VWOI;
        g_pressureWeightDelta = DEFAULT_PRESSURE_WEIGHT_DELTA;
        g_pressureWeightAbsorption = DEFAULT_PRESSURE_WEIGHT_ABSORPTION;
    }
    else
    {
        g_pressureWeightVWOI = PressureWeight_VWOI;
        g_pressureWeightDelta = PressureWeight_Delta;
        g_pressureWeightAbsorption = PressureWeight_Absorption;
    }
    
    // Imbalance EMA Period (10-500)
    if(ImbalanceEMA_Period < 10 || ImbalanceEMA_Period > 500)
    {
        g_imbalanceEMAPeriod = DEFAULT_IMBALANCE_EMA_PERIOD;
        Print("WARNING: Invalid ImbalanceEMA_Period, using default: ", DEFAULT_IMBALANCE_EMA_PERIOD);
    }
    else
        g_imbalanceEMAPeriod = ImbalanceEMA_Period;
    
    // Min Pressure Index (0-1)
    if(MinPressureIndex < 0 || MinPressureIndex > 1)
    {
        g_minPressureIndex = DEFAULT_MIN_PRESSURE_INDEX;
        Print("WARNING: Invalid MinPressureIndex, using default: ", DEFAULT_MIN_PRESSURE_INDEX);
    }
    else
        g_minPressureIndex = MinPressureIndex;
}

//+------------------------------------------------------------------+
//| Validate Fibonacci Parameters                                     |
//+------------------------------------------------------------------+
void ValidateFibonacciParameters()
{
    g_useFibonacci = UseFibonacci;
    
    // Fib Swing Lookback (20-200)
    if(Fib_SwingLookback < 20 || Fib_SwingLookback > 200)
    {
        g_fibSwingLookback = 50;
        Print("WARNING: Invalid Fib_SwingLookback, using default: 50");
    }
    else
        g_fibSwingLookback = Fib_SwingLookback;
    
    // Fib Min Swing Bars (2-20)
    if(Fib_MinSwingBars < 2 || Fib_MinSwingBars > 20)
    {
        g_fibMinSwingBars = 5;
        Print("WARNING: Invalid Fib_MinSwingBars, using default: 5");
    }
    else
        g_fibMinSwingBars = Fib_MinSwingBars;
    
    g_fibAnchorGridLevels = Fib_AnchorGridLevels;
    g_fibBlockBeyond786 = Fib_BlockBeyond786;
    
    // Fib Entry Zone Min (0-100)
    if(Fib_EntryZoneMin < 0 || Fib_EntryZoneMin > 100)
    {
        g_fibEntryZoneMin = 38.2;
        Print("WARNING: Invalid Fib_EntryZoneMin, using default: 38.2");
    }
    else
        g_fibEntryZoneMin = Fib_EntryZoneMin;
    
    // Fib Entry Zone Max (0-100)
    if(Fib_EntryZoneMax < 0 || Fib_EntryZoneMax > 100 || Fib_EntryZoneMax < Fib_EntryZoneMin)
    {
        g_fibEntryZoneMax = 78.6;
        Print("WARNING: Invalid Fib_EntryZoneMax, using default: 78.6");
    }
    else
        g_fibEntryZoneMax = Fib_EntryZoneMax;
    
    g_fibShowOnChart = Fib_ShowOnChart;
}
