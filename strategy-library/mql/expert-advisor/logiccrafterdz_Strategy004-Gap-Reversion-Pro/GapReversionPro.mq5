//+------------------------------------------------------------------+
//|                                           Gap Reversion Pro.mq5 |
//|                           Copyright (c) 2025 LogicCrafterDZ     |
//|                          Email: logiccrafterdz@gmail.com        |
//|                          Twitter: @Arana_lib                    |
//|                          Telegram: https://t.me/LogicCrafterDZ  |
//+------------------------------------------------------------------+

#property copyright " Copyright (c) 2025 LogicCrafterDZ."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Gap Reversion Pro - Advanced gap trading strategy with mean reversion logic"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include "NewsFilter.mqh"

//+------------------------------------------------------------------+
//| External Input Parameters                                         |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double   InpRiskPercent = 2.0;           // Risk per trade (%)
input double   InpBaseLotSize = 0.1;           // Base lot size
input double   InpMaxLotMultiplier = 3.0;      // Maximum lot multiplier

input group "=== Gap Detection ==="
input int      InpAvgRangePeriod = 20;         // Average range calculation period
input double   InpMinGapPercent = 15.0;        // Minimum gap size (% of avg range)
input double   InpGapBuffer = 10.0;            // Gap buffer for SL (%)

input group "=== Take Profit Levels ==="
input double   InpTP1_Percent = 50.0;          // TP1 distance (% of gap)
input double   InpTP2_Percent = 75.0;          // TP2 distance (% of gap)
input double   InpTP3_Percent = 100.0;         // TP3 distance (% of gap)

input group "=== Position Sizing ==="
input double   InpTP1_Size = 50.0;             // TP1 position size (%)
input double   InpTP2_Size = 30.0;             // TP2 position size (%)
input double   InpTP3_Size = 20.0;             // TP3 position size (%)

input group "=== Session Filter ==="
input int      InpLondonStartHour = 6;         // London session start hour
input int      InpLondonEndHour = 18;          // London session end hour
input int      InpNewYorkStartHour = 12;       // New York session start hour
input int      InpNewYorkEndHour = 22;         // New York session end hour

input group "=== Filters ==="
input bool     InpTradeMonday = true;          // Trade on Monday
input bool     InpTradeFriday = true;          // Trade on Friday
input bool     InpNewsFilter = false;          // Enable news filter
input bool     InpSkipGold = true;             // Skip XAUUSD trading
input int      InpNewsHours = 2;               // Hours to avoid before news

input group "=== Adaptation ==="
input int      InpAdaptationPeriod = 20;       // Trades to track for adaptation
input double   InpMinWinRate = 40.0;           // Minimum win rate (%)
input double   InpMaxWinRate = 70.0;           // Maximum win rate (%)
input double   InpLotIncrease = 1.2;           // Lot increase multiplier

input group "=== Exit Rules ==="
input int      InpMaxTradeHours = 6;           // Maximum trade duration (hours)
input int      InpDailyCloseHour = 23;         // Daily close hour
input int      InpDailyCloseMinute = 59;       // Daily close minute

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  position;
COrderInfo     order;
CNewsFilter    newsFilter;

struct TradeRecord {
    datetime time;
    bool     isWin;
    double   profit;
};

TradeRecord    tradeHistory[];
int            historyCount = 0;
double         currentLotMultiplier = 1.0;
datetime       lastTradeDate = 0;
bool           tradingPaused = false;
datetime       pauseUntil = 0;

// Magic numbers for different symbols
int GetMagicNumber(string symbol) {
    int magic = 100000;
    for(int i = 0; i < StringLen(symbol); i++) {
        magic += StringGetCharacter(symbol, i) * (i + 1);
    }
    return magic % 999999 + 100000;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Set trade parameters
    trade.SetExpertMagicNumber(GetMagicNumber(_Symbol));
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    
    // Initialize arrays
    ArrayResize(tradeHistory, InpAdaptationPeriod);
    
    // Initialize struct array manually
    for(int i = 0; i < InpAdaptationPeriod; i++) {
        tradeHistory[i].time = 0;
        tradeHistory[i].isWin = false;
        tradeHistory[i].profit = 0.0;
    }
    
    Print("Gap Reversion Pro EA initialized for ", _Symbol);
    Print("Magic Number: ", GetMagicNumber(_Symbol));
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("Gap Reversion Pro EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Check if trading is paused
    if(tradingPaused && TimeCurrent() < pauseUntil) {
        return;
    } else if(tradingPaused && TimeCurrent() >= pauseUntil) {
        tradingPaused = false;
        Print("Trading resumed after adaptation pause");
    }
    
    // Only run main logic once per hour to avoid spam
    static datetime lastCheck = 0;
    datetime currentHour = (TimeCurrent() / 3600) * 3600; // Round to hour
    if(currentHour == lastCheck) return;
    lastCheck = currentHour;
    
    Print("=== OnTick Check at ", TimeToString(TimeCurrent()), " ===");
    
    // Check for forced exits
    CheckForcedExits();
    
    // Check for new trading opportunities
    CheckNewTrade();
    
    // Manage existing positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Check for new trading opportunities                              |
//+------------------------------------------------------------------+
void CheckNewTrade() {
    // Only check once per day
    datetime currentDate = iTime(_Symbol, PERIOD_D1, 0);
    if(currentDate == lastTradeDate) {
        return;
    }
    
    Print("=== Checking new trade opportunity for ", TimeToString(currentDate), " ===");
    
    // Skip if symbol is restricted
    if(InpSkipGold && StringFind(_Symbol, "XAU") >= 0) {
        Print("Trade skipped: Gold symbol restriction");
        return;
    }
    
    // Day and session filters removed - trading allowed Monday to Friday at any time
    Print("✓ Time filters bypassed - unrestricted trading enabled");
    
    // Check if we already have positions
    if(CountPositions() > 0) {
        Print("Trade skipped: Already have positions");
        return;
    }
    Print("✓ No existing positions");
    
    // Check news filter
    if(InpNewsFilter && newsFilter.IsHighImpactNewsNear(_Symbol, InpNewsHours)) {
        Print("Trade skipped due to high-impact news in next ", InpNewsHours, " hours");
        return;
    }
    Print("✓ News filter passed");
    
    // Detect gap
    double gapSize = 0;
    int gapDirection = DetectGap(gapSize);
    Print("Gap detection: Direction=", gapDirection, ", Size=", DoubleToString(gapSize, _Digits));
    if(gapDirection == 0) {
        Print("Trade skipped: No significant gap detected");
        return;
    }
    Print("✓ Gap detected: ", (gapDirection == 1) ? "Gap Up" : "Gap Down");
    
    // Check trend filter
    int trendDirection = GetTrendDirection();
    Print("Trend direction: ", trendDirection, " (1=Bull, -1=Bear, 0=Sideways)");
    if(!IsValidGapTrend(gapDirection, trendDirection)) {
        Print("Trade skipped: Gap-trend combination not valid");
        return;
    }
    Print("✓ Gap-trend combination valid");
    
    // Wait for H1 confirmation
    if(!CheckH1Confirmation(gapDirection)) {
        Print("Trade skipped: No H1 confirmation");
        return;
    }
    Print("✓ H1 confirmation received");
    
    // Calculate confidence score
    double confidence = CalculateConfidenceScore(gapSize, trendDirection, gapDirection);
    Print("Confidence score: ", DoubleToString(confidence, 3));
    if(confidence < 0.3) {
        Print("Trade skipped: Confidence too low (", DoubleToString(confidence, 3), " < 0.3)");
        return;
    }
    Print("✓ Confidence acceptable");
    
    // Calculate lot size based on confidence
    double lotSize = CalculateLotSize(confidence);
    Print("Calculated lot size: ", DoubleToString(lotSize, 2));
    
    // Place trade
    PlaceTrade(gapDirection, gapSize, lotSize);
    
    lastTradeDate = currentDate;
}

//+------------------------------------------------------------------+
//| Detect gap on daily timeframe                                   |
//+------------------------------------------------------------------+
int DetectGap(double &gapSize) {
    // Get daily data
    double todayOpen = iOpen(_Symbol, PERIOD_D1, 0);
    double yesterdayClose = iClose(_Symbol, PERIOD_D1, 1);
    
    Print("Gap Analysis:");
    Print("  Today Open: ", DoubleToString(todayOpen, _Digits));
    Print("  Yesterday Close: ", DoubleToString(yesterdayClose, _Digits));
    
    // Calculate average daily range
    double avgRange = CalculateAverageRange();
    Print("  Average Range (", InpAvgRangePeriod, " days): ", DoubleToString(avgRange, _Digits));
    
    // Calculate gap
    double gap = todayOpen - yesterdayClose;
    gapSize = MathAbs(gap);
    Print("  Raw Gap: ", DoubleToString(gap, _Digits));
    Print("  Gap Size: ", DoubleToString(gapSize, _Digits));
    
    // Check if gap is significant
    double minGapSize = avgRange * InpMinGapPercent / 100.0;
    Print("  Required Min Gap (", DoubleToString(InpMinGapPercent, 1), "%): ", DoubleToString(minGapSize, _Digits));
    Print("  Gap vs Min: ", DoubleToString(gapSize, _Digits), " vs ", DoubleToString(minGapSize, _Digits));
    
    if(gapSize < minGapSize) {
        Print("  Result: Gap too small");
        return 0;
    }
    
    // Return gap direction
    int direction = (gap > 0) ? 1 : -1; // 1 = Gap Up, -1 = Gap Down
    Print("  Result: Gap detected, Direction: ", (direction == 1) ? "UP" : "DOWN");
    return direction;
}

//+------------------------------------------------------------------+
//| Calculate average daily range                                   |
//+------------------------------------------------------------------+
double CalculateAverageRange() {
    double totalRange = 0;
    for(int i = 1; i <= InpAvgRangePeriod; i++) {
        double high = iHigh(_Symbol, PERIOD_D1, i);
        double low = iLow(_Symbol, PERIOD_D1, i);
        totalRange += (high - low);
    }
    return totalRange / InpAvgRangePeriod;
}

//+------------------------------------------------------------------+
//| Get trend direction                                              |
//+------------------------------------------------------------------+
int GetTrendDirection() {
    double currentClose = iClose(_Symbol, PERIOD_D1, 0);
    double pastClose = iClose(_Symbol, PERIOD_D1, 5);
    
    double diff = currentClose - pastClose;
    double threshold = CalculateAverageRange() * 0.1; // 10% of average range
    
    if(diff > threshold) return 1;      // Bullish
    if(diff < -threshold) return -1;    // Bearish
    return 0;                           // Sideways
}

//+------------------------------------------------------------------+
//| Check if gap and trend combination is valid                     |
//+------------------------------------------------------------------+
bool IsValidGapTrend(int gapDirection, int trendDirection) {
    // Mean reversion logic: trade gaps opposite to trend
    if(gapDirection == 1 && trendDirection == 1) return true;   // Gap up in uptrend -> Sell
    if(gapDirection == -1 && trendDirection == -1) return true; // Gap down in downtrend -> Buy
    return false;
}

//+------------------------------------------------------------------+
//| Check H1 confirmation                                           |
//+------------------------------------------------------------------+
bool CheckH1Confirmation(int gapDirection) {
    // Get first H1 candle after market open
    datetime marketOpen = GetMarketOpenTime();
    int h1Index = iBarShift(_Symbol, PERIOD_H1, marketOpen);
    
    if(h1Index < 0) return false;
    
    double h1Open = iOpen(_Symbol, PERIOD_H1, h1Index);
    double h1Close = iClose(_Symbol, PERIOD_H1, h1Index);
    
    // Check confirmation
    if(gapDirection == 1) {  // Gap Up
        return h1Close < h1Open; // Bearish H1 candle
    } else {  // Gap Down
        return h1Close > h1Open; // Bullish H1 candle
    }
}

//+------------------------------------------------------------------+
//| Get market open time for today                                  |
//+------------------------------------------------------------------+
datetime GetMarketOpenTime() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Calculate confidence score                                       |
//+------------------------------------------------------------------+
double CalculateConfidenceScore(double gapSize, int trendDirection, int gapDirection) {
    double score = 0;
    
    // Gap size component (weight 0.4)
    double avgRange = CalculateAverageRange();
    double gapRatio = gapSize / avgRange;
    double gapScore = MathMin(gapRatio / 2.0, 1.0); // Normalize to 0-1
    score += gapScore * 0.4;
    
    // Trend direction component (weight 0.3)
    double trendScore = (MathAbs(trendDirection) == 1) ? 1.0 : 0.5;
    score += trendScore * 0.3;
    
    // H1 confirmation component (weight 0.2)
    score += 1.0 * 0.2; // Already confirmed if we reach here
    
    // Session component (weight 0.1)
    double sessionScore = IsValidTradingSession() ? 1.0 : 0.0;
    score += sessionScore * 0.1;
    
    return MathMax(0.0, MathMin(1.0, score));
}

//+------------------------------------------------------------------+
//| Calculate lot size based on confidence                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double confidence) {
    double baseLot = InpBaseLotSize * currentLotMultiplier;
    
    // Scale lot size based on confidence (0.3 to 0.9 range)
    double minMultiplier = 0.2;
    double maxMultiplier = 2.0;
    
    double range = maxMultiplier - minMultiplier;
    double confRange = 0.9 - 0.3;
    double multiplier = minMultiplier + (confidence - 0.3) / confRange * range;
    
    double lotSize = baseLot * multiplier;
    
    // Apply broker limits
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = MathRound(lotSize / stepLot) * stepLot;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Place trade with scaling take profits                           |
//+------------------------------------------------------------------+
void PlaceTrade(int gapDirection, double gapSize, double lotSize) {
    double price = (gapDirection == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Calculate stop loss
    double sl = CalculateStopLoss(gapDirection, gapSize);
    
    // Calculate take profit levels
    double tp1 = CalculateTakeProfit(gapDirection, gapSize, InpTP1_Percent);
    double tp2 = CalculateTakeProfit(gapDirection, gapSize, InpTP2_Percent);
    double tp3 = CalculateTakeProfit(gapDirection, gapSize, InpTP3_Percent);
    
    // Calculate position sizes
    double lot1 = lotSize * InpTP1_Size / 100.0;
    double lot2 = lotSize * InpTP2_Size / 100.0;
    double lot3 = lotSize * InpTP3_Size / 100.0;
    
    // Normalize lot sizes
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lot1 = MathMax(minLot, MathRound(lot1 / stepLot) * stepLot);
    lot2 = MathMax(minLot, MathRound(lot2 / stepLot) * stepLot);
    lot3 = MathMax(minLot, MathRound(lot3 / stepLot) * stepLot);
    
    // Place orders
    ENUM_ORDER_TYPE orderType = (gapDirection == 1) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    
    string comment1 = "GRP_TP1_" + IntegerToString(GetMagicNumber(_Symbol));
    string comment2 = "GRP_TP2_" + IntegerToString(GetMagicNumber(_Symbol));
    string comment3 = "GRP_TP3_" + IntegerToString(GetMagicNumber(_Symbol));
    
    if(lot1 > 0) trade.PositionOpen(_Symbol, orderType, lot1, price, sl, tp1, comment1);
    if(lot2 > 0) trade.PositionOpen(_Symbol, orderType, lot2, price, sl, tp2, comment2);
    if(lot3 > 0) trade.PositionOpen(_Symbol, orderType, lot3, price, sl, tp3, comment3);
    
    Print("Gap trade placed: ", (gapDirection == 1) ? "SELL" : "BUY", 
          " Gap size: ", DoubleToString(gapSize, _Digits),
          " Total lot: ", DoubleToString(lotSize, 2));
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                             |
//+------------------------------------------------------------------+
double CalculateStopLoss(int gapDirection, double gapSize) {
    double buffer = gapSize * InpGapBuffer / 100.0;
    
    if(gapDirection == 1) { // Gap Up - SELL
        double high = iHigh(_Symbol, PERIOD_D1, 0);
        return high + buffer;
    } else { // Gap Down - BUY
        double low = iLow(_Symbol, PERIOD_D1, 0);
        return low - buffer;
    }
}

//+------------------------------------------------------------------+
//| Calculate take profit                                           |
//+------------------------------------------------------------------+
double CalculateTakeProfit(int gapDirection, double gapSize, double percent) {
    double todayOpen = iOpen(_Symbol, PERIOD_D1, 0);
    double yesterdayClose = iClose(_Symbol, PERIOD_D1, 1);
    
    double targetDistance = gapSize * percent / 100.0;
    
    if(gapDirection == 1) { // Gap Up - SELL
        return todayOpen - targetDistance;
    } else { // Gap Down - BUY
        return todayOpen + targetDistance;
    }
}

//+------------------------------------------------------------------+
//| Check if current day is valid for trading                      |
//+------------------------------------------------------------------+
bool IsValidTradingDay() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Day filter disabled - trading allowed Monday to Friday without restrictions
    Print("Day Filter Check: DISABLED - All weekdays allowed");
    Print("  Current day of week: ", dt.day_of_week, " (1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 0=Sun)");
    
    // Only block weekends (Saturday=6, Sunday=0)
    if(dt.day_of_week == 0 || dt.day_of_week == 6) {
        Print("  Result: Weekend - trading not allowed");
        return false;
    }
    
    Print("  Result: Weekday - trading allowed");
    return true;
}

//+------------------------------------------------------------------+
//| Check if current time is in valid trading session             |
//+------------------------------------------------------------------+
bool IsValidTradingSession() {
    // Session filter disabled - trading allowed at any time Monday to Friday
    Print("Session Filter Check: DISABLED - All hours allowed");
    return true;
}

//+------------------------------------------------------------------+
//| Count current positions                                         |
//+------------------------------------------------------------------+
int CountPositions() {
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == _Symbol && position.Magic() == GetMagicNumber(_Symbol)) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Manage existing positions                                       |
//+------------------------------------------------------------------+
void ManagePositions() {
    // Position timeout restriction removed - positions can remain open indefinitely
    // Only stop loss and take profit levels will close positions
    Print("Position management: Time restrictions disabled");
}

//+------------------------------------------------------------------+
//| Check for forced exits                                          |
//+------------------------------------------------------------------+
void CheckForcedExits() {
    // Daily close time restriction removed - positions can remain open 24/5
    // Only natural stop loss and take profit exits will occur
    Print("Forced exits disabled - no daily close restrictions");
}

//+------------------------------------------------------------------+
//| Close all positions for this symbol                            |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == _Symbol && position.Magic() == GetMagicNumber(_Symbol)) {
                trade.PositionClose(position.Ticket());
                Print("Position closed at daily close: ", position.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result) {
    
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        if(trans.symbol == _Symbol) {
            // Record trade for adaptation
            RecordTrade(trans);
            
            // Update adaptation parameters
            UpdateAdaptation();
        }
    }
}

//+------------------------------------------------------------------+
//| Record trade for adaptation module                             |
//+------------------------------------------------------------------+
void RecordTrade(const MqlTradeTransaction& trans) {
    // Shift array
    for(int i = InpAdaptationPeriod - 1; i > 0; i--) {
        tradeHistory[i] = tradeHistory[i-1];
    }
    
    // Add new record
    tradeHistory[0].time = TimeCurrent();
    tradeHistory[0].profit = trans.price; // This would need proper profit calculation
    tradeHistory[0].isWin = (trans.price > 0);
    
    historyCount = MathMin(historyCount + 1, InpAdaptationPeriod);
}

//+------------------------------------------------------------------+
//| Update adaptation parameters                                    |
//+------------------------------------------------------------------+
void UpdateAdaptation() {
    if(historyCount < InpAdaptationPeriod) return;
    
    // Calculate win rate
    int wins = 0;
    for(int i = 0; i < historyCount; i++) {
        if(tradeHistory[i].isWin) wins++;
    }
    
    double winRate = (double)wins / historyCount * 100.0;
    
    // Apply adaptation rules
    if(winRate < InpMinWinRate) {
        tradingPaused = true;
        pauseUntil = TimeCurrent() + 24 * 3600; // Pause for 1 day
        Print("Trading paused due to low win rate: ", DoubleToString(winRate, 1), "%");
    }
    else if(winRate > InpMaxWinRate) {
        currentLotMultiplier = MathMin(currentLotMultiplier * InpLotIncrease, InpMaxLotMultiplier);
        Print("Lot multiplier increased to: ", DoubleToString(currentLotMultiplier, 2));
    }
}

//+------------------------------------------------------------------+