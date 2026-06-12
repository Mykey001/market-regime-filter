//+------------------------------------------------------------------+
//|                                                HybridGridEA.mq5   |
//|                      Copyright 2026, Example Research             |
//|                                                                  |
//| This Expert Advisor implements a hybrid grid strategy inspired   |
//| by academic research.  It uses ATR‑based spacing, RSI and SMA    |
//| filters, basket take‑profit, equity guard stops and simple       |
//| anti‑Martingale sizing.  THIS CODE IS FOR EDUCATIONAL PURPOSES   |
//| ONLY.  Trading high‑leverage grid systems can result in rapid    |
//| capital loss.  Use at your own risk and backtest thoroughly.     |
//+------------------------------------------------------------------+

#property version   "1.00"
#property strict
#property description "Hybrid ATR‑RSI grid strategy with basket management"

//--- input parameters
input int    InpGridLevels       = 15;        // number of grid levels
input int    InpATRPeriod        = 10;        // ATR calculation period
input double InpATRFactor        = 0.2;       // spacing multiplier (ATR * factor)
input int    InpRSIPeriod        = 14;        // RSI calculation period
input double InpRSIOver          = 70.0;      // RSI overbought threshold
input double InpRSIUnder         = 30.0;      // RSI oversold threshold
input int    InpSMAPeriod        = 200;       // SMA period for trend filter
input double InpBaseLot          = 0.01;      // base lot size (e.g. 0.01 lot)
input double InpThreshold1       = 200.0;     // equity threshold 1 for lot increase
input double InpThreshold2       = 350.0;     // equity threshold 2 for lot increase
input double InpTakeProfitPct    = 0.02;      // basket take‑profit (2 % of equity)
input double InpDrawdownPct      = 0.30;      // equity drawdown stop (30 %)
input int    InpTradeStartHour   = 13;        // trade start hour (server time)
input int    InpTradeEndHour     = 17;        // trade end hour (server time)
input bool   InpAllowLong        = true;      // allow long positions
input bool   InpAllowShort       = true;      // allow short positions
input int    InpMagicNumber      = 20260225;  // magic number to identify this EA
input string InpSymbol           = "";        // empty to use current chart symbol

//--- global state
double  g_anchor     = 0.0;    // anchor price for current grid
bool    g_gridActive = false;  // is a grid currently active
int     g_direction  = 0;      // 1 = long grid, -1 = short grid

// runtime symbol and indicator handles
string  g_symbol      = "";    // symbol used for trading (resolved from InpSymbol)
int     g_atrHandle   = INVALID_HANDLE; // handle for ATR indicator
int     g_rsiHandle   = INVALID_HANDLE; // handle for RSI indicator
int     g_smaHandle   = INVALID_HANDLE; // handle for SMA indicator

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // resolve symbol: if user left empty, use current chart symbol
   if(InpSymbol == "")
      g_symbol = _Symbol;
   else
      g_symbol = InpSymbol;
   //--- create indicator handles once during initialization
   g_atrHandle = iATR(g_symbol, PERIOD_CURRENT, InpATRPeriod);
   g_rsiHandle = iRSI(g_symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   g_smaHandle = iMA(g_symbol, PERIOD_CURRENT, InpSMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   // verify handles
   if(g_atrHandle == INVALID_HANDLE || g_rsiHandle == INVALID_HANDLE || g_smaHandle == INVALID_HANDLE)
     {
      Print("Indicator handle creation failed");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // clean up: cancel all pending orders and close positions (optional)
   CancelAllPending();
   // release indicator handles
   if(g_atrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
     }
   if(g_rsiHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_rsiHandle);
      g_rsiHandle = INVALID_HANDLE;
     }
   if(g_smaHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_smaHandle);
      g_smaHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Main event handler (called on every tick)                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- symbol context
   string symbol = g_symbol;

   //--- ensure we operate only on the specified symbol
   if(_Symbol != symbol)
      return;

   //--- get current server time and check trading window
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);
   bool trade_window = (tm.hour >= InpTradeStartHour && tm.hour < InpTradeEndHour);

   //--- update indicators using handles
   double atr_buff[1];
   double rsi_buff[1];
   double sma_buff[1];
   // copy one value of ATR, RSI and SMA; ensure buffers updated
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atr_buff) <= 0)
      return;
   if(CopyBuffer(g_rsiHandle, 0, 0, 1, rsi_buff) <= 0)
      return;
   if(CopyBuffer(g_smaHandle, 0, 0, 1, sma_buff) <= 0)
      return;
   double atr_val   = atr_buff[0];
   double rsi_val   = rsi_buff[0];
   double sma_val   = sma_buff[0];
   // use current bid price for close value; according to MQL5 documentation, Close[0] equals Bid【43009934634994†L81-L104】
   double close_val = SymbolInfoDouble(symbol, SYMBOL_BID);

   //--- dynamic lot sizing based on equity thresholds (anti‑Martingale)
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double lot_mult = 1.0;
   if(equity >= InpThreshold2)
      lot_mult = 5.0;
   else if(equity >= InpThreshold1)
      lot_mult = 2.0;
   // Normalize lot size to broker's minimum, maximum and step
   double raw_lot   = InpBaseLot * lot_mult;
   double lot_size = NormalizeVolume(symbol, raw_lot);

   //--- compute spacing based on ATR
   double spacing = atr_val * InpATRFactor;
   // convert spacing into a multiple of the symbol point to ensure valid price increments
   double point_size = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point_size <= 0)
      point_size = 0.0001;
   int spacing_pts = (int)MathRound(spacing / point_size);
   if(spacing_pts < 1)
      spacing_pts = 1;
   spacing = spacing_pts * point_size;
   if(spacing <= 0)
      return; // nothing to do if spacing not available

   //--- compute open positions and profit for this EA
   double open_profit = GetOpenProfit();
   double equity_pct  = (equity > 0.0 ? open_profit / equity : 0.0);

   //--- basket take‑profit and equity guard logic
   if(CountOpenPositions() > 0)
     {
      // close positions if profit target reached
      if(equity_pct >= InpTakeProfitPct)
        {
         CloseAllPositions();
         g_gridActive = false;
        }
      // close positions if drawdown exceeds limit
      if(equity_pct <= -InpDrawdownPct)
        {
         CloseAllPositions();
         g_gridActive = false;
        }
     }

   //--- cancel grid if outside trading window or opposite signal arises
   if(g_gridActive)
     {
      // if trading window closed -> cancel all pending grid orders
      if(!trade_window)
        {
         CancelAllPending();
         g_gridActive = false;
        }
      else
        {
         // check if the opposite signal arises (trend changed)
         bool up_trend   = close_val > sma_val;
         if((g_direction == 1 && !up_trend) || (g_direction == -1 && up_trend))
           {
            CancelAllPending();
            g_gridActive = false;
           }
        }
     }

   //--- open new grid if no positions and no active grid and within trading window
   if(CountOpenPositions() == 0 && !g_gridActive && trade_window)
     {
      bool up_trend   = close_val > sma_val;
      //--- check long condition
      if(InpAllowLong && up_trend && rsi_val < InpRSIUnder)
        {
         StartGrid(symbol, ORDER_TYPE_BUY_LIMIT, close_val, spacing, lot_size);
        }
      //--- check short condition
      else if(InpAllowShort && !up_trend && rsi_val > InpRSIOver)
        {
         StartGrid(symbol, ORDER_TYPE_SELL_LIMIT, close_val, spacing, lot_size);
        }
     }

   //--- if grid active but no pending orders left and no positions, reset state
   if(g_gridActive && CountPendingOrders() == 0 && CountOpenPositions() == 0)
      g_gridActive = false;
  }

//+------------------------------------------------------------------+
//| Start grid: places limit orders based on anchor price and spacing |
//+------------------------------------------------------------------+
void StartGrid(string symbol, ENUM_ORDER_TYPE order_type, double anchor, double spacing, double lot_size)
  {
   g_anchor     = anchor;
   g_gridActive = true;
   g_direction  = (order_type == ORDER_TYPE_BUY_LIMIT ? 1 : -1);
   //--- place limit orders for each grid level
   for(int i = 0; i < InpGridLevels; i++)
     {
      //--- calculate price for this level; shift by one spacing to avoid placing at current price
      double offset = spacing * (i + 1);
      double price = anchor + (order_type == ORDER_TYPE_BUY_LIMIT ? -offset : offset);
      //--- adjust price to tick size and digits
      int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double normalized_price = NormalizeDouble(price, digits);
      //--- create ticket comment
      string comment = (order_type == ORDER_TYPE_BUY_LIMIT ? "LongGrid" : "ShortGrid") + IntegerToString(i);
      //--- prepare request
      MqlTradeRequest request;
      ZeroMemory(request);
      request.action   = TRADE_ACTION_PENDING;
      request.symbol   = symbol;
      request.volume   = lot_size;
      request.type     = order_type;
      request.price    = normalized_price;
      request.sl       = 0.0;
      request.tp       = 0.0;
      request.deviation= 10; // slippage in points
      request.magic    = InpMagicNumber;
      request.comment  = comment;
      //--- result structure
      MqlTradeResult result;
      ZeroMemory(result);
      // send order and ignore return value
      bool send_ok = OrderSend(request, result);
      // reference send_ok to avoid unused variable warning
      if(!send_ok)
        {
         // you can log result.retcode if needed
        }
     }
  }

//+------------------------------------------------------------------+
//| Cancel all pending orders for this EA                           |
//+------------------------------------------------------------------+
void CancelAllPending()
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      // Obtain ticket at index i
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      // Select order by ticket to access its properties
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
        {
         MqlTradeRequest request;
         ZeroMemory(request);
         MqlTradeResult result;
         ZeroMemory(result);
         request.action = TRADE_ACTION_REMOVE;
         request.order  = ticket;
         // send cancellation request and ignore return value
         bool send_ok = OrderSend(request, result);
         if(!send_ok)
           {
            // handle failure if necessary
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Close all open positions for this EA                             |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   // iterate through positions and close them
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      // PositionGetSymbol(i) selects the position and returns its symbol
      string symbol = PositionGetSymbol(i);
      if(symbol != g_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      // determine close type
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE close_type = (ptype == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      double volume = PositionGetDouble(POSITION_VOLUME);
      // Use current bid/ask for closing price
      double price  = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      MqlTradeRequest request;
      ZeroMemory(request);
      MqlTradeResult result;
      ZeroMemory(result);
      request.action = TRADE_ACTION_DEAL;
      request.symbol = symbol;
      request.volume = volume;
      request.type   = close_type;
      request.price  = price;
      request.deviation = 10;
      request.position = ticket;
      request.magic = InpMagicNumber;
      bool send_ok = OrderSend(request, result);
      if(!send_ok)
        {
         // optionally handle error
        }
     }
  }

//+------------------------------------------------------------------+
//| Return cumulative profit of open positions (floating P/L)        |
//+------------------------------------------------------------------+
double GetOpenProfit()
  {
   double total_profit = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      string symb = PositionGetSymbol(i);
      if(symb != g_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      total_profit += PositionGetDouble(POSITION_PROFIT);
     }
   return(total_profit);
  }

//+------------------------------------------------------------------+
//| Count pending orders associated with this EA                    |
//+------------------------------------------------------------------+
int CountPendingOrders()
  {
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Count open positions associated with this EA                    |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
     {
      // PositionGetSymbol(i) both selects the position and returns its symbol
      string symb = PositionGetSymbol(i);
      if(symb != g_symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Normalize lot size based on symbol limits and step               |
//+------------------------------------------------------------------+
double NormalizeVolume(string symbol,double volume)
  {
   // Retrieve symbol trading properties
   double min_vol   = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double max_vol   = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double vol_step  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   // Ensure step is positive
   if(vol_step <= 0)
      vol_step = min_vol;
   // Clamp volume within allowed range
   double vol = MathMax(min_vol, MathMin(max_vol, volume));
   // Adjust to step by flooring
   double steps = MathFloor(vol / vol_step);
   vol = steps * vol_step;
   // Normalize to 8 decimals just in case
   vol = NormalizeDouble(vol, 8);
   return vol;
  }