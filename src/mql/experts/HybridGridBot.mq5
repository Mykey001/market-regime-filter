//+------------------------------------------------------------------+
//|                                               HybridGridBot.mq5  |
//|                        High-Frequency Scalping Grid Bot          |
//|                     Hybrid Grid + Trend Filter + Async Execution |
//|                     + ML Regime Filter Integration               |
//+------------------------------------------------------------------+
#property copyright "HybridGridBot"
#property link      ""
#property version   "1.01"
#property strict

// Include Regime Filter Library (NO conflicts with EA functions)
#include "RegimeFilterLib.mqh"

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

// QQE Indicator Settings (Primary Trend Filter)
input int      QQE_RSI_Period = 14;            // RSI period for QQE calculation
input int      QQE_Smoothing = 5;              // Wilders smoothing factor
input double   QQE_ATR_Multiplier = 4.236;     // ATR multiplier for trailing bands
input double   QQE_MidlineThreshold = 5.0;     // Threshold around 50 mid-line (no trade zone)
input bool     QQE_EnableEarlyExit = true;     // Enable early exit on QQE reversal
input double   QQE_ReversalThreshold = 10.0;   // QQE movement toward 50 to trigger warning (%)

// TMA Slope Settings (Secondary/Optional Confirmation)
input bool     UseTMAConfirmation = false;     // Use TMA as secondary filter
input int      TMA_Period = 20;                // TMA calculation period
input double   TMA_SlopeThreshold = 0.0001;    // Minimum slope for signal

// System Settings
input int      MagicNumber = 123456;           // Unique identifier
input bool     ShowBasketOnChart = true;       // Display basket profit on chart

// Regime Filter Settings (ML-based market regime filter)
input bool     EnableRegimeFilter = true;      // Enable ML regime filter
input string   RegimeFilterHost = "127.0.0.1"; // Python GUI host
input int      RegimeFilterPort = 9090;        // Python GUI port

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
    int    histogram;         // Histogram color: 1=Blue(Buy), -1=Red(Sell)
    bool   crossedBandUp;     // QQE crossed above upper band
    bool   crossedBandDown;   // QQE crossed below lower band
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+

GridState g_gridState;              // Main grid state
QQEState  g_qqeState;               // QQE indicator state
double    g_peakEquity;             // Peak equity for drawdown calculation
bool      g_emergencyStop;          // Emergency stop flag
bool      g_pendingRetry;           // Pending order retry flag
MqlTradeRequest g_retryRequest;     // Request to retry

// Default parameter values for validation
const double DEFAULT_GRID_STEP = 100;
const double DEFAULT_LOT_SIZE = 0.01;
const double DEFAULT_MARTINGALE = 1.5;
const int    DEFAULT_MAX_LEVELS = 10;
const double DEFAULT_TARGET_PROFIT = 5.0;
const double DEFAULT_MAX_DRAWDOWN = 20.0;
const int    DEFAULT_TMA_PERIOD = 20;
const double DEFAULT_TMA_THRESHOLD = 0.0001;

// QQE Default parameter values
const int    DEFAULT_QQE_RSI_PERIOD = 14;
const int    DEFAULT_QQE_SMOOTHING = 5;
const double DEFAULT_QQE_ATR_MULT = 4.236;
const double DEFAULT_QQE_MIDLINE_THRESHOLD = 5.0;
const double DEFAULT_QQE_REVERSAL_THRESHOLD = 10.0;

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

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validate and set parameters
    ValidateParameters();
    
    // Initialize Regime Filter (ML-based)
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
    
    // Initialize grid state
    InitializeGrid();
    
    // Initialize QQE state
    InitializeQQE();
    
    // Initialize equity tracking
    g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_emergencyStop = false;
    g_pendingRetry = false;
    
    // Rebuild state from existing positions (for restart recovery)
    RebuildStateFromPositions();
    
    // Log configuration
    LogConfiguration();
    
    Print("HybridGridBot initialized successfully with QQE trend filter + ML Regime Filter");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Cleanup Regime Filter
    if(EnableRegimeFilter)
    {
        DeinitRegimeFilter();
        Print("ML Regime Filter: Shut down");
    }
    
    // Clean up chart objects
    ObjectDelete(0, "BasketProfit");
    ObjectDelete(0, "DrawdownLabel");
    ObjectDelete(0, "GridLevelLabel");
    ObjectDelete(0, "TargetLabel");
    ObjectDelete(0, "SlopeLabel");
    ObjectDelete(0, "QQELabel");
    ObjectDelete(0, "QQEHistogram");
    ObjectDelete(0, "RegimeLabel");
    ObjectDelete(0, "RegimeStatusLabel");
    
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
    // 1. Check emergency stop flag first
    if(g_emergencyStop)
    {
        // Bot is stopped - do nothing until manual reset
        return;
    }
    
    // 2. Update ML Regime Filter (sends new bars to Python)
    if(EnableRegimeFilter)
    {
        UpdateRegimeFilter();
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
    
    // 5. Update peak equity tracking
    UpdatePeakEquity();
    
    // 6. Check drawdown limit
    if(CheckDrawdownLimit())
    {
        return; // Emergency stop triggered
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
//| Log Trade Action                                                  |
//+------------------------------------------------------------------+
void LogTrade(string action, const GridPosition& pos)
{
    Print(TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), 
          " | ", action,
          " | ", _Symbol,
          " | ", EnumToString(pos.type),
          " | Lots: ", pos.lotSize,
          " | Price: ", pos.openPrice,
          " | Level: ", pos.gridLevel,
          " | Ticket: ", pos.ticket);
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
        Print("TARGET REACHED! Basket Profit: $", DoubleToString(basketProfit, 2), 
              " >= Target: $", DoubleToString(g_targetProfitUSD, 2));
        
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
//| Check Drawdown Limit and Trigger Emergency Stop if Exceeded       |
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
            Print("WARNING: Drawdown approaching limit! Current: ", 
                  DoubleToString(drawdown, 2), "% / Max: ", 
                  DoubleToString(g_maxDrawdownPercent, 2), "%");
            lastWarning = TimeCurrent();
        }
    }
    
    // Emergency stop if limit exceeded
    if(drawdown >= g_maxDrawdownPercent)
    {
        Print("EMERGENCY STOP! Drawdown exceeded limit: ", 
              DoubleToString(drawdown, 2), "% >= ", 
              DoubleToString(g_maxDrawdownPercent, 2), "%");
        
        g_emergencyStop = true;
        CloseAllPositionsAsync();
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
    
    // Check if price has moved against us by grid step
    double currentPrice = GetCurrentPrice(g_gridState.direction);
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
    // Check ML Regime Filter FIRST (most important filter)
    if(EnableRegimeFilter && IsRegimeFilterConnected())
    {
        // Determine direction from QQE
        int qqeSignal = GetQQESignal();
        if(qqeSignal == 0) return; // QQE neutral
        
        string action = (qqeSignal == 1) ? "buy" : "sell";
        
        if(!IsTradeAllowed(action))
        {
            // Log why trade blocked by regime
            int regime = GetCurrentRegime();
            double confidence = GetRegimeConfidence();
            Print("ML Regime Filter BLOCKED ", action, " grid. Regime: ", regime, 
                  ", Confidence: ", DoubleToString(confidence, 1), "%");
            return;
        }
        
        Print("ML Regime Filter ALLOWED ", action, " grid. Regime: ", GetCurrentRegime(), 
              ", Confidence: ", DoubleToString(GetRegimeConfidence(), 1), "%");
    }
    
    // Determine direction based on QQE signal
    int qqeSignal = GetQQESignal();
    
    // Check if we have a valid signal
    if(qqeSignal == 0)
        return; // No signal - stay out (QQE in neutral zone)
    
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
    if(!CanOpenNewGrid(direction))
        return;
    
    // Calculate lot size for first level
    double lots = CalculateLotSize(1);
    
    // Open first position
    if(OpenPositionAsync(orderType, lots, 1))
    {
        g_gridState.direction = direction;
        g_gridState.lastGridPrice = GetCurrentPrice(direction);
        Print("Starting new ", EnumToString(direction), " grid based on QQE signal + ML Regime Filter");
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
        Print("Adding grid level ", newLevel, " with ", lots, " lots");
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
    
    // ML Regime Filter Label (NEW)
    if(EnableRegimeFilter)
    {
        int regime = GetCurrentRegime();
        double confidence = GetRegimeConfidence();
        bool connected = IsRegimeFilterConnected();
        bool allowed = IsTradeAllowedByRegime();
        
        string regimeText = "ML Regime: ";
        if(!connected)
        {
            regimeText += "DISCONNECTED";
            CreateOrUpdateLabel("RegimeLabel", regimeText, 10, 150, clrOrange);
        }
        else if(regime < 0)
        {
            regimeText += "WARMING UP...";
            CreateOrUpdateLabel("RegimeLabel", regimeText, 10, 150, clrYellow);
        }
        else
        {
            regimeText += "R" + IntegerToString(regime) + " (" + DoubleToString(confidence, 1) + "%)";
            color regimeColor = allowed ? clrLime : clrRed;
            CreateOrUpdateLabel("RegimeLabel", regimeText, 10, 150, regimeColor);
            
            // Trade status
            string statusText = "Status: " + (allowed ? "ALLOWED ✓" : "BLOCKED ✗");
            CreateOrUpdateLabel("RegimeStatusLabel", statusText, 10, 170, regimeColor);
        }
    }
    
    // TMA Slope Label (only if TMA confirmation is enabled)
    int yOffset = EnableRegimeFilter ? 190 : 150;
    if(g_useTMAConfirmation)
    {
        double slope = GetTMASlope();
        string slopeText = "TMA Slope: " + DoubleToString(slope, 6);
        color slopeColor = slope > g_tmaSlopeThreshold ? clrLime : 
                           (slope < -g_tmaSlopeThreshold ? clrRed : clrGray);
        CreateOrUpdateLabel("SlopeLabel", slopeText, 10, yOffset, slopeColor);
    }
    else
    {
        ObjectDelete(0, "SlopeLabel");
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
    Print("--- ML Regime Filter (Primary Filter) ---");
    Print("Regime Filter: ", EnableRegimeFilter ? "ENABLED" : "DISABLED");
    if(EnableRegimeFilter)
    {
        Print("Python GUI: ", RegimeFilterHost, ":", RegimeFilterPort);
        Print("Connection: ", IsRegimeFilterConnected() ? "CONNECTED" : "WAITING...");
    }
    Print("--- QQE Settings (Secondary Filter) ---");
    Print("QQE RSI Period: ", g_qqeRSIPeriod);
    Print("QQE Smoothing: ", g_qqeSmoothing);
    Print("QQE ATR Multiplier: ", g_qqeATRMultiplier);
    Print("QQE Midline Threshold: ", g_qqeMidlineThreshold);
    Print("QQE Early Exit: ", g_qqeEnableEarlyExit ? "Enabled" : "Disabled");
    Print("QQE Reversal Threshold: ", g_qqeReversalThreshold, "%");
    Print("--- TMA Settings (Tertiary Filter) ---");
    Print("Use TMA Confirmation: ", g_useTMAConfirmation ? "Yes" : "No");
    Print("TMA Period: ", g_tmaPeriod);
    Print("TMA Threshold: ", g_tmaSlopeThreshold);
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
    g_qqeState.histogram = 0;
    g_qqeState.crossedBandUp = false;
    g_qqeState.crossedBandDown = false;
}

//+------------------------------------------------------------------+
//| Calculate QQE Indicator                                           |
//+------------------------------------------------------------------+
void CalculateQQE()
{
    // Step 1: Calculate RSI
    double rsi = CalculateRSI(g_qqeRSIPeriod, 0);
    
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
    if(g_qqeState.qqeLine > 50 + g_qqeMidlineThreshold)
        g_qqeState.signal = 1;   // Bullish
    else if(g_qqeState.qqeLine < 50 - g_qqeMidlineThreshold)
        g_qqeState.signal = -1;  // Bearish
    else
        g_qqeState.signal = 0;   // Neutral (no trade zone)
    
    // Step 7: Update histogram color
    g_qqeState.histogram = (g_qqeState.qqeLine > g_qqeState.qqeLinePrev) ? 1 : -1;
    
    // Step 8: Check for band crossings (momentum burst signals)
    g_qqeState.crossedBandUp = (g_qqeState.qqeLinePrev <= g_qqeState.trailingBandUp && 
                                g_qqeState.qqeLine > g_qqeState.trailingBandUp);
    g_qqeState.crossedBandDown = (g_qqeState.qqeLinePrev >= g_qqeState.trailingBandDown && 
                                  g_qqeState.qqeLine < g_qqeState.trailingBandDown);
}

//+------------------------------------------------------------------+
//| Get QQE Signal for Trade Direction                                |
//+------------------------------------------------------------------+
int GetQQESignal()
{
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
            Print("QQE EMERGENCY EXIT: QQE crossed below 50 while Buy grid active");
            return true;
        }
    }
    else
    {
        // Sell grid - exit if QQE crosses above 50
        if(g_qqeState.qqeLinePrev <= 50 && g_qqeState.qqeLine > 50)
        {
            Print("QQE EMERGENCY EXIT: QQE crossed above 50 while Sell grid active");
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
    
    // Validate volume first
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    Print("[VALIDATE] Lot size check: Requested=", lots, 
          ", Min=", minLot, ", Max=", maxLot, ", Step=", lotStep);
    
    if(lots < minLot || lots > maxLot)
    {
        Print("[ERROR] Invalid lot size: ", lots, " (Min: ", minLot, ", Max: ", maxLot, ")");
        return false;
    }
    
    // Check if trading is allowed
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Print("[ERROR] Trading is not allowed in terminal");
        return false;
    }
    
    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("[ERROR] Automated trading is disabled in EA settings");
        return false;
    }
    
    // Check symbol trading permissions
    long tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
    {
        Print("[ERROR] Trading is disabled for ", _Symbol);
        return false;
    }
    
    Print("[VALIDATE] Trade mode: ", tradeMode, " (4=Full, 3=CloseOnly, 0=Disabled)");
    
    // Check what fill policies are supported by broker
    long fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    Print("[VALIDATE] Broker supports filling modes: ", fillingMode,
          " (1=FOK, 2=IOC, 4=RETURN/BOC)");
    
    // Fill request structure
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = orderType;
    request.deviation = 50;  // Increased deviation for volatile markets
    request.magic = MagicNumber;
    request.comment = "HybridGrid_L" + IntegerToString(gridLevel);
    
    // Determine fill policy based on broker support
    if((fillingMode & SYMBOL_FILLING_FOK) != 0)
        request.type_filling = ORDER_FILLING_FOK;  // Fill or Kill
    else if((fillingMode & SYMBOL_FILLING_IOC) != 0)
        request.type_filling = ORDER_FILLING_IOC;  // Immediate or Cancel
    else
        request.type_filling = ORDER_FILLING_RETURN;  // Return/Book or Cancel
    
    Print("[VALIDATE] Using fill policy: ", EnumToString(request.type_filling));
    
    // Set price based on order type
    if(orderType == ORDER_TYPE_BUY)
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    else
        request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Validate price
    if(request.price <= 0)
    {
        Print("[ERROR] Invalid price: ", request.price);
        return false;
    }
    
    Print("[SEND] Attempting order: Type=", EnumToString(orderType), 
          ", Volume=", lots, ", Price=", request.price, 
          ", Deviation=", request.deviation,
          ", Filling=", EnumToString(request.type_filling));
    
    // Send order asynchronously
    bool sent = OrderSendAsync(request, result);
    
    if(sent)
    {
        Print("✓ Order sent async - Request ID: ", result.request_id, 
              ", Type: ", EnumToString(orderType), 
              ", Lots: ", lots, 
              ", Level: ", gridLevel);
    }
    else
    {
        int error = GetLastError();
        Print("✗ OrderSendAsync failed - Error: ", error, " - ", ErrorDescription(error));
        Print("  Request details: Action=", request.action, 
              ", Symbol=", request.symbol,
              ", Volume=", request.volume,
              ", Type=", EnumToString(request.type),
              ", Price=", request.price,
              ", Deviation=", request.deviation,
              ", Filling=", EnumToString(request.type_filling));
        
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
