//+------------------------------------------------------------------+
//|                                          RegimeFilterLib.mqh     |
//|                          Library for Regime Filter Integration   |
//|                   Include this in your EA - NO conflicts!        |
//+------------------------------------------------------------------+

// Required for socket operations
#include <Trade\Trade.mqh>

//--- Regime Filter Global Variables (with unique prefix to avoid conflicts)
int g_rf_socketHandle = INVALID_HANDLE;
int g_rf_currentRegime = -1;
double g_rf_regimeConfidence = 0.0;
bool g_rf_tradeAllowed = true;
bool g_rf_connected = false;
string g_rf_terminalName = "";
string g_rf_eaName = "";         // Unique EA identifier for per-EA filtering
string g_rf_receiveBuffer = "";
datetime g_rf_lastBarTime = 0;

//--- Regime Filter Input Parameters (you can override these in your EA)
string g_rf_PythonHost = "127.0.0.1";     // Python GUI Host
int g_rf_PythonPort = 9090;                // Python GUI Port
bool g_rf_EnableFilter = true;             // Enable regime filter

//+------------------------------------------------------------------+
//| Initialize Regime Filter - Call this from your EA's OnInit()    |
//|                                                                  |
//| Parameters:                                                      |
//|   host   - Python GUI host (default "127.0.0.1")                |
//|   port   - Python GUI port (default 9090)                       |
//|   enable - Enable/disable filter (default true)                 |
//|   eaName - Unique EA name for per-EA filtering.                 |
//|            If empty, auto-generated from Symbol + Account.      |
//+------------------------------------------------------------------+
bool RF_InitRegimeFilter(string host = "127.0.0.1", int port = 9090, bool enable = true, string eaName = "")
{
   g_rf_PythonHost = host;
   g_rf_PythonPort = port;
   g_rf_EnableFilter = enable;
   
   // Set EA name - use provided name or auto-generate
   if(eaName != "")
      g_rf_eaName = eaName;
   else
      g_rf_eaName = _Symbol + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   
   Print("=== Regime Filter Initializing ===");
   Print("  EA Name: ", g_rf_eaName);
   
   // Get terminal name for identification
   g_rf_terminalName = TerminalInfoString(TERMINAL_NAME) + " - " + 
                       IntegerToString(TerminalInfoInteger(TERMINAL_BUILD));
   
   // Connect to Python GUI
   if(RF_ConnectToGUI())
   {
      g_rf_connected = true;
      Print("Regime Filter: Connected to Python GUI at ", g_rf_PythonHost, ":", g_rf_PythonPort);
      
      // Send initial handshake
      RF_SendHandshake();
      
      // Send historical bars for warmup
      // Need to send enough bars so that after NaN drop, we have 626+ valid bars
      // Warmup period drops ~575 bars, so send 1200+ to get 626+ valid
      RF_SendHistoricalBars(1300);
      
      return true;
   }
   else
   {
      Print("Regime Filter: Failed to connect. Will work in bypass mode.");
      g_rf_connected = false;
      return false;
   }
}

//+------------------------------------------------------------------+
//| Cleanup Regime Filter - Call this from your EA's OnDeinit()     |
//+------------------------------------------------------------------+
void RF_DeinitRegimeFilter()
{
   Print("Regime Filter: Shutting down...");
   
   if(g_rf_socketHandle != INVALID_HANDLE)
   {
      SocketClose(g_rf_socketHandle);
      g_rf_socketHandle = INVALID_HANDLE;
   }
   
   g_rf_connected = false;
}

//+------------------------------------------------------------------+
//| Update Regime Filter - Call this from your EA's OnTick()        |
//+------------------------------------------------------------------+
void RF_UpdateRegimeFilter()
{
   // Check connection
   if(!g_rf_connected || g_rf_socketHandle == INVALID_HANDLE)
   {
      // Try to reconnect every 10 seconds
      static datetime lastAttempt = 0;
      if(TimeCurrent() - lastAttempt >= 10)
      {
         lastAttempt = TimeCurrent();
         if(RF_ConnectToGUI())
         {
            g_rf_connected = true;
            Print("Regime Filter: Reconnected to Python GUI");
            RF_SendHandshake();
         }
      }
      return;
   }
   
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime != g_rf_lastBarTime)
   {
      g_rf_lastBarTime = currentBarTime;
      RF_SendCurrentBar();
   }
}

//+------------------------------------------------------------------+
//| Connect to Python GUI                                            |
//+------------------------------------------------------------------+
bool RF_ConnectToGUI()
{
   if(g_rf_socketHandle != INVALID_HANDLE)
   {
      SocketClose(g_rf_socketHandle);
      g_rf_socketHandle = INVALID_HANDLE;
   }
   
   g_rf_socketHandle = SocketCreate();
   
   if(g_rf_socketHandle == INVALID_HANDLE)
   {
      Print("Regime Filter: Failed to create socket. Error: ", GetLastError());
      return false;
   }
   
   if(!SocketConnect(g_rf_socketHandle, g_rf_PythonHost, g_rf_PythonPort, 5000))
   {
      Print("Regime Filter: Failed to connect. Error: ", GetLastError());
      Print("  Make sure Python GUI is running and server is started!");
      SocketClose(g_rf_socketHandle);
      g_rf_socketHandle = INVALID_HANDLE;
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Send handshake                                                   |
//+------------------------------------------------------------------+
void RF_SendHandshake()
{
   if(g_rf_socketHandle == INVALID_HANDLE) return;
   
   string json = "{";
   json += "\"type\":\"handshake\",";
   json += "\"terminal\":\"" + g_rf_terminalName + "\",";
   json += "\"ea_name\":\"" + g_rf_eaName + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"account\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   json += "}\n";
   
   RF_SendData(json);
}

//+------------------------------------------------------------------+
//| Send historical bars                                             |
//+------------------------------------------------------------------+
void RF_SendHistoricalBars(int count)
{
   Print("Regime Filter: Requesting ", count, " historical bars from broker...");
   
   MqlRates rates[];
   // FIX: Start from bar 1 (skip bar 0 which is forming)
   // We want only CLOSED bars for stable regime predictions  
   int copied = CopyRates(_Symbol, PERIOD_M5, 1, count, rates);
   
   if(copied <= 0)
   {
      Print("Regime Filter: ERROR - Failed to get historical bars. Error: ", GetLastError());
      Print("  Symbol: ", _Symbol);
      Print("  Timeframe: M5");
      Print("  Requested: ", count, " bars");
      return;
   }
   
   Print("Regime Filter: Got ", copied, " CLOSED bars from broker. Sending to Python...");
   
   int bars_sent = 0;
   for(int i = copied - 1; i >= 0; i--)
   {
      string json = "{";
      json += "\"type\":\"bar\",";
      json += "\"terminal\":\"" + g_rf_terminalName + "\",";
      json += "\"symbol\":\"" + _Symbol + "\",";
      json += "\"time\":\"" + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES) + "\",";
      json += "\"open\":" + DoubleToString(rates[i].open, _Digits) + ",";
      json += "\"high\":" + DoubleToString(rates[i].high, _Digits) + ",";
      json += "\"low\":" + DoubleToString(rates[i].low, _Digits) + ",";
      json += "\"close\":" + DoubleToString(rates[i].close, _Digits) + ",";
      json += "\"tickvol\":" + IntegerToString(rates[i].tick_volume) + ",";
      json += "\"spread\":" + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      json += "}\n";
      
      RF_SendData(json);
      bars_sent++;
      
      // Print progress every 200 bars
      if(bars_sent % 200 == 0)
      {
         Print("  Progress: ", bars_sent, " / ", copied, " bars sent...");
         Sleep(10);
      }
   }
   
   Print("Regime Filter: Successfully sent all ", bars_sent, " CLOSED bars!");
   Print("  Waiting for Python to process and make first prediction...");
   
   // Try to receive initial response
   Sleep(100);
   RF_ReceiveData();
}

//+------------------------------------------------------------------+
//| Send current bar                                                 |
//+------------------------------------------------------------------+
void RF_SendCurrentBar()
{
   if(g_rf_socketHandle == INVALID_HANDLE) return;
   
   MqlRates rates[];
   // FIX: Copy bar 1 (last CLOSED bar), not bar 0 (current forming bar)
   // Bar 0 changes on every tick, causing regime to flip constantly!
   if(CopyRates(_Symbol, PERIOD_M5, 1, 1, rates) <= 0) return;
   
   string json = "{";
   json += "\"type\":\"bar\",";
   json += "\"terminal\":\"" + g_rf_terminalName + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"time\":\"" + TimeToString(rates[0].time, TIME_DATE|TIME_MINUTES) + "\",";
   json += "\"open\":" + DoubleToString(rates[0].open, _Digits) + ",";
   json += "\"high\":" + DoubleToString(rates[0].high, _Digits) + ",";
   json += "\"low\":" + DoubleToString(rates[0].low, _Digits) + ",";
   json += "\"close\":" + DoubleToString(rates[0].close, _Digits) + ",";
   json += "\"tickvol\":" + IntegerToString(rates[0].tick_volume) + ",";
   json += "\"spread\":" + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   json += "}\n";
   
   RF_SendData(json);
   RF_ReceiveData();
}

//+------------------------------------------------------------------+
//| Check if trade is allowed - MAIN FUNCTION FOR YOUR EA           |
//+------------------------------------------------------------------+
bool RF_IsTradeAllowed(string action)
{
   if(!g_rf_EnableFilter || !g_rf_connected)
      return true;  // Allow if filter disabled or not connected
   
   if(g_rf_socketHandle == INVALID_HANDLE)
      return true;
   
   // Reset the trade allowed flag before sending request
   g_rf_tradeAllowed = false;
   
   // SAFETY CHECK: Never trade when regime is -1 (no data / warming up)
   if(g_rf_currentRegime == -1 && g_rf_regimeConfidence == 0.0)
   {
      // Reduce log spam - print once per 10 seconds
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning >= 10)
      {
         Print("[REGIME FILTER] Trade BLOCKED - No regime data available yet (still warming up)");
         Print("  Symbol: ", _Symbol, " | Waiting for Python to process historical bars...");
         lastWarning = TimeCurrent();
      }
      return false;
   }
   
   // Send trade request with ea_name for per-EA filtering
   string json = "{";
   json += "\"type\":\"trade_request\",";
   json += "\"terminal\":\"" + g_rf_terminalName + "\",";
   json += "\"ea_name\":\"" + g_rf_eaName + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"action\":\"" + action + "\",";
   json += "\"account\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   json += "}\n";
   
   Print("[DEBUG] Sending trade request for action: ", action);
   RF_SendData(json);
   
   // Wait for response
   int attempts = 0;
   bool receivedResponse = false;
   
   while(attempts < 10 && g_rf_connected)
   {
      Sleep(100);
      RF_ReceiveData();
      
      if(g_rf_regimeConfidence > 0) 
      {
         receivedResponse = true;
         break;
      }
      
      attempts++;
   }
   
   Print("[DEBUG] Response received: ", (receivedResponse ? "YES" : "NO"), 
         ", TradeAllowed: ", (g_rf_tradeAllowed ? "TRUE" : "FALSE"),
         ", Regime: ", g_rf_currentRegime,
         ", Confidence: ", g_rf_regimeConfidence);
   
   return g_rf_tradeAllowed;
}

//+------------------------------------------------------------------+
//| Send data via socket                                             |
//+------------------------------------------------------------------+
bool RF_SendData(string data)
{
   if(g_rf_socketHandle == INVALID_HANDLE) return false;
   
   uchar sendArray[];
   int len = StringToCharArray(data, sendArray, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   
   if(len <= 0) return false;
   
   int sent = SocketSend(g_rf_socketHandle, sendArray, len);
   
   if(sent < 0)
   {
      g_rf_connected = false;
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Receive data from socket                                         |
//+------------------------------------------------------------------+
void RF_ReceiveData()
{
   if(g_rf_socketHandle == INVALID_HANDLE) return;
   
   uchar recvArray[];
   string response = "";
   uint timeout = 100;
   
   uint received = (uint)SocketIsReadable(g_rf_socketHandle);
   if(received > 0)
   {
      int bytes_read = SocketRead(g_rf_socketHandle, recvArray, (int)received, timeout);
      
      if(bytes_read > 0)
      {
         response = CharArrayToString(recvArray, 0, bytes_read, CP_UTF8);
         g_rf_receiveBuffer += response;
         
         int pos = StringFind(g_rf_receiveBuffer, "\n");
         while(pos >= 0)
         {
            string message = StringSubstr(g_rf_receiveBuffer, 0, pos);
            g_rf_receiveBuffer = StringSubstr(g_rf_receiveBuffer, pos + 1);
            
            if(StringLen(message) > 0)
               RF_ParseResponse(message);
            
            pos = StringFind(g_rf_receiveBuffer, "\n");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Parse response from Python                                       |
//+------------------------------------------------------------------+
void RF_ParseResponse(string json)
{
   Print("[DEBUG] Parsing response: ", json);
   
   int pos;
   
   // Extract allow_trade
   pos = StringFind(json, "\"allow_trade\":");
   if(pos >= 0)
   {
      string substr = StringSubstr(json, pos + 14);
      // Trim leading whitespace
      while(StringLen(substr) > 0 && (StringGetCharacter(substr, 0) == ' ' || StringGetCharacter(substr, 0) == '\t'))
      {
         substr = StringSubstr(substr, 1);
      }
      
      bool oldValue = g_rf_tradeAllowed;
      
      // Check for true/false
      if(StringFind(substr, "true") == 0)
         g_rf_tradeAllowed = true;
      else if(StringFind(substr, "false") == 0)
         g_rf_tradeAllowed = false;
      
      Print("[DEBUG] allow_trade found: substr='", StringSubstr(substr, 0, 20), "...', value=", (g_rf_tradeAllowed ? "TRUE" : "FALSE"));
   }
   else
   {
      Print("[DEBUG] allow_trade NOT found in JSON!");
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
         g_rf_currentRegime = (int)StringToInteger(regimeStr);
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
         g_rf_regimeConfidence = StringToDouble(confStr);
      }
   }
}

//+------------------------------------------------------------------+
//| Get current regime info - HELPER FUNCTIONS FOR YOUR EA          |
//+------------------------------------------------------------------+
int RF_GetCurrentRegime()
{
   return g_rf_currentRegime;
}

double RF_GetRegimeConfidence()
{
   return g_rf_regimeConfidence;
}

bool RF_IsRegimeFilterConnected()
{
   return g_rf_connected;
}

bool RF_IsTradeAllowedByRegime()
{
   return g_rf_tradeAllowed;
}

#ifndef RF_NO_COMPATIBILITY
// Backwards compatibility wrappers
bool InitRegimeFilter(string host = "127.0.0.1", int port = 9090, bool enable = true, string eaName = "")
{
   return RF_InitRegimeFilter(host, port, enable, eaName);
}
void DeinitRegimeFilter()
{
   RF_DeinitRegimeFilter();
}
void UpdateRegimeFilter()
{
   RF_UpdateRegimeFilter();
}
bool IsTradeAllowed(string action)
{
   return RF_IsTradeAllowed(action);
}
int GetCurrentRegime()
{
   return RF_GetCurrentRegime();
}
double GetRegimeConfidence()
{
   return RF_GetRegimeConfidence();
}
bool IsRegimeFilterConnected()
{
   return RF_IsRegimeFilterConnected();
}
bool IsTradeAllowedByRegime()
{
   return RF_IsTradeAllowedByRegime();
}
#endif
//+------------------------------------------------------------------+
