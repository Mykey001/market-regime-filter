//+------------------------------------------------------------------+
//|                                           ICCExpertAdvisor.mq5   |
//|                                  ICC Price Action Trading System |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "ICC Expert Advisor"
#property link      ""
#property version   "1.00"
#property description "Institutional Price Action EA - Indication, Correction, Continuation"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

// Timeframe Settings
input ENUM_TIMEFRAMES InpHTF = PERIOD_H1;              // Higher Timeframe (Context)
input ENUM_TIMEFRAMES InpLTF = PERIOD_M15;             // Lower Timeframe (Execution)

// Structure Detection
input int InpSwingLookback = 5;                        // Swing Point Lookback Bars

// Entry Filters
input bool InpEquilibriumFilter = true;                // Enable Equilibrium Zone Filter
input double InpMinADRVolatility = 50.0;               // Minimum ADR Volatility (%)
input int InpNewsBlockMinutes = 60;                    // News Block Window (minutes)
input bool InpEnableAsianSession = false;              // Enable Asian Session (19:00-22:00 EST)
input bool InpEnableLondonSession = true;              // Enable London Session (02:00-05:00 EST)
input bool InpEnableNYSession = true;                  // Enable New York Session (07:00-10:00 EST)
input bool InpEnableHAFilter = false;                  // Enable Heikin-Ashi Trend Filter

// Risk Management
input double InpRiskPercent = 1.0;                     // Risk Per Trade (%)
input double InpPartialClosePercent = 50.0;            // Partial Close at TP (%)
input int InpMaxSpreadPoints = 20;                     // Maximum Spread (points)
input int InpMaxSlippagePoints = 5;                    // Maximum Slippage (points)

// Trade Management
input int InpCooldownMinutes = 60;                     // Cooldown After Trade (minutes)
input double InpStrongMoveThresholdPips = 20.0;        // Strong Move Threshold for Order Blocks (pips)

// Visual and Logging
input bool InpEnableVisualDebug = true;                // Enable Visual Debugging
input int InpLoggingVerbosity = 2;                     // Logging Level (0=Errors, 1=Warnings, 2=Info, 3=Debug)

//+------------------------------------------------------------------+
//| Core Data Structures                                              |
//+------------------------------------------------------------------+

// Swing Point Structure
struct SwingPoint {
    double price;
    datetime time;
    int bar_index;
    bool is_high;  // true for swing high, false for swing low
    
    void Reset() {
        price = 0.0;
        time = 0;
        bar_index = -1;
        is_high = false;
    }
    
    bool IsValid() {
        return (bar_index >= 0 && price > 0.0);
    }
};

// No Trade Zone Structure
struct NoTradeZone {
    double upper_boundary;  // Swing high
    double lower_boundary;  // Swing low
    datetime created_time;
    bool is_valid;
    
    void Reset() {
        upper_boundary = 0.0;
        lower_boundary = 0.0;
        created_time = 0;
        is_valid = false;
    }
    
    bool IsPriceInZone(double price) {
        return (is_valid && price >= lower_boundary && price <= upper_boundary);
    }
};

// BOS Signal Types
enum BOS_TYPE {
    BOS_NONE,
    BOS_BULLISH,
    BOS_BEARISH,
    BOS_LIQUIDITY_SWEEP
};

// BOS Signal Structure
struct BOSSignal {
    BOS_TYPE type;
    double draw_on_liquidity;  // Extreme price reached
    datetime time;
    int bar_index;
    
    void Reset() {
        type = BOS_NONE;
        draw_on_liquidity = 0.0;
        time = 0;
        bar_index = -1;
    }
    
    bool IsValid() {
        return (type == BOS_BULLISH || type == BOS_BEARISH);
    }
};

// CHoCH Signal Types
enum CHOCH_TYPE {
    CHOCH_NONE,
    CHOCH_BULLISH,
    CHOCH_BEARISH
};

// CHoCH Signal Structure
struct CHoCHSignal {
    CHOCH_TYPE type;
    double break_level;
    datetime time;
    int bar_index;
    
    void Reset() {
        type = CHOCH_NONE;
        break_level = 0.0;
        time = 0;
        bar_index = -1;
    }
    
    bool IsValid() {
        return (type == CHOCH_BULLISH || type == CHOCH_BEARISH);
    }
};

// Equilibrium Zones Structure
struct EquilibriumZones {
    double equilibrium_price;     // 50% level
    double premium_upper;         // Upper boundary (for bearish entries)
    double premium_lower;         // Equilibrium
    double discount_upper;        // Equilibrium
    double discount_lower;        // Lower boundary (for bullish entries)
    
    void Reset() {
        equilibrium_price = 0.0;
        premium_upper = 0.0;
        premium_lower = 0.0;
        discount_upper = 0.0;
        discount_lower = 0.0;
    }
    
    bool IsPriceInDiscountZone(double price) {
        return (price >= discount_lower && price <= discount_upper);
    }
    
    bool IsPriceInPremiumZone(double price) {
        return (price >= premium_lower && price <= premium_upper);
    }
};

// Fair Value Gap Structure
struct FairValueGap {
    double upper_boundary;
    double lower_boundary;
    datetime time;
    bool is_bullish;
    bool is_filled;
    
    void Reset() {
        upper_boundary = 0.0;
        lower_boundary = 0.0;
        time = 0;
        is_bullish = false;
        is_filled = false;
    }
    
    bool IsValid() {
        return (upper_boundary > lower_boundary && time > 0);
    }
};

// Order Block Structure
struct OrderBlock {
    double high;
    double low;
    double body_high;  // close or open, whichever is higher
    double body_low;   // close or open, whichever is lower
    datetime time;
    bool is_bullish;
    
    void Reset() {
        high = 0.0;
        low = 0.0;
        body_high = 0.0;
        body_low = 0.0;
        time = 0;
        is_bullish = false;
    }
    
    bool IsValid() {
        return (high > low && time > 0);
    }
};

// EA State Machine States
enum EA_STATE {
    STATE_INITIALIZING,
    STATE_IDLE_ZONE_SEARCH,
    STATE_AWAITING_INDICATION,
    STATE_MONITORING_CORRECTION,
    STATE_AWAITING_CONTINUATION,
    STATE_ACTIVE_TRADE,
    STATE_COOLDOWN
};

// State Context Structure
struct StateContext {
    EA_STATE current_state;
    NoTradeZone zone;
    BOSSignal bos;
    CHoCHSignal choch;
    EquilibriumZones eq_zones;
    datetime cooldown_end_time;
    datetime last_state_change;
    
    void Reset() {
        current_state = STATE_INITIALIZING;
        zone.Reset();
        bos.Reset();
        choch.Reset();
        eq_zones.Reset();
        cooldown_end_time = 0;
        last_state_change = 0;
    }
};

// Risk Parameters Structure
struct RiskParameters {
    double entry_price;
    double stop_loss;
    double take_profit;
    double lot_size;
    double risk_amount;
    double reward_amount;
    double risk_reward_ratio;
    
    void Reset() {
        entry_price = 0.0;
        stop_loss = 0.0;
        take_profit = 0.0;
        lot_size = 0.0;
        risk_amount = 0.0;
        reward_amount = 0.0;
        risk_reward_ratio = 0.0;
    }
    
    bool IsValid() {
        return (lot_size > 0.0 && stop_loss > 0.0 && take_profit > 0.0);
    }
};

// Symbol Information Cache Structure
struct SymbolInfo {
    double point;
    double tick_size;
    double tick_value;
    double min_lot;
    double max_lot;
    double lot_step;
    int stops_level;
    int digits;
    string name;
    
    void Reset() {
        point = 0.0;
        tick_size = 0.0;
        tick_value = 0.0;
        min_lot = 0.0;
        max_lot = 0.0;
        lot_step = 0.0;
        stops_level = 0;
        digits = 0;
        name = "";
    }
    
    bool LoadSymbolInfo(string symbol) {
        name = symbol;
        point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        
        return (point > 0.0 && tick_value > 0.0);
    }
};

//+------------------------------------------------------------------+
//| CTimeframeManager Class                                           |
//+------------------------------------------------------------------+
class CTimeframeManager {
private:
    ENUM_TIMEFRAMES m_htf;
    ENUM_TIMEFRAMES m_ltf;
    datetime m_last_htf_bar_time;
    datetime m_last_ltf_bar_time;
    string m_symbol;
    bool m_initialized;
    
public:
    // Constructor
    CTimeframeManager() {
        m_htf = PERIOD_CURRENT;
        m_ltf = PERIOD_CURRENT;
        m_last_htf_bar_time = 0;
        m_last_ltf_bar_time = 0;
        m_symbol = "";
        m_initialized = false;
    }
    
    // Initialize with timeframe validation (LTF < HTF)
    bool Initialize(ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES ltf, string symbol = NULL) {
        LogDebug("CTimeframeManager::Initialize() - HTF: " + EnumToString(htf) + ", LTF: " + EnumToString(ltf));
        
        // Use current symbol if not specified
        if(symbol == NULL || symbol == "") {
            m_symbol = _Symbol;
        } else {
            m_symbol = symbol;
        }
        
        // Validate timeframes
        if(!ValidateTimeframes(htf, ltf)) {
            LogError("CTimeframeManager::Initialize() - Timeframe validation failed");
            return false;
        }
        
        m_htf = htf;
        m_ltf = ltf;
        
        // Initialize bar times
        m_last_htf_bar_time = iTime(m_symbol, m_htf, 0);
        m_last_ltf_bar_time = iTime(m_symbol, m_ltf, 0);
        
        if(m_last_htf_bar_time == 0 || m_last_ltf_bar_time == 0) {
            LogError("CTimeframeManager::Initialize() - Failed to get initial bar times");
            return false;
        }
        
        m_initialized = true;
        LogInfo("CTimeframeManager initialized successfully");
        return true;
    }
    
    // Validate that LTF < HTF
    bool ValidateTimeframes(ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES ltf) {
        // Convert timeframes to minutes for comparison
        int htf_minutes = PeriodSeconds(htf) / 60;
        int ltf_minutes = PeriodSeconds(ltf) / 60;
        
        if(ltf_minutes >= htf_minutes) {
            LogError("ValidateTimeframes() - LTF must be smaller than HTF");
            LogError("LTF: " + EnumToString(ltf) + " (" + IntegerToString(ltf_minutes) + " min), " +
                    "HTF: " + EnumToString(htf) + " (" + IntegerToString(htf_minutes) + " min)");
            return false;
        }
        
        LogDebug("ValidateTimeframes() - Validation passed. LTF: " + IntegerToString(ltf_minutes) + 
                " min < HTF: " + IntegerToString(htf_minutes) + " min");
        return true;
    }
    
    // Get HTF bars using CopyRates
    bool GetHTFBars(MqlRates &bars[], int count) {
        if(!m_initialized) {
            LogError("GetHTFBars() - Manager not initialized");
            return false;
        }
        
        if(count <= 0) {
            LogError("GetHTFBars() - Invalid count: " + IntegerToString(count));
            return false;
        }
        
        ArraySetAsSeries(bars, true);
        int copied = CopyRates(m_symbol, m_htf, 0, count, bars);
        
        if(copied < 0) {
            int error = GetLastError();
            LogError("GetHTFBars() - CopyRates failed. Error: " + IntegerToString(error));
            return false;
        }
        
        if(copied < count) {
            LogWarning("GetHTFBars() - Requested " + IntegerToString(count) + 
                      " bars, but only " + IntegerToString(copied) + " available");
        }
        
        LogDebug("GetHTFBars() - Successfully copied " + IntegerToString(copied) + " bars");
        return (copied > 0);
    }
    
    // Get LTF bars using CopyRates
    bool GetLTFBars(MqlRates &bars[], int count) {
        if(!m_initialized) {
            LogError("GetLTFBars() - Manager not initialized");
            return false;
        }
        
        if(count <= 0) {
            LogError("GetLTFBars() - Invalid count: " + IntegerToString(count));
            return false;
        }
        
        ArraySetAsSeries(bars, true);
        int copied = CopyRates(m_symbol, m_ltf, 0, count, bars);
        
        if(copied < 0) {
            int error = GetLastError();
            LogError("GetLTFBars() - CopyRates failed. Error: " + IntegerToString(error));
            return false;
        }
        
        if(copied < count) {
            LogWarning("GetLTFBars() - Requested " + IntegerToString(count) + 
                      " bars, but only " + IntegerToString(copied) + " available");
        }
        
        LogDebug("GetLTFBars() - Successfully copied " + IntegerToString(copied) + " bars");
        return (copied > 0);
    }
    
    // Get HTF bar time at specific shift
    datetime GetHTFBarTime(int shift) {
        if(!m_initialized) {
            LogError("GetHTFBarTime() - Manager not initialized");
            return 0;
        }
        
        datetime time = iTime(m_symbol, m_htf, shift);
        if(time == 0) {
            LogError("GetHTFBarTime() - Failed to get bar time at shift " + IntegerToString(shift));
        }
        return time;
    }
    
    // Get LTF bar time at specific shift
    datetime GetLTFBarTime(int shift) {
        if(!m_initialized) {
            LogError("GetLTFBarTime() - Manager not initialized");
            return 0;
        }
        
        datetime time = iTime(m_symbol, m_ltf, shift);
        if(time == 0) {
            LogError("GetLTFBarTime() - Failed to get bar time at shift " + IntegerToString(shift));
        }
        return time;
    }
    
    // Detect new HTF bar formation
    bool IsNewHTFBar() {
        if(!m_initialized) {
            return false;
        }
        
        datetime current_bar_time = iTime(m_symbol, m_htf, 0);
        
        if(current_bar_time == 0) {
            LogError("IsNewHTFBar() - Failed to get current bar time");
            return false;
        }
        
        if(current_bar_time != m_last_htf_bar_time) {
            LogDebug("IsNewHTFBar() - New HTF bar detected. Time: " + TimeToString(current_bar_time));
            m_last_htf_bar_time = current_bar_time;
            return true;
        }
        
        return false;
    }
    
    // Detect new LTF bar formation
    bool IsNewLTFBar() {
        if(!m_initialized) {
            return false;
        }
        
        datetime current_bar_time = iTime(m_symbol, m_ltf, 0);
        
        if(current_bar_time == 0) {
            LogError("IsNewLTFBar() - Failed to get current bar time");
            return false;
        }
        
        if(current_bar_time != m_last_ltf_bar_time) {
            LogDebug("IsNewLTFBar() - New LTF bar detected. Time: " + TimeToString(current_bar_time));
            m_last_ltf_bar_time = current_bar_time;
            return true;
        }
        
        return false;
    }
    
    // Convert HTF shift to approximate LTF shift
    int ConvertHTFShiftToLTF(int htf_shift) {
        if(!m_initialized) {
            return -1;
        }
        
        // Get the time of the HTF bar
        datetime htf_time = iTime(m_symbol, m_htf, htf_shift);
        if(htf_time == 0) {
            LogError("ConvertHTFShiftToLTF() - Failed to get HTF bar time");
            return -1;
        }
        
        // Find the corresponding LTF bar
        int ltf_shift = iBarShift(m_symbol, m_ltf, htf_time);
        if(ltf_shift < 0) {
            LogError("ConvertHTFShiftToLTF() - Failed to find LTF bar for HTF time");
            return -1;
        }
        
        return ltf_shift;
    }
    
    // Getters
    ENUM_TIMEFRAMES GetHTF() const { return m_htf; }
    ENUM_TIMEFRAMES GetLTF() const { return m_ltf; }
    string GetSymbol() const { return m_symbol; }
    bool IsInitialized() const { return m_initialized; }
};

//+------------------------------------------------------------------+
//| CSwingDetector Class                                              |
//+------------------------------------------------------------------+
class CSwingDetector {
private:
    int m_lookback;
    SwingPoint m_last_high;
    SwingPoint m_last_low;
    bool m_initialized;
    
public:
    // Constructor
    CSwingDetector() {
        m_lookback = 0;
        m_last_high.Reset();
        m_last_low.Reset();
        m_initialized = false;
    }
    
    // Initialize with lookback period (must be >= 2)
    bool Initialize(int lookback_bars) {
        LogDebug("CSwingDetector::Initialize() - Lookback: " + IntegerToString(lookback_bars));
        
        if(lookback_bars < 2) {
            LogError("CSwingDetector::Initialize() - Lookback must be at least 2");
            return false;
        }
        
        m_lookback = lookback_bars;
        m_last_high.Reset();
        m_last_low.Reset();
        m_initialized = true;
        
        LogInfo("CSwingDetector initialized successfully with lookback: " + IntegerToString(m_lookback));
        return true;
    }
    
    // Find swing high at specific index using N-bar lookback algorithm
    // Returns a SwingPoint with bar_index = -1 if no swing high found
    // Requirement 2.1: Swing high where high > N bars before AND after
    SwingPoint FindSwingHigh(const MqlRates &bars[], int start_index) {
        SwingPoint swing;
        swing.Reset();
        
        if(!m_initialized) {
            LogError("FindSwingHigh() - Detector not initialized");
            return swing;
        }
        
        int array_size = ArraySize(bars);
        
        // Need at least N bars before and after the candidate bar
        if(start_index < m_lookback || start_index >= array_size - m_lookback) {
            LogDebug("FindSwingHigh() - Index " + IntegerToString(start_index) + 
                    " out of valid range [" + IntegerToString(m_lookback) + ", " + 
                    IntegerToString(array_size - m_lookback - 1) + "]");
            return swing;
        }
        
        double candidate_high = bars[start_index].high;
        bool is_swing = true;
        
        // Check N bars before
        for(int i = start_index - m_lookback; i < start_index; i++) {
            if(bars[i].high >= candidate_high) {
                is_swing = false;
                break;
            }
        }
        
        // Check N bars after (only if still valid)
        if(is_swing) {
            for(int i = start_index + 1; i <= start_index + m_lookback; i++) {
                if(bars[i].high >= candidate_high) {
                    is_swing = false;
                    break;
                }
            }
        }
        
        // If valid swing high found, populate the structure
        if(is_swing) {
            swing.price = candidate_high;
            swing.time = bars[start_index].time;
            swing.bar_index = start_index;
            swing.is_high = true;
            
            LogDebug("FindSwingHigh() - Swing high found at index " + IntegerToString(start_index) + 
                    ", price: " + DoubleToString(candidate_high, _Digits));
        }
        
        return swing;
    }
    
    // Find swing low at specific index using N-bar lookback algorithm
    // Returns a SwingPoint with bar_index = -1 if no swing low found
    // Requirement 2.2: Swing low where low < N bars before AND after
    SwingPoint FindSwingLow(const MqlRates &bars[], int start_index) {
        SwingPoint swing;
        swing.Reset();
        
        if(!m_initialized) {
            LogError("FindSwingLow() - Detector not initialized");
            return swing;
        }
        
        int array_size = ArraySize(bars);
        
        // Need at least N bars before and after the candidate bar
        if(start_index < m_lookback || start_index >= array_size - m_lookback) {
            LogDebug("FindSwingLow() - Index " + IntegerToString(start_index) + 
                    " out of valid range [" + IntegerToString(m_lookback) + ", " + 
                    IntegerToString(array_size - m_lookback - 1) + "]");
            return swing;
        }
        
        double candidate_low = bars[start_index].low;
        bool is_swing = true;
        
        // Check N bars before
        for(int i = start_index - m_lookback; i < start_index; i++) {
            if(bars[i].low <= candidate_low) {
                is_swing = false;
                break;
            }
        }
        
        // Check N bars after (only if still valid)
        if(is_swing) {
            for(int i = start_index + 1; i <= start_index + m_lookback; i++) {
                if(bars[i].low <= candidate_low) {
                    is_swing = false;
                    break;
                }
            }
        }
        
        // If valid swing low found, populate the structure
        if(is_swing) {
            swing.price = candidate_low;
            swing.time = bars[start_index].time;
            swing.bar_index = start_index;
            swing.is_high = false;
            
            LogDebug("FindSwingLow() - Swing low found at index " + IntegerToString(start_index) + 
                    ", price: " + DoubleToString(candidate_low, _Digits));
        }
        
        return swing;
    }
    
    // Update swing points by scanning HTF bars
    // Requirements 2.4, 2.5: Track most recent swing high and low, update only when new valid swings form
    bool UpdateSwingPoints(const MqlRates &htf_bars[]) {
        if(!m_initialized) {
            LogError("UpdateSwingPoints() - Detector not initialized");
            return false;
        }
        
        int array_size = ArraySize(htf_bars);
        if(array_size < (2 * m_lookback + 1)) {
            LogWarning("UpdateSwingPoints() - Insufficient bars. Need at least " + 
                      IntegerToString(2 * m_lookback + 1) + ", have " + IntegerToString(array_size));
            return false;
        }
        
        bool updated = false;
        
        // Scan for most recent swing high
        // Start from the earliest possible swing point (requires N bars after)
        // Arrays are series (index 0 = most recent), so we scan from higher indices to lower
        for(int i = array_size - m_lookback - 1; i >= m_lookback; i--) {
            SwingPoint swing_high = FindSwingHigh(htf_bars, i);
            
            if(swing_high.IsValid()) {
                // Update if this is a new swing or more recent than the last one
                if(!m_last_high.IsValid() || swing_high.time > m_last_high.time) {
                    m_last_high = swing_high;
                    LogInfo("UpdateSwingPoints() - New swing high detected at " + 
                           TimeToString(swing_high.time) + ", price: " + 
                           DoubleToString(swing_high.price, _Digits));
                    updated = true;
                }
                break; // Found the most recent swing high
            }
        }
        
        // Scan for most recent swing low
        for(int i = array_size - m_lookback - 1; i >= m_lookback; i--) {
            SwingPoint swing_low = FindSwingLow(htf_bars, i);
            
            if(swing_low.IsValid()) {
                // Update if this is a new swing or more recent than the last one
                if(!m_last_low.IsValid() || swing_low.time > m_last_low.time) {
                    m_last_low = swing_low;
                    LogInfo("UpdateSwingPoints() - New swing low detected at " + 
                           TimeToString(swing_low.time) + ", price: " + 
                           DoubleToString(swing_low.price, _Digits));
                    updated = true;
                }
                break; // Found the most recent swing low
            }
        }
        
        if(updated) {
            LogDebug("UpdateSwingPoints() - Swing points updated successfully");
        } else {
            LogDebug("UpdateSwingPoints() - No new swing points found");
        }
        
        return updated;
    }
    
    // Get the last detected swing high
    SwingPoint GetLastSwingHigh() const {
        return m_last_high;
    }
    
    // Get the last detected swing low
    SwingPoint GetLastSwingLow() const {
        return m_last_low;
    }
    
    // Check if detector is initialized
    bool IsInitialized() const {
        return m_initialized;
    }
    
    // Get lookback value
    int GetLookback() const {
        return m_lookback;
    }
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
StateContext g_state;
SymbolInfo g_symbol;
CTimeframeManager* g_timeframe_manager = NULL;
CSwingDetector* g_swing_detector = NULL;

//+------------------------------------------------------------------+
//| Logging Utility Functions                                         |
//+------------------------------------------------------------------+

// Log levels
enum LOG_LEVEL {
    LOG_ERROR = 0,
    LOG_WARNING = 1,
    LOG_INFO = 2,
    LOG_DEBUG = 3
};

// Log message with verbosity control
void Log(LOG_LEVEL level, string message) {
    if(level <= InpLoggingVerbosity) {
        string prefix = "";
        switch(level) {
            case LOG_ERROR:   prefix = "[ERROR] "; break;
            case LOG_WARNING: prefix = "[WARN]  "; break;
            case LOG_INFO:    prefix = "[INFO]  "; break;
            case LOG_DEBUG:   prefix = "[DEBUG] "; break;
        }
        Print(prefix + message);
    }
}

// Convenience logging functions
void LogError(string message)   { Log(LOG_ERROR, message); }
void LogWarning(string message) { Log(LOG_WARNING, message); }
void LogInfo(string message)    { Log(LOG_INFO, message); }
void LogDebug(string message)   { Log(LOG_DEBUG, message); }

// Get state name as string
string GetStateName(EA_STATE state) {
    switch(state) {
        case STATE_INITIALIZING:          return "INITIALIZING";
        case STATE_IDLE_ZONE_SEARCH:      return "IDLE_ZONE_SEARCH";
        case STATE_AWAITING_INDICATION:   return "AWAITING_INDICATION";
        case STATE_MONITORING_CORRECTION: return "MONITORING_CORRECTION";
        case STATE_AWAITING_CONTINUATION: return "AWAITING_CONTINUATION";
        case STATE_ACTIVE_TRADE:          return "ACTIVE_TRADE";
        case STATE_COOLDOWN:              return "COOLDOWN";
        default:                          return "UNKNOWN";
    }
}

// Get BOS type as string
string GetBOSTypeName(BOS_TYPE type) {
    switch(type) {
        case BOS_NONE:            return "NONE";
        case BOS_BULLISH:         return "BULLISH";
        case BOS_BEARISH:         return "BEARISH";
        case BOS_LIQUIDITY_SWEEP: return "LIQUIDITY_SWEEP";
        default:                  return "UNKNOWN";
    }
}

// Get CHoCH type as string
string GetCHoCHTypeName(CHOCH_TYPE type) {
    switch(type) {
        case CHOCH_NONE:     return "NONE";
        case CHOCH_BULLISH:  return "BULLISH";
        case CHOCH_BEARISH:  return "BEARISH";
        default:             return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
    LogInfo("=== ICC Expert Advisor Initialization ===");
    
    // Reset global state
    g_state.Reset();
    g_symbol.Reset();
    
    // Validate input parameters
    if(!ValidateInputParameters()) {
        LogError("Input parameter validation failed. EA will not operate.");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    // Load symbol information
    if(!g_symbol.LoadSymbolInfo(_Symbol)) {
        LogError("Failed to load symbol information for " + _Symbol);
        return INIT_FAILED;
    }
    
    LogInfo("Symbol: " + g_symbol.name);
    LogInfo("Point: " + DoubleToString(g_symbol.point, g_symbol.digits));
    LogInfo("Min Lot: " + DoubleToString(g_symbol.min_lot, 2));
    LogInfo("Max Lot: " + DoubleToString(g_symbol.max_lot, 2));
    LogInfo("Lot Step: " + DoubleToString(g_symbol.lot_step, 2));
    
    // Initialize Timeframe Manager
    g_timeframe_manager = new CTimeframeManager();
    if(!g_timeframe_manager.Initialize(InpHTF, InpLTF, _Symbol)) {
        LogError("Failed to initialize Timeframe Manager");
        delete g_timeframe_manager;
        g_timeframe_manager = NULL;
        return INIT_FAILED;
    }
    
    // Initialize Swing Detector
    g_swing_detector = new CSwingDetector();
    if(!g_swing_detector.Initialize(InpSwingLookback)) {
        LogError("Failed to initialize Swing Detector");
        delete g_timeframe_manager;
        g_timeframe_manager = NULL;
        delete g_swing_detector;
        g_swing_detector = NULL;
        return INIT_FAILED;
    }
    
    // Transition to IDLE_ZONE_SEARCH state
    g_state.current_state = STATE_IDLE_ZONE_SEARCH;
    g_state.last_state_change = TimeCurrent();
    
    LogInfo("Initialization complete. State: " + GetStateName(g_state.current_state));
    LogInfo("HTF: " + EnumToString(InpHTF) + ", LTF: " + EnumToString(InpLTF));
    LogInfo("Swing Lookback: " + IntegerToString(InpSwingLookback));
    LogInfo("Risk Per Trade: " + DoubleToString(InpRiskPercent, 2) + "%");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    LogInfo("=== ICC Expert Advisor Shutdown ===");
    LogInfo("Deinit reason: " + IntegerToString(reason));
    
    // Clean up Timeframe Manager
    if(g_timeframe_manager != NULL) {
        delete g_timeframe_manager;
        g_timeframe_manager = NULL;
        LogDebug("Timeframe Manager cleaned up");
    }
    
    // Clean up Swing Detector
    if(g_swing_detector != NULL) {
        delete g_swing_detector;
        g_swing_detector = NULL;
        LogDebug("Swing Detector cleaned up");
    }
    
    // TODO: Save state persistence
    // TODO: Clean up visual debugging objects
    // TODO: Release indicator handles
    
    LogInfo("Shutdown complete.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick() {
    // Check if Timeframe Manager is initialized
    if(g_timeframe_manager == NULL || !g_timeframe_manager.IsInitialized()) {
        return;
    }
    
    // Check for new HTF bar
    if(g_timeframe_manager.IsNewHTFBar()) {
        LogDebug("OnTick() - New HTF bar detected");
        // TODO: Update HTF analysis (swing points, No Trade Zone)
    }
    
    // Check for new LTF bar
    if(g_timeframe_manager.IsNewLTFBar()) {
        LogDebug("OnTick() - New LTF bar detected");
        // TODO: Update LTF analysis (CHoCH detection)
    }
    
    // TODO: Implement state machine logic
    // This will be implemented in subsequent tasks
}

//+------------------------------------------------------------------+
//| Input Parameter Validation                                        |
//+------------------------------------------------------------------+
bool ValidateInputParameters() {
    bool valid = true;
    
    // Requirement 23.1: Verify LTF period is less than HTF period
    if(InpLTF >= InpHTF) {
        LogError("Invalid timeframe configuration: LTF must be smaller than HTF");
        LogError("LTF: " + EnumToString(InpLTF) + ", HTF: " + EnumToString(InpHTF));
        valid = false;
    }
    
    // Requirement 23.2: Verify Risk_Percent is between 0.1 and 10.0
    if(InpRiskPercent < 0.1 || InpRiskPercent > 10.0) {
        LogError("Invalid Risk_Percent: " + DoubleToString(InpRiskPercent, 2));
        LogError("Risk_Percent must be between 0.1 and 10.0");
        valid = false;
    }
    
    // Requirement 23.3: Verify Partial_Close_Percent is between 0 and 100
    if(InpPartialClosePercent < 0.0 || InpPartialClosePercent > 100.0) {
        LogError("Invalid Partial_Close_Percent: " + DoubleToString(InpPartialClosePercent, 2));
        LogError("Partial_Close_Percent must be between 0 and 100");
        valid = false;
    }
    
    // Requirement 23.4: Verify Swing_Lookback is at least 2
    if(InpSwingLookback < 2) {
        LogError("Invalid Swing_Lookback: " + IntegerToString(InpSwingLookback));
        LogError("Swing_Lookback must be at least 2");
        valid = false;
    }
    
    if(valid) {
        LogInfo("Input parameter validation passed");
    }
    
    return valid;
}

//+------------------------------------------------------------------+
