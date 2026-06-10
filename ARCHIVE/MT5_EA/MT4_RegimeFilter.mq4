//+------------------------------------------------------------------+
//|                                          MT4_RegimeFilter.mq4    |
//|                              Market Regime Trading Filter EA     |
//|                                   Connects to Python GUI         |
//+------------------------------------------------------------------+
#property copyright "Market Regime System"
#property link      ""
#property version   "1.00"
#property strict

#include <socket-library-mt4-mt5.mqh>  // Socket library

//--- Input parameters
input string   PythonHost = "127.0.0.1";     // Python GUI Host
input int      PythonPort = 9090;             // Python GUI Port
input int      UpdateIntervalSeconds = 300;   // Bar update interval (5min)
input bool     EnableFilter = true;           // Enable regime filter

//--- Global variables
ClientSocket* client = NULL;
datetime lastBarTime = 0;
int currentRegime = -1;
double regimeConfidence = 0.0;
bool tradeAllowed = false;
bool connected = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Regime Filter EA initializing...");
   
   // Create socket client
   client = new ClientSocket(PythonHost, PythonPort);
   
   if(client.IsSocketConnected())
   {
      connected = true;
      Print("Connected to Python GUI at ", PythonHost, ":", PythonPort);
      
      // Send initial data
      SendCurrentBar();
   }
   else
   {
      Print("Failed to connect to Python GUI. Will retry...");
      connected = false;
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Regime Filter EA shutting down...");
   
   if(client != NULL)
   {
      delete client;
      client = NULL;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check connection
   if(!connected || client == NULL || !client.IsSocketConnected())
   {
      // Try to reconnect
      if(client != NULL) delete client;
      client = new ClientSocket(PythonHost, PythonPort);
      
      if(client.IsSocketConnected())
      {
         connected = true;
         Print("Reconnected to Python GUI");
      }
      else
      {
         connected = false;
         return;
      }
   }
   
   // Check for new bar
   datetime currentBarTime = iTime(Symbol(), PERIOD_M5, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      SendCurrentBar();
   }
}

//+------------------------------------------------------------------+
//| Send current bar data to Python                                  |
//+------------------------------------------------------------------+
void SendCurrentBar()
{
   if(client == NULL || !client.IsSocketConnected())
      return;
   
   // Get bar data
   double open = iOpen(Symbol(), PERIOD_M5, 0);
   double high = iHigh(Symbol(), PERIOD_M5, 0);
   double low = iLow(Symbol(), PERIOD_M5, 0);
   double close = iClose(Symbol(), PERIOD_M5, 0);
   long volume = iVolume(Symbol(), PERIOD_M5, 0);
   datetime barTime = iTime(Symbol(), PERIOD_M5, 0);
   
   // Build JSON message
   string json = "{";
   json += "\"type\":\"bar\",";
   json += "\"time\":\"" + TimeToStr(barTime, TIME_DATE|TIME_MINUTES) + "\",";
   json += "\"open\":" + DoubleToStr(open, Digits) + ",";
   json += "\"high\":" + DoubleToStr(high, Digits) + ",";
   json += "\"low\":" + DoubleToStr(low, Digits) + ",";
   json += "\"close\":" + DoubleToStr(close, Digits) + ",";
   json += "\"tickvol\":" + IntegerToString(volume) + ",";
   json += "\"spread\":" + IntegerToString(MarketInfo(Symbol(), MODE_SPREAD));
   json += "}";
   
   // Send data
   if(!client.Send(json))
   {
      Print("Failed to send bar data");
      connected = false;
   }
   
   // Receive response (regime info)
   string response = client.Receive("\r\n");
   if(StringLen(response) > 0)
   {
      ParseResponse(response);
   }
}

//+------------------------------------------------------------------+
//| Check if trade is allowed based on regime                        |
//+------------------------------------------------------------------+
bool IsTradeAllowed(string action)
{
   if(!EnableFilter || !connected)
      return true;  // Allow all trades if filter disabled or not connected
   
   if(client == NULL || !client.IsSocketConnected())
      return true;  // Allow if not connected
   
   // Send trade request to Python
   string json = "{";
   json += "\"type\":\"trade_request\",";
   json += "\"symbol\":\"" + Symbol() + "\",";
   json += "\"action\":\"" + action + "\"";
   json += "}";
   
   if(!client.Send(json))
   {
      Print("Failed to send trade request");
      return true;  // Default to allow on error
   }
   
   // Wait for response
   string response = client.Receive("\r\n", 1000);  // 1 second timeout
   if(StringLen(response) > 0)
   {
      ParseResponse(response);
      return tradeAllowed;
   }
   
   return true;  // Default to allow on timeout
}

//+------------------------------------------------------------------+
//| Parse response from Python                                       |
//+------------------------------------------------------------------+
void ParseResponse(string json)
{
   // Simple JSON parsing
   int pos;
   
   // Extract allow_trade
   pos = StringFind(json, "\"allow_trade\":");
   if(pos >= 0)
   {
      string substr = StringSubstr(json, pos + 14);
      tradeAllowed = (StringFind(substr, "true") == 0);
   }
   
   // Extract regime
   pos = StringFind(json, "\"regime\":");
   if(pos >= 0)
   {
      string substr = StringSubstr(json, pos + 9);
      int endPos = StringFind(substr, ",");
      if(endPos > 0)
      {
         string regimeStr = StringSubstr(substr, 0, endPos);
         currentRegime = StrToInteger(regimeStr);
      }
   }
   
   // Extract confidence
   pos = StringFind(json, "\"confidence\":");
   if(pos >= 0)
   {
      string substr = StringSubstr(json, pos + 13);
      int endPos = StringFind(substr, ",");
      if(endPos < 0) endPos = StringFind(substr, "}");
      if(endPos > 0)
      {
         string confStr = StringSubstr(substr, 0, endPos);
         regimeConfidence = StrToDouble(confStr);
      }
   }
   
   Comment("Regime: ", currentRegime, " | Confidence: ", 
           DoubleToStr(regimeConfidence * 100, 1), "% | ",
           "Trade: ", (tradeAllowed ? "ALLOWED" : "BLOCKED"));
}

//+------------------------------------------------------------------+
//| Example: Your EA's trade logic with regime filter               |
//+------------------------------------------------------------------+
void ExecuteBuySignal()
{
   // Check with regime filter
   if(!IsTradeAllowed("buy"))
   {
      Print("Buy signal blocked by regime filter");
      return;
   }
   
   // Your normal trade execution code here
   // Example:
   // int ticket = OrderSend(Symbol(), OP_BUY, 0.1, Ask, 3, 0, 0, "Regime Approved", 0, 0, clrGreen);
   
   Print("Buy trade executed (regime approved)");
}

void ExecuteSellSignal()
{
   // Check with regime filter
   if(!IsTradeAllowed("sell"))
   {
      Print("Sell signal blocked by regime filter");
      return;
   }
   
   // Your normal trade execution code here
   // Example:
   // int ticket = OrderSend(Symbol(), OP_SELL, 0.1, Bid, 3, 0, 0, "Regime Approved", 0, 0, clrRed);
   
   Print("Sell trade executed (regime approved)");
}

//+------------------------------------------------------------------+
//| Get current regime info (for display/logging)                   |
//+------------------------------------------------------------------+
int GetCurrentRegime()
{
   return currentRegime;
}

double GetRegimeConfidence()
{
   return regimeConfidence;
}

bool IsTradeAllowedByRegime()
{
   return tradeAllowed;
}
//+------------------------------------------------------------------+
