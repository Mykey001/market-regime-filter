//+------------------------------------------------------------------+
//|                                                       RSI_EA.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "RSI Trading EA"
#property version   "1.70"
#property strict

// REGIME FILTER: Include the regime filter library (no conflicts!)
#include <Trade\Trade.mqh>
#include "RegimeFilterLib.mqh"
// Input parameters
input group "=== RSI Settings ==="
input int      RSI_Period = 14;                    // RSI Period
input double   RSI_Overbought = 70.0;              // RSI Overbought Level (Sell)
input double   RSI_Oversold = 30.0;                // RSI Oversold Level (Buy)
input ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_M5;   // RSI Timeframe
input bool     TradeOnCandleClose = true;          // Trade on Candle Close (false = on tick)

input group "=== Grid Settings ==="
input bool     UseGrid = true;                     // Enable Grid Trading
input int      MaxPositions = 5;                   // Maximum Grid Positions
input double   GridSpacing = 10.0;                 // Grid Spacing (RSI points)
input double   LotMultiplier = 1.5;                // Lot Multiplier per Grid Level

input group "=== Trade Settings ==="
input bool     UsePercentageRisk = true;           // Use Percentage-based Position Sizing
input double   RiskPercentage = 10.0;              // Risk Percentage per Trade (%)
input double   LotSize = 0.1;                      // Fixed Lot Size (used if Percentage disabled)
input bool     UseDynamicSL = true;                // Use ATR-based Dynamic Stop Loss
input ENUM_TIMEFRAMES SL_Timeframe = PERIOD_M15;   // Stop Loss Timeframe
input double   ATR_SL_Multiplier = 1.5;            // ATR Multiplier for Stop Loss
input int      ATR_SL_Period = 14;                 // ATR Period for Stop Loss
input int      StopLoss = 50;                      // Fixed Stop Loss (points, used if Dynamic SL disabled)
input int      TakeProfit = 100;                   // Take Profit (points, 0 = no TP)
input int      MagicNumber = 123456;               // Magic Number
input string   TradeComment = "RSI_EA";            // Trade Comment

input group "=== Daily Target ==="
input bool     UseDailyTarget = false;             // Enable Daily Profit Target
input bool     UsePercentageTarget = true;         // Use Percentage-based Target
input double   DailyTargetPercent = 10.0;          // Daily Target Profit (% of starting balance)
input double   DailyTargetProfit = 100.0;          // Daily Target Profit (fixed amount, used if % disabled)
input bool     UseDailyLoss = false;               // Enable Daily Loss Limit
input bool     UsePercentageLoss = true;           // Use Percentage-based Loss Limit
input double   DailyLossPercent = 5.0;             // Daily Loss Limit (% of starting balance)
input double   DailyLossLimit = 50.0;              // Daily Loss Limit (fixed amount, used if % disabled)

input group "=== Volatility Filter ==="
input bool     UseVolatilityFilter = true;         // Enable Volatility Filter
input int      ATR_Period = 14;                    // ATR Period
input double   ATR_Multiplier = 2.0;               // ATR Spike Multiplier (higher = less sensitive)
input int      ATR_LookbackBars = 20;              // ATR Average Lookback Bars

input group "=== Drawdown Updates ==="
input bool     UseRSIDrawdownClose = false;        // Enable RSI-based Drawdown Close
input double   RSI_CloseLevel_Buy = 70.0;          // RSI Level to close Buy drawdown
input double   RSI_CloseLevel_Sell = 30.0;         // RSI Level to close Sell drawdown
input bool     AllowEntriesDuringDrawdown = true;  // Allow RSI entries during drawdown

input group "=== Structural Exit (Swing Break) ==="
input bool     UseStructuralExit   = false;        // Exit losing trades on structural break
input ENUM_TIMEFRAMES SE_Timeframe = PERIOD_M15;   // Timeframe to detect swing break
input int      SE_SwingLookback    = 5;            // Bars each side to confirm a swing pivot
input int      SE_ScanBars         = 100;          // How many bars back to scan for the last swing point
input bool     SE_LosingOnly       = true;         // Only exit if the trade is currently at a loss (true recommended)
input bool     SE_BodyClose        = true;         // Require full candle BODY close beyond swing (true=body, false=wick)

input group "=== Loss Recovery ==="
input bool     UseLossRecovery = false;            // Enable Loss Recovery System
input double   MaxRecoveryLot = 5.0;               // Maximum Lot Size for recovery trades

input group "=== Time Filter ==="
input bool     UseTimeFilter = false;              // Enable Daily Start Time Filter
input int      StartHour = 8;                      // Start Hour (0-23)
input int      StartMinute = 0;                    // Start Minute (0-59)

// Regime detection method selector
enum ENUM_REGIME_METHOD
{
   REGIME_EMA,             // EMA — price above/below moving average
   REGIME_MARKET_STRUCTURE // Market Structure — Higher Highs/Lows vs Lower Highs/Lows
};

input group "=== Market Regime Filter ==="
input bool                UseRegimeFilter    = false;         // Enable Market Regime Filter
input ENUM_REGIME_METHOD  Regime_Method      = REGIME_EMA;   // Trend Detection Method
// -- EMA method inputs --
input int                 Regime_MA_Period   = 200;           // [EMA] MA Period
input ENUM_MA_METHOD      Regime_MA_Method   = MODE_SMA;      // [EMA] MA Method
// -- Market Structure method inputs --
input ENUM_TIMEFRAMES     Regime_Timeframe   = PERIOD_H1;     // Timeframe for Trend Detection (both methods)
input int                 MS_SwingLookback   = 5;             // [MS] Bars each side to confirm a swing pivot (3–10)
input int                 MS_ScanBars        = 150;           // [MS] How many bars back to scan for swing points
input int                 MS_MinSwings       = 2;             // [MS] Min confirmed swings needed to declare a trend (2–4)
input bool                TradeOnlyWithTrend = true;          // Only Buy in uptrend, only Sell in downtrend

input group "=== Break Even Settings ==="
input bool     UseBreakEven = false;               // Enable Break Even
input double   BE_ATR_Trigger = 1.0;               // ATR multiples price must move to trigger BE
input double   BE_ATR_Buffer = 0.1;                // ATR buffer above entry for BE SL (0 = exact entry)
input ENUM_TIMEFRAMES BE_ATR_Timeframe = PERIOD_M15; // ATR Timeframe for Break Even

input group "=== Trailing Stop Settings ==="
input bool     UseTrailingStop = false;            // Enable Trailing Stop Loss
input double   TS_ATR_Trigger = 2.0;               // ATR multiples profit needed before trailing starts
input double   TS_ATR_Trail = 1.0;                 // Trail distance behind price (in ATR multiples)
input ENUM_TIMEFRAMES TS_ATR_Timeframe = PERIOD_M15; // ATR Timeframe for Trailing Stop

input group "=== Key Level Zone Filter ==="
input bool     UseKeyLevelFilter  = false;         // Enable Key Level Zone Filter
input bool     KL_UseM5           = true;          // Scan M5 for key levels
input bool     KL_UseM15          = true;          // Scan M15 for key levels
input bool     KL_UseH1           = true;          // Scan H1 for key levels
input int      KL_SwingLookback   = 5;             // Bars left+right to confirm a swing pivot (3-10 typical)
input int      KL_ScanBars        = 200;           // How many bars back to scan per timeframe
input double   KL_ZoneTolerance_ATR = 0.3;         // Zone half-width as ATR multiple (price within = "at level")
input int      KL_MinTouches      = 1;             // Min pivot touches to validate a zone (1 = any pivot qualifies)
input bool     KL_RequireAllTF    = false;         // true=price must be at level on ALL enabled TFs; false=ANY TF

// Global variables
int rsi_handle;
int atr_handle;
int atr_sl_handle;
int atr_be_handle;
int atr_ts_handle;
int atr_kl_handle;
int ma_handle;
double rsi_buffer[];
double atr_buffer[];
double atr_sl_buffer[];
double atr_be_buffer[];
double atr_ts_buffer[];
double atr_kl_buffer[];
double ma_buffer[];
datetime last_bar_time = 0;
datetime se_last_bar_time = 0;   // Structural Exit: tracks last processed candle on SE_Timeframe
double accumulated_loss = 0.0; // Tracks the amount lost to be recovered

// Key Level Zone structure
struct KLZone
{
   double price;    // Zone centre price
   int    touches;  // Number of confirmed pivot touches within clustering tolerance
   bool   is_high;  // true = swing high (resistance), false = swing low (support)
};

// Grid tracking
struct GridLevel
{
   double rsi_level;
   ulong ticket;
   double lot_size;
};

GridLevel buy_grid_levels[];
GridLevel sell_grid_levels[];
int buy_grid_count = 0;
int sell_grid_count = 0;

// Daily tracking
double daily_profit = 0.0;
double daily_start_balance = 0.0;
datetime current_day = 0;
bool daily_target_reached = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // REGIME FILTER: Initialize regime filter first
   // Send more bars to account for warmup period (626 bars needed after NaN drop)
   InitRegimeFilter("127.0.0.1", 9090, true);
   
   // Create RSI indicator handle
   rsi_handle = iRSI(_Symbol, RSI_Timeframe, RSI_Period, PRICE_CLOSE);
   
   if(rsi_handle == INVALID_HANDLE)
   {
      Print("Error creating RSI indicator");
      return(INIT_FAILED);
   }
   
   // Create ATR indicator handle for volatility filter
   if(UseVolatilityFilter)
   {
      atr_handle = iATR(_Symbol, RSI_Timeframe, ATR_Period);
      
      if(atr_handle == INVALID_HANDLE)
      {
         Print("Error creating ATR indicator");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(atr_buffer, true);
   }
   
   // Create ATR indicator handle for dynamic stop loss
   if(UseDynamicSL)
   {
      atr_sl_handle = iATR(_Symbol, SL_Timeframe, ATR_SL_Period);
      
      if(atr_sl_handle == INVALID_HANDLE)
      {
         Print("Error creating ATR SL indicator");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(atr_sl_buffer, true);
   }
   
   // Create MA indicator handle for regime filter (EMA method only)
   if(UseRegimeFilter && Regime_Method == REGIME_EMA)
   {
      ma_handle = iMA(_Symbol, Regime_Timeframe, Regime_MA_Period, 0, Regime_MA_Method, PRICE_CLOSE);
      
      if(ma_handle == INVALID_HANDLE)
      {
         Print("Error creating MA indicator for Regime Filter (EMA method)");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(ma_buffer, true);
   }
   
   // Create ATR handle for Break Even
   if(UseBreakEven)
   {
      atr_be_handle = iATR(_Symbol, BE_ATR_Timeframe, ATR_SL_Period);
      if(atr_be_handle == INVALID_HANDLE)
      {
         Print("Error creating ATR indicator for Break Even");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(atr_be_buffer, true);
   }
   
   // Create ATR handle for Trailing Stop
   if(UseTrailingStop)
   {
      atr_ts_handle = iATR(_Symbol, TS_ATR_Timeframe, ATR_SL_Period);
      if(atr_ts_handle == INVALID_HANDLE)
      {
         Print("Error creating ATR indicator for Trailing Stop");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(atr_ts_buffer, true);
   }
   
   // Create ATR handle for Key Level zone tolerance (M15 timeframe)
   if(UseKeyLevelFilter)
   {
      atr_kl_handle = iATR(_Symbol, PERIOD_M15, ATR_SL_Period);
      if(atr_kl_handle == INVALID_HANDLE)
      {
         Print("Error creating ATR indicator for Key Level Filter");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(atr_kl_buffer, true);
   }
   
   // Set array as series
   ArraySetAsSeries(rsi_buffer, true);
   
   // Initialize grid arrays
   ArrayResize(buy_grid_levels, MaxPositions);
   ArrayResize(sell_grid_levels, MaxPositions);
   
   // Reset grid counters
   buy_grid_count = 0;
   sell_grid_count = 0;
   
   // Initialize daily tracking
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   current_day = StructToTime(dt);
   daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   daily_profit = CalculateDailyProfit();
   daily_target_reached = false;
   
   // Initialize accumulated loss from history if needed (optional, starting fresh here)
   accumulated_loss = 0.0;
   
   Print("RSI EA initialized successfully");
   Print("Trade Mode: ", TradeOnCandleClose ? "Candle Close" : "On Tick");
   Print("Grid Trading: ", UseGrid ? "Enabled" : "Disabled");
   if(UseGrid)
      Print("Max Positions: ", MaxPositions, " | Grid Spacing: ", GridSpacing, " | Lot Multiplier: ", LotMultiplier);
   if(UsePercentageRisk)
      Print("Position Sizing: ", RiskPercentage, "% of account balance");
   else
      Print("Position Sizing: Fixed ", LotSize, " lots");
   if(UseDailyTarget)
   {
      if(UsePercentageTarget)
         Print("Daily Target: ", DailyTargetPercent, "% (", DoubleToString(daily_start_balance * DailyTargetPercent / 100, 2), ") | Current: ", DoubleToString(daily_profit, 2));
      else
         Print("Daily Target: ", DailyTargetProfit, " | Current: ", DoubleToString(daily_profit, 2));
   }
   if(UseDailyLoss)
   {
      if(UsePercentageLoss)
         Print("Daily Loss Limit: ", DailyLossPercent, "% (", DoubleToString(daily_start_balance * DailyLossPercent / 100, 2), ")");
      else
         Print("Daily Loss Limit: ", DailyLossLimit);
   }
   if(UseVolatilityFilter)
      Print("Volatility Filter: Enabled | ATR Period: ", ATR_Period, " | Multiplier: ", ATR_Multiplier);
   if(UseDynamicSL)
      Print("Dynamic SL: Enabled | Timeframe: ", EnumToString(SL_Timeframe), " | ATR Multiplier: ", ATR_SL_Multiplier);
   if(UseLossRecovery)
      Print("Loss Recovery: Enabled | Max Recovery Lot: ", MaxRecoveryLot);
   if(UseTimeFilter)
      Print("Time Filter: Enabled | Start Time: ", StartHour, ":", StartMinute);
   if(UseRegimeFilter)
   {
      if(Regime_Method == REGIME_EMA)
         Print("Regime Filter: EMA method | Period: ", Regime_MA_Period, " | TF: ", EnumToString(Regime_Timeframe));
      else
         Print("Regime Filter: Market Structure method | SwingLB: ", MS_SwingLookback,
               " | ScanBars: ", MS_ScanBars, " | MinSwings: ", MS_MinSwings,
               " | TF: ", EnumToString(Regime_Timeframe));
   }
   if(UseBreakEven)
      Print("Break Even: Enabled | Trigger: ", BE_ATR_Trigger, " ATR | Buffer: ", BE_ATR_Buffer, " ATR | TF: ", EnumToString(BE_ATR_Timeframe));
   if(UseTrailingStop)
      Print("Trailing Stop: Enabled | Trigger: ", TS_ATR_Trigger, " ATR | Trail: ", TS_ATR_Trail, " ATR | TF: ", EnumToString(TS_ATR_Timeframe));
   if(UseStructuralExit)
      Print("Structural Exit: Enabled | TF: ", EnumToString(SE_Timeframe),
            " | SwingLB: ", SE_SwingLookback, " | ScanBars: ", SE_ScanBars,
            " | LosingOnly: ", SE_LosingOnly ? "Yes" : "No",
            " | Trigger: ", SE_BodyClose ? "Body Close" : "Wick Break");
   if(UseKeyLevelFilter)
   {
      string kl_tfs = "";
      if(KL_UseM5)  kl_tfs += "M5 ";
      if(KL_UseM15) kl_tfs += "M15 ";
      if(KL_UseH1)  kl_tfs += "H1";
      Print("Key Level Filter: Enabled | TFs: ", kl_tfs,
            " | SwingLB: ", KL_SwingLookback, " | ScanBars: ", KL_ScanBars,
            " | Tolerance: ", KL_ZoneTolerance_ATR, " ATR | MinTouches: ", KL_MinTouches,
            " | Mode: ", KL_RequireAllTF ? "ALL TFs" : "ANY TF");
   }
   
   // REGIME FILTER: Print connection status
   Print("==================================================");
   Print("ML REGIME FILTER: ", IsRegimeFilterConnected() ? "CONNECTED" : "DISCONNECTED");
   if(IsRegimeFilterConnected())
   {
      int current_regime = GetCurrentRegime();
      if(current_regime == -1)
      {
         Print("Regime Status: WARMING UP (sending 1300 historical bars...)");
         Print("First prediction will be available after warmup completes (~10-15 seconds)");
         Print("Watch for regime updates in the chart comment");
      }
      else
      {
         Print("Current Regime: ", current_regime, " | Confidence: ", DoubleToString(GetRegimeConfidence() * 100, 1), "%");
      }
      Print("Regime filter is active - trades will be filtered by ML model");
   }
   else
   {
      Print("WARNING: Regime filter NOT connected - trades will NOT be filtered!");
      Print("Make sure the Python GUI is running with 'Start Server' enabled");
   }
   Print("==================================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // REGIME FILTER: Cleanup regime filter
   DeinitRegimeFilter();
   
   // Release indicator handles
   if(rsi_handle != INVALID_HANDLE)
      IndicatorRelease(rsi_handle);
      
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
      
   if(atr_sl_handle != INVALID_HANDLE)
      IndicatorRelease(atr_sl_handle);
      
   if(atr_be_handle != INVALID_HANDLE)
      IndicatorRelease(atr_be_handle);
      
   if(atr_ts_handle != INVALID_HANDLE)
      IndicatorRelease(atr_ts_handle);
      
   if(atr_kl_handle != INVALID_HANDLE)
      IndicatorRelease(atr_kl_handle);
      
   if(ma_handle != INVALID_HANDLE)
      IndicatorRelease(ma_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // REGIME FILTER: Update regime filter on each tick
   UpdateRegimeFilter();
   
   // Check for new day and reset daily profit
   CheckNewDay();
   
   // Update accumulated loss from history
   if(UseLossRecovery)
      UpdateAccumulatedLoss();
   
   // Calculate actual target/loss values
   double actual_target = UsePercentageTarget ? (daily_start_balance * DailyTargetPercent / 100.0) : DailyTargetProfit;
   double actual_loss_limit = UsePercentageLoss ? (daily_start_balance * DailyLossPercent / 100.0) : DailyLossLimit;
   
   // Check if daily target or loss limit reached
   if(UseDailyTarget && daily_target_reached)
   {
      Comment("Daily target reached: ", DoubleToString(daily_profit, 2), " / ", DoubleToString(actual_target, 2), " - Trading stopped for today");
      return;
   }
   
   if(UseDailyLoss && daily_profit <= -actual_loss_limit)
   {
      Comment("Daily loss limit reached: ", DoubleToString(daily_profit, 2), " / -", DoubleToString(actual_loss_limit, 2), " - Trading stopped for today");
      return;
   }
   
   // Update comment with current daily profit and recovery status
   string comment_text = "";
   if(UseDailyTarget || UseDailyLoss)
   {
      comment_text = "Daily P/L: " + DoubleToString(daily_profit, 2);
      if(UseDailyTarget)
         comment_text += " | Target: " + DoubleToString(actual_target, 2);
      if(UseDailyLoss)
         comment_text += " | Limit: -" + DoubleToString(actual_loss_limit, 2);
   }
   
   if(UseLossRecovery && accumulated_loss > 0)
   {
      if(comment_text != "") comment_text += "\n";
      comment_text += "Recovery Mode: Loss to recover = " + DoubleToString(accumulated_loss, 2);
   }
   
   // Check Time Filter
   bool is_trading_time = true;
   if(UseTimeFilter)
   {
      MqlDateTime now;
      TimeCurrent(now);
      if(now.hour < StartHour || (now.hour == StartHour && now.min < StartMinute))
      {
         is_trading_time = false;
         if(comment_text != "") comment_text += "\n";
         comment_text += "Waiting for Start Time: " + IntegerToString(StartHour) + ":" + IntegerToString(StartMinute);
      }
   }
   
   // Check Market Regime Filter
   bool can_buy = true;
   bool can_sell = true;
   if(UseRegimeFilter)
   {
      if(Regime_Method == REGIME_EMA)
      {
         // --- EMA method (original) ---
         if(CopyBuffer(ma_handle, 0, 0, 1, ma_buffer) < 1)
         {
            Print("Error copying MA buffer");
         }
         else
         {
            double current_ma    = ma_buffer[0];
            double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            
            if(TradeOnlyWithTrend)
            {
               if(current_price > current_ma)
               {
                  can_sell = false;
                  if(comment_text != "") comment_text += "\n";
                  comment_text += "Regime [EMA]: Bullish (Only Buy)";
               }
               else
               {
                  can_buy = false;
                  if(comment_text != "") comment_text += "\n";
                  comment_text += "Regime [EMA]: Bearish (Only Sell)";
               }
            }
         }
      }
      else // REGIME_MARKET_STRUCTURE
      {
         // --- Market Structure method (HH/HL = uptrend, LH/LL = downtrend) ---
         int ms_trend = GetMarketStructureTrend();
         
         if(TradeOnlyWithTrend)
         {
            if(ms_trend == 1)          // Confirmed uptrend (HH + HL sequence)
            {
               can_sell = false;
               if(comment_text != "") comment_text += "\n";
               comment_text += "Regime [MS]: Uptrend — HH+HL (Only Buy)";
            }
            else if(ms_trend == -1)    // Confirmed downtrend (LH + LL sequence)
            {
               can_buy = false;
               if(comment_text != "") comment_text += "\n";
               comment_text += "Regime [MS]: Downtrend — LH+LL (Only Sell)";
            }
            else                       // Neutral / insufficient structure
            {
               can_buy  = false;
               can_sell = false;
               if(comment_text != "") comment_text += "\n";
               comment_text += "Regime [MS]: Neutral — No clear structure";
            }
         }
      }
   }
   
   // REGIME FILTER: Add regime filter status to comment
   if(comment_text != "") comment_text += "\n";
   
   int current_regime = GetCurrentRegime();
   if(current_regime == -1)
   {
      // Still warming up
      comment_text += StringFormat("ML Regime: WARMING UP | Status: %s", 
                                   IsRegimeFilterConnected() ? "Connected" : "Disconnected");
   }
   else
   {
      // Regime available
      comment_text += StringFormat("ML Regime: %d | Confidence: %.1f%% | Status: %s", 
                                   current_regime, 
                                   GetRegimeConfidence() * 100,
                                   IsRegimeFilterConnected() ? "Connected" : "Disconnected");
   }
   
   if(comment_text != "") Comment(comment_text);
   
   // Check if we should trade on candle close
   if(TradeOnCandleClose)
   {
      datetime current_bar_time = iTime(_Symbol, RSI_Timeframe, 0);
      
      // If bar hasn't changed, skip
      if(current_bar_time == last_bar_time)
         return;
         
      last_bar_time = current_bar_time;
   }
   
   // Copy RSI values
   if(CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer) < 3)
   {
      Print("Error copying RSI buffer");
      return;
   }
   
   double current_rsi = rsi_buffer[0];
   
   // Feature 1: RSI-based Drawdown Close
   if(UseRSIDrawdownClose)
   {
      if(HasOpenBuyPositions() && current_rsi >= RSI_CloseLevel_Buy)
      {
         Print("RSI Drawdown Close: RSI reached ", current_rsi, ". Closing all Buy positions.");
         ClosePositionsByType(POSITION_TYPE_BUY);
      }
      if(HasOpenSellPositions() && current_rsi <= RSI_CloseLevel_Sell)
      {
         Print("RSI Drawdown Close: RSI reached ", current_rsi, ". Closing all Sell positions.");
         ClosePositionsByType(POSITION_TYPE_SELL);
      }
   }
   
   // Feature 1b: Structural Exit — close losing trades when price body closes beyond a swing point
   if(UseStructuralExit)
      CheckStructuralExit();
   
   // Feature 2: Break Even and Trailing Stop management (runs on every tick regardless of candle close)
   if(UseBreakEven || UseTrailingStop)
      ManagePositions();
   
   // Check volatility filter
   if(UseVolatilityFilter && IsVolatilitySpike())
   {
      if(comment_text != "")
         Comment(comment_text + "\nVolatility Spike Detected - Trading Paused");
      else
         Comment("Volatility Spike Detected - Trading Paused");
      return;
   }
   
   // Update grid tracking - remove closed positions
   UpdateGridTracking();
   
   // Skip new entries if not trading time
   if(!is_trading_time) return;
   
   // Feature 3: Key Level Zone Filter — evaluate once before all entry logic
   bool at_key_level_buy  = true;
   bool at_key_level_sell = true;
   if(UseKeyLevelFilter)
   {
      double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      at_key_level_buy  = IsAtKeyLevel(ask_price);
      at_key_level_sell = IsAtKeyLevel(bid_price);
   }
   
   if(!UseGrid)
   {
      // Original logic - single position only
      if(PositionSelect(_Symbol))
         return;
      
      double lot = CalculateFinalLotSize();
         
      if(current_rsi <= RSI_Oversold && can_buy)
      {
         if(at_key_level_buy)
            OpenTrade(ORDER_TYPE_BUY, current_rsi, lot);
         else
            Print("Key Level Filter: BUY blocked — no key zone nearby (RSI=", DoubleToString(current_rsi,2), ")");
      }
      else if(current_rsi >= RSI_Overbought && can_sell)
      {
         if(at_key_level_sell)
            OpenTrade(ORDER_TYPE_SELL, current_rsi, lot);
         else
            Print("Key Level Filter: SELL blocked — no key zone nearby (RSI=", DoubleToString(current_rsi,2), ")");
      }
   }
   else
   {
      // Grid logic
      // Check for BUY grid opportunities (RSI below oversold)
      if(current_rsi <= RSI_Oversold && can_buy)
      {
         if(buy_grid_count == 0 || (AllowEntriesDuringDrawdown && buy_grid_count < MaxPositions))
         {
            if(buy_grid_count == 0)
            {
               // First grid entry: must pass key level filter
               if(at_key_level_buy)
               {
                  double lot = CalculateFinalLotSize();
                  ulong ticket = OpenTrade(ORDER_TYPE_BUY, current_rsi, lot);
                  if(ticket > 0)
                  {
                     buy_grid_levels[buy_grid_count].rsi_level = current_rsi;
                     buy_grid_levels[buy_grid_count].ticket = ticket;
                     buy_grid_levels[buy_grid_count].lot_size = lot;
                     buy_grid_count++;
                  }
               }
               else
                  Print("Key Level Filter: Grid BUY #1 blocked — no key zone nearby (RSI=", DoubleToString(current_rsi,2), ")");
            }
            else
            {
               // Subsequent grid entries: RSI spacing check only (already confirmed zone on entry 1)
               double last_grid_rsi = buy_grid_levels[buy_grid_count - 1].rsi_level;
               if(current_rsi <= last_grid_rsi - GridSpacing)
               {
                  double lot = buy_grid_levels[buy_grid_count - 1].lot_size * LotMultiplier;
                  lot = NormalizeDouble(lot, 2);
                  ulong ticket = OpenTrade(ORDER_TYPE_BUY, current_rsi, lot);
                  if(ticket > 0)
                  {
                     buy_grid_levels[buy_grid_count].rsi_level = current_rsi;
                     buy_grid_levels[buy_grid_count].ticket = ticket;
                     buy_grid_levels[buy_grid_count].lot_size = lot;
                     buy_grid_count++;
                  }
               }
            }
         }
      }
      
      // Check for SELL grid opportunities (RSI above overbought)
      if(current_rsi >= RSI_Overbought && can_sell)
      {
         if(sell_grid_count == 0 || (AllowEntriesDuringDrawdown && sell_grid_count < MaxPositions))
         {
            if(sell_grid_count == 0)
            {
               // First grid entry: must pass key level filter
               if(at_key_level_sell)
               {
                  double lot = CalculateFinalLotSize();
                  ulong ticket = OpenTrade(ORDER_TYPE_SELL, current_rsi, lot);
                  if(ticket > 0)
                  {
                     sell_grid_levels[sell_grid_count].rsi_level = current_rsi;
                     sell_grid_levels[sell_grid_count].ticket = ticket;
                     sell_grid_levels[sell_grid_count].lot_size = lot;
                     sell_grid_count++;
                  }
               }
               else
                  Print("Key Level Filter: Grid SELL #1 blocked — no key zone nearby (RSI=", DoubleToString(current_rsi,2), ")");
            }
            else
            {
               // Subsequent grid entries: RSI spacing check only
               double last_grid_rsi = sell_grid_levels[sell_grid_count - 1].rsi_level;
               if(current_rsi >= last_grid_rsi + GridSpacing)
               {
                  double lot = sell_grid_levels[sell_grid_count - 1].lot_size * LotMultiplier;
                  lot = NormalizeDouble(lot, 2);
                  ulong ticket = OpenTrade(ORDER_TYPE_SELL, current_rsi, lot);
                  if(ticket > 0)
                  {
                     sell_grid_levels[sell_grid_count].rsi_level = current_rsi;
                     sell_grid_levels[sell_grid_count].ticket = ticket;
                     sell_grid_levels[sell_grid_count].lot_size = lot;
                     sell_grid_count++;
                  }
               }
            }
         }
      }
      
      // Reset grids when RSI returns to neutral zone
      if(current_rsi > RSI_Oversold + GridSpacing && buy_grid_count > 0)
      {
         if(!HasOpenBuyPositions())
         {
            buy_grid_count = 0;
            Print("Buy grid reset - RSI returned to neutral");
         }
      }
      
      if(current_rsi < RSI_Overbought - GridSpacing && sell_grid_count > 0)
      {
         if(!HasOpenSellPositions())
         {
            sell_grid_count = 0;
            Print("Sell grid reset - RSI returned to neutral");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open Trade Function                                              |
//+------------------------------------------------------------------+
ulong OpenTrade(ENUM_ORDER_TYPE order_type, double rsi_value, double lot)
{
   // REGIME FILTER: Check if trade is allowed by regime filter
   string action = (order_type == ORDER_TYPE_BUY) ? "buy" : "sell";
   if(!IsTradeAllowed(action))
   {
      Print("Trade BLOCKED by Regime Filter: ", action, " | RSI: ", DoubleToString(rsi_value, 2),
            " | Regime: ", GetCurrentRegime(), " | Confidence: ", DoubleToString(GetRegimeConfidence() * 100, 1), "%");
      return 0;
   }
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   double price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Calculate SL
   double sl = 0;
   
   if(UseDynamicSL)
   {
      // Use ATR-based dynamic stop loss
      sl = CalculateDynamicStopLoss(order_type, price);
   }
   else if(StopLoss > 0)
   {
      // Use fixed stop loss
      if(order_type == ORDER_TYPE_BUY)
         sl = NormalizeDouble(price - StopLoss * point, digits);
      else
         sl = NormalizeDouble(price + StopLoss * point, digits);
   }
   
   // Calculate TP
   double tp = 0;
   if(TakeProfit > 0)
   {
      if(order_type == ORDER_TYPE_BUY)
         tp = NormalizeDouble(price + TakeProfit * point, digits);
      else
         tp = NormalizeDouble(price - TakeProfit * point, digits);
   }
   
   // Fill request structure
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = order_type;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = MagicNumber;
   // REGIME FILTER: Add regime info to trade comment
   request.comment = StringFormat("%s | R%d | C%.0f%%", TradeComment, GetCurrentRegime(), GetRegimeConfidence() * 100);
   
   // Send order
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
      {
         Print("Order opened successfully: ", order_type == ORDER_TYPE_BUY ? "BUY" : "SELL", 
               " | Lot: ", DoubleToString(lot, 2),
               " | RSI: ", DoubleToString(rsi_value, 2), 
               " | Price: ", DoubleToString(price, digits),
               " | SL: ", DoubleToString(sl, digits),
               " | TP: ", DoubleToString(tp, digits),
               " | Regime: ", GetCurrentRegime(),
               " | Confidence: ", DoubleToString(GetRegimeConfidence() * 100, 1), "%");
         return result.order;
      }
      else
      {
         Print("Order failed. Error code: ", result.retcode);
         return 0;
      }
   }
   else
   {
      Print("OrderSend error: ", GetLastError());
      return 0;
   }
}

//+------------------------------------------------------------------+
//| Structural Exit — exit losing trades on swing-point body break  |
//|                                                                  |
//| Logic:                                                           |
//|  • Scans SE_Timeframe for the most recent confirmed swing low    |
//|    and swing high (N-bar fractal, same as other swing detection) |
//|  • On each NEW closed candle on SE_Timeframe:                    |
//|    - Losing BUY:  last closed candle body (Close) < swing low    |
//|                   → bearish structure break → close all buys     |
//|    - Losing SELL: last closed candle body (Close) > swing high   |
//|                   → bullish structure break → close all sells    |
//|  • SE_LosingOnly = true  → only fires when trade is in the red   |
//|  • SE_BodyClose  = true  → uses iClose (body); false = iLow/iHigh|
//+------------------------------------------------------------------+
void CheckStructuralExit()
{
   // Only act on a new completed candle on the SE_Timeframe
   datetime current_se_bar = iTime(_Symbol, SE_Timeframe, 0);
   if(current_se_bar == se_last_bar_time)
      return;
   se_last_bar_time = current_se_bar;
   
   // We evaluate bar index 1 (the just-completed candle, fully confirmed)
   int eval_bar = 1;
   
   // ---------------------------------------------------------------
   // Find the most recent confirmed swing low (support)
   // A swing low at bar i requires iLow[i] < iLow[i±k] for k=1..lb
   // We skip bar 0 (current forming) and bar 1 (our evaluation bar).
   // Start from bar (lb+2) so the pivot itself has lb confirmed bars
   // on its right side, none of which is our live eval bar.
   // ---------------------------------------------------------------
   int lb   = SE_SwingLookback;
   int scan = SE_ScanBars;
   
   double last_swing_low  = 0.0;
   double last_swing_high = 0.0;
   
   int bars_available = (int)SeriesInfoInteger(_Symbol, SE_Timeframe, SERIES_BARS_COUNT);
   int max_bar = MathMin(scan + lb + 2, bars_available - 1);
   
   for(int i = lb + 2; i <= max_bar; i++)
   {
      double lo = iLow(_Symbol,  SE_Timeframe, i);
      double hi = iHigh(_Symbol, SE_Timeframe, i);
      
      // Check swing low
      if(last_swing_low == 0.0)
      {
         bool is_sl = true;
         for(int k = 1; k <= lb && is_sl; k++)
         {
            if(iLow(_Symbol, SE_Timeframe, i - k) <= lo) is_sl = false;
            if(iLow(_Symbol, SE_Timeframe, i + k) <= lo) is_sl = false;
         }
         if(is_sl) last_swing_low = lo;
      }
      
      // Check swing high
      if(last_swing_high == 0.0)
      {
         bool is_sh = true;
         for(int k = 1; k <= lb && is_sh; k++)
         {
            if(iHigh(_Symbol, SE_Timeframe, i - k) >= hi) is_sh = false;
            if(iHigh(_Symbol, SE_Timeframe, i + k) >= hi) is_sh = false;
         }
         if(is_sh) last_swing_high = hi;
      }
      
      // Stop once we have both
      if(last_swing_low > 0.0 && last_swing_high > 0.0)
         break;
   }
   
   // Need at least one swing point to act
   if(last_swing_low == 0.0 && last_swing_high == 0.0)
      return;
   
   // Price level of the evaluation candle
   double eval_close = iClose(_Symbol, SE_Timeframe, eval_bar);
   double eval_low   = iLow(_Symbol,   SE_Timeframe, eval_bar);
   double eval_high  = iHigh(_Symbol,  SE_Timeframe, eval_bar);
   
   // The break price we compare against
   double break_price_down = SE_BodyClose ? eval_close : eval_low;   // body or wick for bearish break
   double break_price_up   = SE_BodyClose ? eval_close : eval_high;  // body or wick for bullish break
   
   // ---------------------------------------------------------------
   // Check each open position individually
   // ---------------------------------------------------------------
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double pos_profit           = PositionGetDouble(POSITION_PROFIT);
      double pos_swap             = PositionGetDouble(POSITION_SWAP);
      double total_pnl            = pos_profit + pos_swap;
      double entry_price          = PositionGetDouble(POSITION_PRICE_OPEN);
      
      // Losing-only guard
      if(SE_LosingOnly && total_pnl >= 0.0)
         continue;
      
      if(pos_type == POSITION_TYPE_BUY && last_swing_low > 0.0)
      {
         // Bearish structural break: candle body closed below the most recent swing low
         if(break_price_down < last_swing_low)
         {
            Print("Structural Exit [BUY #", ticket, "]: ",
                  SE_BodyClose ? "Body" : "Wick",
                  " closed at ", DoubleToString(break_price_down, _Digits),
                  " below swing low ", DoubleToString(last_swing_low, _Digits),
                  " | P&L: ", DoubleToString(total_pnl, 2),
                  " | Entry: ", DoubleToString(entry_price, _Digits));
            
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action    = TRADE_ACTION_DEAL;
            req.position  = ticket;
            req.symbol    = _Symbol;
            req.volume    = PositionGetDouble(POSITION_VOLUME);
            req.type      = ORDER_TYPE_SELL;
            req.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            req.deviation = 10;
            req.magic     = MagicNumber;
            req.comment   = "SE: swing low break";
            
            if(!OrderSend(req, res))
               Print("Structural Exit: Failed to close BUY #", ticket, " | Error: ", GetLastError());
            else
            {
               // Clean ticket from grid tracking
               for(int g = 0; g < buy_grid_count; g++)
               {
                  if(buy_grid_levels[g].ticket == ticket)
                  {
                     for(int j = g; j < buy_grid_count - 1; j++)
                        buy_grid_levels[j] = buy_grid_levels[j + 1];
                     buy_grid_count--;
                     break;
                  }
               }
            }
         }
      }
      else if(pos_type == POSITION_TYPE_SELL && last_swing_high > 0.0)
      {
         // Bullish structural break: candle body closed above the most recent swing high
         if(break_price_up > last_swing_high)
         {
            Print("Structural Exit [SELL #", ticket, "]: ",
                  SE_BodyClose ? "Body" : "Wick",
                  " closed at ", DoubleToString(break_price_up, _Digits),
                  " above swing high ", DoubleToString(last_swing_high, _Digits),
                  " | P&L: ", DoubleToString(total_pnl, 2),
                  " | Entry: ", DoubleToString(entry_price, _Digits));
            
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action    = TRADE_ACTION_DEAL;
            req.position  = ticket;
            req.symbol    = _Symbol;
            req.volume    = PositionGetDouble(POSITION_VOLUME);
            req.type      = ORDER_TYPE_BUY;
            req.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            req.deviation = 10;
            req.magic     = MagicNumber;
            req.comment   = "SE: swing high break";
            
            if(!OrderSend(req, res))
               Print("Structural Exit: Failed to close SELL #", ticket, " | Error: ", GetLastError());
            else
            {
               // Clean ticket from grid tracking
               for(int g = 0; g < sell_grid_count; g++)
               {
                  if(sell_grid_levels[g].ticket == ticket)
                  {
                     for(int j = g; j < sell_grid_count - 1; j++)
                        sell_grid_levels[j] = sell_grid_levels[j + 1];
                     sell_grid_count--;
                     break;
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Market Structure Trend Detection                                 |
//| Scans swing highs and lows on Regime_Timeframe and classifies   |
//| Returns: +1 = uptrend (HH+HL), -1 = downtrend (LH+LL), 0 = neutral
//+------------------------------------------------------------------+
int GetMarketStructureTrend()
{
   int lb   = MS_SwingLookback;
   int scan = MS_ScanBars;
   int bars_available = (int)SeriesInfoInteger(_Symbol, Regime_Timeframe, SERIES_BARS_COUNT);
   scan = MathMin(scan + lb * 2, bars_available - 1);
   
   if(scan < lb * 2 + 2)
      return 0;  // Not enough data
   
   // ----------------------------------------------------------------
   // Step 1: Collect all confirmed swing highs and swing lows
   // We only look at bars [lb+1 .. scan-lb] so every pivot has lb
   // confirmed bars on both sides (no repainting).
   // We store them newest-first (bar index = newest = 0).
   // ----------------------------------------------------------------
   double swing_highs[];
   double swing_lows[];
   ArrayResize(swing_highs, scan);
   ArrayResize(swing_lows,  scan);
   int   sh_count = 0;
   int   sl_count = 0;
   
   for(int i = lb + 1; i <= scan - lb; i++)
   {
      double hi = iHigh(_Symbol, Regime_Timeframe, i);
      double lo = iLow(_Symbol,  Regime_Timeframe, i);
      
      // Check swing high: hi must be strictly greater than lb bars on each side
      bool is_sh = true;
      for(int k = 1; k <= lb && is_sh; k++)
      {
         if(iHigh(_Symbol, Regime_Timeframe, i - k) >= hi) is_sh = false;
         if(iHigh(_Symbol, Regime_Timeframe, i + k) >= hi) is_sh = false;
      }
      
      // Check swing low: lo must be strictly less than lb bars on each side
      bool is_sl = true;
      for(int k = 1; k <= lb && is_sl; k++)
      {
         if(iLow(_Symbol, Regime_Timeframe, i - k) <= lo) is_sl = false;
         if(iLow(_Symbol, Regime_Timeframe, i + k) <= lo) is_sl = false;
      }
      
      if(is_sh) { swing_highs[sh_count++] = hi; }
      if(is_sl) { swing_lows[sl_count++]  = lo; }
   }
   
   // Need at least MS_MinSwings swing highs AND swing lows to make a call
   if(sh_count < MS_MinSwings || sl_count < MS_MinSwings)
      return 0;
   
   // ----------------------------------------------------------------
   // Step 2: Score the most recent MS_MinSwings swings
   // swing_highs[0] = most recent swing high (smallest bar index = newest)
   // Uptrend   = each successive swing high is HIGHER  AND each successive swing low is HIGHER
   // Downtrend = each successive swing high is LOWER   AND each successive swing low is LOWER
   // ----------------------------------------------------------------
   int n = MS_MinSwings;
   
   // Count how many consecutive pairs are HH (each newer high > older high)
   int hh_count = 0;
   int lh_count = 0;
   for(int i = 0; i < n - 1; i++)
   {
      // swing_highs[0] is newest, swing_highs[1] is next oldest, etc.
      if(swing_highs[i] > swing_highs[i + 1]) hh_count++;  // newer high is higher → HH
      else                                     lh_count++;  // newer high is lower  → LH
   }
   
   // Count how many consecutive pairs are HL (each newer low > older low)
   int hl_count = 0;
   int ll_count = 0;
   for(int i = 0; i < n - 1; i++)
   {
      if(swing_lows[i] > swing_lows[i + 1]) hl_count++;  // newer low is higher → HL
      else                                   ll_count++;  // newer low is lower  → LL
   }
   
   // ----------------------------------------------------------------
   // Step 3: Classify
   // Uptrend requires a MAJORITY of pairs to be HH and HL
   // Downtrend requires a MAJORITY of pairs to be LH and LL
   // ----------------------------------------------------------------
   int pairs   = n - 1;
   int majority = (pairs / 2) + 1;
   
   bool uptrend   = (hh_count >= majority && hl_count >= majority);
   bool downtrend = (lh_count >= majority && ll_count >= majority);
   
   if(uptrend && !downtrend)
   {
      return 1;   // Confirmed uptrend
   }
   else if(downtrend && !uptrend)
   {
      return -1;  // Confirmed downtrend
   }
   
   return 0;  // Mixed / neutral
}

//+------------------------------------------------------------------+
//| Manage Break Even and Trailing Stop for open positions           |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double atr_be = 0.0;
   if(UseBreakEven)
   {
      if(CopyBuffer(atr_be_handle, 0, 0, 1, atr_be_buffer) < 1) return;
      atr_be = atr_be_buffer[0];
   }
   
   double atr_ts = 0.0;
   if(UseTrailingStop)
   {
      if(CopyBuffer(atr_ts_handle, 0, 0, 1, atr_ts_buffer) < 1) return;
      atr_ts = atr_ts_buffer[0];
   }
   
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      ENUM_POSITION_TYPE pos_type  = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur_sl  = PositionGetDouble(POSITION_SL);
      double cur_tp  = PositionGetDouble(POSITION_TP);
      double new_sl  = cur_sl;
      
      // --- BREAK EVEN ---
      if(UseBreakEven && atr_be > 0.0)
      {
         double trigger = atr_be * BE_ATR_Trigger;
         if(pos_type == POSITION_TYPE_BUY)
         {
            double be_sl = NormalizeDouble(entry + atr_be * BE_ATR_Buffer, digits);
            if((bid - entry) >= trigger && cur_sl < be_sl)
            {
               new_sl = be_sl;
               Print("Break Even BUY #", ticket, " | Entry:", DoubleToString(entry,digits), " New SL:", DoubleToString(new_sl,digits));
            }
         }
         else
         {
            double be_sl = NormalizeDouble(entry - atr_be * BE_ATR_Buffer, digits);
            if((entry - ask) >= trigger && (cur_sl == 0.0 || cur_sl > be_sl))
            {
               new_sl = be_sl;
               Print("Break Even SELL #", ticket, " | Entry:", DoubleToString(entry,digits), " New SL:", DoubleToString(new_sl,digits));
            }
         }
      }
      
      // --- TRAILING STOP ---
      if(UseTrailingStop && atr_ts > 0.0)
      {
         double ts_trigger = atr_ts * TS_ATR_Trigger;
         double ts_trail   = atr_ts * TS_ATR_Trail;
         if(pos_type == POSITION_TYPE_BUY)
         {
            if((bid - entry) >= ts_trigger)
            {
               double desired = NormalizeDouble(bid - ts_trail, digits);
               if(desired > new_sl)
               {
                  new_sl = desired;
                  Print("Trailing Stop BUY #", ticket, " | Bid:", DoubleToString(bid,digits), " New SL:", DoubleToString(new_sl,digits));
               }
            }
         }
         else
         {
            if((entry - ask) >= ts_trigger)
            {
               double desired = NormalizeDouble(ask + ts_trail, digits);
               if(cur_sl == 0.0 || desired < new_sl)
               {
                  new_sl = desired;
                  Print("Trailing Stop SELL #", ticket, " | Ask:", DoubleToString(ask,digits), " New SL:", DoubleToString(new_sl,digits));
               }
            }
         }
      }
      
      // Apply new SL if changed
      if(new_sl != cur_sl && new_sl > 0.0)
      {
         MqlTradeRequest req = {};
         MqlTradeResult  res = {};
         req.action   = TRADE_ACTION_SLTP;
         req.position = ticket;
         req.symbol   = _Symbol;
         req.sl       = new_sl;
         req.tp       = cur_tp;
         req.magic    = MagicNumber;
         if(!OrderSend(req, res))
            Print("ManagePositions: SL modify failed for #", ticket, " Error:", GetLastError(), " Retcode:", res.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Update Grid Tracking - Remove closed positions                   |
//+------------------------------------------------------------------+
void UpdateGridTracking()
{
   // Check buy grid positions
   for(int i = 0; i < buy_grid_count; i++)
   {
      if(!PositionSelectByTicket(buy_grid_levels[i].ticket))
      {
         // Position closed, remove from grid
         for(int j = i; j < buy_grid_count - 1; j++)
         {
            buy_grid_levels[j] = buy_grid_levels[j + 1];
         }
         buy_grid_count--;
         i--;
      }
   }
   
   // Check sell grid positions
   for(int i = 0; i < sell_grid_count; i++)
   {
      if(!PositionSelectByTicket(sell_grid_levels[i].ticket))
      {
         // Position closed, remove from grid
         for(int j = i; j < sell_grid_count - 1; j++)
         {
            sell_grid_levels[j] = sell_grid_levels[j + 1];
         }
         sell_grid_count--;
         i--;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there are open buy positions                            |
//+------------------------------------------------------------------+
bool HasOpenBuyPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if there are open sell positions                           |
//+------------------------------------------------------------------+
bool HasOpenSellPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close positions by type                                          |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE pos_type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == pos_type)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = MagicNumber;
            
            OrderSend(request, result);
         }
      }
   }
   
   if(pos_type == POSITION_TYPE_BUY) buy_grid_count = 0;
   if(pos_type == POSITION_TYPE_SELL) sell_grid_count = 0;
}

//+------------------------------------------------------------------+
//| Check for new day and reset daily profit                         |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime today = StructToTime(dt);
   
   if(today != current_day)
   {
      // New day started
      current_day = today;
      daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      daily_profit = 0.0;
      daily_target_reached = false;
      Print("New trading day started. Daily profit reset. Starting balance: ", DoubleToString(daily_start_balance, 2));
   }
   else
   {
      // Update daily profit
      double new_profit = CalculateDailyProfit();
      
      // Calculate actual target/loss values
      double actual_target = UsePercentageTarget ? (daily_start_balance * DailyTargetPercent / 100.0) : DailyTargetProfit;
      double actual_loss_limit = UsePercentageLoss ? (daily_start_balance * DailyLossPercent / 100.0) : DailyLossLimit;
      
      // Check if target reached
      if(UseDailyTarget && !daily_target_reached && new_profit >= actual_target)
      {
         daily_target_reached = true;
         Print("Daily target reached! Profit: ", DoubleToString(new_profit, 2), " / Target: ", DoubleToString(actual_target, 2));
         
         // Close all open positions
         CloseAllPositions();
      }
      
      // Check if loss limit reached
      if(UseDailyLoss && new_profit <= -actual_loss_limit)
      {
         Print("Daily loss limit reached! Loss: ", DoubleToString(new_profit, 2), " / Limit: -", DoubleToString(actual_loss_limit, 2));
         
         // Close all open positions
         CloseAllPositions();
      }
      
      daily_profit = new_profit;
   }
}

//+------------------------------------------------------------------+
//| Calculate daily profit for this EA                               |
//+------------------------------------------------------------------+
double CalculateDailyProfit()
{
   double profit = 0.0;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime today_start = StructToTime(dt);
   
   // Check history deals
   HistorySelect(today_start, TimeCurrent());
   
   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
            profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         }
      }
   }
   
   // Add floating profit from open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            profit += PositionGetDouble(POSITION_PROFIT);
            profit += PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   
   return profit;
}

//+------------------------------------------------------------------+
//| Close all positions for this EA                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.deviation = 10;
            request.magic = MagicNumber;
            
            OrderSend(request, result);
         }
      }
   }
   
   // Reset grid counters
   buy_grid_count = 0;
   sell_grid_count = 0;
}

//+------------------------------------------------------------------+
//| Check for volatility spike using ATR                             |
//+------------------------------------------------------------------+
bool IsVolatilitySpike()
{
   if(!UseVolatilityFilter)
      return false;
      
   // Copy ATR values
   if(CopyBuffer(atr_handle, 0, 0, ATR_LookbackBars + 1, atr_buffer) < ATR_LookbackBars + 1)
   {
      Print("Error copying ATR buffer");
      return false;
   }
   
   double current_atr = atr_buffer[0];
   
   // Calculate average ATR over lookback period
   double atr_sum = 0.0;
   for(int i = 1; i <= ATR_LookbackBars; i++)
   {
      atr_sum += atr_buffer[i];
   }
   double avg_atr = atr_sum / ATR_LookbackBars;
   
   // Check if current ATR is significantly higher than average
   double spike_threshold = avg_atr * ATR_Multiplier;
   
   if(current_atr > spike_threshold)
   {
      Print("Volatility spike detected! Current ATR: ", DoubleToString(current_atr, 5), 
            " | Avg ATR: ", DoubleToString(avg_atr, 5), 
            " | Threshold: ", DoubleToString(spike_threshold, 5));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss based on ATR                         |
//+------------------------------------------------------------------+
double CalculateDynamicStopLoss(ENUM_ORDER_TYPE order_type, double entry_price)
{
   if(!UseDynamicSL)
      return 0.0;
      
   // Copy ATR values from the specified timeframe
   if(CopyBuffer(atr_sl_handle, 0, 0, 1, atr_sl_buffer) < 1)
   {
      Print("Error copying ATR SL buffer");
      return 0.0;
   }
   
   double atr_value = atr_sl_buffer[0];
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Calculate stop loss distance based on ATR
   double sl_distance = atr_value * ATR_SL_Multiplier;
   
   double sl = 0.0;
   if(order_type == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(entry_price - sl_distance, digits);
   }
   else // SELL
   {
      sl = NormalizeDouble(entry_price + sl_distance, digits);
   }
   
   Print("Dynamic SL calculated: ATR=", DoubleToString(atr_value, 5), 
         " | Distance=", DoubleToString(sl_distance, 5), 
         " | SL=", DoubleToString(sl, digits));
   
   return sl;
}

//+------------------------------------------------------------------+
//| Calculate Base Lot Size                                          |
//+------------------------------------------------------------------+
double CalculateBaseLotSize()
{
   if(!UsePercentageRisk)
      return LotSize;
      
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (RiskPercentage / 100.0);
   
   // Calculate lot size: for every $100, 10% = 0.01 lot
   double calculated_lot = risk_amount / 10000.0;
   
   return NormalizeDouble(calculated_lot, 2);
}

//+------------------------------------------------------------------+
//| Calculate Final Lot Size including Recovery                      |
//+------------------------------------------------------------------+
double CalculateFinalLotSize()
{
   double lot = CalculateBaseLotSize();
   
   if(UseLossRecovery && accumulated_loss > 0 && TakeProfit > 0)
   {
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      
      if(tick_size > 0 && tick_value > 0)
      {
         // Calculate how much 1 lot earns per point
         double profit_per_lot_per_point = tick_value * (point / tick_size);
         double total_points = TakeProfit;
         
         // Lot needed to recover accumulated_loss over TakeProfit points
         double recovery_lot = accumulated_loss / (total_points * profit_per_lot_per_point);
         
         Print("Recovery Calculation: Loss=", accumulated_loss, " | TP Points=", total_points, " | Recovery Lot Needed=", recovery_lot);
         
         lot += recovery_lot;
      }
   }
   
   // Get symbol lot limits
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Apply Max Recovery Lot limit
   if(UseLossRecovery && lot > MaxRecoveryLot)
      lot = MaxRecoveryLot;
      
   // Ensure lot size is within broker limits
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
      
   // Round to lot step
   lot = MathFloor(lot / lot_step) * lot_step;
   lot = NormalizeDouble(lot, 2);
   
   Print("Final Lot Size: ", lot, " (Base: ", CalculateBaseLotSize(), ", Accumulated Loss: ", accumulated_loss, ")");
   
   return lot;
}

//+------------------------------------------------------------------+
//| Update Accumulated Loss from History                             |
//+------------------------------------------------------------------+
void UpdateAccumulatedLoss()
{
   // We look at the last closed trade. If it was a loss, we add it to accumulated_loss.
   // If it was a profit, we subtract it from accumulated_loss (but not below 0).
   
   static datetime last_history_check = 0;
   if(last_history_check == 0) last_history_check = TimeCurrent() - 3600; // Start from 1 hour ago on first run
   
   HistorySelect(last_history_check, TimeCurrent());
   int total_deals = HistoryDealsTotal();
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         datetime deal_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         if(deal_time <= last_history_check) continue;
         
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
            HistoryDealGetInteger(ticket, DEAL_MAGIC) == MagicNumber &&
            HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                           HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                           HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            
            if(profit < 0)
            {
               accumulated_loss += MathAbs(profit);
               Print("Loss detected: ", profit, ". New accumulated loss: ", accumulated_loss);
            }
            else if(profit > 0)
            {
               accumulated_loss -= profit;
               if(accumulated_loss < 0) accumulated_loss = 0;
               Print("Profit detected: ", profit, ". Remaining loss to recover: ", accumulated_loss);
            }
            
            if(deal_time > last_history_check) last_history_check = deal_time;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Scan one timeframe for swing pivot key levels                    |
//| Returns array of KLZone structs (clustered & touch-counted)      |
//+------------------------------------------------------------------+
int ScanKeyLevels(ENUM_TIMEFRAMES tf, KLZone &zones[], double zone_tolerance)
{
   int count = 0;
   int bars_available = (int)SeriesInfoInteger(_Symbol, tf, SERIES_BARS_COUNT);
   int scan = MathMin(KL_ScanBars + KL_SwingLookback * 2, bars_available - 1);
   
   if(scan < KL_SwingLookback * 2 + 1)
      return 0;
   
   // Temporary raw pivot list
   double raw_pivots[];
   bool   raw_is_high[];
   int    raw_count = 0;
   ArrayResize(raw_pivots,   scan);
   ArrayResize(raw_is_high,  scan);
   
   int lb = KL_SwingLookback;
   
   // ----- Detect swing highs and lows -----
   // We iterate from bar (lb) to (scan - lb), leaving lb bars on each side
   // to confirm the pivot (no repaint: we only look at confirmed closed bars,
   // so bar index 0 is current; index 1 is last closed, etc.)
   // We start from bar (lb+1) to avoid any partially formed pivot.
   for(int i = lb + 1; i <= scan - lb; i++)
   {
      double hi = iHigh(_Symbol, tf, i);
      double lo = iLow(_Symbol, tf, i);
      
      bool is_swing_high = true;
      bool is_swing_low  = true;
      
      for(int j = 1; j <= lb; j++)
      {
         if(iHigh(_Symbol, tf, i - j) >= hi) { is_swing_high = false; break; }
      }
      if(is_swing_high)
      {
         for(int j = 1; j <= lb; j++)
         {
            if(iHigh(_Symbol, tf, i + j) >= hi) { is_swing_high = false; break; }
         }
      }
      
      for(int j = 1; j <= lb; j++)
      {
         if(iLow(_Symbol, tf, i - j) <= lo) { is_swing_low = false; break; }
      }
      if(is_swing_low)
      {
         for(int j = 1; j <= lb; j++)
         {
            if(iLow(_Symbol, tf, i + j) <= lo) { is_swing_low = false; break; }
         }
      }
      
      if(is_swing_high)
      {
         raw_pivots[raw_count]  = hi;
         raw_is_high[raw_count] = true;
         raw_count++;
      }
      if(is_swing_low)
      {
         raw_pivots[raw_count]  = lo;
         raw_is_high[raw_count] = false;
         raw_count++;
      }
   }
   
   if(raw_count == 0) return 0;
   
   // ----- Cluster nearby pivots into zones -----
   // Two pivots merge into one zone if they are within 2 * zone_tolerance of each other.
   ArrayResize(zones, raw_count); // max possible zones = raw_count
   count = 0;
   
   bool merged[];
   ArrayResize(merged, raw_count);
   ArrayInitialize(merged, 0);
   
   for(int i = 0; i < raw_count; i++)
   {
      if(merged[i]) continue;
      
      double zone_sum    = raw_pivots[i];
      int    zone_hits   = 1;
      bool   zone_is_hi  = raw_is_high[i];
      
      for(int j = i + 1; j < raw_count; j++)
      {
         if(merged[j]) continue;
         if(MathAbs(raw_pivots[j] - raw_pivots[i]) <= zone_tolerance * 2.0)
         {
            zone_sum  += raw_pivots[j];
            zone_hits++;
            merged[j]  = true;
         }
      }
      
      zones[count].price    = zone_sum / zone_hits;
      zones[count].touches  = zone_hits;
      zones[count].is_high  = zone_is_hi;
      count++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
//| Returns true if 'price' is within zone_tolerance of any          |
//| validated key level on the enabled timeframes                    |
//+------------------------------------------------------------------+
bool IsAtKeyLevel(double price)
{
   if(!UseKeyLevelFilter) return true;
   
   // Get current ATR for tolerance calculation
   if(CopyBuffer(atr_kl_handle, 0, 0, 1, atr_kl_buffer) < 1)
   {
      Print("IsAtKeyLevel: Error copying ATR KL buffer — allowing entry");
      return true; // Fail open so ATR error doesn't kill all trades
   }
   double atr_val       = atr_kl_buffer[0];
   double zone_tolerance = atr_val * KL_ZoneTolerance_ATR;
   
   if(zone_tolerance <= 0) return true;
   
   // Which timeframes to scan
   ENUM_TIMEFRAMES tfs[3];
   bool            use[3];
   tfs[0] = PERIOD_M5;  use[0] = KL_UseM5;
   tfs[1] = PERIOD_M15; use[1] = KL_UseM15;
   tfs[2] = PERIOD_H1;  use[2] = KL_UseH1;
   
   int tfs_enabled = 0;
   int tfs_matched = 0;
   
   for(int t = 0; t < 3; t++)
   {
      if(!use[t]) continue;
      tfs_enabled++;
      
      KLZone zones[];
      int zone_count = ScanKeyLevels(tfs[t], zones, zone_tolerance);
      
      for(int z = 0; z < zone_count; z++)
      {
         if(zones[z].touches < KL_MinTouches) continue;
         
         if(MathAbs(price - zones[z].price) <= zone_tolerance)
         {
            tfs_matched++;
            
            string tf_name = EnumToString(tfs[t]);
            Print("Key Level HIT | TF:", tf_name,
                  " | Level:", DoubleToString(zones[z].price, _Digits),
                  " | Touches:", zones[z].touches,
                  " | Type:", zones[z].is_high ? "Resistance" : "Support",
                  " | Price:", DoubleToString(price, _Digits),
                  " | Tolerance:", DoubleToString(zone_tolerance, _Digits));
            break; // One match per timeframe is enough
         }
      }
   }
   
   if(tfs_enabled == 0) return true; // No TFs enabled, let trades through
   
   if(KL_RequireAllTF)
      return (tfs_matched >= tfs_enabled);
   else
      return (tfs_matched >= 1);
}
//+------------------------------------------------------------------+