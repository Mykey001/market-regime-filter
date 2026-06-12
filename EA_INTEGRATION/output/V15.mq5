//+------------------------------------------------------------------+
//|                     V15 Standalone Grid Defense EA.mq5            |
//|                      Extracted from v16.1 Combined Regime         |
//|                      V15 Breakout + Grid Defense System           |
//+------------------------------------------------------------------+
#property copyright "V15 Standalone Strategy"
#property version   "15.11"
#property strict

#include <Trade/Trade.mqh>
#include "RegimeFilterLib.mqh"  // ML Regime Filter Integration
CTrade trade;

//+------------------------------------------------------------------+
//| V15 STANDALONE ARCHITECTURE                                       |
//| ----------------------------------------------------------------- |
//| ALWAYS ACTIVE: V15 Breakout/Trend logic runs on every bar        |
//| ----------------------------------------------------------------- |
//| GRID DEFENSE SYSTEM (from v16.1)                                 |
//| ├── Layer 1: Impulse Detection → Freeze grid during momentum      |
//| ├── Layer 2: Dynamic Grid Spacing → ATR-based adaptive spacing    |
//| ├── Layer 3: Lot Scaling Control → Hybrid sequence with caps      |
//| ├── Layer 4: Grid Expansion Lock → Hard limits on grid size       |
//| ├── Layer 5: Partial Shedding → Intelligent position reduction    |
//| └── Layer 6: Equity Kill Switch → Final catastrophic protection   |
//+------------------------------------------------------------------+

// Input Parameters
input group "=== Telegram Settings ==="
input bool UseTelegram = false;
input string TelegramToken = "7950524854:AAGkeh9aIWgCk9MVA4UShJQC7aoDQa7Tfq8";
input string TelegramChatID = "-1003572893349";

input group "=== GRID DEFENSE SYSTEM SETTINGS ==="
input bool EnableImpulseDetection = true;
input bool EnableDynamicSpacing = true;
input bool EnableLotScaling = true;
input bool EnableExpansionLock = false;
input bool EnablePartialShedding = false;
input bool EnableKillSwitch = false;

input group "=== IMPULSE DETECTION SETTINGS ==="
input double ImpulseATRMultiplier = 1.8;
input double ImpulseCandleBodyPct = 0.70;
input double ImpulseEMAExpansionPct = 0.50;
input double ImpulseWickRetracement = 0.25;
input int ImpulseDeactivationBars = 2;

input group "=== DYNAMIC GRID SPACING SETTINGS ==="
input double GridSpacingNormalMult = 2.0;    // Increased to 2.0 per ATR-based Spacing Fix
input double GridSpacingImpulseMult = 2.5;
input int GridSpacingMinPoints = 100;
input int GridSpacingMaxPoints = 500;
input double GridSpacingRecalcThreshold = 0.20;

input group "=== LOT SCALING SETTINGS ==="
input double LotSequence1 = 0.01;
input double LotSequence2 = 0.02;
input double LotSequence3 = 0.03;
input double LotSequence4 = 0.05;
input double LotSequence5 = 0.08;
input double LotSequence6 = 0.12;
input double MaxLotPerLevel = 0.12;
input double MaxTotalGridExposure = 0.50;

input group "=== EXPANSION LOCK SETTINGS ==="
input int DefenseMaxGridLevels = 5;
input double MaxRangeATRMultiplier = 1.5;

input group "=== PARTIAL SHEDDING SETTINGS ==="
input double SheddingEquityThreshold = 0.12;
input double SheddingATRExtension = 2.0;
input double SheddingRSIThreshold = 75.0;
input double MaxSheddingPercent = 0.50;
input int SheddingCooldownSeconds = 60;

input group "=== KILL SWITCH SETTINGS ==="
input double KillSwitchDrawdownPct = 0.20;
input int KillSwitchCooldownMinutes = 30;

input group "=== RANGE DETECTOR SETTINGS ==="
input bool   EnableRangeDetector = false;              // Enable Range Detector Drawing
input ENUM_TIMEFRAMES RangeDetectorTF = PERIOD_CURRENT; // Range Detector Timeframe
input int    InpMinRangeLen   = 20;                   // Minimum Range Length
input double InpRangeWidth    = 1.0;                  // Range Width (ATR multiplier)
input int    InpATRLength     = 500;                  // ATR Length
input color  InpUpColor       = C'8,153,129';         // Broken Upward Color
input color  InpDnColor       = C'242,54,69';         // Broken Downward Color
input color  InpUnbrokenColor = C'33,87,243';         // Unbroken Range Color

input group "=== CAPITAL ALLOCATION ==="
input double V15_RiskMultiplier = 1.0;

input group "=== KELLY CRITERION SETTINGS ==="
input bool   EnableKellyCriterion     = false;      // Enable Kelly Lot Sizing
input double KellyWinRate             = 0.55;      // Historical Win Rate (0.0 - 1.0)
input double KellyAvgWin              = 150.0;     // Average Win ($)
input double KellyAvgLoss             = 100.0;     // Average Loss ($)
input double KellyFraction            = 0.5;       // Fractional Kelly (0.25=Quarter, 0.5=Half, 1.0=Full)
input double KellyMinLot              = 0.01;      // Minimum Kelly Lot
input double KellyMaxLot              = 0.50;      // Maximum Kelly Lot
input double KellyMaxRiskPct          = 5.0;       // Max Risk Per Trade (% of equity)
input int    KellyLookbackTrades      = 50;        // Lookback Trades for Adaptive Kelly (0=use inputs)

input group "=== ADAPTIVE BASKET PROFIT SETTINGS ==="
input bool   EnableAdaptiveBasket     = false;      // Enable Equity-Scaled Basket Target
input double BasketBasePct            = 0.5;       // Base Basket Target (% of equity)
input double BasketMinUSD             = 5.0;       // Minimum Basket Target ($)
input double BasketMaxUSD             = 500.0;     // Maximum Basket Target ($)
input double BasketGrowthFactor       = 1.2;       // Growth Acceleration Factor

input group "=== PROGRESSIVE DRAWDOWN CONTROL ==="
input bool   EnableProgressiveDD      = false;      // Enable Progressive DD Protection
input double DDThrottleLevel1Pct      = 5.0;       // DD Level 1 — reduce lot by 50%
input double DDThrottleLevel2Pct      = 10.0;      // DD Level 2 — reduce lot by 75%
input double DDThrottleLevel3Pct      = 15.0;      // DD Level 3 — stop new entries
input double DDRecoveryBuffer         = 2.0;       // Recovery buffer before re-enabling (%)

input group "=== V15 BREAKOUT DETECTION SETTINGS ==="
input ENUM_TIMEFRAMES BreakoutTF = PERIOD_H1;
input int ConsolidationBars = 8;
input double RangeATRMultiplier = 1.5;
input double BreakoutATRMultiplier = 1.0;
input double VolumeBreakoutMultiplier = 1.2;
input double ADXBreakoutThreshold = 25.0;
input bool RequireEMAAlignment = true;
input int BreakoutEMAFast = 5;
input int BreakoutEMASlow = 15;
input double BollingerSqueezePct = 2.0;
input int BollingerPeriod = 20;
input double BollingerDeviation = 2.0;

input group "=== V15 MAIN EA (SCALPING) SETTINGS ==="
input int FastEMA = 5;
input int SlowEMA = 15;
input ENUM_TIMEFRAMES TF_1HR = PERIOD_M1;
input ENUM_TIMEFRAMES TF_15M = PERIOD_M5;
input ENUM_TIMEFRAMES TF_1M = PERIOD_M1;
input double InitialLotSize = 0.01;
input int Slippage = 30;
input int MagicNumber_V15 = 161015;

input group "=== V15 GRID SETTINGS ==="
input double LotMultiplier = 2.0;
input int GridStepPoints = 200;
input int MaxGridLevels = 5;
input double BasketProfitUSD = 10.0;
input double BasketMaxLossUSD = 500.0;
input bool EnableGridCandleConfirm = true;  // Require candle confirmation for grid layers

input group "=== DAILY LIMIT SETTINGS ==="
input bool   UseDailyProfitLimit = false;
input double DailyProfitLimitUSD = 100.0;

input group "=== PROFIT LOCK SETTINGS ==="
input bool   UseBasketProfitLock = true;
input double BasketProfitLockTriggerPct = 60.0;
input double BasketProfitLockRetainPct  = 50.0;

// LuxSessions Settings
input group "=== LUX SESSIONS SETTINGS ==="
input bool   EnableLuxSessions= false;       // Enable LuxAlgo Sessions
input bool   LuxShowSesA      = true;       // Show Session A
input string LuxTxtSesA       = "New York"; // Session A Name
input string LuxTimeSesA      = "1300-2200";// Session A Time
input color  LuxColorSesA     = C'255,93,0';// Session A Color
input bool   LuxRangeA        = true;       // Show Range A
input bool   LuxTrendlineA    = false;      // Show Trendline A
input bool   LuxMeanA         = false;      // Show Mean A
input bool   LuxVwapA         = false;      // Show VWAP A

input bool   LuxShowSesB      = true;       // Show Session B
input string LuxTxtSesB       = "London";   // Session B Name
input string LuxTimeSesB      = "0700-1600";// Session B Time
input color  LuxColorSesB     = C'33,87,243';
input bool   LuxRangeB        = true;
input bool   LuxTrendlineB    = false;
input bool   LuxMeanB         = false;
input bool   LuxVwapB         = false;

input bool   LuxShowSesC      = true;       // Show Session C
input string LuxTxtSesC       = "Tokyo";    // Session C Name
input string LuxTimeSesC      = "0000-0900";// Session C Time
input color  LuxColorSesC     = C'233,30,99';
input bool   LuxRangeC        = true;
input bool   LuxTrendlineC    = false;
input bool   LuxMeanC         = false;
input bool   LuxVwapC         = false;

input bool   LuxShowSesD      = true;       // Show Session D
input string LuxTxtSesD       = "Sydney";   // Session D Name
input string LuxTimeSesD      = "2100-0600";// Session D Time
input color  LuxColorSesD     = C'255,235,59';
input bool   LuxRangeD        = true;
input bool   LuxTrendlineD    = false;
input bool   LuxMeanD         = false;
input bool   LuxVwapD         = false;

input int    LuxBgTransp      = 90;         // Range Area Transparency (0-100)
input bool   LuxShowOutline   = true;       // Range Outline
input bool   LuxShowTxt       = true;       // Range Label
input bool   LuxShowDash      = true;       // Show Dashboard
input bool   LuxAdvDash       = true;       // Advanced Dashboard
enum ENUM_LUX_DASH_LOC { LUX_TOP_RIGHT, LUX_BOTTOM_RIGHT, LUX_BOTTOM_LEFT };
input ENUM_LUX_DASH_LOC LuxDashLoc = LUX_TOP_RIGHT;
input bool   LuxShowDayDiv    = true;       // Show Daily Divider

input group "=== V15 COUNTER TRADE SETTINGS ==="
input bool UseCounterTrades = false;
input double CounterTradeLossThreshold = 200.0;
input double CounterTradeLotSize = 0.01;
input int MaxCounterTrades = 5;
input double CounterLotMultiplier = 1.5;
input double RecoveryMultiplier = 1.5;
input double MinCounterProfitUSD = 5.0;
input double MaxCounterProfitUSD = 100.0;
input bool UseDrawdownWeighting = true;
input bool   EnableCounterDefense     = true;      // Enable Level 3/4 Counter Defense
input double CounterDefenseBasketProfit = 5.0;     // Profit target for counter defense basket ($)
input bool   CounterDefenseUseBreakeven = true;    // Close counter trades when price returns to entry

input group "=== COUNTER TRADE RSI FILTER ==="
input bool   EnableCounterRSIFilter = true;        // Enable RSI Filter for Counter Trades
input double CounterRSI_Upper       = 60.0;        // RSI Upper Boundary
input double CounterRSI_Lower       = 30.0;        // RSI Lower Boundary

input group "=== STALE EQUITY DETECTION ==="
input bool   EnableStaleEquityClose    = true;      // Close all if equity stalls
input int    StaleEquityMinutes        = 60;        // Duration of stall before closing (minutes)
input double StaleEquityToleranceUSD   = 2.0;       // Max P&L change considered "stale" ($)

input group "=== MARGIN RECOVERY SETTINGS ==="
input bool   EnableMarginRecovery         = true;      // Enable Margin Recovery Trade
input double MarginRecoveryRSI_Overbought = 70.0;      // RSI Upper Level for SELL grid
input double MarginRecoveryRSI_Oversold   = 30.0;      // RSI Lower Level for BUY grid
input double MarginRecoveryFreeMarginPct  = 80.0;      // Percentage of free margin to use
input double MarginRecoveryMinLossUSD     = 100.0;     // Minimum floating loss ($) to trigger
input double MarginRecoveryBreakEvenUSD   = 0.0;       // Profit level to switch to "Ride" mode
input double MarginRecoveryTargetProfitUSD = 50.0;     // Final target to close recovery basket
input bool   MarginRecoveryUseADXFilter   = true;     // Only open recovery when ADX is decreasing

input group "=== ADX HEDGE EXIT SETTINGS ==="
input bool   EnableADXHoldHedge        = true;      // Hold hedge while ADX is increasing
input ENUM_TIMEFRAMES HedgeExitADXTF   = PERIOD_M1;  // ADX Timeframe for exit logic
input int    HedgeExitADXPeriod        = 14;         // ADX Period

//+------------------------------------------------------------------+
//| V15 FILTERS                                                        |
//+------------------------------------------------------------------+
input group "=== V15 FILTERS ==="
input bool UseReverseMode = true;
input bool UseVolumeFilter = false;
input double VolumeMultiplier = 1.2;
input bool UseTrendFilter = false;
input bool AllowCounterTrend = false;
input bool UseBreakoutFilter = false;
input bool UseThreeCandleMomentumEntry = true;
input bool UseMomentumCandleOnly = true;     // Trade ONLY on 3-candle momentum (pauses EMA signal)
input bool WaitForCandleClose = false;         // Wait for signal candle to close before entry

input group "=== HTF TREND & STRUCTURE FILTERS ==="
input bool   UseHTFTrendEMAFilter = true;         // Block buys below / sells above HTF EMA
input ENUM_TIMEFRAMES HTF_EMA_TF  = PERIOD_H1;    // Timeframe for HTF Trend EMA
input int    HTF_EMA_Period       = 50;           // EMA Period (e.g. 50 or 200)
input bool   UseHTFStructureFilter = true;        // Block contra-structure entries (BOS/CHoCH)
input ENUM_TIMEFRAMES HTF_Structure_TF = PERIOD_H1; // Timeframe for Structure Detection
input int    HTF_SwingStrength    = 3;            // Swing High/Low Strength (bars on each side)

input group "=== ADX ENTRY FILTER SETTINGS ==="
input bool   UseADXEntryFilter = true;        // Block entry if trend is too strong against it
input double ADXEntryThreshold = 25.0;        // Trend strength threshold (25-30 is strong)
input int    ADXEntryPeriod    = 14;          // ADX lookback period
input ENUM_TIMEFRAMES ADXEntryTF = PERIOD_M1; // ADX ENTRY Timeframe (DEFAULT: M1)

input group "=== REGIME FILTER SETTINGS ==="
input bool   UseRegimeFilter = false;
input ENUM_TIMEFRAMES RegimeTF = PERIOD_H1;
input int    RegimeHurstLen  = 30;
input int    RegimeChopLen   = 14;
input int    RegimeSMALen    = 200;
input int    RegimeATRLen    = 14;

input group "=== VISUAL SETTINGS ==="
input bool ShowSignalTable = false;
input bool ShowDebugInfo = true;
input bool ShowDefenseStatus = false;
input color BuyColor = clrLime;
input color SellColor = clrRed;


//+------------------------------------------------------------------+
//| ENUMS                                                              |
//+------------------------------------------------------------------+
enum ENUM_MARKET_STRUCTURE {
    MS_BULLISH,
    MS_BEARISH,
    MS_NEUTRAL
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                         |
//+------------------------------------------------------------------+

struct GridPosition {
    ulong ticket;
    double lotSize;
    double openPrice;
    int level;
    bool isCounterTrade;
    double targetProfit;
    double drawdownAtOpen;
    int engine;
};

struct SignalInfo {
    string type;
    double entryPrice;
    string trend_1H;
    string trend_15M;
    string trend_1M;
    datetime signalTime;
    bool isValid;
    string reason;
    bool isBreakout;
    double breakoutStrength;
};

//+------------------------------------------------------------------+
//| DEFENSE SYSTEM STRUCTURES                                          |
//+------------------------------------------------------------------+

struct ImpulseState {
    bool isActive;
    datetime activationTime;
    string triggerCondition;
    int consecutiveNormalBars;
    double atrSpike;
    double emaExpansion;
    int momentumCandles;
};

struct GridSpacingState {
    double currentStep;
    double lastATR;
    double normalMultiplier;
    double impulseMultiplier;
    datetime lastRecalculation;
};

struct LotScalingConfig {
    double sequence[6];
    double maxLotPerLevel;
    double maxTotalExposure;
};

struct ExpansionLockState {
    bool isLocked;
    string lockReason;
    int currentLevels;
    double priceRangePoints;
    double firstEntryPrice;
    double h1ATR;
};

struct SheddingState {
    bool evaluationTriggered;
    int priority;
    datetime lastSheddingTime;
    int positionsShed;
};

struct KillSwitchState {
    double sessionHighEquity;
    double currentDrawdownPct;
    bool triggered;
    bool inCooldown;
    datetime cooldownEndTime;
};

struct DefenseSystemState {
    ImpulseState impulse;
    GridSpacingState spacing;
    LotScalingConfig lotConfig;
    ExpansionLockState expansionLock;
    SheddingState shedding;
    KillSwitchState killSwitch;
    bool gridExpansionAllowed;
    string blockingLayer;
    string blockingReason;
};

struct DefenseStatistics {
    int impulseActivations;
    int spacingRecalculations;
    int lotCapApplications;
    int expansionLockActivations;
    int sheddingExecutions;
    int killSwitchTriggers;
    double totalLotsShed;
    double totalLossAvoided;
};

struct KellyState {
    double currentKellyPct;       // Raw Kelly output (f*)
    double fractionalKellyPct;    // After applying fraction
    double kellyLotSize;          // Computed lot from Kelly
    double currentWinRate;        // Live or input win rate
    double currentPayoffRatio;    // Live or input R (avg win / avg loss)
    double equityAtCalc;          // Equity when last calculated
    int    totalWins;             // Tracked wins
    int    totalLosses;           // Tracked losses
    double sumWins;               // Sum of winning trade profits
    double sumLosses;             // Sum of losing trade losses (absolute)
    double ddThrottleMultiplier;  // 1.0=full, 0.5=half, 0.25=quarter, 0.0=stopped
    string ddThrottleLevel;       // "NORMAL", "LEVEL1", "LEVEL2", "LEVEL3"
    double currentBasketTarget;   // Dynamic basket profit target
    double initialEquity;         // Equity at EA start (for growth tracking)
};


//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+

// === DEFENSE SYSTEM ===
ImpulseState g_impulseState;
GridSpacingState g_spacingState;
LotScalingConfig g_lotConfig;
ExpansionLockState g_expansionLockState;
SheddingState g_sheddingState;
KillSwitchState g_killSwitchState;
DefenseSystemState g_defenseState;
DefenseStatistics g_defenseStats;
KellyState g_kellyState;

int g_defenseATRHandle = INVALID_HANDLE;
int g_defenseEMAFastHandle = INVALID_HANDLE;
int g_defenseEMASlowHandle = INVALID_HANDLE;
int g_defenseRSIHandle = INVALID_HANDLE;
int g_h1ATRHandle = INVALID_HANDLE;  // H1 ATR for expansion lock
int g_hedgeExitADXHandle = INVALID_HANDLE; // ADX handle for hedge exit logic

// === RANGE DETECTOR STATE ===
int    g_rd_atrHandle = INVALID_HANDLE;
int    g_rd_maHandle = INVALID_HANDLE;
string g_rd_objPrefix = "RngDet_EA_";
int    g_rd_boxCount  = 0;
int    g_rd_os        = 0;
double g_rd_rangeMax  = 0;
double g_rd_rangeMin  = 0;
string g_rd_curBoxName = "";
string g_rd_curLineName = "";
int    g_rd_prevCount = -1;
datetime g_rd_lastProcessedBarTime = 0;

int g_adxEntryHandle = INVALID_HANDLE;

// === V15 ENGINE ===
int g_htfTrendEMAHandle = INVALID_HANDLE;
ENUM_MARKET_STRUCTURE g_htfMarketStructure = MS_NEUTRAL;
double g_lastSwingHigh = 0;
double g_lastSwingLow = 0;

int atrHandle;
int bollingerHandle;
int breakoutEMAFastHandle;
int breakoutEMASlowHandle;
int breakoutADXHandle;
int breakoutVolumeHandle;

double atrBuffer[];
double bollingerUpper[];
double bollingerLower[];
double bollingerMiddle[];
double breakoutEMAFast[];
double breakoutEMASlow[];
double breakoutADX[];
double breakoutVolume[];

int regimeATRHandle = INVALID_HANDLE;

int fastEmaHandle_1M, slowEmaHandle_1M;
int fastEmaHandle_15M, slowEmaHandle_15M;
int fastEmaHandle_1H, slowEmaHandle_1H;
int volumeHandle_1M;

double fastEma_1M[], slowEma_1M[];
double fastEma_15M[], slowEma_15M[];
double fastEma_1H[], slowEma_1H[];
double tickVolume[];

// Daily limit tracking
double g_dailyStartEquity = 0;
datetime g_currentDay = 0;
bool g_dailyLimitReached = false;

// Basket Profit Lock tracking
bool v15BasketProfitLocked = false;

// LuxSessions structural tracking
struct LuxSessionState
{
    bool   isActive;
    int    startBar;
    datetime startTime;
    datetime lastTime;
    
    double maxVal;
    double minVal;
    double sumClose;
    double sumWtClose;
    double sumVolume;
    double sumCloseSquare;
    double sumWmaClose;
    
    int    barCount;
    int    boxCount;
    
    string boxName;
    string lblName;
    string tlName;
    string meanName;
    
    double stdev;
    double r2;
};

LuxSessionState g_luxStateA, g_luxStateB, g_luxStateC, g_luxStateD;
datetime g_lux_lastProcessedBarTime = 0;

// Consolidation tracking
double consolidationHigh = 0;
double consolidationLow = 0;
int consolidationBarCount = 0;
bool inConsolidation = false;
datetime lastBreakoutTime = 0;
string lastBreakoutDirection = "";

// Grid tracking
GridPosition v15GridPositions[];
int v15CurrentGridLevel = 0;
string v15CurrentGridDirection = "";
double v15LastGridPrice = 0;
int v15CounterTradeCount = 0;
bool v15CounterTradesEnabled = false;
double v15PeakDrawdown = 0;
int v15BreakoutTradesExecuted = 0;
double v15TotalRecoveredProfit = 0;
int v15CounterTradesClosedProfit = 0;

// Counter Defense Tracking
bool v15Level3Pending = false;
bool v15Level4Pending = false;
bool v15CounterDefenseActive = false;

// Stale Equity Detection
datetime v15StaleEquityStartTime = 0;   // When the equity first appeared stale
double  v15StaleEquityBaseline = 0;     // P&L snapshot when stale period started
bool    v15StaleEquityTracking = false;  // Are we currently tracking a stale period?

// Margin Recovery Tracking
bool v15MarginRecoveryActive = false;
bool v15RecoveryAtBreakEven = false;  // Is the recovery currently riding to target?
bool v15TriggerRecoveryAfterHedge = false; // Flag to trace hedge exit and trigger recovery

// Grid candle confirmation state
bool   v15GridPaused       = false;  // Grid paused waiting for confirming candle
bool   v15GridLevelPending  = false;  // A grid level is pending confirmation

// Signal tracking
datetime lastBarTime;
datetime lastSignalTime = 0;
datetime lastCounterSignalTime = 0;
int signalCount = 0;
int tradeCount = 0;
SignalInfo currentSignal;

// Pending signal (wait for candle close)
bool hasPendingSignal = false;
SignalInfo pendingSignal;

//+------------------------------------------------------------------+
//| Order Filling Auto-Detection                                     |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode(string symbol)
{
    long fill_flags = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
    
    // Check if Fill Or Kill is allowed
    if((fill_flags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
        return ORDER_FILLING_FOK;
        
    // Check if Immediate Or Cancel is allowed
    if((fill_flags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
        return ORDER_FILLING_IOC;
        
    // Default to Return
    return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+

// ==================== ML Regime Filter Settings ====================
input bool     EnableRegimeFilter = true;      // Enable ML regime filter
input string   RegimeFilterHost = "127.0.0.1"; // Python GUI host  
input int      RegimeFilterPort = 9090;        // Python GUI port
// ====================================================================

int OnInit()
{
    
    // ===== ML Regime Filter Initialization =====
    if(EnableRegimeFilter)
    {
        Print("=== Initializing ML Regime Filter ===");
        if(InitRegimeFilter(RegimeFilterHost, RegimeFilterPort, EnableRegimeFilter))
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

    // Auto-detect and configure broker filling mode globally for CTrade execution
    trade.SetTypeFilling(GetFillingMode(_Symbol));

    Print("========================================");
    Print("V15 Standalone Grid Defense EA v15.10 Starting...");
    Print("Architecture: V15 Breakout Engine + 6-Layer Defense System");
    Print("========================================");

    if(!InitializeDefenseSystem())
    {
        Print("ERROR: Failed to initialize Defense System!");
        return(INIT_FAILED);
    }

    if(EnableRangeDetector)
    {
        g_rd_atrHandle = iATR(_Symbol, RangeDetectorTF, InpATRLength);
        g_rd_maHandle = iMA(_Symbol, RangeDetectorTF, InpMinRangeLen, 0, MODE_SMA, PRICE_CLOSE);
        if(g_rd_atrHandle == INVALID_HANDLE || g_rd_maHandle == INVALID_HANDLE)
            Print("Warning: Failed to create Range Detector indicators");
            
        g_rd_boxCount   = 0;
        g_rd_os         = 0;
        g_rd_rangeMax   = 0;
        g_rd_rangeMin   = 0;
        g_rd_curBoxName = "";
        g_rd_curLineName = "";
        g_rd_prevCount  = -1;
        g_rd_lastProcessedBarTime = 0;
    }

    if(!InitializeV15Engine())
    {
        Print("ERROR: Failed to initialize V15 Engine!");
        return(INIT_FAILED);
    }
    // Initialize ADX Entry Filter
    g_adxEntryHandle = iADX(_Symbol, ADXEntryTF, ADXEntryPeriod);
    if(g_adxEntryHandle == INVALID_HANDLE)
        Print("Warning: Failed to create ADX Entry Filter handle");

    // Initialize ADX Hedge Exit Handle
    g_hedgeExitADXHandle = iADX(_Symbol, HedgeExitADXTF, HedgeExitADXPeriod);
    if(g_hedgeExitADXHandle == INVALID_HANDLE)
        Print("Warning: Failed to create ADX Hedge Exit handle");

    // Initialize state
    ArrayResize(v15GridPositions, 0);
    lastBarTime = 0;
    currentSignal.isValid = false;
    v15CurrentGridLevel = 0;
    v15CurrentGridDirection = "";
    v15LastGridPrice = 0;
    v15CounterTradeCount = 0;
    v15CounterTradesEnabled = false;
    v15PeakDrawdown = 0;
    v15BreakoutTradesExecuted = 0;
    v15GridPaused = false;
    v15GridLevelPending = false;
    v15Level3Pending = false;
    v15Level4Pending = false;
    v15CounterDefenseActive = false;
    v15StaleEquityTracking = false;
    v15StaleEquityStartTime = 0;
    v15StaleEquityBaseline = 0;
    v15MarginRecoveryActive = false;
    v15TriggerRecoveryAfterHedge = false;

    // Initialize Kelly Criterion
    InitializeKellyState();

    CreateSignalTable();

    Print("--- V15 Engine Settings ---");
    Print("Breakout TF: ", EnumToString(BreakoutTF));
    Print("Grid Step: ", GridStepPoints, " pts | Max Levels: ", MaxGridLevels);
    Print("Basket Target: $", BasketProfitUSD, " | Max Loss: $", BasketMaxLossUSD);
    Print("--- Defense System Settings ---");
    Print("Impulse Detection: ", EnableImpulseDetection ? "ENABLED" : "DISABLED");
    Print("Dynamic Spacing: ", EnableDynamicSpacing ? "ENABLED" : "DISABLED");
    Print("Lot Scaling: ", EnableLotScaling ? "ENABLED" : "DISABLED");
    Print("Expansion Lock: ", EnableExpansionLock ? "ENABLED" : "DISABLED");
    Print("Partial Shedding: ", EnablePartialShedding ? "ENABLED" : "DISABLED");
    Print("Kill Switch: ", EnableKillSwitch ? "ENABLED" : "DISABLED");
    if(EnableKellyCriterion)
    {
        Print("--- Kelly Criterion Settings ---");
        Print("Kelly f*: ", DoubleToString(g_kellyState.currentKellyPct * 100, 2), "% | Fractional: ", DoubleToString(g_kellyState.fractionalKellyPct * 100, 2), "%");
        Print("Kelly Lot: ", DoubleToString(g_kellyState.kellyLotSize, 2), " | Basket Target: $", DoubleToString(g_kellyState.currentBasketTarget, 2));
        Print("Progressive DD: ", EnableProgressiveDD ? "ENABLED" : "DISABLED");
    }
    Print("========================================");

    SendEAStartedNotification();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Initialize Defense System                                          |
//+------------------------------------------------------------------+
bool InitializeDefenseSystem()
{
    Print("Initializing Grid Defense System...");

    ZeroMemory(g_impulseState);
    g_impulseState.isActive = false;

    ZeroMemory(g_spacingState);
    g_spacingState.currentStep = GridStepPoints;
    g_spacingState.normalMultiplier = GridSpacingNormalMult;
    g_spacingState.impulseMultiplier = GridSpacingImpulseMult;

    ZeroMemory(g_lotConfig);
    g_lotConfig.sequence[0] = LotSequence1;
    g_lotConfig.sequence[1] = LotSequence2;
    g_lotConfig.sequence[2] = LotSequence3;
    g_lotConfig.sequence[3] = LotSequence4;
    g_lotConfig.sequence[4] = LotSequence5;
    g_lotConfig.sequence[5] = LotSequence6;
    g_lotConfig.maxLotPerLevel = MaxLotPerLevel;
    g_lotConfig.maxTotalExposure = MaxTotalGridExposure;

    ZeroMemory(g_expansionLockState);
    g_expansionLockState.isLocked = false;

    ZeroMemory(g_sheddingState);

    ZeroMemory(g_killSwitchState);
    g_killSwitchState.sessionHighEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    ZeroMemory(g_defenseState);
    g_defenseState.gridExpansionAllowed = true;

    ZeroMemory(g_defenseStats);

    // Defense indicator handles
    g_defenseATRHandle = iATR(_Symbol, PERIOD_M1, 14);
    g_defenseEMAFastHandle = iMA(_Symbol, PERIOD_M1, 9, 0, MODE_EMA, PRICE_CLOSE);
    g_defenseEMASlowHandle = iMA(_Symbol, PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
    g_defenseRSIHandle = iRSI(_Symbol, PERIOD_M1, 14, PRICE_CLOSE);

    // H1 ATR for expansion lock range calculation
    g_h1ATRHandle = iATR(_Symbol, PERIOD_H1, 14);

    if(g_defenseATRHandle == INVALID_HANDLE)
        Print("Warning: Failed to create Defense ATR indicator");
    if(g_defenseEMAFastHandle == INVALID_HANDLE || g_defenseEMASlowHandle == INVALID_HANDLE)
        Print("Warning: Failed to create Defense EMA indicators");
    if(g_defenseRSIHandle == INVALID_HANDLE)
        Print("Warning: Failed to create Defense RSI indicator");
    if(g_h1ATRHandle == INVALID_HANDLE)
        Print("Warning: Failed to create H1 ATR indicator");

    Print("Defense System initialized successfully");
    return true;
}

//+------------------------------------------------------------------+
//| Initialize V15 Engine                                              |
//+------------------------------------------------------------------+
bool InitializeV15Engine()
{
    atrHandle = iATR(_Symbol, BreakoutTF, 14);
    bollingerHandle = iBands(_Symbol, BreakoutTF, BollingerPeriod, 0, BollingerDeviation, PRICE_CLOSE);
    breakoutEMAFastHandle = iMA(_Symbol, BreakoutTF, BreakoutEMAFast, 0, MODE_EMA, PRICE_CLOSE);
    breakoutEMASlowHandle = iMA(_Symbol, BreakoutTF, BreakoutEMASlow, 0, MODE_EMA, PRICE_CLOSE);
    breakoutADXHandle = iADX(_Symbol, BreakoutTF, 14);
    breakoutVolumeHandle = iVolumes(_Symbol, BreakoutTF, VOLUME_TICK);
    regimeATRHandle = iATR(_Symbol, RegimeTF, RegimeATRLen);

    if(atrHandle == INVALID_HANDLE || bollingerHandle == INVALID_HANDLE ||
       breakoutEMAFastHandle == INVALID_HANDLE || breakoutEMASlowHandle == INVALID_HANDLE ||
       breakoutADXHandle == INVALID_HANDLE || breakoutVolumeHandle == INVALID_HANDLE ||
       regimeATRHandle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create V15 breakout or regime indicators!");
        return false;
    }

    fastEmaHandle_1M = iMA(_Symbol, TF_1M, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
    slowEmaHandle_1M = iMA(_Symbol, TF_1M, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
    fastEmaHandle_15M = iMA(_Symbol, TF_15M, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
    slowEmaHandle_15M = iMA(_Symbol, TF_15M, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
    fastEmaHandle_1H = iMA(_Symbol, TF_1HR, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
    slowEmaHandle_1H = iMA(_Symbol, TF_1HR, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
    volumeHandle_1M = iVolumes(_Symbol, TF_1M, VOLUME_TICK);

    if(fastEmaHandle_1M == INVALID_HANDLE || slowEmaHandle_1M == INVALID_HANDLE ||
       fastEmaHandle_15M == INVALID_HANDLE || slowEmaHandle_15M == INVALID_HANDLE ||
       fastEmaHandle_1H == INVALID_HANDLE || slowEmaHandle_1H == INVALID_HANDLE ||
       volumeHandle_1M == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create V15 EMA indicators!");
        return false;
    }

    ArraySetAsSeries(atrBuffer, true);
    ArraySetAsSeries(bollingerUpper, true);
    ArraySetAsSeries(bollingerLower, true);
    ArraySetAsSeries(bollingerMiddle, true);
    ArraySetAsSeries(breakoutEMAFast, true);
    ArraySetAsSeries(breakoutEMASlow, true);
    ArraySetAsSeries(breakoutADX, true);
    ArraySetAsSeries(breakoutVolume, true);
    ArraySetAsSeries(fastEma_1M, true);
    ArraySetAsSeries(slowEma_1M, true);
    ArraySetAsSeries(fastEma_15M, true);
    ArraySetAsSeries(slowEma_15M, true);
    ArraySetAsSeries(fastEma_1H, true);
    ArraySetAsSeries(slowEma_1H, true);
    ArraySetAsSeries(tickVolume, true);

    if(UseHTFTrendEMAFilter)
    {
        g_htfTrendEMAHandle = iMA(_Symbol, HTF_EMA_TF, HTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
        if(g_htfTrendEMAHandle == INVALID_HANDLE)
            Print("Warning: Failed to create HTF Trend EMA handle");
    }

    Print("V15 Engine initialized successfully");
    return true;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    
    // ML Regime Filter Cleanup
    if(EnableRegimeFilter)
    {
        DeinitRegimeFilter();
        Print("ML Regime Filter: Shut down");
    }

    // Release Defense System handles
    if(g_defenseATRHandle != INVALID_HANDLE) IndicatorRelease(g_defenseATRHandle);
    if(g_defenseEMAFastHandle != INVALID_HANDLE) IndicatorRelease(g_defenseEMAFastHandle);
    if(g_defenseEMASlowHandle != INVALID_HANDLE) IndicatorRelease(g_defenseEMASlowHandle);
    if(g_defenseRSIHandle != INVALID_HANDLE) IndicatorRelease(g_defenseRSIHandle);
    if(g_h1ATRHandle != INVALID_HANDLE) IndicatorRelease(g_h1ATRHandle);

    // Release Range Detector handles
    if(g_rd_atrHandle != INVALID_HANDLE) IndicatorRelease(g_rd_atrHandle);
    if(g_rd_maHandle != INVALID_HANDLE) IndicatorRelease(g_rd_maHandle);
    ObjectsDeleteAll(0, g_rd_objPrefix);

    // Release V15 handles
    if(g_htfTrendEMAHandle != INVALID_HANDLE) IndicatorRelease(g_htfTrendEMAHandle);
    IndicatorRelease(atrHandle);
    IndicatorRelease(bollingerHandle);
    IndicatorRelease(breakoutEMAFastHandle);
    IndicatorRelease(breakoutEMASlowHandle);
    IndicatorRelease(breakoutADXHandle);
    IndicatorRelease(breakoutVolumeHandle);
    if(regimeATRHandle != INVALID_HANDLE) IndicatorRelease(regimeATRHandle);
    IndicatorRelease(fastEmaHandle_1M);
    IndicatorRelease(slowEmaHandle_1M);
    IndicatorRelease(fastEmaHandle_15M);
    IndicatorRelease(slowEmaHandle_15M);
    IndicatorRelease(fastEmaHandle_1H);
    IndicatorRelease(slowEmaHandle_1H);
    if(g_adxEntryHandle != INVALID_HANDLE) IndicatorRelease(g_adxEntryHandle);
    IndicatorRelease(volumeHandle_1M);

    ObjectsDeleteAll(0, "Signal_");
    ObjectsDeleteAll(0, "Breakout_");
    ObjectsDeleteAll(0, "Defense_");
    ObjectsDeleteAll(0, "LuxSes_EA_");
    ObjectsDeleteAll(0, "LuxDash_EA_");
    ObjectsDeleteAll(0, "LuxSes_EADayDiv_");
    ObjectsDeleteAll(0, "LuxSes_EADayLbg_");
    ObjectsDeleteAll(0, "Kelly_");

    Print("V15 EA Stopped.");
    Print("Defense Stats - Impulse: ", g_defenseStats.impulseActivations,
          " | Kill Switch: ", g_defenseStats.killSwitchTriggers);
}


//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
    
    // Update ML Regime Filter
    if(EnableRegimeFilter)
    {
        UpdateRegimeFilter();
    }

    // DAILY LIMIT CHECK
    if(UseDailyProfitLimit)
    {
        datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);
        if(currentDay != g_currentDay)
        {
            g_currentDay = currentDay;
            g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            g_dailyLimitReached = false;
            Print("=== NEW DAY STARTED - Equity: $", DoubleToString(g_dailyStartEquity, 2), " ===");
        }

        if(!g_dailyLimitReached)
        {
            double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            double todaysProfit = currentEquity - g_dailyStartEquity;

            if(todaysProfit >= DailyProfitLimitUSD)
            {
                g_dailyLimitReached = true;
                Print("=== DAILY PROFIT LIMIT REACHED: $", DoubleToString(todaysProfit, 2), " ===");
                
                if(PositionsTotal() > 0)
                {
                    CloseAllV15Positions("Daily Profit Limit Reached");
                }

                if(UseTelegram) SendTelegramMessage("🎯 <b>DAILY PROFIT LIMIT REACHED</b>\nToday's Profit: $" + DoubleToString(todaysProfit, 2) + "\nTarget: $" + DoubleToString(DailyProfitLimitUSD, 2) + "\nTrading suspended until tomorrow.");
            }
        }
    }

    // STEP 0: Update Custom Visuals
    if(EnableRangeDetector) UpdateRangeDetector();
    if(EnableLuxSessions) UpdateLuxSessions();

    // STEP 1: Update Impulse Detection (Defense Layer 1)
    DetectImpulseMode();

    // STEP 2: Evaluate All Defense Layers
    EvaluateAllDefenseLayers(g_defenseState);

    // STEP 3: Update Kill Switch - track session high equity
    UpdateSessionHighEquity(g_killSwitchState, AccountInfoDouble(ACCOUNT_EQUITY));
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdown = CalculateDrawdownFromHigh(g_killSwitchState, currentEquity);
    g_killSwitchState.currentDrawdownPct = drawdown;

    // Kill switch armed warning
    static bool killSwitchArmed = false;
    double armThreshold = KillSwitchDrawdownPct * 0.75;
    if(drawdown >= armThreshold && drawdown < KillSwitchDrawdownPct && !killSwitchArmed)
    {
        killSwitchArmed = true;
        SendKillSwitchArmedNotification(drawdown, KillSwitchDrawdownPct);
    }
    else if(drawdown < armThreshold)
    {
        killSwitchArmed = false;
    }

    // Check if kill switch should trigger
    if(CheckKillSwitchTrigger(g_killSwitchState))
    {
        ExecuteKillSwitch(g_killSwitchState);
        killSwitchArmed = false;
        return;
    }

    // STEP 3.5: Progressive Drawdown Throttling (soft landing before kill switch)
    if(EnableProgressiveDD)
        EvaluateProgressiveDrawdown();

    // STEP 4: Manage existing positions
    ManageV15Grid();
    ManageV15CounterTrades();

    // STEP 4.5: Stale Equity Detection
    if(EnableStaleEquityClose && v15CurrentGridLevel > 0)
        CheckStaleEquity();

    // STEP 4.6: Margin Recovery System
    if(EnableMarginRecovery && v15CurrentGridLevel > 0)
        ManageV15MarginRecovery();

    // Track peak drawdown
    double v15PL = GetV15BasketProfit();
    if(v15PL < 0 && MathAbs(v15PL) > v15PeakDrawdown)
        v15PeakDrawdown = MathAbs(v15PL);

    // STEP 5: Partial shedding evaluation (Defense Layer 5)
    if(EnablePartialShedding && v15CurrentGridLevel > 0)
    {
        double equityDD = drawdown;
        double currentATR = 0;
        double priceExtension = 0;
        double rsiVal = 50;

        if(g_defenseATRHandle != INVALID_HANDLE)
        {
            double atrBuf[];
            ArraySetAsSeries(atrBuf, true);
            if(CopyBuffer(g_defenseATRHandle, 0, 0, 1, atrBuf) > 0)
                currentATR = atrBuf[0];
        }
        if(g_defenseRSIHandle != INVALID_HANDLE)
        {
            double rsiBuf[];
            ArraySetAsSeries(rsiBuf, true);
            if(CopyBuffer(g_defenseRSIHandle, 0, 0, 1, rsiBuf) > 0)
                rsiVal = rsiBuf[0];
        }

        if(currentATR > 0 && v15CurrentGridLevel > 0 && ArraySize(v15GridPositions) > 0)
        {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double firstEntry = v15GridPositions[0].openPrice;
            priceExtension = MathAbs(currentPrice - firstEntry) / currentATR;
        }

        if(EvaluateSheddingConditions(g_sheddingState, equityDD, priceExtension, rsiVal))
        {
            int gridDir = (v15CurrentGridDirection == "BUY") ? 1 : -1;
            g_sheddingState.priority = CalculateSheddingPriority(rsiVal, gridDir);
            ExecutePartialShedding(g_sheddingState, v15GridPositions);
        }
    }

    // STEP 6: Update expansion lock state
    CheckExpansionLock(g_expansionLockState);
    g_defenseState.expansionLock = g_expansionLockState;

    // STEP 7: Check for new bar
    datetime currentBarTime = iTime(_Symbol, TF_1M, 0);
    if(currentBarTime == lastBarTime)
        return;
    lastBarTime = currentBarTime;

    // STEP 8A: Execute pending signal from previous bar (candle has now closed)
    if(hasPendingSignal)
    {
        ExecutePendingSignal();
        hasPendingSignal = false;
    }

    // STEP 8B: Execute V15 strategy (always active)
    UpdateV15ConsolidationTracking();
    ExecuteV15Strategy();

    // STEP 9: Update display
    if(ShowSignalTable)
        UpdateV15Display();
}


//+------------------------------------------------------------------+
//| Check if Hedge ADX is increasing                                  |
//| Returns true if trend is strengthening                            |
//+------------------------------------------------------------------+
bool IsHedgeADXIncreasing()
{
    if(!EnableADXHoldHedge || g_hedgeExitADXHandle == INVALID_HANDLE) return false;

    double adxBuf[];
    ArraySetAsSeries(adxBuf, true);

    if(CopyBuffer(g_hedgeExitADXHandle, 0, 0, 2, adxBuf) >= 2)
    {
        // adxBuf[0] is current, adxBuf[1] is previous
        return (adxBuf[0] > adxBuf[1]);
    }

    return false;
}

//+------------------------------------------------------------------+
//| V15 ENGINE FUNCTIONS                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check ADX trend filter for new entries                           |
//| Returns true if trade should be blocked                          |
//+------------------------------------------------------------------+
bool IsEntryBlockedByADX(string signalType)
{
    if(!UseADXEntryFilter || g_adxEntryHandle == INVALID_HANDLE) return false;

    double adxMain[], diPlus[], diMinus[];
    ArraySetAsSeries(adxMain, true);
    ArraySetAsSeries(diPlus, true);
    ArraySetAsSeries(diMinus, true);

    if(CopyBuffer(g_adxEntryHandle, 0, 1, 1, adxMain) <= 0) return false;
    if(CopyBuffer(g_adxEntryHandle, 1, 1, 1, diPlus) <= 0) return false;
    if(CopyBuffer(g_adxEntryHandle, 2, 1, 1, diMinus) <= 0) return false;

    double currentADX = adxMain[0];
    double currentPlusDI = diPlus[0];
    double currentMinusDI = diMinus[0];

    if(currentADX >= ADXEntryThreshold)
    {
        if(signalType == "SELL" && currentPlusDI > currentMinusDI)
        {
            if(ShowDebugInfo) Print("ADX FILTER: SELL blocked — Strong Uptrend (ADX: ", DoubleToString(currentADX, 1), " +DI > -DI)");
            return true; 
        }
        if(signalType == "BUY" && currentMinusDI > currentPlusDI)
        {
            if(ShowDebugInfo) Print("ADX FILTER: BUY blocked — Strong Downtrend (ADX: ", DoubleToString(currentADX, 1), " -DI > +DI)");
            return true;
        }
    }

    return false;
}

void ExecuteV15Strategy()
{
    if(!CopyV15IndicatorData())
    {
        if(ShowDebugInfo) Print("DEBUG: Failed to copy V15 indicator data");
        return;
    }

    string trend_1H = AnalyzeV15Trend(TF_1HR);
    string trend_15M = AnalyzeV15Trend(TF_15M);
    string trend_1M = AnalyzeV15Trend(TF_1M);

    if(ShowDebugInfo)
    {
        static datetime lastDebugTime = 0;
        if(TimeCurrent() - lastDebugTime > 300)
        {
            string breakoutStatus = inConsolidation ? "CONSOLIDATING" :
                                    (IsInBreakoutWindow() ? "BREAKOUT:" + lastBreakoutDirection : "NONE");
            Print("DEBUG [V15] - Breakout: ", breakoutStatus, " | Grid Level: ", v15CurrentGridLevel);
            lastDebugTime = TimeCurrent();
        }
    }

    SignalInfo signal;

    if(UseMomentumCandleOnly)
    {
        // Standalone momentum mode: 3 consecutive candles = signal, no EMA needed
        signal.isValid = false;
        signal.trend_1H = trend_1H;
        signal.trend_15M = trend_15M;
        signal.trend_1M = trend_1M;
        signal.signalTime = TimeCurrent();
        signal.reason = "";
        signal.isBreakout = false;
        signal.breakoutStrength = 0;

        int cooldown = 60;
        if(v15CounterTradesEnabled && CountV15ActiveCounterTrades() > 0)
            cooldown = 30;
        if(TimeCurrent() - lastSignalTime < cooldown)
            return;

        int momentumType = GetCandleMomentumType(TF_1M);
        if(momentumType == 0)
            return; // No 3-candle momentum, skip

        if(momentumType == 1)
        {
            signal.type = UseReverseMode ? "SELL" : "BUY";
            signal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            signal.isValid = true;
            signal.reason = "3-Candle Momentum BUY";
            lastSignalTime = TimeCurrent();
        }
        else if(momentumType == -1)
        {
            signal.type = UseReverseMode ? "BUY" : "SELL";
            signal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            signal.isValid = true;
            signal.reason = "3-Candle Momentum SELL";
            lastSignalTime = TimeCurrent();
        }

        if(signal.isValid && IsEntryBlockedByADX(signal.type))
        {
            signal.isValid = false;
            signal.reason = "Blocked by ADX Trend Filter";
            return;
        }
    }
    else
    {
        signal = CheckV15EMACrossover(trend_1H, trend_15M, trend_1M);
    }

    if(signal.isValid)
    {
        string htfReason = "";
        if(IsEntryBlockedByHTF(signal.type, htfReason))
        {
            signal.isValid = false;
            signal.reason = htfReason;
            if(ShowDebugInfo) Print("V15 SIGNAL BLOCKED: ", htfReason);
            return;
        }

        if(UseBreakoutFilter)
        {
            string breakoutDir = GetBreakoutDirection();

            if(breakoutDir != "")
            {
                string actualTradeType = signal.type;
                if(UseReverseMode)
                    actualTradeType = (signal.type == "BUY") ? "SELL" : "BUY";

                if(actualTradeType != breakoutDir)
                {
                    if(ShowDebugInfo) Print("V15 Signal blocked - Against breakout direction");
                    return;
                }

                signal.isBreakout = true;
                signal.breakoutStrength = GetBreakoutStrength();
            }
            else if(inConsolidation)
            {
                if(ShowDebugInfo) Print("V15 Signal blocked - In consolidation");
                return;
            }
        }

        signalCount++;
        currentSignal = signal;

        Print("=== NEW V15 SIGNAL #", signalCount, " ===");
        Print("Type: ", signal.type, signal.isBreakout ? " [BREAKOUT]" : "");

        if(WaitForCandleClose)
        {
            Print("Signal queued — waiting for candle close before entry");
            pendingSignal = signal;
            hasPendingSignal = true;
        }
        else
        {
            if(v15CurrentGridLevel == 0)
            {
                OpenV15GridPosition(signal);
                if(signal.isBreakout)
                    v15BreakoutTradesExecuted++;
            }
            else if(UseCounterTrades && v15CounterTradesEnabled && CountV15ActiveCounterTrades() < MaxCounterTrades)
            {
                OpenV15CounterTrade(signal);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Execute Pending Signal (called on next bar after signal candle)    |
//+------------------------------------------------------------------+
void ExecutePendingSignal()
{
    if(!pendingSignal.isValid) return;

    // If a grid is already open, only allow counter trades
    if(v15CurrentGridLevel == 0)
    {
        Print("=== EXECUTING PENDING SIGNAL (candle closed) ===");
        Print("Type: ", pendingSignal.type, pendingSignal.isBreakout ? " [BREAKOUT]" : "");
        OpenV15GridPosition(pendingSignal);
        if(pendingSignal.isBreakout)
            v15BreakoutTradesExecuted++;
    }
    else if(UseCounterTrades && v15CounterTradesEnabled && CountV15ActiveCounterTrades() < MaxCounterTrades)
    {
        Print("=== EXECUTING PENDING COUNTER SIGNAL (candle closed) ===");
        OpenV15CounterTrade(pendingSignal);
    }

    // Clear pending state
    pendingSignal.isValid = false;
}

//+------------------------------------------------------------------+
//| Update V15 Consolidation Tracking                                  |
//+------------------------------------------------------------------+
void UpdateV15ConsolidationTracking()
{
    if(!CopyBreakoutData()) return;

    double highs[], lows[], closes[], opens[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(opens, true);

    int barsToCheck = ConsolidationBars + 5;
    if(CopyHigh(_Symbol, BreakoutTF, 0, barsToCheck, highs) <= 0) return;
    if(CopyLow(_Symbol, BreakoutTF, 0, barsToCheck, lows) <= 0) return;
    if(CopyClose(_Symbol, BreakoutTF, 0, barsToCheck, closes) <= 0) return;
    if(CopyOpen(_Symbol, BreakoutTF, 0, barsToCheck, opens) <= 0) return;

    double bbWidth = 0;
    if(bollingerMiddle[1] > 0)
        bbWidth = ((bollingerUpper[1] - bollingerLower[1]) / bollingerMiddle[1]) * 100;

    bool bollingerSqueeze = (bbWidth < BollingerSqueezePct);

    double avgATR = 0;
    for(int i = 1; i <= 14; i++)
        avgATR += atrBuffer[i];
    avgATR /= 14;

    bool lowATR = (atrBuffer[1] < avgATR * 0.8);
    bool lowADX = (breakoutADX[1] < ADXBreakoutThreshold);

    if(!inConsolidation)
    {
        if((bollingerSqueeze || lowATR) && lowADX)
        {
            double rangeHigh = highs[1];
            double rangeLow = lows[1];

            for(int i = 2; i <= ConsolidationBars; i++)
            {
                if(highs[i] > rangeHigh) rangeHigh = highs[i];
                if(lows[i] < rangeLow) rangeLow = lows[i];
            }

            double rangeSize = rangeHigh - rangeLow;
            if(rangeSize <= avgATR * RangeATRMultiplier)
            {
                consolidationHigh = rangeHigh;
                consolidationLow = rangeLow;
                consolidationBarCount = ConsolidationBars;
                inConsolidation = true;

                if(ShowDebugInfo) Print("V15 CONSOLIDATION DETECTED");
            }
        }
    }
    else
    {
        double currentClose = closes[1];

        if(currentClose > consolidationLow && currentClose < consolidationHigh)
        {
            consolidationBarCount++;
        }
        else
        {
            CheckV15Breakout(closes[1], opens[1], highs[1], lows[1]);
        }
    }
}

//+------------------------------------------------------------------+
//| Check V15 Breakout                                                 |
//+------------------------------------------------------------------+
bool CheckV15Breakout(double close, double open, double high, double low)
{
    if(!inConsolidation) return false;

    double bodySize = MathAbs(close - open);
    bool largeCandleBody = (bodySize >= atrBuffer[1] * BreakoutATRMultiplier);

    double avgVolume = 0;
    for(int i = 2; i <= 15; i++)
        avgVolume += breakoutVolume[i];
    avgVolume /= 14;

    bool volumeSpike = (breakoutVolume[1] >= avgVolume * VolumeBreakoutMultiplier);
    bool adxConfirm = (breakoutADX[1] >= ADXBreakoutThreshold) ||
                      (breakoutADX[1] > breakoutADX[2] && breakoutADX[1] > 20);

    bool validBreakout = false;

    if(close > consolidationHigh)
    {
        bool emaAligned = !RequireEMAAlignment || (breakoutEMAFast[1] > breakoutEMASlow[1]);
        if(largeCandleBody && volumeSpike && adxConfirm && emaAligned)
        {
            validBreakout = true;
            lastBreakoutDirection = "BUY";
            lastBreakoutTime = TimeCurrent();
            if(ShowDebugInfo) Print("V15 BULLISH BREAKOUT CONFIRMED!");
        }
    }
    else if(close < consolidationLow)
    {
        bool emaAligned = !RequireEMAAlignment || (breakoutEMAFast[1] < breakoutEMASlow[1]);
        if(largeCandleBody && volumeSpike && adxConfirm && emaAligned)
        {
            validBreakout = true;
            lastBreakoutDirection = "SELL";
            lastBreakoutTime = TimeCurrent();
            if(ShowDebugInfo) Print("V15 BEARISH BREAKOUT CONFIRMED!");
        }
    }

    if(close > consolidationHigh || close < consolidationLow)
    {
        inConsolidation = false;
        consolidationBarCount = 0;
    }

    return validBreakout;
}

//+------------------------------------------------------------------+
//| Is In Breakout Window                                              |
//+------------------------------------------------------------------+
bool IsInBreakoutWindow()
{
    if(lastBreakoutTime == 0) return false;
    int breakoutTFSeconds = PeriodSeconds(BreakoutTF);
    int windowSeconds = breakoutTFSeconds * 4;
    return (TimeCurrent() - lastBreakoutTime <= windowSeconds);
}

//+------------------------------------------------------------------+
//| Get Breakout Direction                                             |
//+------------------------------------------------------------------+
string GetBreakoutDirection()
{
    if(!IsInBreakoutWindow()) return "";
    return lastBreakoutDirection;
}

//+------------------------------------------------------------------+
//| Get Breakout Strength                                              |
//+------------------------------------------------------------------+
double GetBreakoutStrength()
{
    if(!IsInBreakoutWindow()) return 0;

    double strength = 0;

    if(breakoutADX[1] >= ADXBreakoutThreshold)
        strength += MathMin(40, (breakoutADX[1] - 20) * 2);

    double avgVolume = 0;
    for(int i = 2; i <= 15; i++)
        avgVolume += breakoutVolume[i];
    avgVolume /= 14;

    double volRatio = breakoutVolume[1] / avgVolume;
    if(volRatio >= VolumeBreakoutMultiplier)
        strength += MathMin(30, (volRatio - 1) * 30);

    if(lastBreakoutDirection == "BUY" && breakoutEMAFast[1] > breakoutEMASlow[1])
        strength += 30;
    else if(lastBreakoutDirection == "SELL" && breakoutEMAFast[1] < breakoutEMASlow[1])
        strength += 30;

    return MathMin(100, strength);
}

//+------------------------------------------------------------------+
//| Copy Breakout Data                                                 |
//+------------------------------------------------------------------+
bool CopyBreakoutData()
{
    if(CopyBuffer(atrHandle, 0, 0, 20, atrBuffer) <= 0) return false;
    if(CopyBuffer(bollingerHandle, 0, 0, 20, bollingerMiddle) <= 0) return false;
    if(CopyBuffer(bollingerHandle, 1, 0, 20, bollingerUpper) <= 0) return false;
    if(CopyBuffer(bollingerHandle, 2, 0, 20, bollingerLower) <= 0) return false;
    if(CopyBuffer(breakoutEMAFastHandle, 0, 0, 10, breakoutEMAFast) <= 0) return false;
    if(CopyBuffer(breakoutEMASlowHandle, 0, 0, 10, breakoutEMASlow) <= 0) return false;
    if(CopyBuffer(breakoutADXHandle, 0, 0, 10, breakoutADX) <= 0) return false;
    if(CopyBuffer(breakoutVolumeHandle, 0, 0, 20, breakoutVolume) <= 0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| Copy V15 Indicator Data                                            |
//+------------------------------------------------------------------+
bool CopyV15IndicatorData()
{
    if(CopyBuffer(fastEmaHandle_1M, 0, 0, 5, fastEma_1M) <= 0) return false;
    if(CopyBuffer(slowEmaHandle_1M, 0, 0, 5, slowEma_1M) <= 0) return false;
    if(CopyBuffer(fastEmaHandle_15M, 0, 0, 5, fastEma_15M) <= 0) return false;
    if(CopyBuffer(slowEmaHandle_15M, 0, 0, 5, slowEma_15M) <= 0) return false;
    if(CopyBuffer(fastEmaHandle_1H, 0, 0, 5, fastEma_1H) <= 0) return false;
    if(CopyBuffer(slowEmaHandle_1H, 0, 0, 5, slowEma_1H) <= 0) return false;
    if(CopyBuffer(volumeHandle_1M, 0, 0, 20, tickVolume) <= 0) return false;
    return true;
}

//+------------------------------------------------------------------+
//| HTF MARKET STRUCTURE ENGINE                                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Detect HTF Market Structure (BOS/CHoCH)                            |
//+------------------------------------------------------------------+
void DetectHTFStructure()
{
    if(!UseHTFStructureFilter) return;

    int strength = HTF_SwingStrength;
    int lookback = 150;

    double highs[], lows[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    if(CopyHigh(_Symbol, HTF_Structure_TF, 0, lookback, highs) < lookback) return;
    if(CopyLow(_Symbol, HTF_Structure_TF, 0, lookback, lows) < lookback) return;

    // Find latest Swing High and Swing Low (Fractals)
    double latestSH = 0, latestSL = 0;
    int shIdx = -1, slIdx = -1;

    for(int i = strength; i < lookback - strength; i++)
    {
        // Swing High check
        bool isSH = true;
        for(int j = 1; j <= strength; j++)
        {
            if(highs[i] <= highs[i-j] || highs[i] < highs[i+j])
            {
                isSH = false;
                break;
            }
        }
        if(isSH && shIdx == -1)
        {
            latestSH = highs[i];
            shIdx = i;
        }

        // Swing Low check
        bool isSL = true;
        for(int j = 1; j <= strength; j++)
        {
            if(lows[i] >= lows[i-j] || lows[i] > lows[i+j])
            {
                isSL = false;
                break;
            }
        }
        if(isSL && slIdx == -1)
        {
            latestSL = lows[i];
            slIdx = i;
        }

        if(shIdx != -1 && slIdx != -1) break;
    }

    if(latestSH == 0 || latestSL == 0) return;

    // Update global state if changed
    if(latestSH != g_lastSwingHigh || latestSL != g_lastSwingLow)
    {
        double currentPrice = iClose(_Symbol, HTF_Structure_TF, 0);

        // Detect BOS/CHoCH
        if(currentPrice > latestSH)
        {
            if(g_htfMarketStructure == MS_BEARISH) 
                Print("HTF STRUCTURE: CHoCH Bullish (", EnumToString(HTF_Structure_TF), ") @ ", DoubleToString(currentPrice, _Digits));
            else if(latestSH != g_lastSwingHigh)
                Print("HTF STRUCTURE: BOS Bullish (", EnumToString(HTF_Structure_TF), ") @ ", DoubleToString(currentPrice, _Digits));
            
            g_htfMarketStructure = MS_BULLISH;
        }
        else if(currentPrice < latestSL)
        {
            if(g_htfMarketStructure == MS_BULLISH)
                Print("HTF STRUCTURE: CHoCH Bearish (", EnumToString(HTF_Structure_TF), ") @ ", DoubleToString(currentPrice, _Digits));
            else if(latestSL != g_lastSwingLow)
                Print("HTF STRUCTURE: BOS Bearish (", EnumToString(HTF_Structure_TF), ") @ ", DoubleToString(currentPrice, _Digits));
                
            g_htfMarketStructure = MS_BEARISH;
        }

        g_lastSwingHigh = latestSH;
        g_lastSwingLow = latestSL;
    }
}

//+------------------------------------------------------------------+
//| Check if entry is blocked by HTF Trend or Structure               |
//+------------------------------------------------------------------+
bool IsEntryBlockedByHTF(string signalType, string& reason)
{
    // 1. HTF Trend Filter (EMA)
    if(UseHTFTrendEMAFilter && g_htfTrendEMAHandle != INVALID_HANDLE)
    {
        double emaBuf[];
        ArraySetAsSeries(emaBuf, true);
        if(CopyBuffer(g_htfTrendEMAHandle, 0, 0, 1, emaBuf) > 0)
        {
            double currentPrice = (signalType == "BUY") ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double htfEMA = emaBuf[0];

            if(signalType == "BUY" && currentPrice < htfEMA)
            {
                reason = "HTF TREND: Price below " + IntegerToString(HTF_EMA_Period) + " EMA on " + EnumToString(HTF_EMA_TF);
                return true;
            }
            if(signalType == "SELL" && currentPrice > htfEMA)
            {
                reason = "HTF TREND: Price above " + IntegerToString(HTF_EMA_Period) + " EMA on " + EnumToString(HTF_EMA_TF);
                return true;
            }
        }
    }

    // 2. HTF Structure Filter (BOS/CHoCH)
    if(UseHTFStructureFilter)
    {
        DetectHTFStructure(); // Refresh structure state

        if(signalType == "BUY" && g_htfMarketStructure == MS_BEARISH)
        {
            reason = "HTF STRUCTURE: Bearish bias on " + EnumToString(HTF_Structure_TF);
            return true;
        }
        if(signalType == "SELL" && g_htfMarketStructure == MS_BULLISH)
        {
            reason = "HTF STRUCTURE: Bullish bias on " + EnumToString(HTF_Structure_TF);
            return true;
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Analyze V15 Trend                                                  |
//+------------------------------------------------------------------+
string AnalyzeV15Trend(ENUM_TIMEFRAMES timeframe)
{
    double closes[];
    ArraySetAsSeries(closes, true);

    if(CopyClose(_Symbol, timeframe, 0, 50, closes) <= 0) return "NEUTRAL";

    int bullishBars = 0, bearishBars = 0;

    for(int i = 1; i < 10; i++)
    {
        if(closes[i] > closes[i+1])
            bullishBars++;
        else
            bearishBars++;
    }

    if(bullishBars >= 7) return "BULLISH";
    else if(bearishBars >= 7) return "BEARISH";
    else return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Get Candle Momentum Type (Last 3 Candles)                          |
//| Returns:  1 if 3 Bullish (invalid for mixture, force buy)          |
//|          -1 if 3 Bearish (invalid for mixture, force sell)         |
//|           0 if Mixture (valid for mixture)                         |
//+------------------------------------------------------------------+
int GetCandleMomentumType(ENUM_TIMEFRAMES tf)
{
    double o[3], c[3];
    if(CopyOpen(_Symbol, tf, 1, 3, o) <= 0) return 0; // Default to mixture if unable to read
    if(CopyClose(_Symbol, tf, 1, 3, c) <= 0) return 0;

    bool isBull0 = (c[0] > o[0]);
    bool isBull1 = (c[1] > o[1]);
    bool isBull2 = (c[2] > o[2]);

    bool isBear0 = (c[0] < o[0]);
    bool isBear1 = (c[1] < o[1]);
    bool isBear2 = (c[2] < o[2]);

    if(isBull0 && isBull1 && isBull2) return 1;
    if(isBear0 && isBear1 && isBear2) return -1;

    return 0; // Mixture
}

//+------------------------------------------------------------------+
//| REGIME ENGINE NATIVE INTEGRATION                                 |
//+------------------------------------------------------------------+
struct RegimeState {
    bool isBullRegime;
    bool isBearRegime;
    bool isSidewaysRegime;
    bool isQuiet;
    string label;
};

double HighestHighSeries(ENUM_TIMEFRAMES tf, int startIdx, int period)
{
    double maxVal = 0;
    for(int i = startIdx; i < startIdx + period; i++)
    {
        double h = iHigh(_Symbol, tf, i);
        if(i == startIdx || h > maxVal) maxVal = h;
    }
    return maxVal;
}

double LowestLowSeries(ENUM_TIMEFRAMES tf, int startIdx, int period)
{
    double minVal = 0;
    for(int i = startIdx; i < startIdx + period; i++)
    {
        double l = iLow(_Symbol, tf, i);
        if(i == startIdx || l < minVal) minVal = l;
    }
    return minVal;
}

double DonchianSeries(ENUM_TIMEFRAMES tf, int startIdx, int period)
{
    return (HighestHighSeries(tf, startIdx, period) + LowestLowSeries(tf, startIdx, period)) / 2.0;
}

double TrueRangeSeries(ENUM_TIMEFRAMES tf, int idx)
{
    double h = iHigh(_Symbol, tf, idx);
    double l = iLow(_Symbol, tf, idx);
    double c_prev = iClose(_Symbol, tf, idx + 1);
    
    double hl = h - l;
    double hc = MathAbs(h - c_prev);
    double lc = MathAbs(l - c_prev);
    return MathMax(hl, MathMax(hc, lc));
}

double ManualSMASeries(ENUM_TIMEFRAMES tf, int startIdx, int period)
{
    double sum = 0;
    for(int i=startIdx; i<startIdx+period; i++) sum += iClose(_Symbol, tf, i);
    return sum / period;
}

double SMATRSeries(ENUM_TIMEFRAMES tf, int startIdx, int period)
{
    double sum = 0;
    for(int i=startIdx; i<startIdx+period; i++) sum += TrueRangeSeries(tf, i);
    return sum / period;
}

double CalcChopSeries(ENUM_TIMEFRAMES tf, int startIdx, int period)
{
    double atrVal = SMATRSeries(tf, startIdx, period);
    double hh = HighestHighSeries(tf, startIdx, period);
    double ll = LowestLowSeries(tf, startIdx, period);
    double range = hh - ll;
    
    if(range <= 0.0) return 50.0;
    double ratio = atrVal / range;
    if(ratio <= 0.0) return 50.0;
    
    return 100.0 * MathLog10(ratio) / MathLog10((double)period);
}

RegimeState EA_GetCurrentRegime()
{
    RegimeState r;
    ZeroMemory(r);
    
    int startIdx = 1; 
    
    double close0 = iClose(_Symbol, RegimeTF, startIdx);
    double sma200 = ManualSMASeries(RegimeTF, startIdx, RegimeSMALen);
    bool macroBull = (close0 > sma200);
    bool macroBear = (close0 < sma200);
    
    int shiftIdx = startIdx + 26;
    double tenkan26 = DonchianSeries(RegimeTF, shiftIdx, 9);
    double kijun26 = DonchianSeries(RegimeTF, shiftIdx, 26);
    double spanA26 = (tenkan26 + kijun26) / 2.0;
    double spanB26 = DonchianSeries(RegimeTF, shiftIdx, 52);
    
    bool ichimokuBull = (close0 > spanA26) && (close0 > spanB26);
    bool ichimokuBear = (close0 < spanA26) && (close0 < spanB26);
    
    r.isBullRegime = macroBull && ichimokuBull;
    r.isBearRegime = macroBear && ichimokuBear;
    
    double chop = CalcChopSeries(RegimeTF, startIdx, RegimeChopLen);
    r.isSidewaysRegime = (!r.isBullRegime && !r.isBearRegime) || (chop > 61.8);
    
    if(r.isSidewaysRegime)
    {
       r.isBullRegime = false;
       r.isBearRegime = false;
    }
    
    if(regimeATRHandle != INVALID_HANDLE)
    {
        double atrData[];
        ArraySetAsSeries(atrData, true);
        if(CopyBuffer(regimeATRHandle, 0, startIdx, 100, atrData) >= 100)
        {
            double currentAtr = atrData[0];
            double atrSum = 0;
            for(int i=0; i<100; i++) atrSum += atrData[i];
            double atrAvg = atrSum / 100.0;
            r.isQuiet = (currentAtr < atrAvg);
        }
    }
    
    if(r.isBullRegime) r.label = r.isQuiet ? "Bull Quiet" : "Bull Volatile";
    else if(r.isBearRegime) r.label = r.isQuiet ? "Bear Quiet" : "Bear Volatile";
    else r.label = r.isQuiet ? "Side Quiet" : "Side Volatile";
    
    return r;
}

//+------------------------------------------------------------------+
//| Check V15 EMA Crossover                                            |
//+------------------------------------------------------------------+
SignalInfo CheckV15EMACrossover(string trend_1H, string trend_15M, string trend_1M)
{
    SignalInfo signal;
    signal.isValid = false;
    signal.trend_1H = trend_1H;
    signal.trend_15M = trend_15M;
    signal.trend_1M = trend_1M;
    signal.signalTime = TimeCurrent();
    signal.reason = "";
    signal.isBreakout = false;
    signal.breakoutStrength = 0;

    int cooldown = 60;
    if(v15CounterTradesEnabled && CountV15ActiveCounterTrades() > 0)
        cooldown = 30;

    if(TimeCurrent() - lastSignalTime < cooldown)
    {
        signal.reason = "Too soon after last signal";
        return signal;
    }

    if(UseVolumeFilter)
    {
        double avgVolume = 0;
        for(int i = 1; i < 20; i++)
            avgVolume += tickVolume[i];
        avgVolume /= 19;

        if(tickVolume[0] < avgVolume * VolumeMultiplier)
        {
            signal.reason = "Volume too low";
            return signal;
        }
    }

    bool buyCross = (fastEma_1M[1] > slowEma_1M[1] && fastEma_1M[2] <= slowEma_1M[2]);
    bool sellCross = (fastEma_1M[1] < slowEma_1M[1] && fastEma_1M[2] >= slowEma_1M[2]);

    if(!buyCross && !sellCross)
    {
        signal.reason = "No EMA crossover";
        return signal;
    }

    string finalType = buyCross ? "BUY" : "SELL";
    int momentumType = GetCandleMomentumType(TF_1M);

    if (UseThreeCandleMomentumEntry)
    {
        if (momentumType == 1) finalType = UseReverseMode ? "SELL" : "BUY";
        else if (momentumType == -1) finalType = UseReverseMode ? "BUY" : "SELL";
    }
    else
    {
        if (momentumType != 0)
        {
            signal.reason = "Candle mixture filter failed";
            return signal;
        }
    }

    if(UseRegimeFilter)
    {
        RegimeState req = EA_GetCurrentRegime();
        if(!req.isSidewaysRegime) 
        {
            if(req.isBullRegime && finalType == "SELL")
            {
                signal.reason = "Regime filter blocked SELL in Bull regime";
                return signal;
            }
            if(req.isBearRegime && finalType == "BUY")
            {
                signal.reason = "Regime filter blocked BUY in Bear regime";
                return signal;
            }
        }
    }

    if(finalType == "BUY")
    {
        signal.type = "BUY";
        signal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        bool trendOK = !UseTrendFilter || AllowCounterTrend ||
                       trend_1M == "BULLISH" || trend_1M == "NEUTRAL" ||
                       (trend_15M == "BULLISH" && trend_1M == "NEUTRAL");

        if(!trendOK) { signal.reason = "Trend filter failed"; return signal; }

        if(IsEntryBlockedByADX("BUY")) { signal.reason = "Blocked by ADX Trend Filter"; return signal; }

        signal.isValid = true;
        signal.reason = "Valid BUY signal";
        lastSignalTime = TimeCurrent();
    }
    else
    {
        signal.type = "SELL";
        signal.entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        bool trendOK = !UseTrendFilter || AllowCounterTrend ||
                       trend_1M == "BEARISH" || trend_1M == "NEUTRAL" ||
                       (trend_15M == "BEARISH" && trend_1M == "NEUTRAL");

        if(!trendOK) { signal.reason = "Trend filter failed"; return signal; }

        if(IsEntryBlockedByADX("SELL")) { signal.reason = "Blocked by ADX Trend Filter"; return signal; }

        signal.isValid = true;
        signal.reason = "Valid SELL signal";
        lastSignalTime = TimeCurrent();
    }

    return signal;
}

//+------------------------------------------------------------------+
//| Open V15 Grid Position                                             |
//+------------------------------------------------------------------+
void OpenV15GridPosition(SignalInfo &signal)
{
    if(!CanExpandGrid(g_defenseState))
    {
        Print("DEFENSE BLOCK: Cannot open V15 initial position - ",
              g_defenseState.blockingLayer, ": ", g_defenseState.blockingReason);
        return;
    }

    v15CurrentGridLevel++;
    double lot = CalculateV15GridLot(v15CurrentGridLevel) * V15_RiskMultiplier;

    if(!CanAddGridLevel(lot))
    {
        Print("Cannot open initial grid position - Exposure limit reached");
        v15CurrentGridLevel--;
        return;
    }

    string actualTradeType = signal.type;
    if(UseReverseMode)
        actualTradeType = (signal.type == "BUY") ? "SELL" : "BUY";

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeLot(lot);
    request.deviation = Slippage;
    request.magic = MagicNumber_V15;

    string comment = "V15-Grid-L" + IntegerToString(v15CurrentGridLevel);
    if(signal.isBreakout) comment += "-BO";
    request.comment = comment;

    if(actualTradeType == "BUY")
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }
    else
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
        {
            GridPosition pos;
            pos.ticket = result.order;
            pos.lotSize = request.volume;
            pos.openPrice = request.price;
            pos.level = v15CurrentGridLevel;
            pos.isCounterTrade = false;
            pos.targetProfit = 0;
            pos.drawdownAtOpen = 0;
            pos.engine = 15;

            int size = ArraySize(v15GridPositions);
            ArrayResize(v15GridPositions, size + 1);
            v15GridPositions[size] = pos;

            v15CurrentGridDirection = actualTradeType;
            v15LastGridPrice = request.price;
            tradeCount++;

            SendV15TradeNotification(actualTradeType, v15CurrentGridLevel, request.volume, request.price, signal.isBreakout);
        }
    }
}

//+------------------------------------------------------------------+
//| Add V15 Grid Level                                                 |
//+------------------------------------------------------------------+
void AddV15GridLevel()
{
    if(!CanExpandGrid(g_defenseState))
    {
        Print("DEFENSE BLOCK: Cannot add V15 grid level - ",
              g_defenseState.blockingLayer, ": ", g_defenseState.blockingReason);

        if(UseTelegram && g_defenseState.blockingLayer != "")
        {
            static datetime lastBlockNotification = 0;
            if(TimeCurrent() - lastBlockNotification > 300)
            {
                string message = "🛡️ <b>DEFENSE SYSTEM BLOCK</b>\n\n";
                message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
                message += "🚫 <b>Layer:</b> " + g_defenseState.blockingLayer + "\n";
                message += "📝 <b>Reason:</b> " + g_defenseState.blockingReason + "\n";
                message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
                SendTelegramMessage(message);
                lastBlockNotification = TimeCurrent();
            }
        }
        return;
    }

    v15CurrentGridLevel++;
    double lot = CalculateV15GridLot(v15CurrentGridLevel) * V15_RiskMultiplier;

    if(!CanAddGridLevel(lot))
    {
        Print("Cannot add grid level - Exposure limit reached");
        v15CurrentGridLevel--;
        return;
    }

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeLot(lot);
    request.deviation = Slippage;
    request.magic = MagicNumber_V15;
    request.comment = "V15-Grid-L" + IntegerToString(v15CurrentGridLevel);

    if(v15CurrentGridDirection == "BUY")
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }
    else
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
        {
            GridPosition pos;
            pos.ticket = result.order;
            pos.lotSize = request.volume;
            pos.openPrice = request.price;
            pos.level = v15CurrentGridLevel;
            pos.isCounterTrade = false;
            pos.targetProfit = 0;
            pos.drawdownAtOpen = 0;
            pos.engine = 15;

            int size = ArraySize(v15GridPositions);
            ArrayResize(v15GridPositions, size + 1);
            v15GridPositions[size] = pos;

            v15LastGridPrice = request.price;
            tradeCount++;
            
            // --- PARTIAL SHEDDING CIRCUIT BREAKER ---
            // If Level 5 is reached, close Level 1 to cap exposure and shift center of gravity
            if(v15CurrentGridLevel == 5)
            {
                Print("=== CIRCUIT BREAKER: Level 5 Reached! Closing Level 1 ===");
                if(UseTelegram) SendTelegramMessage("🛡️ <b>CIRCUIT BREAKER ACTIVATED</b>\nGrid Level 5 reached. Shedding Level 1.");
                
                for(int i = 0; i < ArraySize(v15GridPositions); i++)
                {
                    if(v15GridPositions[i].level == 1 && !v15GridPositions[i].isCounterTrade)
                    {
                        ulong targetTicket = v15GridPositions[i].ticket;
                        if(PositionSelectByTicket(targetTicket))
                        {
                            if(ClosePositionByTicket(targetTicket, MagicNumber_V15))
                            {
                                Print("Successfully closed Level 1: Ticket ", targetTicket);
                            }
                        }
                    }
                }
            }
            // ----------------------------------------
        }
    }
}

//+------------------------------------------------------------------+
//| Open V15 Counter Trade                                             |
//+------------------------------------------------------------------+
void OpenV15CounterTrade(SignalInfo &signal)
{
    if(CountV15ActiveCounterTrades() >= MaxCounterTrades) return;

    v15CounterTradeCount++;
    double currentDrawdown = MathAbs(GetV15MainGridProfit());
    double lot = CalculateV15CounterLot(v15CounterTradeCount, currentDrawdown) * V15_RiskMultiplier;
    double target = CalculateV15WeightedTarget(currentDrawdown, v15CounterTradeCount);

    if(!CanAddGridLevel(lot))
    {
        Print("Cannot open counter trade - Exposure limit reached");
        v15CounterTradeCount--;
        return;
    }

    string counterType = (v15CurrentGridDirection == "BUY") ? "SELL" : "BUY";

    // --- Counter Trade RSI Filter ---
    if(EnableCounterRSIFilter && g_defenseRSIHandle != INVALID_HANDLE)
    {
        double rsiBuf[];
        if(CopyBuffer(g_defenseRSIHandle, 0, 0, 1, rsiBuf) > 0)
        {
            double currentRSI = rsiBuf[0];
            if(counterType == "BUY" && currentRSI >= CounterRSI_Upper)
            {
                if(ShowDebugInfo) Print("COUNTER TRADE BLOCKED: BUY restricted by RSI (", DoubleToString(currentRSI, 2), " >= ", CounterRSI_Upper, ")");
                v15CounterTradeCount--; // Reverse the increment
                return;
            }
            if(counterType == "SELL" && currentRSI <= CounterRSI_Lower)
            {
                if(ShowDebugInfo) Print("COUNTER TRADE BLOCKED: SELL restricted by RSI (", DoubleToString(currentRSI, 2), " <= ", CounterRSI_Lower, ")");
                v15CounterTradeCount--; // Reverse the increment
                return;
            }
        }
    }
    // --------------------------------

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeLot(lot);
    request.deviation = Slippage;
    request.magic = MagicNumber_V15;
    request.comment = "V15-Counter-" + IntegerToString(v15CounterTradeCount);

    if(counterType == "BUY")
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }
    else
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
        {
            GridPosition pos;
            pos.ticket = result.order;
            pos.lotSize = request.volume;
            pos.openPrice = request.price;
            pos.level = v15CounterTradeCount;
            pos.isCounterTrade = true;
            pos.targetProfit = target;
            pos.drawdownAtOpen = currentDrawdown;
            pos.engine = 15;

            int size = ArraySize(v15GridPositions);
            ArrayResize(v15GridPositions, size + 1);
            v15GridPositions[size] = pos;

            lastCounterSignalTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Open V15 Counter Defense Trade (Levels 3 & 4)                      |
//+------------------------------------------------------------------+
void OpenV15CounterDefenseTrade(int level)
{
    double lot = CalculateV15GridLot(level) * V15_RiskMultiplier;
    string counterType = (v15CurrentGridDirection == "BUY") ? "SELL" : "BUY";

    // --- Counter Defense Filterless Entry ---
    // (Bypassing RSI filters per user request for instant hedging at levels 3 & 4)

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = NormalizeLot(lot);
    request.deviation = Slippage;
    request.magic = MagicNumber_V15;
    request.comment = "V15-CounterDefense-L" + IntegerToString(level);

    if(counterType == "BUY")
    {
        request.type = ORDER_TYPE_BUY;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    }
    else
    {
        request.type = ORDER_TYPE_SELL;
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    }

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
        {
            GridPosition pos;
            pos.ticket = result.order;
            pos.lotSize = request.volume;
            pos.openPrice = request.price;
            pos.level = level;
            pos.isCounterTrade = true;
            pos.targetProfit = 0;
            pos.drawdownAtOpen = 0;
            pos.engine = 15;

            int size = ArraySize(v15GridPositions);
            ArrayResize(v15GridPositions, size + 1);
            v15GridPositions[size] = pos;

            if(UseTelegram) 
                SendTelegramMessage("🛡️ <b>COUNTER DEFENSE OPENED</b>\nLevel: " + IntegerToString(level) + "\nType: " + counterType + "\nLot: " + DoubleToString(request.volume, 2));
        }
    }
}

//+------------------------------------------------------------------+
//| Check Grid Candle Confirmation                                     |
//| Returns true if grid can proceed, false if it should pause         |
//+------------------------------------------------------------------+
bool CheckGridCandleConfirmation()
{
    double opens[], closes[];
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(closes, true);

    // Read last 3 closed candles (index 1, 2, and 3)
    if(CopyOpen(_Symbol, TF_1M, 1, 3, opens) < 3) return true;  // Allow if data unavailable
    if(CopyClose(_Symbol, TF_1M, 1, 3, closes) < 3) return true;

    // Check for 3 consecutive opposing candles
    if(v15CurrentGridDirection == "BUY")
    {
        // For BUY grid: 3 consecutive bearish candles = pause
        bool candle1Bearish = (closes[0] < opens[0]);  // Most recent closed candle
        bool candle2Bearish = (closes[1] < opens[1]);  // Second most recent
        bool candle3Bearish = (closes[2] < opens[2]);  // Third most recent

        if(candle1Bearish && candle2Bearish && candle3Bearish)
        {
            if(ShowDebugInfo) Print("GRID CANDLE CHECK: 3 consecutive bearish candles detected against BUY grid");
            return false;  // Pause
        }
    }
    else if(v15CurrentGridDirection == "SELL")
    {
        // For SELL grid: 3 consecutive bullish candles = pause
        bool candle1Bullish = (closes[0] > opens[0]);
        bool candle2Bullish = (closes[1] > opens[1]);
        bool candle3Bullish = (closes[2] > opens[2]);

        if(candle1Bullish && candle2Bullish && candle3Bullish)
        {
            if(ShowDebugInfo) Print("GRID CANDLE CHECK: 3 consecutive bullish candles detected against SELL grid");
            return false;  // Pause
        }
    }

    return true;  // Proceed normally
}

//+------------------------------------------------------------------+
//| Check Grid Pause Resolution                                        |
//| When grid is paused, check if a confirming candle has closed       |
//+------------------------------------------------------------------+
void CheckGridPauseResolution()
{
    if(!v15GridPaused) return;

    double opens[], closes[];
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(closes, true);

    // Read last closed candle (index 1)
    if(CopyOpen(_Symbol, TF_1M, 1, 1, opens) < 1) return;
    if(CopyClose(_Symbol, TF_1M, 1, 1, closes) < 1) return;

    bool confirmed = false;

    if(v15CurrentGridDirection == "BUY" && closes[0] > opens[0])
        confirmed = true;   // Bullish candle confirms BUY grid
    else if(v15CurrentGridDirection == "SELL" && closes[0] < opens[0])
        confirmed = true;   // Bearish candle confirms SELL grid

    if(confirmed)
    {
        Print("=== GRID PAUSE RESOLVED: Confirming candle closed — adding grid level ===");

        if(UseTelegram)
        {
            string message = "✅ <b>GRID PAUSE RESOLVED</b>\n\n";
            message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
            message += "📈 <b>Direction:</b> " + v15CurrentGridDirection + "\n";
            message += "🕐 <b>Confirming candle closed</b>\n";
            message += "➕ Adding grid level " + IntegerToString(v15CurrentGridLevel + 1) + "\n";
            message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
            SendTelegramMessage(message);
        }

        v15GridPaused = false;
        v15GridLevelPending = false;
        AddV15GridLevel();
    }
}

//+------------------------------------------------------------------+
//| Manage V15 Grid                                                    |
//+------------------------------------------------------------------+
void ManageV15Grid()
{
    if(v15CurrentGridLevel == 0) return;

    double basketProfit = GetV15BasketProfit();

    // Determine basket target: adaptive (Kelly) or fixed
    double basketTarget = BasketProfitUSD;
    if(EnableAdaptiveBasket)
    {
        CalculateAdaptiveBasketTarget();
        basketTarget = g_kellyState.currentBasketTarget;
    }

    bool shouldClose = false;
    string closeReason = "";

    if(v15MarginRecoveryActive)
    {
        // 1. Check for Break-Even transition
        if(!v15RecoveryAtBreakEven && basketProfit >= MarginRecoveryBreakEvenUSD)
        {
            v15RecoveryAtBreakEven = true;
            Print("=== MARGIN RECOVERY: Break-Even Reached ($", DoubleToString(basketProfit, 2), ") — Letting it ride to $", DoubleToString(MarginRecoveryTargetProfitUSD, 2), " ===");
            if(UseTelegram) SendTelegramMessage("🏁 <b>RECOVERY BREAK-EVEN REACHED</b>\nProfit: $" + DoubleToString(basketProfit, 2) + "\nRiding to target: $" + DoubleToString(MarginRecoveryTargetProfitUSD, 2));
        }

        // 2. If riding, check for target or reversal
        if(v15RecoveryAtBreakEven)
        {
            if(basketProfit >= MarginRecoveryTargetProfitUSD)
            {
                shouldClose = true;
                closeReason = "Recovery Target Profit ($" + DoubleToString(MarginRecoveryTargetProfitUSD, 2) + ")";
            }
            else if(basketProfit < MarginRecoveryBreakEvenUSD - 1.0)
            {
                shouldClose = true;
                closeReason = "Recovery Reversal (Secured Break-Even)";
            }
        }
        else if(basketProfit >= basketTarget)
        {
            shouldClose = true;
            closeReason = "Basket Profit Target ($" + DoubleToString(basketTarget, 2) + ")";
        }
    }
    else if(basketProfit >= basketTarget)
    {
        shouldClose = true;
        closeReason = "Basket Profit Target ($" + DoubleToString(basketTarget, 2) + ")";
    }

    if(shouldClose)
    {
        RecordKellyTradeResult(true, basketProfit);
        CloseAllV15Positions(closeReason);
        ResetExpansionLock(g_expansionLockState);
        return;
    }

    if(basketProfit <= -BasketMaxLossUSD)
    {
        RecordKellyTradeResult(false, MathAbs(basketProfit));
        CloseAllV15Positions("Basket Max Loss");
        return;
    }

    // Profit Lock Logic (uses adaptive target)
    if(UseBasketProfitLock && basketTarget > 0)
    {
        double triggerUSD = basketTarget * (BasketProfitLockTriggerPct / 100.0);
        double lockUSD = basketTarget * (BasketProfitLockRetainPct / 100.0);

        if(!v15BasketProfitLocked && basketProfit >= triggerUSD)
        {
            v15BasketProfitLocked = true;
            Print("=== BASKET PROFIT LOCK ACTIVATED at $", DoubleToString(basketProfit, 2), " ===");
            if(UseTelegram) SendTelegramMessage("🔒 <b>PROFIT LOCK ACTIVATED</b>\nProfit reached: $" + DoubleToString(basketProfit, 2) + "\nLocked at: $" + DoubleToString(lockUSD, 2));
        }
        else if(v15BasketProfitLocked && basketProfit <= lockUSD)
        {
            RecordKellyTradeResult(true, basketProfit);
            CloseAllV15Positions("Basket Profit Lock Triggered");
            return;
        }
    }

    // Add grid levels if needed
    if(v15CurrentGridLevel < MaxGridLevels)
    {
        // Check if grid is paused waiting for confirming candle
        if(EnableGridCandleConfirm && v15GridPaused)
        {
            CheckGridPauseResolution();
            // Don't process further grid additions while paused
        }
        else
        {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            // Get current ATR for dynamic spacing
            double atrBuf[];
            ArraySetAsSeries(atrBuf, true);
            double currentATR = 0;
            if(g_defenseATRHandle != INVALID_HANDLE && CopyBuffer(g_defenseATRHandle, 0, 0, 1, atrBuf) > 0)
            {
                currentATR = atrBuf[0];

                if(ShouldRecalculateSpacing(currentATR, g_spacingState.lastATR))
                    CalculateDynamicGridStep(g_impulseState.isActive, currentATR);
            }

            double gridStep = EnableDynamicSpacing ? g_spacingState.currentStep * _Point : GridStepPoints * _Point;

            double nextTriggerPrice = (v15CurrentGridDirection == "BUY") ? v15LastGridPrice - gridStep : v15LastGridPrice + gridStep;
            if(v15Level3Pending)
                nextTriggerPrice = (v15CurrentGridDirection == "BUY") ? v15LastGridPrice - 2 * gridStep : v15LastGridPrice + 2 * gridStep;

            bool shouldAddLevel = false;
            if(v15CurrentGridDirection == "BUY" && currentPrice <= nextTriggerPrice)
                shouldAddLevel = true;
            else if(v15CurrentGridDirection == "SELL" && currentPrice >= nextTriggerPrice)
                shouldAddLevel = true;

            if(shouldAddLevel)
            {
                int nextLevel = v15CurrentGridLevel + 1;
                if(v15Level3Pending) nextLevel = 4;
                
                if(EnableCounterDefense && (nextLevel == 3 || nextLevel == 4))
                {
                    if(nextLevel == 3 && !v15Level3Pending)
                    {
                        v15Level3Pending = true;
                        v15CounterDefenseActive = true;
                        OpenV15CounterDefenseTrade(3);
                        Print("=== COUNTER DEFENSE: Level 3 reached — Opening Hedge ===");
                    }
                    else if(nextLevel == 4 && !v15Level4Pending)
                    {
                        v15Level4Pending = true;
                        v15CounterDefenseActive = true;
                        OpenV15CounterDefenseTrade(4);
                        Print("=== COUNTER DEFENSE: Level 4 reached — Opening Hedge ===");
                    }
                }
                else
                {
                    // Check candle confirmation before adding grid level
                    if(EnableGridCandleConfirm && !CheckGridCandleConfirmation())
                    {
                        v15GridPaused = true;
                        v15GridLevelPending = true;
                        Print("=== GRID PAUSED: 3 consecutive opposing candles detected — waiting for confirming ",
                              v15CurrentGridDirection, " candle close ===");

                        if(UseTelegram)
                        {
                            string message = "⏸️ <b>GRID PAUSED</b>\n\n";
                            message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
                            message += "📈 <b>Direction:</b> " + v15CurrentGridDirection + "\n";
                            message += "🚫 <b>3 opposing candles detected</b>\n";
                            message += "⏳ Waiting for confirming candle to add level " + IntegerToString(nextLevel) + "\n";
                            message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
                            SendTelegramMessage(message);
                        }
                    }
                    else
                    {
                        AddV15GridLevel();
                    }
                }
            }
        }
    }

    double mainGridPL = GetV15MainGridProfit();
    if(!v15CounterTradesEnabled && mainGridPL <= -CounterTradeLossThreshold)
    {
        v15CounterTradesEnabled = true;
        Print("=== V15 COUNTER TRADES ENABLED ===");
    }
}

//+------------------------------------------------------------------+
//| Calculate Max Margin Lot                                           |
//+------------------------------------------------------------------+
double CalcMaxMarginLot(string symbol, ENUM_ORDER_TYPE orderType, double leveragePct)
{
    // Bound leverage between 1% and 95% to avoid immediate margin out blocks
    double safePercent = MathMax(1.0, MathMin(95.0, leveragePct));
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginToUse = freeMargin * (safePercent / 100.0);
    double marginPerLot = 0;

    double openPrice = 0;
    if(orderType == ORDER_TYPE_BUY)
        openPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
    else
        openPrice = SymbolInfoDouble(symbol, SYMBOL_BID);

    if(!OrderCalcMargin(orderType, symbol, 1.0, openPrice, marginPerLot))
    {
        Print("Failed to calculate margin. Error: ", GetLastError());
        return 0;
    }

    if(marginPerLot <= 0) return 0;

    double maxLot = marginToUse / marginPerLot;
    return NormalizeLot(maxLot);
}

//+------------------------------------------------------------------+
//| Manage V15 Margin Recovery                                         |
//+------------------------------------------------------------------+
void ManageV15MarginRecovery()
{
    if(v15MarginRecoveryActive) return;

    bool triggerRecovery = false;
    double currentRSI = 0;
    string triggerReason = "";
    string tradeDirection = "";
    ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
    double gridPL = GetV15BasketProfit();

    // 1. Check for Forced Trigger from Hedge Exit
    if(v15TriggerRecoveryAfterHedge)
    {
        triggerRecovery = true;
        triggerReason = "ADX Hedge Exit Flash Recovery";
        if(v15CurrentGridDirection == "SELL") { tradeDirection = "SELL"; orderType = ORDER_TYPE_SELL; }
        else { tradeDirection = "BUY"; orderType = ORDER_TYPE_BUY; }
        
        Print("=== MARGIN RECOVERY: Forced trigger detected from Hedge Exit ===");
    }
    // 2. Standard RSI/Loss Filters
    else
    {
        if(gridPL > -MarginRecoveryMinLossUSD) return; // Not enough loss yet
        if(g_defenseRSIHandle == INVALID_HANDLE) return;

        double rsiBuf[];
        ArraySetAsSeries(rsiBuf, true);
        if(CopyBuffer(g_defenseRSIHandle, 0, 0, 1, rsiBuf) <= 0) return;

        currentRSI = rsiBuf[0];
        if(v15CurrentGridDirection == "SELL" && currentRSI >= MarginRecoveryRSI_Overbought)
        {
            triggerRecovery = true;
            triggerReason = "RSI Overbought";
            tradeDirection = "SELL";
            orderType = ORDER_TYPE_SELL;
        }
        else if(v15CurrentGridDirection == "BUY" && currentRSI <= MarginRecoveryRSI_Oversold)
        {
            triggerRecovery = true;
            triggerReason = "RSI Oversold";
            tradeDirection = "BUY";
            orderType = ORDER_TYPE_BUY;
        }

        if(triggerRecovery && MarginRecoveryUseADXFilter && g_adxEntryHandle != INVALID_HANDLE)
        {
            double adxBuf[];
            ArraySetAsSeries(adxBuf, true);
            if(CopyBuffer(g_adxEntryHandle, 0, 0, 2, adxBuf) >= 2)
            {
                if(adxBuf[0] >= adxBuf[1])
                {
                    Print("=== MARGIN RECOVERY HALTED: ADX is rising (", 
                          DoubleToString(adxBuf[0], 2), " >= ", DoubleToString(adxBuf[1], 2), 
                          ") — Waiting for trend to fade ===");
                    return;
                }
            }
        }
    }

    if(triggerRecovery)
    {
        double recoveryLot = CalcMaxMarginLot(_Symbol, orderType, MarginRecoveryFreeMarginPct);
        if(recoveryLot <= 0) 
        {
            Print("Margin Recovery Alert: Calculated lot is 0 due to insufficient funds.");
            return;
        }

        MqlTradeRequest request;
        MqlTradeResult result;
        ZeroMemory(request);
        ZeroMemory(result);

        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        request.volume = recoveryLot; // Already normalized
        request.deviation = Slippage;
        request.magic = MagicNumber_V15;
        request.comment = "V15-MarginRecovery";
        request.type = orderType;

        if(orderType == ORDER_TYPE_BUY)
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        else
            request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        if(OrderSend(request, result))
        {
            if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
            {
                GridPosition pos;
                pos.ticket = result.order;
                pos.lotSize = request.volume;
                pos.openPrice = request.price;
                pos.level = v15CurrentGridLevel + 900; // Special indicator
                pos.isCounterTrade = false; // Add to main grid P&L evaluation natively
                pos.targetProfit = 0;
                pos.drawdownAtOpen = gridPL;
                pos.engine = 15;

                int size = ArraySize(v15GridPositions);
                ArrayResize(v15GridPositions, size + 1);
                v15GridPositions[size] = pos;

                v15MarginRecoveryActive = true;
                v15RecoveryAtBreakEven = false; // Reset "riding" state for fresh recovery cycle
                v15TriggerRecoveryAfterHedge = false; // Reset forced trigger flag

                Print("=== MARGIN RECOVERY TRADE OPENED ===");
                Print("Direction: ", tradeDirection, " | RSI: ", DoubleToString(currentRSI, 2), " | Lot: ", DoubleToString(recoveryLot, 2));
                
                if(UseTelegram)
                {
                    string message = "🚨 <b>MARGIN RECOVERY ACTIVATED</b>\n";
                    message += "Direction: " + tradeDirection + "\n";
                    message += "RSI: " + DoubleToString(currentRSI, 1) + "\n";
                    message += "Drawn down: $" + DoubleToString(gridPL, 2) + "\n";
                    message += "Lot Size: " + DoubleToString(request.volume, 2) + " (" + DoubleToString(MarginRecoveryFreeMarginPct, 0) + "% Margin)";
                    SendTelegramMessage(message);
                }
            }
            else
            {
                Print("Margin Recovery Trade failed! Error: ", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage V15 Counter Trades                                          |
//+------------------------------------------------------------------+
void ManageV15CounterTrades()
{
    double defenseProfit = 0;
    bool anyDefense = false;

    // First pass: Process normal counter trades and calculate defense basket profit
    for(int i = ArraySize(v15GridPositions) - 1; i >= 0; i--)
    {
        if(v15GridPositions[i].isCounterTrade)
        {
            if(PositionSelectByTicket(v15GridPositions[i].ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                string comment = PositionGetString(POSITION_COMMENT);
                long posType = PositionGetInteger(POSITION_TYPE);
                
                // --- Counter Trade RSI Profit Lock-in ---
                bool closeByRSI = false;
                if(EnableCounterRSIFilter && profit > 0 && g_defenseRSIHandle != INVALID_HANDLE)
                {
                    double rsiBuf[];
                    if(CopyBuffer(g_defenseRSIHandle, 0, 0, 1, rsiBuf) > 0)
                    {
                        double currentRSI = rsiBuf[0];
                        if(posType == POSITION_TYPE_BUY && currentRSI >= CounterRSI_Upper) closeByRSI = true;
                        if(posType == POSITION_TYPE_SELL && currentRSI <= CounterRSI_Lower) closeByRSI = true;
                    }
                }
                
                if(closeByRSI)
                {
                    Print("=== COUNTER TRADE RSI FILTER: Closing profitable position based on RSI Lock-in ===");
                    if(ClosePositionByTicket(v15GridPositions[i].ticket, MagicNumber_V15))
                    {
                        v15TotalRecoveredProfit += profit;
                        v15CounterTradesClosedProfit++;
                        RemoveV15PositionFromArray(v15GridPositions[i].ticket);
                        continue;
                    }
                }
                // ----------------------------------------
                
                if (StringFind(comment, "CounterDefense") >= 0)
                {
                    defenseProfit += profit;
                    anyDefense = true;

                    // Breakeven check
                    if (CounterDefenseUseBreakeven)
                    {
                        double openPrice = v15GridPositions[i].openPrice;
                        double curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                        double curAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                        
                        bool triggerBreakeven = false;
                        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && curBid <= openPrice) triggerBreakeven = true;
                        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && curAsk >= openPrice) triggerBreakeven = true;

                        if (triggerBreakeven)
                        {
                            Print("=== COUNTER DEFENSE: Price returned to breakeven for Level ", v15GridPositions[i].level, " — Closing defense basket ===");
                            CloseAllDefenseTrades();
                            CheckAndResumeMainGrid();
                            return;
                        }
                    }
                }
                else
                {
                    // Existing normal counter trade management
                    if(profit >= v15GridPositions[i].targetProfit)
                    {
                        ClosePositionByTicket(v15GridPositions[i].ticket, MagicNumber_V15);
                        v15TotalRecoveredProfit += profit;
                        v15CounterTradesClosedProfit++;
                        RemoveV15PositionFromArray(v15GridPositions[i].ticket);
                    }
                }
            }
            else
            {
                RemoveV15PositionFromArray(v15GridPositions[i].ticket);
            }
        }
    }

    // Check defense basket profit
    if (anyDefense && defenseProfit >= CounterDefenseBasketProfit)
    {
        if(EnableADXHoldHedge)
        {
            if(IsHedgeADXIncreasing())
            {
                static datetime lastLog = 0;
                if(TimeCurrent() - lastLog > 60)
                {
                    Print("=== COUNTER DEFENSE: Profit target reached ($", DoubleToString(defenseProfit, 2), 
                          ") but ADX is strengthening — Holding Hedge Position ===");
                    lastLog = TimeCurrent();
                }
                return; // Hold the position
            }
            else
            {
                Print("=== COUNTER DEFENSE: Target reached and ADX trend fading/flat — Closing basket and triggering Recovery ===");
                v15TriggerRecoveryAfterHedge = true;
            }
        }
        else
        {
            Print("=== COUNTER DEFENSE: Basket profit reached ($", DoubleToString(defenseProfit, 2), ") — Closing defense basket ===");
        }

        CloseAllDefenseTrades();
        CheckAndResumeMainGrid();
    }
}

//+------------------------------------------------------------------+
//| Check Stale Equity — close all if P&L flat for too long            |
//+------------------------------------------------------------------+
void CheckStaleEquity()
{
    double currentPL = GetV15BasketProfit();
    
    if(!v15StaleEquityTracking)
    {
        // Start tracking
        v15StaleEquityTracking = true;
        v15StaleEquityStartTime = TimeCurrent();
        v15StaleEquityBaseline = currentPL;
        return;
    }
    
    // Check if P&L has moved outside tolerance
    double plChange = MathAbs(currentPL - v15StaleEquityBaseline);
    
    if(plChange > StaleEquityToleranceUSD)
    {
        // Equity is moving — reset the tracker
        v15StaleEquityStartTime = TimeCurrent();
        v15StaleEquityBaseline = currentPL;
        return;
    }
    
    // P&L is still within tolerance — check duration
    int elapsedSeconds = (int)(TimeCurrent() - v15StaleEquityStartTime);
    int thresholdSeconds = StaleEquityMinutes * 60;
    
    if(elapsedSeconds >= thresholdSeconds)
    {
        Print("=== STALE EQUITY DETECTED ===");
        Print("Floating P&L: $", DoubleToString(currentPL, 2), 
              " | Baseline: $", DoubleToString(v15StaleEquityBaseline, 2),
              " | Stale for: ", elapsedSeconds / 60, " minutes");
        
        if(UseTelegram)
        {
            string message = "\xE2\x9A\xA0 <b>STALE EQUITY — CLOSING ALL</b>\n\n";
            message += "\xF0\x9F\x93\x8A <b>Symbol:</b> " + _Symbol + "\n";
            message += "\xF0\x9F\x92\xB0 <b>Floating P&L:</b> $" + DoubleToString(currentPL, 2) + "\n";
            message += "\xE2\x8F\xB1 <b>Stale Duration:</b> " + IntegerToString(elapsedSeconds / 60) + " min\n";
            message += "\xF0\x9F\x94\x84 Equity hedged/flat for too long — closing all positions";
            SendTelegramMessage(message);
        }
        
        CloseAllV15Positions("Stale Equity (" + IntegerToString(elapsedSeconds / 60) + " min flat)");
    }
}

//+------------------------------------------------------------------+
//| Close All Counter Defense Trades                                   |
//+------------------------------------------------------------------+
void CloseAllDefenseTrades()
{
    // The trigger flag v15TriggerRecoveryAfterHedge is set in ManageV15CounterTrades 
    // specifically when closing due to ADX/Target conditions to ensure intentional behavior.

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber_V15)
            {
                string comment = PositionGetString(POSITION_COMMENT);
                if (StringFind(comment, "CounterDefense") >= 0)
                {
                    ClosePositionByTicket(ticket, MagicNumber_V15);
                    RemoveV15PositionFromArray(ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check and Resume Main Grid Expansion                               |
//+------------------------------------------------------------------+
void CheckAndResumeMainGrid()
{
    if (v15Level3Pending || v15Level4Pending)
    {
        Print("=== RESUMING NORMAL GRID OPERATIONS ===");
        
        // Open level 3 if it was pending
        if (v15Level3Pending)
        {
            v15Level3Pending = false;
            Print("Resuming Level 3...");
            AddV15GridLevel();
        }
        
        // Open level 4 if it was also reached
        if (v15Level4Pending)
        {
            v15Level4Pending = false;
            Print("Resuming Level 4...");
            AddV15GridLevel();
        }
        
        v15CounterDefenseActive = false;
        
        if(UseTelegram) SendTelegramMessage("🔄 <b>GRID RESUMED</b>\nCounter defense closed. Resuming main grid levels.");
    }
}

//+------------------------------------------------------------------+
//| Get V15 Main Grid Profit                                           |
//+------------------------------------------------------------------+
double GetV15MainGridProfit()
{
    double totalProfit = 0;

    for(int i = 0; i < ArraySize(v15GridPositions); i++)
    {
        if(!v15GridPositions[i].isCounterTrade)
        {
            if(PositionSelectByTicket(v15GridPositions[i].ticket))
                totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
    }

    return totalProfit;
}

//+------------------------------------------------------------------+
//| Get V15 Basket Profit                                              |
//+------------------------------------------------------------------+
double GetV15BasketProfit()
{
    double totalProfit = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber_V15)
            {
                totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            }
        }
    }

    return totalProfit;
}

//+------------------------------------------------------------------+
//| Count V15 Active Counter Trades                                    |
//+------------------------------------------------------------------+
int CountV15ActiveCounterTrades()
{
    int count = 0;
    for(int i = 0; i < ArraySize(v15GridPositions); i++)
    {
        if(v15GridPositions[i].isCounterTrade)
        {
            if(PositionSelectByTicket(v15GridPositions[i].ticket))
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Remove V15 Position From Array                                     |
//+------------------------------------------------------------------+
void RemoveV15PositionFromArray(ulong ticket)
{
    for(int i = 0; i < ArraySize(v15GridPositions); i++)
    {
        if(v15GridPositions[i].ticket == ticket)
        {
            for(int j = i; j < ArraySize(v15GridPositions) - 1; j++)
                v15GridPositions[j] = v15GridPositions[j + 1];
            ArrayResize(v15GridPositions, ArraySize(v15GridPositions) - 1);
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Close All V15 Positions                                            |
//+------------------------------------------------------------------+
void CloseAllV15Positions(string reason)
{
    Print("=== CLOSING ALL V15 POSITIONS: ", reason, " ===");
    double closedPL = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber_V15)
            {
                closedPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                ClosePositionByTicket(ticket, MagicNumber_V15);
            }
        }
    }

    ArrayResize(v15GridPositions, 0);
    v15CurrentGridLevel = 0;
    v15CurrentGridDirection = "";
    v15LastGridPrice = 0;
    v15CounterTradeCount = 0;
    v15CounterTradesEnabled = false;
    v15PeakDrawdown = 0;
    v15BasketProfitLocked = false;
    v15GridPaused = false;
    v15GridLevelPending = false;
    v15Level3Pending = false;
    v15Level4Pending = false;
    v15CounterDefenseActive = false;
    v15StaleEquityTracking = false;
    v15StaleEquityStartTime = 0;
    v15StaleEquityBaseline = 0;
    v15MarginRecoveryActive = false;
    v15RecoveryAtBreakEven = false;
    v15TriggerRecoveryAfterHedge = false;

    ResetExpansionLock(g_expansionLockState);

    SendV15CloseNotification(reason, closedPL);
}

//+------------------------------------------------------------------+
//| Close Position by Ticket                                           |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket, int magic)
{
    if(!PositionSelectByTicket(ticket))
        return false;

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = _Symbol;
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.deviation = Slippage;
    request.magic = magic;

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

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Calculate V15 Grid Lot                                             |
//+------------------------------------------------------------------+
double CalculateV15GridLot(int level)
{
    return GetHybridLotSize(level);
}

//+------------------------------------------------------------------+
//| Calculate V15 Counter Lot                                          |
//+------------------------------------------------------------------+
double CalculateV15CounterLot(int level, double currentDrawdown)
{
    double lot = CounterTradeLotSize;

    for(int i = 1; i < level; i++)
        lot *= CounterLotMultiplier;

    if(UseDrawdownWeighting && currentDrawdown > CounterTradeLossThreshold)
    {
        double drawdownRatio = MathAbs(currentDrawdown) / CounterTradeLossThreshold;
        double weightFactor = 1.0 + (drawdownRatio - 1.0) * 0.5;
        weightFactor = MathMin(weightFactor, 3.0);
        lot *= weightFactor;
    }

    return lot;
}

//+------------------------------------------------------------------+
//| Calculate V15 Weighted Target                                      |
//+------------------------------------------------------------------+
double CalculateV15WeightedTarget(double currentDrawdown, int counterLevel)
{
    double target = MinCounterProfitUSD;

    if(UseDrawdownWeighting && currentDrawdown < 0)
    {
        double absDrawdown = MathAbs(currentDrawdown);
        double portionToRecover = absDrawdown / MaxCounterTrades;
        target = portionToRecover * RecoveryMultiplier;
        target *= (1.0 + (counterLevel - 1) * 0.2);
        target = MathMax(target, MinCounterProfitUSD);
        target = MathMin(target, MaxCounterProfitUSD);
    }

    return target;
}

//+------------------------------------------------------------------+
//| Normalize Lot Size                                                 |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lot = MathFloor(lot / lotStep) * lotStep;
    if(lot < minLot) lot = minLot;
    if(lot > maxLot) lot = maxLot;

    return lot;
}


//+------------------------------------------------------------------+
//| DEFENSE SYSTEM FUNCTIONS                                           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check ATR Spike Detection                                          |
//+------------------------------------------------------------------+
bool CheckATRSpike(double &ratio)
{
    if(g_defenseATRHandle == INVALID_HANDLE) { ratio = 0; return false; }

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);

    if(CopyBuffer(g_defenseATRHandle, 0, 0, 15, atrBuf) < 15) { ratio = 0; return false; }

    double currentATR = atrBuf[0];
    double avgATR = 0;
    for(int i = 1; i <= 14; i++) avgATR += atrBuf[i];
    avgATR /= 14.0;

    if(avgATR <= 0) { ratio = 0; return false; }

    ratio = currentATR / avgATR;
    g_impulseState.atrSpike = ratio;

    return (ratio > ImpulseATRMultiplier);
}

//+------------------------------------------------------------------+
//| Check Momentum Candles                                             |
//+------------------------------------------------------------------+
bool CheckMomentumCandles(int &count)
{
    double opens[], closes[], highs[], lows[];
    ArraySetAsSeries(opens, true);
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);

    if(CopyOpen(_Symbol, PERIOD_M1, 1, 2, opens) < 2) { count = 0; return false; }
    if(CopyClose(_Symbol, PERIOD_M1, 1, 2, closes) < 2) { count = 0; return false; }
    if(CopyHigh(_Symbol, PERIOD_M1, 1, 2, highs) < 2) { count = 0; return false; }
    if(CopyLow(_Symbol, PERIOD_M1, 1, 2, lows) < 2) { count = 0; return false; }

    count = 0;
    int consecutiveMomentum = 0;
    int lastDirection = 0;

    for(int i = 0; i < 2; i++)
    {
        double range = highs[i] - lows[i];
        if(range <= 0) { consecutiveMomentum = 0; lastDirection = 0; continue; }

        double body = MathAbs(closes[i] - opens[i]);
        double bodyPct = body / range;

        if(bodyPct > ImpulseCandleBodyPct)
        {
            int direction = (closes[i] > opens[i]) ? 1 : -1;
            if(consecutiveMomentum == 0)
            { consecutiveMomentum = 1; lastDirection = direction; }
            else if(direction == lastDirection)
            { consecutiveMomentum++; }
            else
            { consecutiveMomentum = 1; lastDirection = direction; }
        }
        else
        { consecutiveMomentum = 0; lastDirection = 0; }
    }

    count = consecutiveMomentum;
    g_impulseState.momentumCandles = count;
    return (consecutiveMomentum >= 2);
}

//+------------------------------------------------------------------+
//| Check EMA Expansion Detection                                      |
//+------------------------------------------------------------------+
bool CheckEMAExpansion(double &ratio)
{
    if(g_defenseEMAFastHandle == INVALID_HANDLE || g_defenseEMASlowHandle == INVALID_HANDLE)
    { ratio = 0; return false; }

    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);

    if(CopyBuffer(g_defenseEMAFastHandle, 0, 0, 6, emaFast) < 6) { ratio = 0; return false; }
    if(CopyBuffer(g_defenseEMASlowHandle, 0, 0, 6, emaSlow) < 6) { ratio = 0; return false; }

    double currentDist = MathAbs(emaFast[0] - emaSlow[0]);

    double avgDist = 0;
    for(int i = 1; i <= 5; i++)
        avgDist += MathAbs(emaFast[i] - emaSlow[i]);
    avgDist /= 5.0;

    if(avgDist <= 0) { ratio = 0; return false; }

    ratio = currentDist / avgDist;
    g_impulseState.emaExpansion = ratio;

    return (ratio > (1.0 + ImpulseEMAExpansionPct));
}

//+------------------------------------------------------------------+
//| Detect Impulse Mode                                                |
//+------------------------------------------------------------------+
bool DetectImpulseMode()
{
    if(!EnableImpulseDetection)
    {
        g_impulseState.isActive = false;
        return false;
    }

    double atrRatio = 0;
    bool atrSpike = CheckATRSpike(atrRatio);

    int momentumCount = 0;
    bool momentumCandles = CheckMomentumCandles(momentumCount);

    double emaRatio = 0;
    bool emaExpansion = CheckEMAExpansion(emaRatio);

    bool impulseConditionMet = atrSpike || (momentumCandles && emaExpansion) || (atrSpike && momentumCandles);

    if(impulseConditionMet && !g_impulseState.isActive)
    {
        g_impulseState.isActive = true;
        g_impulseState.activationTime = TimeCurrent();
        g_impulseState.consecutiveNormalBars = 0;

        string trigger = "";
        if(atrSpike)        trigger += "ATR_SPIKE(" + DoubleToString(atrRatio, 2) + "x) ";
        if(momentumCandles) trigger += "MOMENTUM(" + IntegerToString(momentumCount) + ") ";
        if(emaExpansion)    trigger += "EMA_EXPAND(" + DoubleToString(emaRatio, 2) + "x)";
        g_impulseState.triggerCondition = trigger;

        g_defenseStats.impulseActivations++;

        Print("=== IMPULSE MODE ACTIVATED ===");
        Print("Trigger: ", trigger);

        SendImpulseNotification(true, trigger);
    }
    else if(!impulseConditionMet && g_impulseState.isActive)
    {
        g_impulseState.consecutiveNormalBars++;

        if(g_impulseState.consecutiveNormalBars >= ImpulseDeactivationBars)
        {
            g_impulseState.isActive = false;

            Print("=== IMPULSE MODE DEACTIVATED ===");
            SendImpulseNotification(false, "");

            g_impulseState.triggerCondition = "";
            g_impulseState.consecutiveNormalBars = 0;
        }
    }

    return g_impulseState.isActive;
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Grid Step                                        |
//+------------------------------------------------------------------+
double CalculateDynamicGridStep(bool impulseMode, double currentATR)
{
    if(!EnableDynamicSpacing) return GridStepPoints;

    if(currentATR <= 0)
    {
        Print("Warning: Invalid ATR for grid spacing: ", currentATR);
        return g_spacingState.currentStep;
    }

    double multiplier = impulseMode ? g_spacingState.impulseMultiplier : g_spacingState.normalMultiplier;
    double calculatedStep = currentATR * multiplier * MathPow(10, _Digits);

    if(calculatedStep < GridSpacingMinPoints)       calculatedStep = GridSpacingMinPoints;
    else if(calculatedStep > GridSpacingMaxPoints)  calculatedStep = GridSpacingMaxPoints;

    g_spacingState.currentStep = calculatedStep;
    g_spacingState.lastATR = currentATR;
    g_spacingState.lastRecalculation = TimeCurrent();

    if(ShowDebugInfo)
    {
        static datetime lastLogTime = 0;
        if(TimeCurrent() - lastLogTime > 60)
        {
            Print("Dynamic Grid Step: ", DoubleToString(calculatedStep, 0), " pts | ATR: ",
                  DoubleToString(currentATR, _Digits), " | Mode: ", impulseMode ? "IMPULSE" : "NORMAL");
            lastLogTime = TimeCurrent();
        }
    }

    return calculatedStep;
}

//+------------------------------------------------------------------+
//| Should Recalculate Spacing                                         |
//+------------------------------------------------------------------+
bool ShouldRecalculateSpacing(double currentATR, double lastATR)
{
    if(!EnableDynamicSpacing) return false;
    if(lastATR <= 0) return true;

    double atrChange = MathAbs(currentATR - lastATR) / lastATR;
    bool shouldRecalc = atrChange > GridSpacingRecalcThreshold;

    if(shouldRecalc) g_defenseStats.spacingRecalculations++;

    return shouldRecalc;
}

//+------------------------------------------------------------------+
//| KELLY CRITERION ENGINE                                             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Initialize Kelly State                                             |
//+------------------------------------------------------------------+
void InitializeKellyState()
{
    ZeroMemory(g_kellyState);
    g_kellyState.initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_kellyState.ddThrottleMultiplier = 1.0;
    g_kellyState.ddThrottleLevel = "NORMAL";
    g_kellyState.currentWinRate = KellyWinRate;
    g_kellyState.currentPayoffRatio = (KellyAvgLoss > 0) ? KellyAvgWin / KellyAvgLoss : 1.5;

    // Try to learn from trade history if enabled
    if(KellyLookbackTrades > 0)
        UpdateKellyFromTradeHistory();

    // Calculate initial Kelly
    CalculateKellyPct();
    CalculateKellyLot();
    CalculateAdaptiveBasketTarget();

    Print("Kelly Criterion initialized: f*=", DoubleToString(g_kellyState.currentKellyPct * 100, 2),
          "%, Fractional=", DoubleToString(g_kellyState.fractionalKellyPct * 100, 2),
          "%, Lot=", DoubleToString(g_kellyState.kellyLotSize, 2));
    Print("Adaptive Basket Target: $", DoubleToString(g_kellyState.currentBasketTarget, 2),
          " (Equity: $", DoubleToString(g_kellyState.initialEquity, 2), ")");
    Print("Progressive DD: Level=", g_kellyState.ddThrottleLevel,
          ", Throttle=", DoubleToString(g_kellyState.ddThrottleMultiplier, 2), "x");
}

//+------------------------------------------------------------------+
//| Calculate Kelly Percentage: f* = (b*p - q) / b                     |
//+------------------------------------------------------------------+
void CalculateKellyPct()
{
    double p = g_kellyState.currentWinRate;
    double q = 1.0 - p;
    double b = g_kellyState.currentPayoffRatio;

    // Guard: no edge or invalid inputs
    if(p <= 0 || p >= 1.0 || b <= 0)
    {
        g_kellyState.currentKellyPct = 0;
        g_kellyState.fractionalKellyPct = 0;
        return;
    }

    // Kelly formula: f* = (b*p - q) / b
    double rawKelly = (b * p - q) / b;

    // If negative, strategy has no edge — don't bet
    if(rawKelly <= 0)
    {
        g_kellyState.currentKellyPct = 0;
        g_kellyState.fractionalKellyPct = 0;
        Print("WARNING: Kelly f* is negative (", DoubleToString(rawKelly * 100, 2),
              "%) — no statistical edge detected");
        return;
    }

    // Clamp raw Kelly to max risk
    rawKelly = MathMin(rawKelly, KellyMaxRiskPct / 100.0);

    g_kellyState.currentKellyPct = rawKelly;
    g_kellyState.fractionalKellyPct = rawKelly * KellyFraction;
    g_kellyState.equityAtCalc = AccountInfoDouble(ACCOUNT_EQUITY);
}

//+------------------------------------------------------------------+
//| Calculate Kelly Lot from equity percentage                         |
//+------------------------------------------------------------------+
void CalculateKellyLot()
{
    if(!EnableKellyCriterion || g_kellyState.fractionalKellyPct <= 0)
    {
        g_kellyState.kellyLotSize = KellyMinLot;
        return;
    }

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount = equity * g_kellyState.fractionalKellyPct;

    // Convert risk $ to lots using tick value
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    if(tickValue <= 0 || tickSize <= 0)
    {
        g_kellyState.kellyLotSize = KellyMinLot;
        return;
    }

    // Use ATR as the expected move for lot calculation
    double atrVal = 0;
    if(g_defenseATRHandle != INVALID_HANDLE)
    {
        double atrBuf[];
        ArraySetAsSeries(atrBuf, true);
        if(CopyBuffer(g_defenseATRHandle, 0, 0, 1, atrBuf) > 0)
            atrVal = atrBuf[0];
    }

    // If ATR available, use it as expected stop distance
    if(atrVal > 0)
    {
        double stopTicks = atrVal / tickSize;
        double riskPerLot = stopTicks * tickValue;
        if(riskPerLot > 0)
            g_kellyState.kellyLotSize = riskAmount / riskPerLot;
        else
            g_kellyState.kellyLotSize = KellyMinLot;
    }
    else
    {
        // Fallback: use grid step as stop distance
        double stopTicks = GridStepPoints;
        double riskPerLot = stopTicks * tickValue;
        if(riskPerLot > 0)
            g_kellyState.kellyLotSize = riskAmount / riskPerLot;
        else
            g_kellyState.kellyLotSize = KellyMinLot;
    }

    // Clamp to Kelly lot limits
    g_kellyState.kellyLotSize = MathMax(g_kellyState.kellyLotSize, KellyMinLot);
    g_kellyState.kellyLotSize = MathMin(g_kellyState.kellyLotSize, KellyMaxLot);
}

//+------------------------------------------------------------------+
//| Update Kelly from Trade History (learn win rate + payoff)           |
//+------------------------------------------------------------------+
void UpdateKellyFromTradeHistory()
{
    if(KellyLookbackTrades <= 0) return;

    // Select deal history for the last 90 days
    datetime fromDate = TimeCurrent() - 90 * 24 * 60 * 60;
    datetime toDate = TimeCurrent();

    if(!HistorySelect(fromDate, toDate)) return;

    int totalDeals = HistoryDealsTotal();
    if(totalDeals == 0) return;

    int wins = 0, losses = 0;
    double sumW = 0, sumL = 0;
    int counted = 0;

    // Iterate from most recent deals backward
    for(int i = totalDeals - 1; i >= 0 && counted < KellyLookbackTrades; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket == 0) continue;

        // Only count deals for our magic number and symbol
        if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber_V15) continue;
        if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;

        // Only exit deals (DEAL_ENTRY_OUT)
        if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                        HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                        HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

        if(profit > 0)
        {
            wins++;
            sumW += profit;
        }
        else if(profit < 0)
        {
            losses++;
            sumL += MathAbs(profit);
        }

        counted++;
    }

    int totalTrades = wins + losses;
    if(totalTrades >= 10) // Need at least 10 trades for meaningful stats
    {
        g_kellyState.currentWinRate = (double)wins / totalTrades;
        double avgWin = (wins > 0) ? sumW / wins : KellyAvgWin;
        double avgLoss = (losses > 0) ? sumL / losses : KellyAvgLoss;
        g_kellyState.currentPayoffRatio = (avgLoss > 0) ? avgWin / avgLoss : 1.5;
        g_kellyState.totalWins = wins;
        g_kellyState.totalLosses = losses;
        g_kellyState.sumWins = sumW;
        g_kellyState.sumLosses = sumL;

        Print("Kelly ADAPTIVE: Learned from ", totalTrades, " trades (",
              wins, "W/", losses, "L) | WinRate: ", DoubleToString(g_kellyState.currentWinRate * 100, 1),
              "% | R: ", DoubleToString(g_kellyState.currentPayoffRatio, 2));
    }
    else
    {
        Print("Kelly: Only ", totalTrades, " trades found (need 10+). Using input defaults.");
    }
}

//+------------------------------------------------------------------+
//| Record Kelly Trade Result (called on basket close)                 |
//+------------------------------------------------------------------+
void RecordKellyTradeResult(bool isWin, double amount)
{
    if(!EnableKellyCriterion) return;

    if(isWin)
    {
        g_kellyState.totalWins++;
        g_kellyState.sumWins += amount;
    }
    else
    {
        g_kellyState.totalLosses++;
        g_kellyState.sumLosses += amount;
    }

    // Recalculate live stats if we have enough data
    int totalTrades = g_kellyState.totalWins + g_kellyState.totalLosses;
    if(totalTrades >= 10)
    {
        g_kellyState.currentWinRate = (double)g_kellyState.totalWins / totalTrades;
        double avgWin = (g_kellyState.totalWins > 0) ? g_kellyState.sumWins / g_kellyState.totalWins : KellyAvgWin;
        double avgLoss = (g_kellyState.totalLosses > 0) ? g_kellyState.sumLosses / g_kellyState.totalLosses : KellyAvgLoss;
        g_kellyState.currentPayoffRatio = (avgLoss > 0) ? avgWin / avgLoss : 1.5;
    }

    // Recalculate Kelly for next cycle
    CalculateKellyPct();
    CalculateKellyLot();
    CalculateAdaptiveBasketTarget();

    Print("Kelly Updated: ", isWin ? "WIN" : "LOSS", " $", DoubleToString(amount, 2),
          " | W/L: ", g_kellyState.totalWins, "/", g_kellyState.totalLosses,
          " | f*: ", DoubleToString(g_kellyState.currentKellyPct * 100, 2), "%",
          " | Lot: ", DoubleToString(g_kellyState.kellyLotSize, 2),
          " | Target: $", DoubleToString(g_kellyState.currentBasketTarget, 2));
}

//+------------------------------------------------------------------+
//| Calculate Adaptive Basket Target (grows with equity)                |
//+------------------------------------------------------------------+
void CalculateAdaptiveBasketTarget()
{
    if(!EnableAdaptiveBasket)
    {
        g_kellyState.currentBasketTarget = BasketProfitUSD;
        return;
    }

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double initialEquity = g_kellyState.initialEquity;
    if(initialEquity <= 0) initialEquity = equity;

    // Base target as percentage of current equity
    double baseTarget = equity * (BasketBasePct / 100.0);

    // Growth acceleration: scale with equity growth
    double equityGrowthRatio = equity / initialEquity;
    if(equityGrowthRatio > 1.0)
    {
        // Apply growth factor only when equity has grown
        double growthBoost = MathPow(equityGrowthRatio, BasketGrowthFactor - 1.0);
        baseTarget *= growthBoost;
    }

    // Clamp to limits
    baseTarget = MathMax(baseTarget, BasketMinUSD);
    baseTarget = MathMin(baseTarget, BasketMaxUSD);

    g_kellyState.currentBasketTarget = baseTarget;
}

//+------------------------------------------------------------------+
//| Evaluate Progressive Drawdown Throttling                           |
//+------------------------------------------------------------------+
void EvaluateProgressiveDrawdown()
{
    if(!EnableProgressiveDD)
    {
        g_kellyState.ddThrottleMultiplier = 1.0;
        g_kellyState.ddThrottleLevel = "NORMAL";
        return;
    }

    double ddPct = g_killSwitchState.currentDrawdownPct * 100.0; // Convert to percentage

    string prevLevel = g_kellyState.ddThrottleLevel;
    double prevMultiplier = g_kellyState.ddThrottleMultiplier;

    // Apply recovery buffer for hysteresis (prevent oscillation)
    double effectiveL1 = DDThrottleLevel1Pct;
    double effectiveL2 = DDThrottleLevel2Pct;
    double effectiveL3 = DDThrottleLevel3Pct;

    // If already throttled, require recovery below threshold minus buffer
    if(prevLevel == "LEVEL3")
    {
        effectiveL3 -= DDRecoveryBuffer;
        effectiveL2 -= DDRecoveryBuffer;
        effectiveL1 -= DDRecoveryBuffer;
    }
    else if(prevLevel == "LEVEL2")
    {
        effectiveL2 -= DDRecoveryBuffer;
        effectiveL1 -= DDRecoveryBuffer;
    }
    else if(prevLevel == "LEVEL1")
    {
        effectiveL1 -= DDRecoveryBuffer;
    }

    // Determine throttle level
    if(ddPct >= DDThrottleLevel3Pct)
    {
        g_kellyState.ddThrottleMultiplier = 0.0;  // Stop all new entries
        g_kellyState.ddThrottleLevel = "LEVEL3";
    }
    else if(ddPct >= DDThrottleLevel2Pct)
    {
        g_kellyState.ddThrottleMultiplier = 0.25; // Quarter lots
        g_kellyState.ddThrottleLevel = "LEVEL2";
    }
    else if(ddPct >= effectiveL1)
    {
        g_kellyState.ddThrottleMultiplier = 0.5;  // Half lots
        g_kellyState.ddThrottleLevel = "LEVEL1";
    }
    else
    {
        g_kellyState.ddThrottleMultiplier = 1.0;  // Full Kelly
        g_kellyState.ddThrottleLevel = "NORMAL";
    }

    // Log level changes
    if(g_kellyState.ddThrottleLevel != prevLevel)
    {
        Print("=== DD THROTTLE CHANGE: ", prevLevel, " -> ", g_kellyState.ddThrottleLevel,
              " | DD: ", DoubleToString(ddPct, 2), "% | Multiplier: ",
              DoubleToString(g_kellyState.ddThrottleMultiplier, 2), "x ===");

        if(UseTelegram)
        {
            string emoji = g_kellyState.ddThrottleMultiplier < prevMultiplier ? "⚠️" : "✅";
            string message = emoji + " <b>DD THROTTLE: " + g_kellyState.ddThrottleLevel + "</b>\n\n";
            message += "📉 <b>Drawdown:</b> " + DoubleToString(ddPct, 2) + "%\n";
            message += "🎚️ <b>Lot Multiplier:</b> " + DoubleToString(g_kellyState.ddThrottleMultiplier, 2) + "x\n";
            if(g_kellyState.ddThrottleMultiplier == 0)
                message += "🛑 <b>NEW ENTRIES STOPPED</b>\n";
            message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
            SendTelegramMessage(message);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Hybrid Lot Size (Kelly-Aware)                                  |
//+------------------------------------------------------------------+
double GetHybridLotSize(int gridLevel)
{
    // Kelly Criterion path
    if(EnableKellyCriterion)
    {
        // Recalculate Kelly lot with current equity
        CalculateKellyLot();

        double baseLot = g_kellyState.kellyLotSize;

        if(gridLevel > 1)
        {
            // Scale subsequent grid levels with controlled growth
            // Level 2 = base × 1.5, Level 3 = base × 2.0, etc.
            double gridScaleFactor = 1.0 + (gridLevel - 1) * 0.5;
            gridScaleFactor = MathMin(gridScaleFactor, 3.0); // Cap at 3x
            baseLot *= gridScaleFactor;
        }

        // Apply progressive drawdown throttle
        if(EnableProgressiveDD)
            baseLot *= g_kellyState.ddThrottleMultiplier;

        // Clamp to Kelly lot limits
        baseLot = MathMax(baseLot, KellyMinLot);
        baseLot = MathMin(baseLot, KellyMaxLot);

        // Also respect existing defense lot cap
        if(EnableLotScaling && baseLot > g_lotConfig.maxLotPerLevel)
        {
            baseLot = g_lotConfig.maxLotPerLevel;
            g_defenseStats.lotCapApplications++;
        }

        return baseLot;
    }

    // Original hybrid lot logic (unchanged)
    if(!EnableLotScaling)
    {
        double lot = InitialLotSize;
        for(int i = 1; i < gridLevel; i++) lot *= LotMultiplier;
        return lot;
    }

    if(gridLevel < 1) return g_lotConfig.sequence[0];

    int sequenceIndex = gridLevel - 1;
    double calculatedLot = (sequenceIndex < 6) ? g_lotConfig.sequence[sequenceIndex] : g_lotConfig.sequence[5];

    double finalLot = calculatedLot;
    if(calculatedLot > g_lotConfig.maxLotPerLevel)
    {
        finalLot = g_lotConfig.maxLotPerLevel;
        g_defenseStats.lotCapApplications++;
        Print("LOT CAP APPLIED - Level: ", gridLevel,
              " | Calculated: ", DoubleToString(calculatedLot, 2),
              " | Capped to: ", DoubleToString(finalLot, 2));
    }

    return finalLot;
}

//+------------------------------------------------------------------+
//| Get Total Grid Exposure                                            |
//+------------------------------------------------------------------+
double GetTotalGridExposure()
{
    double totalExposure = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == MagicNumber_V15)
            {
                totalExposure += PositionGetDouble(POSITION_VOLUME);
            }
        }
    }

    return totalExposure;
}

//+------------------------------------------------------------------+
//| Can Add Grid Level                                                 |
//+------------------------------------------------------------------+
bool CanAddGridLevel(double proposedLot)
{
    if(!EnableLotScaling) return true;

    double currentExposure = GetTotalGridExposure();
    double projectedExposure = currentExposure + proposedLot;

    bool canAdd = projectedExposure <= g_lotConfig.maxTotalExposure;

    if(!canAdd)
    {
        Print("EXPOSURE LIMIT REACHED - Current: ", DoubleToString(currentExposure, 2),
              " | Proposed: ", DoubleToString(proposedLot, 2),
              " | Max: ", DoubleToString(g_lotConfig.maxTotalExposure, 2));
    }

    return canAdd;
}

//+------------------------------------------------------------------+
//| Check Expansion Lock                                               |
//+------------------------------------------------------------------+
bool CheckExpansionLock(ExpansionLockState &state)
{
    if(!EnableExpansionLock)
    {
        state.isLocked = false;
        state.lockReason = "";
        return false;
    }

    int currentLevels = v15CurrentGridLevel;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double firstEntryPrice = 0;
    if(ArraySize(v15GridPositions) > 0)
        firstEntryPrice = v15GridPositions[0].openPrice;

    double h1ATR = 0;
    if(g_h1ATRHandle != INVALID_HANDLE)
    {
        double atrBuf[];
        ArraySetAsSeries(atrBuf, true);
        if(CopyBuffer(g_h1ATRHandle, 0, 0, 1, atrBuf) > 0)
            h1ATR = atrBuf[0];
    }

    state.currentLevels = currentLevels;
    state.firstEntryPrice = firstEntryPrice;
    state.h1ATR = h1ATR;

    if(firstEntryPrice > 0)
        state.priceRangePoints = MathAbs(currentPrice - firstEntryPrice) / _Point;
    else
        state.priceRangePoints = 0;

    bool levelLimitReached = (currentLevels >= DefenseMaxGridLevels);
    bool rangeLimitReached = false;

    if(firstEntryPrice > 0 && h1ATR > 0)
    {
        double maxRangePoints = (h1ATR / _Point) * MaxRangeATRMultiplier;
        rangeLimitReached = (state.priceRangePoints > maxRangePoints);
    }

    bool wasLocked = state.isLocked;

    if(levelLimitReached)
    {
        state.isLocked = true;
        state.lockReason = "Max Levels (" + IntegerToString(DefenseMaxGridLevels) + ")";
        if(!wasLocked)
        {
            g_defenseStats.expansionLockActivations++;
            Print("=== EXPANSION LOCK ACTIVATED: ", state.lockReason, " ===");
            SendExpansionLockNotification(true, state.lockReason, currentLevels, state.priceRangePoints);
        }
    }
    else if(rangeLimitReached)
    {
        state.isLocked = true;
        state.lockReason = "Max Range (" + DoubleToString(MaxRangeATRMultiplier, 1) + "x H1 ATR)";
        if(!wasLocked)
        {
            g_defenseStats.expansionLockActivations++;
            Print("=== EXPANSION LOCK ACTIVATED: ", state.lockReason, " ===");
            SendExpansionLockNotification(true, state.lockReason, currentLevels, state.priceRangePoints);
        }
    }
    else
    {
        if(wasLocked) Print("=== EXPANSION LOCK DEACTIVATED ===");
        state.isLocked = false;
        state.lockReason = "";
    }

    return state.isLocked;
}

//+------------------------------------------------------------------+
//| Reset Expansion Lock                                               |
//+------------------------------------------------------------------+
void ResetExpansionLock(ExpansionLockState &state)
{
    bool wasLocked = state.isLocked;

    state.isLocked = false;
    state.lockReason = "";
    state.currentLevels = 0;
    state.priceRangePoints = 0;
    state.firstEntryPrice = 0;
    state.h1ATR = 0;

    if(wasLocked && ShowDebugInfo)
        Print("Expansion Lock RESET");
}

//+------------------------------------------------------------------+
//| Evaluate Shedding Conditions                                       |
//+------------------------------------------------------------------+
bool EvaluateSheddingConditions(SheddingState &state, double equityDD, double priceExtension, double rsi)
{
    if(!EnablePartialShedding) { state.evaluationTriggered = false; return false; }

    bool equityThresholdMet = (equityDD > SheddingEquityThreshold);
    bool priceExtensionMet = (priceExtension > SheddingATRExtension);
    bool shouldEvaluate = equityThresholdMet && priceExtensionMet;

    state.evaluationTriggered = shouldEvaluate;

    if(shouldEvaluate && ShowDebugInfo)
        Print("=== SHEDDING EVALUATION TRIGGERED ===");

    return shouldEvaluate;
}

//+------------------------------------------------------------------+
//| Calculate Shedding Priority                                        |
//+------------------------------------------------------------------+
int CalculateSheddingPriority(double rsi, int gridDirection)
{
    int priority = 1;

    if(gridDirection < 0 && rsi > SheddingRSIThreshold)
        priority = 3;
    else if(gridDirection > 0 && rsi < (100 - SheddingRSIThreshold))
        priority = 3;

    return priority;
}

//+------------------------------------------------------------------+
//| Select Position to Shed                                            |
//+------------------------------------------------------------------+
ulong SelectPositionToShed(GridPosition &positions[], int method)
{
    int posCount = ArraySize(positions);
    if(posCount == 0) return 0;

    ulong selectedTicket = 0;

    if(method == 1)
    {
        double maxLot = 0;
        for(int i = 0; i < posCount; i++)
        {
            if(positions[i].lotSize > maxLot)
            {
                maxLot = positions[i].lotSize;
                selectedTicket = positions[i].ticket;
            }
        }
    }
    else if(method == 2)
    {
        int maxLevel = 0;
        for(int i = 0; i < posCount; i++)
        {
            if(positions[i].level > maxLevel)
            {
                maxLevel = positions[i].level;
                selectedTicket = positions[i].ticket;
            }
        }
    }

    return selectedTicket;
}

//+------------------------------------------------------------------+
//| Execute Partial Shedding                                           |
//+------------------------------------------------------------------+
bool ExecutePartialShedding(SheddingState &state, GridPosition &positions[])
{
    if(state.lastSheddingTime > 0)
    {
        int secondsSinceLast = (int)(TimeCurrent() - state.lastSheddingTime);
        if(secondsSinceLast < SheddingCooldownSeconds) return false;
    }

    int posCount = ArraySize(positions);
    if(posCount == 0) return false;

    int maxToShed = (int)MathFloor(posCount * MaxSheddingPercent);
    if(maxToShed < 1) maxToShed = 1;

    Print("=== EXECUTING PARTIAL SHEDDING === Max to Shed: ", maxToShed);

    int positionsShed = 0;
    double totalLotsShed = 0;
    double totalPLShed = 0;

    ulong largestTicket = SelectPositionToShed(positions, 1);
    if(largestTicket > 0 && PositionSelectByTicket(largestTicket))
    {
        double lotSize = PositionGetDouble(POSITION_VOLUME);
        double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

        if(ClosePositionByTicket(largestTicket, MagicNumber_V15))
        {
            positionsShed++;
            totalLotsShed += lotSize;
            totalPLShed += profit;
        }
    }

    if(positionsShed < maxToShed && posCount > 1)
    {
        for(int attempt = 0; attempt < 2 && positionsShed < maxToShed; attempt++)
        {
            ulong lastTicket = SelectPositionToShed(positions, 2);
            if(lastTicket > 0 && lastTicket != largestTicket && PositionSelectByTicket(lastTicket))
            {
                double lotSize = PositionGetDouble(POSITION_VOLUME);
                double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

                if(ClosePositionByTicket(lastTicket, MagicNumber_V15))
                {
                    positionsShed++;
                    totalLotsShed += lotSize;
                    totalPLShed += profit;
                }
            }
        }
    }

    state.lastSheddingTime = TimeCurrent();
    state.positionsShed += positionsShed;

    g_defenseStats.sheddingExecutions++;
    g_defenseStats.totalLotsShed += totalLotsShed;

    if(UseTelegram && positionsShed > 0)
    {
        string message = "🔻 PARTIAL SHEDDING EXECUTED\n\n";
        message += "Positions Closed: " + IntegerToString(positionsShed) + "\n";
        message += "Lots Shed: " + DoubleToString(totalLotsShed, 2) + "\n";
        message += "P/L: $" + DoubleToString(totalPLShed, 2);
        SendTelegramMessage(message);
    }

    return (positionsShed > 0);
}

//+------------------------------------------------------------------+
//| Update Session High Equity                                         |
//+------------------------------------------------------------------+
void UpdateSessionHighEquity(KillSwitchState &state, double currentEquity)
{
    if(!EnableKillSwitch) return;

    if(currentEquity > state.sessionHighEquity)
        state.sessionHighEquity = currentEquity;
}

//+------------------------------------------------------------------+
//| Calculate Drawdown From High                                       |
//+------------------------------------------------------------------+
double CalculateDrawdownFromHigh(KillSwitchState &state, double currentEquity)
{
    if(!EnableKillSwitch) return 0;

    if(state.sessionHighEquity <= 0)
    {
        state.sessionHighEquity = currentEquity;
        return 0;
    }

    double drawdown = 0;
    if(currentEquity < state.sessionHighEquity)
        drawdown = (state.sessionHighEquity - currentEquity) / state.sessionHighEquity;

    state.currentDrawdownPct = drawdown;
    return drawdown;
}

//+------------------------------------------------------------------+
//| Check Kill Switch Trigger                                          |
//+------------------------------------------------------------------+
bool CheckKillSwitchTrigger(KillSwitchState &state)
{
    if(!EnableKillSwitch) return false;
    if(state.triggered || state.inCooldown) return false;

    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    UpdateSessionHighEquity(state, currentEquity);
    double drawdown = CalculateDrawdownFromHigh(state, currentEquity);

    return (drawdown >= KillSwitchDrawdownPct);
}

//+------------------------------------------------------------------+
//| Execute Kill Switch                                                |
//+------------------------------------------------------------------+
void ExecuteKillSwitch(KillSwitchState &state)
{
    if(!EnableKillSwitch) return;

    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdown = state.currentDrawdownPct;
    double drawdownAmount = state.sessionHighEquity - currentEquity;

    Print("========================================");
    Print("!!! EQUITY KILL SWITCH ACTIVATED !!!");
    Print("Session High: $", DoubleToString(state.sessionHighEquity, 2));
    Print("Current Equity: $", DoubleToString(currentEquity, 2));
    Print("Drawdown: ", DoubleToString(drawdown * 100, 2), "%");
    Print("========================================");

    int closedCount = 0;
    double totalLots = 0;
    double totalPL = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            if((int)PositionGetInteger(POSITION_MAGIC) == MagicNumber_V15)
            {
                totalLots += PositionGetDouble(POSITION_VOLUME);
                totalPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                if(ClosePositionByTicket(ticket, MagicNumber_V15)) closedCount++;
            }
        }
    }

    Print("Closed ", closedCount, " positions");

    state.triggered = true;
    state.inCooldown = true;
    state.cooldownEndTime = TimeCurrent() + (KillSwitchCooldownMinutes * 60);

    ArrayResize(v15GridPositions, 0);
    v15CurrentGridLevel = 0;
    v15CurrentGridDirection = "";
    v15LastGridPrice = 0;
    v15CounterTradeCount = 0;
    v15CounterTradesEnabled = false;
    v15PeakDrawdown = 0;
    v15BasketProfitLocked = false;

    ResetExpansionLock(g_expansionLockState);

    g_defenseStats.killSwitchTriggers++;

    if(UseTelegram)
    {
        string message = "🚨🚨🚨 <b>KILL SWITCH ACTIVATED</b> 🚨🚨🚨\n\n";
        message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
        message += "💰 <b>Session High:</b> $" + DoubleToString(state.sessionHighEquity, 2) + "\n";
        message += "💸 <b>Current Equity:</b> $" + DoubleToString(currentEquity, 2) + "\n";
        message += "📉 <b>Drawdown:</b> " + DoubleToString(drawdown * 100, 2) + "% ($" + DoubleToString(drawdownAmount, 2) + ")\n";
        message += "🔒 <b>Positions Closed:</b> " + IntegerToString(closedCount) + "\n";
        message += "📦 <b>Total Lots:</b> " + DoubleToString(totalLots, 2) + "\n";
        message += "💵 <b>P/L:</b> $" + DoubleToString(totalPL, 2) + "\n\n";
        message += "⏸️ <b>Cooldown:</b> " + IntegerToString(KillSwitchCooldownMinutes) + " minutes\n";
        message += "⏰ <b>Resume:</b> " + TimeToString(state.cooldownEndTime, TIME_DATE|TIME_MINUTES);
        SendTelegramMessage(message);
    }
}

//+------------------------------------------------------------------+
//| Is In Kill Switch Cooldown                                         |
//+------------------------------------------------------------------+
bool IsInCooldown(KillSwitchState &state)
{
    if(!EnableKillSwitch || !state.inCooldown) return false;

    if(TimeCurrent() >= state.cooldownEndTime)
    {
        state.inCooldown = false;
        state.triggered = false;
        state.cooldownEndTime = 0;
        state.sessionHighEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        state.currentDrawdownPct = 0;

        Print("=== KILL SWITCH COOLDOWN EXPIRED - Trading Resumed ===");

        if(UseTelegram)
        {
            string message = "✅ <b>KILL SWITCH COOLDOWN EXPIRED</b>\n\n";
            message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
            message += "🔓 Trading resumed | Equity: $" + DoubleToString(state.sessionHighEquity, 2);
            SendTelegramMessage(message);
        }

        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Evaluate All Defense Layers                                        |
//+------------------------------------------------------------------+
void EvaluateAllDefenseLayers(DefenseSystemState &state)
{
    state.gridExpansionAllowed = true;
    state.blockingLayer = "";
    state.blockingReason = "";

    state.impulse = g_impulseState;
    state.spacing = g_spacingState;
    state.lotConfig = g_lotConfig;
    state.expansionLock = g_expansionLockState;
    state.shedding = g_sheddingState;
    state.killSwitch = g_killSwitchState;

    // Daily Profit Limit Layer
    if(UseDailyProfitLimit && g_dailyLimitReached)
    {
        state.gridExpansionAllowed = false;
        state.blockingLayer = "Daily Profit Limit";
        state.blockingReason = "Target reached for the day";
        return;
    }

    // Layer 1: Impulse Detection
    if(EnableImpulseDetection && state.impulse.isActive)
    {
        state.gridExpansionAllowed = false;
        state.blockingLayer = "Impulse Detection";
        state.blockingReason = "Impulse mode active: " + state.impulse.triggerCondition;
        return;
    }

    // Layer 3: Lot Scaling
    if(EnableLotScaling)
    {
        double totalExposure = GetTotalGridExposure();
        if(totalExposure >= state.lotConfig.maxTotalExposure)
        {
            state.gridExpansionAllowed = false;
            state.blockingLayer = "Lot Scaling Control";
            state.blockingReason = "Total exposure limit: " + DoubleToString(totalExposure, 2) +
                                   " / " + DoubleToString(state.lotConfig.maxTotalExposure, 2) + " lots";
            return;
        }
    }

    // Layer 4: Grid Expansion Lock
    if(EnableExpansionLock && state.expansionLock.isLocked)
    {
        state.gridExpansionAllowed = false;
        state.blockingLayer = "Grid Expansion Lock";
        state.blockingReason = "Expansion locked: " + state.expansionLock.lockReason;
        return;
    }

    // Layer 6: Kill Switch
    if(EnableKillSwitch && state.killSwitch.inCooldown)
    {
        state.gridExpansionAllowed = false;
        state.blockingLayer = "Kill Switch";
        state.blockingReason = "Kill switch cooldown until " +
                               TimeToString(state.killSwitch.cooldownEndTime, TIME_DATE|TIME_MINUTES);
        return;
    }

    // Layer 7: Progressive DD Throttle (stop new entries at Level 3)
    if(EnableProgressiveDD && g_kellyState.ddThrottleMultiplier <= 0)
    {
        state.gridExpansionAllowed = false;
        state.blockingLayer = "DD Throttle";
        state.blockingReason = "DD Level 3 active (" + DoubleToString(g_killSwitchState.currentDrawdownPct * 100, 1) + "%) - entries stopped";
        return;
    }
}

//+------------------------------------------------------------------+
//| Can Expand Grid                                                    |
//+------------------------------------------------------------------+
bool CanExpandGrid(DefenseSystemState &state)
{
    EvaluateAllDefenseLayers(state);
    return state.gridExpansionAllowed;
}


//+------------------------------------------------------------------+
//| DISPLAY AND NOTIFICATION FUNCTIONS                                 |
//+------------------------------------------------------------------+

void CreateSignalTable()
{
    if(!ShowSignalTable) return;

    string objName = "Signal_Table_BG";
    if(ObjectFind(0, objName) < 0)
    {
        ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 20);
        ObjectSetInteger(0, objName, OBJPROP_XSIZE, 420);
        ObjectSetInteger(0, objName, OBJPROP_YSIZE, 640);
        ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrBlack);
        ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrWhite);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
    }
}

void UpdateV15Display()
{
    if(!ShowSignalTable) return;

    int x = 20, y = 30;
    int lh = 20;

    CreateLabel("Signal_Header", "=== V15 STANDALONE GRID DEFENSE EA v15.10 ===", x, y, clrYellow, 10);

    // V15 Engine Status
    CreateLabel("Signal_Engine", "ENGINE: V15 BREAKOUT/TREND [ALWAYS ACTIVE]", x, y + lh, clrLime, 11);

    // Breakout Status
    string breakoutStatus = inConsolidation ? "CONSOLIDATING" :
                            (IsInBreakoutWindow() ? "BREAKOUT: " + lastBreakoutDirection : "SCANNING");
    color breakoutColor = inConsolidation ? clrYellow : (IsInBreakoutWindow() ? clrLime : clrGray);
    CreateLabel("Signal_Breakout", "Breakout: " + breakoutStatus, x, y + lh * 2, breakoutColor);

    // Grid Status
    CreateLabel("Signal_Grid", "Grid Level: " + IntegerToString(v15CurrentGridLevel) +
                " / " + IntegerToString(MaxGridLevels) +
                " | Dir: " + v15CurrentGridDirection,
                x, y + lh * 3, clrWhite);

    // P&L
    double pl = GetV15BasketProfit();
    double basketTarget = EnableAdaptiveBasket ? g_kellyState.currentBasketTarget : BasketProfitUSD;
    CreateLabel("Signal_PL", "Basket P/L: $" + DoubleToString(pl, 2) + " / $" + DoubleToString(basketTarget, 2),
                x, y + lh * 4, pl >= 0 ? clrLimeGreen : clrRed, 11);

    // Stats
    CreateLabel("Signal_Stats1", "Signals: " + IntegerToString(signalCount) +
                " | Trades: " + IntegerToString(tradeCount), x, y + lh * 5, clrAqua);
    CreateLabel("Signal_Stats2", "Breakout Trades: " + IntegerToString(v15BreakoutTradesExecuted) +
                " | Recovered: $" + DoubleToString(v15TotalRecoveredProfit, 2),
                x, y + lh * 6, clrWhite);

    // Counter Trades
    string ctStatus = v15CounterTradesEnabled ?
                      "ENABLED (" + IntegerToString(CountV15ActiveCounterTrades()) + "/" + IntegerToString(MaxCounterTrades) + ")" :
                      "Standby";
    CreateLabel("Signal_CT", "Counter Trades: " + ctStatus, x, y + lh * 7,
                v15CounterTradesEnabled ? clrOrange : clrGray);

    // Defense System Status
    if(ShowDefenseStatus)
    {
        CreateLabel("Defense_Header", "=== DEFENSE SYSTEM STATUS ===", x, y + lh * 9, clrOrange, 10);

        string impulseStr = g_impulseState.isActive ? "ACTIVE: " + g_impulseState.triggerCondition : "Inactive";
        color impulseColor = g_impulseState.isActive ? clrRed : clrGreen;
        CreateLabel("Defense_Impulse", "Impulse: " + impulseStr, x, y + lh * 10, impulseColor);

        CreateLabel("Defense_Step", "Grid Step: " + DoubleToString(g_spacingState.currentStep, 0) + " pts",
                    x, y + lh * 11, clrWhite);

        double currentExposure = GetTotalGridExposure();
        color lotCapColor = currentExposure >= g_lotConfig.maxTotalExposure ? clrRed :
                           (currentExposure >= g_lotConfig.maxTotalExposure * 0.8 ? clrOrange : clrGreen);
        CreateLabel("Defense_LotCap", "Lot Exposure: " + DoubleToString(currentExposure, 2) +
                    "/" + DoubleToString(g_lotConfig.maxTotalExposure, 2),
                    x, y + lh * 12, lotCapColor);

        string lockStr = g_expansionLockState.isLocked ? "LOCKED: " + g_expansionLockState.lockReason : "Unlocked";
        color lockColor = g_expansionLockState.isLocked ? clrRed : clrGreen;
        CreateLabel("Defense_Lock", "Expansion: " + lockStr, x, y + lh * 13, lockColor);

        double ddPct = 0;
        if(g_killSwitchState.sessionHighEquity > 0)
            ddPct = (g_killSwitchState.sessionHighEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_killSwitchState.sessionHighEquity * 100;
        double distToKill = (KillSwitchDrawdownPct * 100) - ddPct;
        color killColor = distToKill < 5 ? clrRed : (distToKill < 10 ? clrOrange : clrGreen);
        CreateLabel("Defense_Kill", "Kill Switch: " + DoubleToString(distToKill, 1) + "% to trigger",
                    x, y + lh * 14, killColor);

        CreateLabel("Defense_Stats1", "Stats | Impulse: " + IntegerToString(g_defenseStats.impulseActivations) +
                    " | Recalcs: " + IntegerToString(g_defenseStats.spacingRecalculations),
                    x, y + lh * 15, clrAqua);
        CreateLabel("Defense_Stats2", "Lot Caps: " + IntegerToString(g_defenseStats.lotCapApplications) +
                    " | Locks: " + IntegerToString(g_defenseStats.expansionLockActivations),
                    x, y + lh * 16, clrAqua);
        CreateLabel("Defense_Stats3", "Shedding: " + IntegerToString(g_defenseStats.sheddingExecutions) +
                    " | Kill Triggers: " + IntegerToString(g_defenseStats.killSwitchTriggers),
                    x, y + lh * 17, clrAqua);
    }

    // Kelly Criterion Status
    if(EnableKellyCriterion)
    {
        int kellyStartRow = ShowDefenseStatus ? 19 : 9;

        CreateLabel("Kelly_Header", "=== KELLY CRITERION ===", x, y + lh * kellyStartRow, C'255,215,0', 10);

        string kellyPctStr = "f*: " + DoubleToString(g_kellyState.currentKellyPct * 100, 2) +
                             "% | Frac: " + DoubleToString(g_kellyState.fractionalKellyPct * 100, 2) + "%";
        CreateLabel("Kelly_Pct", kellyPctStr, x, y + lh * (kellyStartRow + 1), clrWhite);

        CreateLabel("Kelly_Lot", "Kelly Lot: " + DoubleToString(g_kellyState.kellyLotSize, 2) +
                    " | WinRate: " + DoubleToString(g_kellyState.currentWinRate * 100, 1) + "%",
                    x, y + lh * (kellyStartRow + 2), clrWhite);

        CreateLabel("Kelly_WL", "W/L: " + IntegerToString(g_kellyState.totalWins) + "/" +
                    IntegerToString(g_kellyState.totalLosses) +
                    " | R: " + DoubleToString(g_kellyState.currentPayoffRatio, 2),
                    x, y + lh * (kellyStartRow + 3), clrAqua);

        // Adaptive basket target
        color basketClr = EnableAdaptiveBasket ? clrLime : clrGray;
        CreateLabel("Kelly_Basket", "Basket Target: $" + DoubleToString(g_kellyState.currentBasketTarget, 2),
                    x, y + lh * (kellyStartRow + 4), basketClr);

        // DD Throttle
        color ddClr = clrGreen;
        if(g_kellyState.ddThrottleLevel == "LEVEL1") ddClr = clrYellow;
        else if(g_kellyState.ddThrottleLevel == "LEVEL2") ddClr = clrOrange;
        else if(g_kellyState.ddThrottleLevel == "LEVEL3") ddClr = clrRed;
        CreateLabel("Kelly_DDThrottle", "DD Throttle: " + g_kellyState.ddThrottleLevel +
                    " (" + DoubleToString(g_kellyState.ddThrottleMultiplier, 2) + "x)",
                    x, y + lh * (kellyStartRow + 5), ddClr);
    }
}

void CreateLabel(string name, string text, int x, int y, color clr, int fontSize = 9)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
    }

    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}


//+------------------------------------------------------------------+
//| TELEGRAM FUNCTIONS                                                 |
//+------------------------------------------------------------------+

bool SendTelegramMessage(string message)
{
    if(!UseTelegram || TelegramToken == "" || TelegramChatID == "")
        return false;

    string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage";

    string encodedMessage = "";
    uchar msgArray[];
    StringToCharArray(message, msgArray, 0, WHOLE_ARRAY, CP_UTF8);

    int len = ArraySize(msgArray);
    if(len > 0) len--;

    for(int i = 0; i < len; i++)
    {
        uchar ch = msgArray[i];
        if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') ||
           ch == '-' || ch == '_' || ch == '.' || ch == '~')
            encodedMessage += CharToString(ch);
        else
            encodedMessage += StringFormat("%%%02X", ch);
    }

    string postData = "chat_id=" + TelegramChatID + "&text=" + encodedMessage + "&parse_mode=HTML";

    char data[];
    char result[];
    string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
    string resultHeaders;

    int dataLen = StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8);
    if(dataLen > 0) ArrayResize(data, dataLen - 1);

    int res = WebRequest("POST", url, headers, 5000, data, result, resultHeaders);
    return (res == 200);
}

void SendEAStartedNotification()
{
    if(!UseTelegram) return;

    string message = "🎯 <b>V15 STANDALONE GRID DEFENSE EA STARTED v15.10</b> 🎯\n\n";
    message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
    message += "⚡ <b>Mode:</b> V15 Breakout/Trend Engine - Always Active\n\n";
    message += "⚙️ <b>Grid Settings:</b>\n";
    message += "   Step: " + IntegerToString(GridStepPoints) + " pts | Max Levels: " + IntegerToString(MaxGridLevels) + "\n";
    message += "   Target: $" + DoubleToString(BasketProfitUSD, 0) + " | Max Loss: $" + DoubleToString(BasketMaxLossUSD, 0) + "\n\n";
    message += "🛡️ <b>Defense Layers:</b>\n";
    message += "   Impulse: " + (EnableImpulseDetection ? "✅" : "❌") + "\n";
    message += "   Spacing: " + (EnableDynamicSpacing ? "✅" : "❌") + "\n";
    message += "   Lot Scaling: " + (EnableLotScaling ? "✅" : "❌") + "\n";
    message += "   Expansion Lock: " + (EnableExpansionLock ? "✅" : "❌") + "\n";
    message += "   Partial Shedding: " + (EnablePartialShedding ? "✅" : "❌") + "\n";
    message += "   Kill Switch: " + (EnableKillSwitch ? "✅" : "❌") +
               " (" + DoubleToString(KillSwitchDrawdownPct * 100, 0) + "%)\n\n";
    if(EnableKellyCriterion)
    {
        message += "📐 <b>Kelly Criterion:</b>\n";
        message += "   f*: " + DoubleToString(g_kellyState.currentKellyPct * 100, 2) +
                   "% | Frac: " + DoubleToString(g_kellyState.fractionalKellyPct * 100, 2) + "%\n";
        message += "   Lot: " + DoubleToString(g_kellyState.kellyLotSize, 2) +
                   " | Basket: $" + DoubleToString(g_kellyState.currentBasketTarget, 2) + "\n";
        message += "   DD Protection: " + (EnableProgressiveDD ? "✅" : "❌") + "\n\n";
    }
    message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

    SendTelegramMessage(message);
}

void SendV15TradeNotification(string tradeType, int level, double lot, double price, bool isBreakout = false)
{
    if(!UseTelegram) return;

    string emoji = (tradeType == "BUY") ? "🟢" : "🔴";
    string typeStr = isBreakout ? "V15 BREAKOUT TRADE" : "V15 GRID POSITION";

    string message = emoji + " <b>" + typeStr + "</b> " + emoji + "\n\n";
    message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
    message += "📈 <b>Type:</b> " + tradeType + "\n";
    message += "📍 <b>Level:</b> " + IntegerToString(level) + "\n";
    message += "💰 <b>Lot:</b> " + DoubleToString(lot, 2) + "\n";
    message += "📍 <b>Price:</b> " + DoubleToString(price, _Digits) + "\n";
    message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

    SendTelegramMessage(message);
}

void SendV15CloseNotification(string reason, double profit)
{
    if(!UseTelegram) return;

    string emoji = (profit >= 0) ? "💰" : "📉";

    string message = emoji + " <b>V15 POSITIONS CLOSED</b> " + emoji + "\n\n";
    message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
    message += "📝 <b>Reason:</b> " + reason + "\n";
    message += "💵 <b>P/L:</b> $" + DoubleToString(profit, 2) + "\n\n";
    message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

    SendTelegramMessage(message);
}

void SendImpulseNotification(bool activated, string trigger)
{
    if(!UseTelegram) return;

    string emoji = activated ? "⚡" : "✅";
    string status = activated ? "ACTIVATED" : "DEACTIVATED";

    string message = emoji + " <b>IMPULSE MODE " + status + "</b> " + emoji + "\n\n";
    message += "📊 <b>Symbol:</b> " + _Symbol + "\n";

    if(activated)
    {
        message += "🔥 <b>Trigger:</b> " + trigger + "\n";
        message += "🛡️ Grid expansion BLOCKED\n";
    }
    else
    {
        message += "✅ Normal conditions restored\n";
    }

    message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    SendTelegramMessage(message);
}

void SendExpansionLockNotification(bool locked, string reason, int levels, double rangePoints)
{
    if(!UseTelegram) return;

    string emoji = locked ? "🔒" : "🔓";
    string message = emoji + " <b>EXPANSION LOCK " + (locked ? "ACTIVATED" : "DEACTIVATED") + "</b>\n\n";
    message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
    message += "🔐 <b>Reason:</b> " + reason + "\n";
    message += "📈 <b>Levels:</b> " + IntegerToString(levels) + "\n";
    message += "📏 <b>Range:</b> " + DoubleToString(rangePoints, 0) + " pts\n";
    message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    SendTelegramMessage(message);
}

void SendKillSwitchArmedNotification(double currentDrawdown, double triggerThreshold)
{
    if(!UseTelegram) return;

    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdownAmount = g_killSwitchState.sessionHighEquity - currentEquity;

    string message = "⚠️ <b>KILL SWITCH ARMED</b> ⚠️\n\n";
    message += "📊 <b>Symbol:</b> " + _Symbol + "\n";
    message += "💰 <b>Session High:</b> $" + DoubleToString(g_killSwitchState.sessionHighEquity, 2) + "\n";
    message += "💸 <b>Current Equity:</b> $" + DoubleToString(currentEquity, 2) + "\n";
    message += "📉 <b>Drawdown:</b> " + DoubleToString(currentDrawdown * 100, 2) + "% ($" + DoubleToString(drawdownAmount, 2) + ")\n";
    message += "🎯 <b>Trigger:</b> " + DoubleToString(triggerThreshold * 100, 2) + "%\n";
    message += "⏰ " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    SendTelegramMessage(message);
}

//+------------------------------------------------------------------+
//| RANGE DETECTOR FUNCTIONS                                         |
//+------------------------------------------------------------------+

void UpdateRangeDetector()
{
    if(g_rd_atrHandle == INVALID_HANDLE || g_rd_maHandle == INVALID_HANDLE) return;

    datetime currentBarTime = iTime(_Symbol, RangeDetectorTF, 0);

    // If new bar, process the closed bar [1]
    if(currentBarTime != g_rd_lastProcessedBarTime)
    {
        if(g_rd_lastProcessedBarTime == 0)
        {
            // First time: process 1000 bars history
            ProcessRangeDetectorHistory(1000);
        }
        else
        {
            // Process the closed bar 1
            ProcessRangeDetectorBar(1);
        }
        g_rd_lastProcessedBarTime = currentBarTime;
    }

    // Every tick: update the color of the active box based on current close [0]
    double currentClose = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(StringLen(g_rd_curBoxName) > 0 && ObjectFind(0, g_rd_curBoxName) >= 0)
    {
        double boxTop = ObjectGetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 0);
        double boxBottom = ObjectGetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 1);

        if(currentClose > boxTop)
        {
            SetObjectColor(g_rd_curBoxName, InpUpColor);
            if(ObjectFind(0, g_rd_curLineName) >= 0) ObjectSetInteger(0, g_rd_curLineName, OBJPROP_COLOR, InpUpColor);
        }
        else if(currentClose < boxBottom)
        {
            SetObjectColor(g_rd_curBoxName, InpDnColor);
            if(ObjectFind(0, g_rd_curLineName) >= 0) ObjectSetInteger(0, g_rd_curLineName, OBJPROP_COLOR, InpDnColor);
        }
        // Update the right side of the box to the current time [0]
        ObjectSetInteger(0, g_rd_curBoxName, OBJPROP_TIME, 1, currentBarTime);
        if(ObjectFind(0, g_rd_curLineName) >= 0) ObjectSetInteger(0, g_rd_curLineName, OBJPROP_TIME, 1, currentBarTime);
    }
}

void ProcessRangeDetectorHistory(int historyBars)
{
    double atrArr[], maArr[], closes[];
    datetime times[];

    if(CopyBuffer(g_rd_atrHandle, 0, 1, historyBars, atrArr) <= 0) return;
    if(CopyBuffer(g_rd_maHandle, 0, 1, historyBars, maArr) <= 0) return;
    if(CopyClose(_Symbol, RangeDetectorTF, 1, historyBars + InpMinRangeLen, closes) <= 0) return;
    if(CopyTime(_Symbol, RangeDetectorTF, 1, historyBars + InpMinRangeLen, times) <= 0) return;

    ArraySetAsSeries(atrArr, true);
    ArraySetAsSeries(maArr, true);
    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(times, true);

    // Iterate oldest to newest
    for(int i = historyBars - 1; i >= 0; i--)
    {
        double atr = atrArr[i] * InpRangeWidth;
        double ma = maArr[i];
        
        int count = 0;
        for(int j = 0; j < InpMinRangeLen; j++)
        {
            if(MathAbs(closes[i + j] - ma) > atr) count++;
        }

        ProcessRangeState(count, atr, ma, times[i], times[i + InpMinRangeLen - 1], closes[i]);
    }
}

void ProcessRangeDetectorBar(int barIndex)
{
    double atrArr[1], maArr[1], closes[];
    datetime times[];

    if(CopyBuffer(g_rd_atrHandle, 0, barIndex, 1, atrArr) <= 0) return;
    if(CopyBuffer(g_rd_maHandle, 0, barIndex, 1, maArr) <= 0) return;
    if(CopyClose(_Symbol, RangeDetectorTF, barIndex, InpMinRangeLen + 1, closes) <= 0) return;
    if(CopyTime(_Symbol, RangeDetectorTF, barIndex, InpMinRangeLen + 1, times) <= 0) return;

    ArraySetAsSeries(closes, true);
    ArraySetAsSeries(times, true);

    double atr = atrArr[0] * InpRangeWidth;
    double ma = maArr[0];
    
    int count = 0;
    for(int j = 0; j < InpMinRangeLen; j++)
    {
        if(MathAbs(closes[j] - ma) > atr) count++;
    }

    ProcessRangeState(count, atr, ma, times[0], times[InpMinRangeLen - 1], closes[0]);
}

void ProcessRangeState(int count, double atr, double ma, datetime timeCurrent, datetime timeStart, double closeCurrent)
{
    if(count == 0 && g_rd_prevCount != 0)
    {
        datetime rangeStartTime = timeStart;
        datetime rangeEndTime = timeCurrent;

        bool overlap = false;
        if(StringLen(g_rd_curBoxName) > 0 && ObjectFind(0, g_rd_curBoxName) >= 0)
        {
            datetime prevRight = (datetime)ObjectGetInteger(0, g_rd_curBoxName, OBJPROP_TIME, 1);
            if(rangeStartTime <= prevRight) overlap = true;
        }

        if(overlap)
        {
            double prevTop = ObjectGetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 0);
            double prevBottom = ObjectGetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 1);
            g_rd_rangeMax = MathMax(ma + atr, prevTop);
            g_rd_rangeMin = MathMin(ma - atr, prevBottom);

            ObjectSetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 0, g_rd_rangeMax);
            ObjectSetInteger(0, g_rd_curBoxName, OBJPROP_TIME, 1, rangeEndTime);
            ObjectSetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 1, g_rd_rangeMin);
            SetObjectColor(g_rd_curBoxName, InpUnbrokenColor);

            if(StringLen(g_rd_curLineName) > 0 && ObjectFind(0, g_rd_curLineName) >= 0)
            {
                double avg = (g_rd_rangeMax + g_rd_rangeMin) / 2.0;
                ObjectSetDouble(0, g_rd_curLineName, OBJPROP_PRICE, 0, avg);
                ObjectSetDouble(0, g_rd_curLineName, OBJPROP_PRICE, 1, avg);
                ObjectSetInteger(0, g_rd_curLineName, OBJPROP_TIME, 1, rangeEndTime);
                ObjectSetInteger(0, g_rd_curLineName, OBJPROP_COLOR, InpUnbrokenColor);
            }
        }
        else
        {
            g_rd_rangeMax = ma + atr;
            g_rd_rangeMin = ma - atr;

            g_rd_boxCount++;
            g_rd_curBoxName = g_rd_objPrefix + "Box_" + IntegerToString(g_rd_boxCount);
            g_rd_curLineName = g_rd_objPrefix + "Mid_" + IntegerToString(g_rd_boxCount);

            CreateRangeBox(g_rd_curBoxName, rangeStartTime, g_rd_rangeMax, rangeEndTime, g_rd_rangeMin, InpUnbrokenColor);
            CreateMidLine(g_rd_curLineName, rangeStartTime, rangeEndTime, (g_rd_rangeMax + g_rd_rangeMin) / 2.0, InpUnbrokenColor);
            g_rd_os = 0;
        }
    }
    else if(count == 0)
    {
        if(StringLen(g_rd_curBoxName) > 0 && ObjectFind(0, g_rd_curBoxName) >= 0)
        {
            ObjectSetInteger(0, g_rd_curBoxName, OBJPROP_TIME, 1, timeCurrent);
            ObjectSetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 1, g_rd_rangeMin);
        }
        if(StringLen(g_rd_curLineName) > 0 && ObjectFind(0, g_rd_curLineName) >= 0)
            ObjectSetInteger(0, g_rd_curLineName, OBJPROP_TIME, 1, timeCurrent);
    }

    if(StringLen(g_rd_curBoxName) > 0 && ObjectFind(0, g_rd_curBoxName) >= 0)
    {
        double boxTop = ObjectGetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 0);
        double boxBottom = ObjectGetDouble(0, g_rd_curBoxName, OBJPROP_PRICE, 1);

        if(closeCurrent > boxTop)
        {
            SetObjectColor(g_rd_curBoxName, InpUpColor);
            if(StringLen(g_rd_curLineName) > 0 && ObjectFind(0, g_rd_curLineName) >= 0)
                ObjectSetInteger(0, g_rd_curLineName, OBJPROP_COLOR, InpUpColor);
            g_rd_os = 1;
        }
        else if(closeCurrent < boxBottom)
        {
            SetObjectColor(g_rd_curBoxName, InpDnColor);
            if(StringLen(g_rd_curLineName) > 0 && ObjectFind(0, g_rd_curLineName) >= 0)
                ObjectSetInteger(0, g_rd_curLineName, OBJPROP_COLOR, InpDnColor);
            g_rd_os = -1;
        }
    }

    g_rd_prevCount = count;
}

void CreateRangeBox(string name, datetime t1, double price1, datetime t2, double price2, color clr)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

    ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price1, t2, price2);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreateMidLine(string name, datetime t1, datetime t2, double price, color clr)
{
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

    ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void SetObjectColor(string name, color clr)
{
    if(ObjectFind(0, name) < 0) return;
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| LUX SESSIONS FUNCTIONS                                           |
//+------------------------------------------------------------------+
void UpdateLuxSessions()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(currentBarTime != g_lux_lastProcessedBarTime)
    {
        if(g_lux_lastProcessedBarTime == 0)
        {
            // First time: process 500 bars history
            ProcessLuxSessionsHistory(500);
        }
        else
        {
            // Process the closed bar 1
            ProcessLuxSessionsBar(1);
        }
        g_lux_lastProcessedBarTime = currentBarTime;
    }

    // Process current live bar statelessly
    UpdateLuxSessionVisuals_Live();
}

void ProcessLuxSessionsHistory(int bars)
{
    double c[], h[], l[];
    long v[];
    datetime t[];
    
    if(CopyClose(_Symbol, PERIOD_CURRENT, 1, bars, c) <= 0) return;
    if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, bars, h) <= 0) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, 1, bars, l) <= 0) return;
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, bars, v) <= 0) return;
    if(CopyTime(_Symbol, PERIOD_CURRENT, 1, bars, t) <= 0) return;
    
    for(int i = 0; i < bars; i++)
    {
        // Process Daily Divider History
        if(LuxShowDayDiv && i > 0)
        {
            MqlDateTime dtCurrent, dtPrev;
            TimeToStruct(t[i], dtCurrent);
            TimeToStruct(t[i-1], dtPrev);
            if(dtCurrent.day_of_year != dtPrev.day_of_year)
            {
                string divName = "LuxSes_EADayDiv_" + TimeToString(t[i]);
                if(ObjectFind(0, divName) < 0)
                {
                    ObjectCreate(0, divName, OBJ_VLINE, 0, t[i], 0);
                    ObjectSetInteger(0, divName, OBJPROP_COLOR, clrGray);
                    ObjectSetInteger(0, divName, OBJPROP_STYLE, STYLE_DASH);
                    ObjectSetInteger(0, divName, OBJPROP_SELECTABLE, false);
                    ObjectSetInteger(0, divName, OBJPROP_HIDDEN, true);
                    
                    string lblName = "LuxSes_EADayLbg_" + TimeToString(t[i]);
                    ObjectCreate(0, lblName, OBJ_TEXT, 0, t[i], h[i]);
                    ObjectSetString(0, lblName, OBJPROP_TEXT, "New Day");
                    ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrGray);
                    ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, true);
                }
            }
        }
        
        ProcessLuxSession_History(c[i], h[i], l[i], (double)v[i], t[i], g_luxStateA, LuxShowSesA, LuxTxtSesA, LuxTimeSesA, LuxColorSesA, LuxRangeA, LuxTrendlineA, LuxMeanA, "LuxSes_EA_A_");
        ProcessLuxSession_History(c[i], h[i], l[i], (double)v[i], t[i], g_luxStateB, LuxShowSesB, LuxTxtSesB, LuxTimeSesB, LuxColorSesB, LuxRangeB, LuxTrendlineB, LuxMeanB, "LuxSes_EA_B_");
        ProcessLuxSession_History(c[i], h[i], l[i], (double)v[i], t[i], g_luxStateC, LuxShowSesC, LuxTxtSesC, LuxTimeSesC, LuxColorSesC, LuxRangeC, LuxTrendlineC, LuxMeanC, "LuxSes_EA_C_");
        ProcessLuxSession_History(c[i], h[i], l[i], (double)v[i], t[i], g_luxStateD, LuxShowSesD, LuxTxtSesD, LuxTimeSesD, LuxColorSesD, LuxRangeD, LuxTrendlineD, LuxMeanD, "LuxSes_EA_D_");
    }
}

void ProcessLuxSessionsBar(int barIndex)
{
    double c[1], h[1], l[1];
    long v[1];
    datetime t[1];
    
    if(CopyClose(_Symbol, PERIOD_CURRENT, barIndex, 1, c) <= 0) return;
    if(CopyHigh(_Symbol, PERIOD_CURRENT, barIndex, 1, h) <= 0) return;
    if(CopyLow(_Symbol, PERIOD_CURRENT, barIndex, 1, l) <= 0) return;
    if(CopyTickVolume(_Symbol, PERIOD_CURRENT, barIndex, 1, v) <= 0) return;
    if(CopyTime(_Symbol, PERIOD_CURRENT, barIndex, 1, t) <= 0) return;
    
    if(LuxShowDayDiv)
    {
        MqlDateTime dtCurrent, dtPrev;
        TimeToStruct(t[0], dtCurrent);
        TimeToStruct(iTime(_Symbol, PERIOD_CURRENT, barIndex+1), dtPrev);
        if(dtCurrent.day_of_year != dtPrev.day_of_year)
        {
            string divName = "LuxSes_EADayDiv_" + TimeToString(t[0]);
            if(ObjectFind(0, divName) < 0)
            {
                ObjectCreate(0, divName, OBJ_VLINE, 0, t[0], 0);
                ObjectSetInteger(0, divName, OBJPROP_COLOR, clrGray);
                ObjectSetInteger(0, divName, OBJPROP_STYLE, STYLE_DASH);
                ObjectSetInteger(0, divName, OBJPROP_SELECTABLE, false);
                ObjectSetInteger(0, divName, OBJPROP_HIDDEN, true);
                
                string lblName = "LuxSes_EADayLbg_" + TimeToString(t[0]);
                ObjectCreate(0, lblName, OBJ_TEXT, 0, t[0], h[0]);
                ObjectSetString(0, lblName, OBJPROP_TEXT, "New Day");
                ObjectSetInteger(0, lblName, OBJPROP_COLOR, clrGray);
                ObjectSetInteger(0, lblName, OBJPROP_HIDDEN, true);
            }
        }
    }
    
    ProcessLuxSession_History(c[0], h[0], l[0], (double)v[0], t[0], g_luxStateA, LuxShowSesA, LuxTxtSesA, LuxTimeSesA, LuxColorSesA, LuxRangeA, LuxTrendlineA, LuxMeanA, "LuxSes_EA_A_");
    ProcessLuxSession_History(c[0], h[0], l[0], (double)v[0], t[0], g_luxStateB, LuxShowSesB, LuxTxtSesB, LuxTimeSesB, LuxColorSesB, LuxRangeB, LuxTrendlineB, LuxMeanB, "LuxSes_EA_B_");
    ProcessLuxSession_History(c[0], h[0], l[0], (double)v[0], t[0], g_luxStateC, LuxShowSesC, LuxTxtSesC, LuxTimeSesC, LuxColorSesC, LuxRangeC, LuxTrendlineC, LuxMeanC, "LuxSes_EA_C_");
    ProcessLuxSession_History(c[0], h[0], l[0], (double)v[0], t[0], g_luxStateD, LuxShowSesD, LuxTxtSesD, LuxTimeSesD, LuxColorSesD, LuxRangeD, LuxTrendlineD, LuxMeanD, "LuxSes_EA_D_");
    
    UpdateLuxDashboard();
}

void UpdateLuxSessionVisuals_Live()
{
    double c = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double h = iHigh(_Symbol, PERIOD_CURRENT, 0);
    double l = iLow(_Symbol, PERIOD_CURRENT, 0);
    double v = (double)iVolume(_Symbol, PERIOD_CURRENT, 0);
    datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
    
    ProcessLuxSession_Live(c, h, l, v, t, g_luxStateA, LuxShowSesA, LuxTxtSesA, LuxTimeSesA, LuxColorSesA, LuxRangeA, LuxTrendlineA, LuxMeanA);
    ProcessLuxSession_Live(c, h, l, v, t, g_luxStateB, LuxShowSesB, LuxTxtSesB, LuxTimeSesB, LuxColorSesB, LuxRangeB, LuxTrendlineB, LuxMeanB);
    ProcessLuxSession_Live(c, h, l, v, t, g_luxStateC, LuxShowSesC, LuxTxtSesC, LuxTimeSesC, LuxColorSesC, LuxRangeC, LuxTrendlineC, LuxMeanC);
    ProcessLuxSession_Live(c, h, l, v, t, g_luxStateD, LuxShowSesD, LuxTxtSesD, LuxTimeSesD, LuxColorSesD, LuxRangeD, LuxTrendlineD, LuxMeanD);
    
    UpdateLuxDashboard();
}

bool IsLuxTimeInSession(datetime time, string sessionStr)
{
    string parts[];
    if(StringSplit(sessionStr, '-', parts) != 2) return false;
    if(StringLen(parts[0]) < 4 || StringLen(parts[1]) < 4) return false;
    
    int startHour = (int)StringToInteger(StringSubstr(parts[0], 0, 2));
    int startMin  = (int)StringToInteger(StringSubstr(parts[0], 2, 2));
    int endHour   = (int)StringToInteger(StringSubstr(parts[1], 0, 2));
    int endMin    = (int)StringToInteger(StringSubstr(parts[1], 2, 2));
    
    int startTotal = startHour * 60 + startMin;
    int endTotal   = endHour * 60 + endMin;
    
    MqlDateTime dt;
    TimeToStruct(time, dt);
    
    int barTotal = dt.hour * 60 + dt.min;
    
    if(startTotal <= endTotal)
        return (barTotal >= startTotal && barTotal < endTotal);
    else
        return (barTotal >= startTotal || barTotal < endTotal);
}

void ResetLuxTrackingSession(LuxSessionState &state, string prefix)
{
    state.isActive = false;
    state.barCount = 0;
    state.startBar = 0;
    state.startTime = 0;
    state.maxVal = 0;
    state.minVal = 0;
    state.sumClose = 0;
    state.sumWtClose = 0;
    state.sumVolume = 0;
    state.sumCloseSquare = 0;
    state.sumWmaClose = 0;
    state.stdev = 0;
    state.r2 = 0;
    state.boxName = prefix + "Bx_" + IntegerToString(state.boxCount);
    state.lblName = prefix + "Lb_" + IntegerToString(state.boxCount);
    state.tlName  = prefix + "Tl_" + IntegerToString(state.boxCount);
    state.meanName= prefix + "Mn_" + IntegerToString(state.boxCount);
}

void DrawLuxBox(string name, datetime t1, double p1, datetime t2, double p2, color clr, bool showOutline)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
        long fillColor = ColorToARGB(clr, (uchar)(255 - (LuxBgTransp * 2.55)));
        ObjectSetInteger(0, name, OBJPROP_COLOR, showOutline ? clr : clrNONE);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr); 
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    else
    {
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    }
}

void DrawLuxTextLabel(string name, datetime t1, datetime t2, double p1, string txt, color clr)
{
    if(ObjectFind(0, name) < 0)
    {
        datetime midT = t1 + (t2 - t1)/2;
        ObjectCreate(0, name, OBJ_TEXT, 0, midT, p1);
        ObjectSetString(0, name, OBJPROP_TEXT, txt);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    else
    {
        datetime midT = t1 + (t2 - t1)/2;
        ObjectSetInteger(0, name, OBJPROP_TIME, 0, midT);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
    }
}

void DrawLuxLine(string name, datetime t1, double p1, datetime t2, double p2, color clr)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    else
    {
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
    }
}

void ProcessLuxSession_History(double close, double high, double low, double volume, datetime time,
                               LuxSessionState &state, bool isGlobalShow, string txt, string timeStr, color clr,
                               bool showRange, bool showTL, bool showMean, string prefix)
{
    if(!isGlobalShow) return;

    bool inSessionNow = IsLuxTimeInSession(time, timeStr);
    
    if(inSessionNow && !state.isActive)
    {
        state.boxCount++;
        ResetLuxTrackingSession(state, prefix);
        state.isActive = true;
        state.startTime = time;
        state.maxVal = high;
        state.minVal = low;
    }
    
    if(inSessionNow)
    {
        state.barCount++;
        state.lastTime = time;
        state.maxVal = MathMax(state.maxVal, high);
        state.minVal = MathMin(state.minVal, low);
        
        state.sumClose += close;
        state.sumVolume += volume;
        state.sumWtClose += close * volume;
        state.sumCloseSquare += close * close;
        state.sumWmaClose += close * state.barCount;
        
        double sma = state.sumClose / state.barCount;
        
        if(showRange)
        {
            DrawLuxBox(state.boxName, state.startTime, state.maxVal, state.lastTime, state.minVal, clr, LuxShowOutline);
            if(LuxShowTxt) DrawLuxTextLabel(state.lblName, state.startTime, state.lastTime, state.maxVal, txt, clr);
        }
        
        if(showMean) DrawLuxLine(state.meanName, state.startTime, sma, state.lastTime, sma, clr);
        
        if(showTL || LuxAdvDash)
        {
            double wma = state.sumWmaClose / (state.barCount * (state.barCount + 1) / 2.0);
            double cov = (wma - sma) * (state.barCount + 1) / 2.0;
            state.stdev = MathSqrt(MathMax(0, state.sumCloseSquare / state.barCount - sma * sma));
            
            if(state.barCount > 1 && state.stdev > 0)
                state.r2 = cov / (state.stdev * (MathSqrt(state.barCount*state.barCount - 1) / (2 * MathSqrt(3))));
            else
                state.r2 = 0;
                
            if(showTL && state.barCount > 1)
            {
                double y1 = 4 * sma - 3 * wma;
                double y2 = 3 * wma - 2 * sma;
                DrawLuxLine(state.tlName, state.startTime, y1, state.lastTime, y2, clr);
            }
        }
    }
    else
    {
        state.isActive = false;
        state.stdev = 0;
        state.r2 = 0;
        state.sumVolume = 0;
    }
}

void ProcessLuxSession_Live(double close, double high, double low, double volume, datetime time,
                            LuxSessionState &state, bool isGlobalShow, string txt, string timeStr, color clr,
                            bool showRange, bool showTL, bool showMean)
{
    if(!isGlobalShow) return;
    if(!IsLuxTimeInSession(time, timeStr) || !state.isActive) return;
    
    double tempMax = MathMax(state.maxVal, high);
    double tempMin = MathMin(state.minVal, low);
    
    if(showRange && StringLen(state.boxName) > 0)
    {
        ObjectSetDouble(0, state.boxName, OBJPROP_PRICE, 0, tempMax);
        ObjectSetDouble(0, state.boxName, OBJPROP_PRICE, 1, tempMin);
        ObjectSetInteger(0, state.boxName, OBJPROP_TIME, 1, time);
        if(LuxShowTxt && ObjectFind(0, state.lblName) >= 0)
        {
            datetime midT = state.startTime + (time - state.startTime)/2;
            ObjectSetInteger(0, state.lblName, OBJPROP_TIME, 0, midT);
            ObjectSetDouble(0, state.lblName, OBJPROP_PRICE, 0, tempMax);
        }
    }
    
    double tempSumClose = state.sumClose + close;
    int tempBarCount = state.barCount + 1;
    double sma = tempSumClose / tempBarCount;
    
    if(showMean && StringLen(state.meanName) > 0)
        ObjectSetInteger(0, state.meanName, OBJPROP_TIME, 1, time);
        
    if((showTL || LuxAdvDash) && tempBarCount > 1)
    {
        double tempSumWma = state.sumWmaClose + (close * tempBarCount);
        double wma = tempSumWma / (tempBarCount * (tempBarCount + 1) / 2.0);
        if(showTL && StringLen(state.tlName) > 0)
        {
            double y2 = 3 * wma - 2 * sma;
            ObjectSetInteger(0, state.tlName, OBJPROP_TIME, 1, time);
            ObjectSetDouble(0, state.tlName, OBJPROP_PRICE, 1, y2);
        }
    }
}

void DrawLuxDashLabel(string name, string text, int x, int y, ENUM_BASE_CORNER corner, color clr, bool bold=false)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
}

void UpdateLuxDashboard()
{
    if(!LuxShowDash) return;

    int ox = 20, oy = 30;
    int colWidth = 60;
    int rowHeight = 20;
    
    ENUM_BASE_CORNER corner = CORNER_RIGHT_UPPER;
    if(LuxDashLoc == LUX_BOTTOM_RIGHT) corner = CORNER_RIGHT_LOWER;
    if(LuxDashLoc == LUX_BOTTOM_LEFT)  corner = CORNER_LEFT_LOWER;
    
    string bgName = "LuxDash_EA_BG";
    if(ObjectFind(0, bgName) < 0)
    {
        ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'30,34,45');
        ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'55,58,70');
        ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }
    ObjectSetInteger(0, bgName, OBJPROP_CORNER, corner);
    
    int totalCols = LuxAdvDash ? 6 : 2;
    int totalRows = 5; 
    ObjectSetInteger(0, bgName, OBJPROP_XSIZE, totalCols * colWidth + 20);
    ObjectSetInteger(0, bgName, OBJPROP_YSIZE, totalRows * rowHeight + 20);
    ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, ox);
    ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, oy);

    DrawLuxDashLabel("LuxDash_EA_Title", "LuxAlgo Sessions", ox + 10, oy + 5, corner, clrWhite, true);
    
    string names[4] = {LuxTxtSesA, LuxTxtSesB, LuxTxtSesC, LuxTxtSesD};
    color  clrs[4]  = {LuxColorSesA, LuxColorSesB, LuxColorSesC, LuxColorSesD};
    bool   st[4]    = {g_luxStateA.isActive, g_luxStateB.isActive, g_luxStateC.isActive, g_luxStateD.isActive};
    double vols[4]  = {g_luxStateA.sumVolume, g_luxStateB.sumVolume, g_luxStateC.sumVolume, g_luxStateD.sumVolume};
    double r2s[4]   = {g_luxStateA.r2, g_luxStateB.r2, g_luxStateC.r2, g_luxStateD.r2};
    double stds[4]  = {g_luxStateA.stdev, g_luxStateB.stdev, g_luxStateC.stdev, g_luxStateD.stdev};
    
    if(LuxAdvDash)
    {
        DrawLuxDashLabel("LuxDash_EA_H_Ses", "Session", ox + 10, oy + 5 + rowHeight, corner, clrWhite);
        DrawLuxDashLabel("LuxDash_EA_H_St", "Status", ox + 10 + colWidth, oy + 5 + rowHeight, corner, clrWhite);
        DrawLuxDashLabel("LuxDash_EA_H_Tr", "Trend", ox + 10 + colWidth*2, oy + 5 + rowHeight, corner, clrWhite);
        DrawLuxDashLabel("LuxDash_EA_H_Vo", "Volume", ox + 10 + colWidth*3, oy + 5 + rowHeight, corner, clrWhite);
        DrawLuxDashLabel("LuxDash_EA_H_Sd", "Stdev", ox + 10 + colWidth*4, oy + 5 + rowHeight, corner, clrWhite);
    }

    for(int i=0; i<4; i++)
    {
        int y = oy + 5 + rowHeight * (i + (LuxAdvDash?2:1));
        
        DrawLuxDashLabel("LuxDash_EA_N_"+IntegerToString(i), names[i], ox + 10, y, corner, clrs[i]);
        
        string statStr = st[i] ? "Active" : "Inactive";
        color  statClr = st[i] ? C'8,153,129' : C'242,54,69';
        DrawLuxDashLabel("LuxDash_EA_S_"+IntegerToString(i), statStr, ox + 10 + colWidth, y, corner, statClr);
        
        if(LuxAdvDash)
        {
            DrawLuxDashLabel("LuxDash_EA_T_"+IntegerToString(i), DoubleToString(r2s[i], 2), ox + 10 + colWidth*2, y, corner, r2s[i] >= 0 ? C'8,153,129' : C'242,54,69');
            DrawLuxDashLabel("LuxDash_EA_V_"+IntegerToString(i), DoubleToString(vols[i]/1000.0, 1)+"k", ox + 10 + colWidth*3, y, corner, clrWhite);
            DrawLuxDashLabel("LuxDash_EA_D_"+IntegerToString(i), DoubleToString(stds[i], 4), ox + 10 + colWidth*4, y, corner, clrWhite);
        }
    }
}
