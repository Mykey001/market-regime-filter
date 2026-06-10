//+------------------------------------------------------------------+
//|                                      INTEGRATION_EXAMPLES.mq5    |
//|                     How to Integrate Regime Filter with Any EA   |
//+------------------------------------------------------------------+

/*
   This file shows 3 different integration methods.
   Choose the one that fits your EA best.
*/

//+------------------------------------------------------------------+
//  METHOD 1: INCLUDE THE FILTER EA (Simplest)
//+------------------------------------------------------------------+

#property copyright "Integration Examples"
#property version   "1.00"

// Include the regime filter functions
#include "MT5_RegimeFilter.mq5"

//--- Your EA's existing inputs
input double LotSize = 0.1;
input int StopLoss = 50;
input int TakeProfit = 100;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    // Your EA's initialization code
    Print("My Trading EA initializing...");
    
    // The filter will auto-connect in the background
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function - METHOD 1: Simple Check                    |
//+------------------------------------------------------------------+
void OnTick_Method1()
{
    // Your existing trading logic
    bool BuySignal = CheckBuyConditions();
    bool SellSignal = CheckSellConditions();
    
    // JUST ADD THIS: Check regime filter before trading
    if(BuySignal && IsTradeAllowed("buy"))
    {
        // Your normal buy code
        double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double sl = price - StopLoss * _Point;
        double tp = price + TakeProfit * _Point;
        
        // Your OrderSend code
        // trade.Buy(LotSize, _Symbol, price, sl, tp, "Regime Approved");
        
        Print("BUY trade executed (Regime: ", GetCurrentRegime(), 
              ", Confidence: ", DoubleToString(GetRegimeConfidence() * 100, 1), "%)");
    }
    
    if(SellSignal && IsTradeAllowed("sell"))
    {
        // Your normal sell code
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double sl = price + StopLoss * _Point;
        double tp = price - TakeProfit * _Point;
        
        // Your OrderSend code
        // trade.Sell(LotSize, _Symbol, price, sl, tp, "Regime Approved");
        
        Print("SELL trade executed (Regime: ", GetCurrentRegime(), 
              ", Confidence: ", DoubleToString(GetRegimeConfidence() * 100, 1), "%)");
    }
}

//+------------------------------------------------------------------+
//| METHOD 2: Check Regime Before Trade Logic                        |
//+------------------------------------------------------------------+
void OnTick_Method2()
{
    // Check regime FIRST before even analyzing signals
    // This saves CPU time if regime doesn't allow trading
    
    if(!IsTradeAllowedByRegime())
    {
        // Don't even check signals in bad regimes
        return;
    }
    
    // Now check your trading signals
    bool BuySignal = CheckBuyConditions();
    bool SellSignal = CheckSellConditions();
    
    if(BuySignal)
    {
        // Execute buy
        Print("Buy signal in good regime - executing");
    }
    
    if(SellSignal)
    {
        // Execute sell
        Print("Sell signal in good regime - executing");
    }
}

//+------------------------------------------------------------------+
//| METHOD 3: Regime-Specific Strategy                               |
//+------------------------------------------------------------------+
void OnTick_Method3()
{
    // Use DIFFERENT strategies for DIFFERENT regimes
    
    int regime = GetCurrentRegime();
    double confidence = GetRegimeConfidence();
    
    // Only trade if confident
    if(confidence < 0.6)
    {
        Print("Low confidence regime - skipping");
        return;
    }
    
    // Strategy selection based on regime
    switch(regime)
    {
        case 1:  // Normal/Calm - Use Mean Reversion
            MeanReversionStrategy();
            break;
            
        case 3:  // Bullish Trending - Follow Trend
            TrendFollowingStrategy(true);  // Bullish
            break;
            
        case 7:  // Bearish Trending - Follow Trend
            TrendFollowingStrategy(false); // Bearish
            break;
            
        case 8:  // Bullish Momentum - Aggressive Buy
            MomentumStrategy(true);
            break;
            
        case 4:  // Extreme Vol Spike - Stay Out
        case 5:  // Crisis Mode - Stay Out
        case 9:  // Choppy/Erratic - Stay Out
            Print("Dangerous regime - no trading");
            break;
            
        default:
            // Default strategy for other regimes
            StandardStrategy();
            break;
    }
}

//+------------------------------------------------------------------+
//| Example Strategy Functions                                        |
//+------------------------------------------------------------------+

void MeanReversionStrategy()
{
    Print("Using Mean Reversion Strategy");
    // Buy when oversold, sell when overbought
    // Your mean reversion logic here
}

void TrendFollowingStrategy(bool bullish)
{
    if(bullish)
    {
        Print("Using Bullish Trend Following");
        // Only look for buy signals
    }
    else
    {
        Print("Using Bearish Trend Following");
        // Only look for sell signals
    }
}

void MomentumStrategy(bool bullish)
{
    Print("Using Momentum Strategy");
    // Aggressive entries with wider stops
}

void StandardStrategy()
{
    Print("Using Standard Strategy");
    // Your normal strategy
}

//+------------------------------------------------------------------+
//| Your existing signal functions                                    |
//+------------------------------------------------------------------+

bool CheckBuyConditions()
{
    // Your existing buy signal logic
    // Example: MA crossover, RSI oversold, etc.
    return false;  // Replace with your logic
}

bool CheckSellConditions()
{
    // Your existing sell signal logic
    return false;  // Replace with your logic
}

//+------------------------------------------------------------------+
//| Main OnTick - Choose which method to use                         |
//+------------------------------------------------------------------+
void OnTick()
{
    // Uncomment the method you want to use:
    
    // OnTick_Method1();  // Simple check before trades
    // OnTick_Method2();  // Check regime first
    // OnTick_Method3();  // Regime-specific strategies
}
//+------------------------------------------------------------------+
