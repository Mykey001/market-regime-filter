//+------------------------------------------------------------------+
//|                                                       RSI_EA.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "RSI Trading EA"
#property version   "1.41"
#property strict

#include "RegimeFilterLib.mqh"  // ML Regime Filter Integration

// ==================== ML Regime Filter Settings ====================
input bool     EnableRegimeFilter = true;      // Enable ML regime filter
input string   RegimeFilterHost = "127.0.0.1"; // Python GUI host  
input int      RegimeFilterPort = 9090;        // Python GUI port
// ====================================================================

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

input group "=== Loss Recovery ==="
input bool     UseLossRecovery = false;            // Enable Loss Recovery System
input double   MaxRecoveryLot = 5.0;               // Maximum Lot Size for recovery trades

input group "=== Time Filter ==="
input bool     UseTimeFilter = false;              // Enable Daily Start Time Filter
input int      StartHour = 8;                      // Start Hour (0-23)
input int      StartMinute = 0;                    // Start Minute (0-59)

input group "=== Market Regime Filter ==="
input bool     UseRegimeFilter = false;            // Enable Market Regime Filter
input int      Regime_MA_Period = 200;             // MA Period for Trend Detection
input ENUM_MA_METHOD Regime_MA_Method = MODE_SMA;  // MA Method
input ENUM_TIMEFRAMES Regime_Timeframe = PERIOD_H1;// Timeframe for Regime Detection
input bool     TradeOnlyWithTrend = true;          // Only Buy above MA, Sell below MA

// Global variables
int rsi_handle;
int atr_handle;
int atr_sl_handle;
int ma_handle;
double rsi_buffer[];
double atr_buffer[];
double atr_sl_buffer[];
double ma_buffer[];
datetime last_bar_time = 0;
double accumulated_loss = 0.0; // Tracks the amount lost to be recovered

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
   
   // Create MA indicator handle for regime filter
   if(UseRegimeFilter)
   {
      ma_handle = iMA(_Symbol, Regime_Timeframe, Regime_MA_Period, 0, Regime_MA_Method, PRICE_CLOSE);
      
      if(ma_handle == INVALID_HANDLE)
      {
         Print("Error creating MA indicator for Regime Filter");
         return(INIT_FAILED);
      }
      ArraySetAsSeries(ma_buffer, true);
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
      Print("Regime Filter: Enabled | MA Period: ", Regime_MA_Period, " | Timeframe: ", EnumToString(Regime_Timeframe));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ML Regime Filter Cleanup
   if(EnableRegimeFilter)
   {
      DeinitRegimeFilter();
      Print("ML Regime Filter: Shut down");
   }
   
   // Release indicator handles
   if(rsi_handle != INVALID_HANDLE)
      IndicatorRelease(rsi_handle);
      
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
      
   if(atr_sl_handle != INVALID_HANDLE)
      IndicatorRelease(atr_sl_handle);
      
   if(ma_handle != INVALID_HANDLE)
      IndicatorRelease(ma_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update ML Regime Filter
   if(EnableRegimeFilter)
   {
      UpdateRegimeFilter();
   }
   
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
      if(CopyBuffer(ma_handle, 0, 0, 1, ma_buffer) < 1)
      {
         Print("Error copying MA buffer");
      }
      else
      {
         double current_ma = ma_buffer[0];
         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         if(TradeOnlyWithTrend)
         {
            if(current_price > current_ma)
            {
               can_sell = false; // Above MA, only Buy
               if(comment_text != "") comment_text += "\n";
               comment_text += "Regime: Bullish (Only Buy)";
            }
            else
            {
               can_buy = false; // Below MA, only Sell
               if(comment_text != "") comment_text += "\n";
               comment_text += "Regime: Bearish (Only Sell)";
            }
         }
      }
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
   
   if(!UseGrid)
   {
      // Original logic - single position only
      if(PositionSelect(_Symbol))
         return;
      
      double lot = CalculateFinalLotSize();
         
      if(current_rsi <= RSI_Oversold && can_buy)
         OpenTrade(ORDER_TYPE_BUY, current_rsi, lot);
      else if(current_rsi >= RSI_Overbought && can_sell)
         OpenTrade(ORDER_TYPE_SELL, current_rsi, lot);
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
               // Open first buy position
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
            {
               // Check if RSI has moved enough below the last grid level
               double last_grid_rsi = buy_grid_levels[buy_grid_count - 1].rsi_level;
               if(current_rsi <= last_grid_rsi - GridSpacing)
               {
                  double lot = buy_grid_levels[buy_grid_count - 1].lot_size * LotMultiplier;
                  lot = NormalizeDouble(lot, 2); // Round to 2 decimal places
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
               // Open first sell position
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
            {
               // Check if RSI has moved enough above the last grid level
               double last_grid_rsi = sell_grid_levels[sell_grid_count - 1].rsi_level;
               if(current_rsi >= last_grid_rsi + GridSpacing)
               {
                  double lot = sell_grid_levels[sell_grid_count - 1].lot_size * LotMultiplier;
                  lot = NormalizeDouble(lot, 2); // Round to 2 decimal places
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
   request.comment = TradeComment;
   
   // ===== ML Regime Filter Check =====
   if(EnableRegimeFilter && IsRegimeFilterConnected())
   {
      string trade_direction = (order_type == ORDER_TYPE_BUY) ? "buy" : "sell";
      if(!IsTradeAllowed(trade_direction))
      {
         Print("ML Regime Filter BLOCKED ", trade_direction, " trade. Regime: ", GetCurrentRegime(), 
               ", Confidence: ", DoubleToString(GetRegimeConfidence(), 1), "%");
         return 0;  // Trade blocked by regime filter
      }
      Print("ML Regime Filter ALLOWED ", trade_direction, " trade. Regime: ", GetCurrentRegime(), 
            ", Confidence: ", DoubleToString(GetRegimeConfidence(), 1), "%");
   }
   // ===================================
   
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
               " | TP: ", DoubleToString(tp, digits));
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
