//+------------------------------------------------------------------+
//|                                      test_connection_simple.mq5  |
//|                          Simple test of regime filter connection |
//+------------------------------------------------------------------+
#property copyright "Test"
#property version   "1.00"
#property strict

#include "EAs to add filter/RegimeFilterLib.mqh"

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("SIMPLE CONNECTION TEST");
   Print("========================================");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", EnumToString(PERIOD_M5));
   Print("");
   
   // Test 1: Initialize connection
   Print("TEST 1: Initializing connection...");
   bool connected = InitRegimeFilter("127.0.0.1", 9090, true);
   
   if(connected)
   {
      Print("  SUCCESS: Connected to Python GUI");
   }
   else
   {
      Print("  FAILED: Could not connect to Python GUI");
      Print("  Make sure Python GUI is running and server is started!");
      return(INIT_FAILED);
   }
   
   Print("");
   Print("TEST 2: Connection status...");
   Print("  Connected: ", IsRegimeFilterConnected() ? "YES" : "NO");
   Print("  Current regime: ", GetCurrentRegime());
   Print("  Confidence: ", GetRegimeConfidence() * 100, "%");
   
   Print("");
   Print("========================================");
   Print("Initialization complete");
   Print("Watch for bar sending messages above");
   Print("Should see: 'Sending 1300 historical bars...'");
   Print("========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeinitRegimeFilter();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static bool first_tick = true;
   if(first_tick)
   {
      first_tick = false;
      Print("");
      Print("First tick received");
      Print("  Current regime: ", GetCurrentRegime());
      Print("  Connected: ", IsRegimeFilterConnected() ? "YES" : "NO");
      
      if(GetCurrentRegime() == -1)
      {
         Print("");
         Print("WARNING: Still no regime prediction!");
         Print("If you see 'Sending 1300 historical bars...' above, wait 15 seconds.");
         Print("If you DON'T see that message, there's a problem with InitRegimeFilter.");
      }
   }
   
   UpdateRegimeFilter();
}
//+------------------------------------------------------------------+
