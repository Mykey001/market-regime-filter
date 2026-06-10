//+------------------------------------------------------------------+
//|                                          MT5_RegimeFilter.mq5    |
//|                              Market Regime Trading Filter EA     |
//|                                   Connects to Python GUI         |
//+------------------------------------------------------------------+
#property copyright "Market Regime System"
#property link      ""
#property version   "2.01"
#property strict

// Required for socket operations
#include <Trade\Trade.mqh>

//--- Input parameters
input string   PythonHost = "127.0.0.1";     // Python GUI Host
input int      PythonPort = 9090;             // Python GUI Port
input bool     EnableFilter = true;           // Enable regime filter

//--- Global variables
int socketHandle = INVALID_HANDLE;
datetime lastBarTime = 0;
int currentRegime = -1;
double regimeConfidence = 0.0;
bool tradeAllowed = false;
bool connected = false;
string terminalName = "";
string receiveBuffer = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Regime Filter EA initializing...");
   
   // Get terminal name for identification
   terminalName = TerminalInfoString(TERMINAL_NAME) + " - " + 
                  IntegerToString(TerminalInfoInteger(TERMINAL_BUILD));
   
   // Connect to Python GUI
   if(ConnectToGUI())
   {
      connected = true;
      Print("Connected to Python GUI at ", PythonHost, ":", PythonPort);
      
      // Send initial handshake with terminal info
      SendHandshake();
      
      // Send historical bars (last 700 bars to ensure warmup)
      SendHistoricalBars(700);
      
      // Send current bar
      SendCurrentBar();
   }
   else
   {
      Print("Failed to connect to Python GUI. Will retry on tick...");
      connected = false;
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Send historical bars for warmup                                  |
//+------------------------------------------------------------------+
void SendHistoricalBars(int count)
{
   Print("Sending ", count, " historical bars for warmup...");
   
   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M5, 0, count, rates);
   
   if(copied <= 0)
   {
      Print("Failed to get historical bars");
      return;
   }
   
   Print("Retrieved ", copied, " historical bars");
   
   // Send bars from oldest to newest
   for(int i = copied - 1; i >= 0; i--)
   {
      string json = "{";
      json += "\"type\":\"bar\",";
      json += "\"terminal\":\"" + terminalName + "\",";
      json += "\"symbol\":\"" + _Symbol + "\",";
      json += "\"time\":\"" + TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES) + "\",";
      json += "\"open\":" + DoubleToString(rates[i].open, _Digits) + ",";
      json += "\"high\":" + DoubleToString(rates[i].high, _Digits) + ",";
      json += "\"low\":" + DoubleToString(rates[i].low, _Digits) + ",";
      json += "\"close\":" + DoubleToString(rates[i].close, _Digits) + ",";
      json += "\"tickvol\":" + IntegerToString(rates[i].tick_volume) + ",";
      json += "\"spread\":" + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
      json += "}\n";
      
      SendData(json);
      
      // Small delay to avoid overwhelming the receiver
      if(i % 100 == 0)
      {
         Sleep(10);
         Print("Sent ", (copied - i), " / ", copied, " bars...");
      }
   }
   
   Print("Historical bars sent successfully!");
   
   // Try to receive any responses
   ReceiveData();
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Regime Filter EA shutting down...");
   
   if(socketHandle != INVALID_HANDLE)
   {
      SocketClose(socketHandle);
      socketHandle = INVALID_HANDLE;
   }
   
   connected = false;
}

//+------------------------------------------------------------------+
//| Connect to Python GUI                                            |
//+------------------------------------------------------------------+
bool ConnectToGUI()
{
   if(socketHandle != INVALID_HANDLE)
   {
      SocketClose(socketHandle);
      socketHandle = INVALID_HANDLE;
   }
   
   // Check if sockets are allowed
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      Print("Terminal not connected to trade server");
      return false;
   }
   
   socketHandle = SocketCreate();
   
   if(socketHandle == INVALID_HANDLE)
   {
      int error = GetLastError();
      Print("Failed to create socket. Error: ", error);
      Print("  Common causes:");
      Print("  - Check Tools->Options->Expert Advisors");
      Print("  - Allow automated trading must be enabled");
      Print("  - Allow DLL imports must be enabled");
      Print("  - Check antivirus is not blocking MT5");
      return false;
   }
   
   Print("Socket created successfully, attempting to connect to ", PythonHost, ":", PythonPort);
   
   if(!SocketConnect(socketHandle, PythonHost, PythonPort, 5000))
   {
      int error = GetLastError();
      Print("Failed to connect socket. Error: ", error);
      Print("  Host: ", PythonHost);
      Print("  Port: ", PythonPort);
      Print("  Make sure Python GUI is running and server is started!");
      SocketClose(socketHandle);
      socketHandle = INVALID_HANDLE;
      return false;
   }
   
   Print("Successfully connected to Python GUI!");
   return true;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check connection
   if(!connected || socketHandle == INVALID_HANDLE)
   {
      // Try to reconnect every 10 seconds
      static datetime lastAttempt = 0;
      if(TimeCurrent() - lastAttempt >= 10)
      {
         lastAttempt = TimeCurrent();
         if(ConnectToGUI())
         {
            connected = true;
            Print("Reconnected to Python GUI");
            SendHandshake();
         }
         else
         {
            connected = false;
         }
      }
      return;
   }
   
   // Check for new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      SendCurrentBar();
   }
}

//+------------------------------------------------------------------+
//| Send handshake with terminal info                                |
//+------------------------------------------------------------------+
void SendHandshake()
{
   if(socketHandle == INVALID_HANDLE)
      return;
   
   string json = "{";
   json += "\"type\":\"handshake\",";
   json += "\"terminal\":\"" + terminalName + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"account\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   json += "}\n";
   
   SendData(json);
}

//+------------------------------------------------------------------+
//| Send current bar data to Python                                  |
//+------------------------------------------------------------------+
void SendCurrentBar()
{
   if(socketHandle == INVALID_HANDLE)
      return;
   
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_M5, 0, 1, rates) <= 0)
   {
      Print("Failed to get bar data");
      return;
   }
   
   // Build JSON message
   string json = "{";
   json += "\"type\":\"bar\",";
   json += "\"terminal\":\"" + terminalName + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"time\":\"" + TimeToString(rates[0].time, TIME_DATE|TIME_MINUTES) + "\",";
   json += "\"open\":" + DoubleToString(rates[0].open, _Digits) + ",";
   json += "\"high\":" + DoubleToString(rates[0].high, _Digits) + ",";
   json += "\"low\":" + DoubleToString(rates[0].low, _Digits) + ",";
   json += "\"close\":" + DoubleToString(rates[0].close, _Digits) + ",";
   json += "\"tickvol\":" + IntegerToString(rates[0].tick_volume) + ",";
   json += "\"spread\":" + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   json += "}\n";
   
   SendData(json);
   
   // Try to receive response
   ReceiveData();
}

//+------------------------------------------------------------------+
//| Check if trade is allowed based on regime                        |
//+------------------------------------------------------------------+
bool IsTradeAllowed(string action)
{
   if(!EnableFilter || !connected)
      return true;  // Allow all trades if filter disabled or not connected
   
   if(socketHandle == INVALID_HANDLE)
      return true;  // Allow if not connected
   
   // Send trade request to Python
   string json = "{";
   json += "\"type\":\"trade_request\",";
   json += "\"terminal\":\"" + terminalName + "\",";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"action\":\"" + action + "\"";
   json += "}\n";
   
   SendData(json);
   
   // Wait for response (with timeout)
   int attempts = 0;
   while(attempts < 10 && connected)  // Max 1 second wait
   {
      Sleep(100);
      ReceiveData();
      
      if(regimeConfidence > 0)  // We got a response
         break;
      
      attempts++;
   }
   
   return tradeAllowed;
}

//+------------------------------------------------------------------+
//| Send data via socket                                             |
//+------------------------------------------------------------------+
bool SendData(string data)
{
   if(socketHandle == INVALID_HANDLE)
      return false;
   
   uchar sendArray[];
   int len = StringToCharArray(data, sendArray, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   
   if(len <= 0)
      return false;
   
   int sent = SocketSend(socketHandle, sendArray, len);
   
   if(sent < 0)
   {
      Print("Socket send error: ", GetLastError());
      connected = false;
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Receive data from socket                                         |
//+------------------------------------------------------------------+
void ReceiveData()
{
   if(socketHandle == INVALID_HANDLE)
      return;
   
   uchar recvArray[];
   string response = "";
   uint timeout = 100;
   
   int received = SocketIsReadable(socketHandle);
   if(received > 0)
   {
      received = SocketRead(socketHandle, recvArray, received, timeout);
      
      if(received > 0)
      {
         response = CharArrayToString(recvArray, 0, received, CP_UTF8);
         receiveBuffer += response;
         
         // Process complete JSON messages (ending with \n)
         int pos = StringFind(receiveBuffer, "\n");
         while(pos >= 0)
         {
            string message = StringSubstr(receiveBuffer, 0, pos);
            receiveBuffer = StringSubstr(receiveBuffer, pos + 1);
            
            if(StringLen(message) > 0)
            {
               ParseResponse(message);
            }
            
            pos = StringFind(receiveBuffer, "\n");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Parse response from Python                                       |
//+------------------------------------------------------------------+
void ParseResponse(string json)
{
   // Simple JSON parsing (you may want to use a proper JSON library)
   // This is a basic implementation
   
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
         currentRegime = (int)StringToInteger(regimeStr);
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
         regimeConfidence = StringToDouble(confStr);
      }
   }
   
   Comment("Regime: ", currentRegime, " | Confidence: ", 
           DoubleToString(regimeConfidence * 100, 1), "% | ",
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
   // ...
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
   // ...
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
