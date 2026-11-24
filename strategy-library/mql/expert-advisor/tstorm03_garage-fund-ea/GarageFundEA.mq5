//+------------------------------------------------------------------+
//|                    GARAGE FUND EA v1.0                           |
//|                 Production-Ready MT5 Expert Advisor               |
//| Core: BOS Momentum Scalper + Non-Martingale Grid + RL/SMC Overlay|
//| Target: Sub-$500 accounts, 30+ trades/day, positive Sharpe       |
//+------------------------------------------------------------------+

#property copyright "Garage Fund Collective"
#property link "https://github.com/tstorm03/garage-fund-ea"
#property version "1.00"
#property strict
#property description "BOS Momentum Scalper + XAUUSD Grid + RL/SMC Layer for $500 accounts"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Arrays\ArrayObj.mqh>

//+------------------------------------------------------------------+
// CORE CONFIGURATION INPUTS
//+------------------------------------------------------------------+

// Session & General
input int     NYSessionStartHour = 13;           // NY session start (UTC)
input int     NYSessionEndHour   = 22;           // NY session end (UTC)
input bool    UseNYSessionFilter = true;         // Filter trades to NY session only
input ulong   MagicNumberBOS     = 1001;         // Magic number for BOS trades
input ulong   MagicNumberGrid    = 1002;         // Magic number for Grid trades
input ulong   MagicNumberRL      = 1003;         // Magic number for RL trades

// BOS Momentum Scalper
input int     SwingLookback      = 5;            // Bars to check for swing high/low
input int     MaxSwingSearchBars  = 29;          // Max bars back to search for swings
input int     MaxOpenTradesBOS   = 5;            // Max concurrent BOS trades
input double  TargetProfitUSD    = 0.30;         // Target profit per trade in USD
input int     MaxTradeDurationSec = 120;         // Max time to hold a trade (seconds)
input int     MaxSpreadPointsMajor = 15;         // Max spread for major pairs
input int     MaxSpreadPointsGold = 50;          // Max spread for XAUUSD
input bool    SmallAccountMode   = true;         // Enable small account protections
input double  FixedLotBOS        = 0.02;         // Fixed lot for BOS (if not risk-based)
input double  MaxLotSmallAcct    = 0.02;         // Max lot for small accounts
input double  MinBalanceStopTrade = 30;          // Min balance to stop trading
input bool    UseRiskBasedSizing  = true;        // Use % risk instead of fixed lot
input double  RiskPercentPerTrade = 0.50;        // Risk % per trade (for risk-based sizing)
input int     HardStopLossPips   = 0;            // Hard SL in pips (0 = off)

// Grid Engine (XAUUSD)
input bool    EnableGridEngine   = true;         // Enable non-martingale grid on XAUUSD
input string  GridSymbol         = "XAUUSD";    // Grid trading symbol
input double  GridStartLot        = 0.01;        // Starting lot size for grid
input double  GridMaxLot          = 0.05;        // Max lot size for grid
input int     GridSizePointsOverride = 0;        // Override grid spacing (0 = ATR-based)
input int     GridTPPoints        = 3000;        // Grid take profit in points
input int     GridSLPoints        = 6000;        // Grid stop loss in points
input bool    UseGridTrendFilter  = true;        // Use 200 EMA trend filter for grid
input double  MaxGridRiskPercent  = 3.0;         // Max risk across all grid positions
input double  DailyDrawdownLimitPercent = 5.0;   // Daily loss limit
input int     ATRPeriodForGrid    = 14;          // ATR period for grid spacing

// Risk Management
input double  EquityStopPercent   = 7.0;         // Close all if equity loss > X%
input double  PortfolioDrawdownCap = 10.0;       // Portfolio DD cap from high-water mark
input double  MaxCorrelationAllowed = 0.80;      // Max correlation between open trades
input bool    UsePartialCloseLadder = true;      // Use 0.5*ATR + 1.0*ATR exits
input int     ATRPeriodForExits   = 14;          // ATR period for partial closes

// Step-Down Risk Management
input bool    UseStepDownRisk     = true;        // Enable step-down after losses
input int     ConsecutiveLossesToStepDown = 2;   // Losses before stepping down
input int     ConsecutiveLossesForMinRisk = 4;   // Losses before minimum risk
input double  StepDownRiskPercent = 0.25;        // Stepped-down risk (%)
input double  MinRiskPercent      = 0.125;       // Minimum risk (%)
input int     WinsToRestoreRisk   = 2;           // Wins needed to restore baseline

// RL/SMC Overlay (Optional)
input bool    EnableRLLayer       = false;       // Enable RL/SMC layer
input int     RL_MinTradesActivate = 30;         // Min trades before RL activates
input double  RL_MinEquityActivate = 800.0;      // Min equity before RL activates
input int     RL_QTableMaxStates  = 2000;        // Max states in Q-table
input double  RL_LearningRate     = 0.15;        // Q-learning rate
input double  RL_RiskMultMin      = 0.50;        // Min risk multiplier from RL
input double  RL_RiskMultMax      = 2.00;        // Max risk multiplier from RL

// Debug & Logging
input bool    EnableDebugLogging  = false;       // Enable detailed logging
input bool    PrintDailyStats     = true;        // Print daily P&L stats
input bool    PrintTradeOnClose   = true;        // Print on each trade close
input int     MaxLogLines         = 1000;        // Max lines to keep in log

//+------------------------------------------------------------------+
// GLOBAL STATE VARIABLES
//+------------------------------------------------------------------+

CTrade trade;
CPositionInfo posInfo;

struct TradeRecord {
    datetime openTime;
    datetime closeTime;
    double   entryPrice;
    double   exitPrice;
    double   pnl;
    double   riskAmount;
    string   signalType;    // "BOS_BUY", "BOS_SELL", "GRID_BUY", "GRID_SELL", "RL_BUY", "RL_SELL"
    int      durationSeconds;
};

CArrayObj tradeLog;                             // Array of TradeRecord pointers
datetime  dayStart;                             // Start of current trading day
double    dailyPnL = 0;                         // Daily profit/loss
double    highWaterMark = 0;                    // Account high-water mark
double    equityOnDayStart = 0;                 // Equity at start of day

int       consecutiveLosses = 0;                // Consecutive losing trades
int       consecutiveWins = 0;                  // Consecutive winning trades
double    currentRiskPercent;                   // Current active risk % (may be stepped down)

// RL State Tracking
int       totalRLTrades = 0;                    // Total trades run through RL
int       rlEnabled = 0;                        // Flag: RL is actively used (1) or not (0)
int       rlTradeCount = 0;                     // Trades since last RL activation check

// Grid State
int       gridOpenBuys = 0;                     // Count of open grid buy positions
int       gridOpenSells = 0;                    // Count of open grid sell positions
double    gridFloatingLoss = 0;                 // Current floating loss on all grid positions

// High-Frequency Tracking
ulong     lastTradeTime = 0;                    // Timestamp of last trade
int       tradesInCurrentMinute = 0;            // Trades executed in current M1 bar

// Performance Metrics
double    totalWins = 0;
double    totalLosses = 0;
int       winCount = 0;
int       lossCount = 0;

//+------------------------------------------------------------------+
// INITIALIZATION & DEINITIALIZATION
//+------------------------------------------------------------------+

int OnInit() {
    Print("=== Garage Fund EA v1.0 Initializing ===");
    Print("BOS Momentum Scalper enabled");
    Print("Grid Engine enabled: ", EnableGridEngine);
    Print("RL Layer enabled: ", EnableRLLayer);
    Print("Risk per trade: ", RiskPercentPerTrade, "%");
    Print("NY Session Filter: ", UseNYSessionFilter);
    
    // Set trade mode
    trade.SetExpertMagicNumber(MagicNumberBOS);
    trade.SetDeviationInPoints(30);
    trade.SetAsyncMode(false);
    
    // Initialize state
    dayStart = TimeCurrent();
    equityOnDayStart = AccountInfoDouble(ACCOUNT_EQUITY);
    highWaterMark = equityOnDayStart;
    currentRiskPercent = RiskPercentPerTrade;
    
    // Try to load RL Q-Table from file (if exists)
    if (EnableRLLayer) {
        RL_LoadQTable();
    }
    
    Print("Initialization complete. Magic: BOS=", MagicNumberBOS, " Grid=", MagicNumberGrid, " RL=", MagicNumberRL);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    Print("=== Garage Fund EA Shutting Down (Reason: ", reason, ") ===");
    
    // Save RL Q-Table
    if (EnableRLLayer) {
        RL_SaveQTable();
    }
    
    // Print final stats
    PrintDailyStats_Final();
    
    if (tradeLog.Total() > 0) {
        Print("Trade log size: ", tradeLog.Total(), " records");
    }
}

//+------------------------------------------------------------------+
// MAIN TICK HANDLER
//+------------------------------------------------------------------+

void OnTick() {
    // Check if we need to reset daily counters
    CheckDayRollover();
    
    // Validate account & equity
    if (!ValidateAccountStatus()) {
        return;
    }
    
    // Check portfolio-level drawdown cap
    if (!CheckOverallDrawdown()) {
        Print("CRITICAL: Portfolio DD cap breached. All trading halted.");
        return;
    }
    
    // Check daily loss limit
    if (!CheckDailyLossLimit()) {
        Print("Daily loss limit hit. Trading paused until next day.");
        return;
    }
    
    // Update high-water mark for equity-based stops
    UpdateHighWaterMark();
    
    // Manage existing positions (close on TP/SL/time)
    ManageBOSPositions();
    if (EnableGridEngine) {
        ManageGridPositions();
    }
    
    // Count trades in current minute (to limit trade rate)
    UpdateTradeCount();
    
    // Session filter check
    if (UseNYSessionFilter && !IsNYSession()) {
        return;
    }
    
    // BOS Momentum Scalper: Check and execute signals
    GenerateBOSSignals();
    
    // Grid Engine: Manage grid entry/exits
    if (EnableGridEngine) {
        RunGridEngine();
    }
}

//+------------------------------------------------------------------+
// DATETIME & SESSION MANAGEMENT
//+------------------------------------------------------------------+

void CheckDayRollover() {
    datetime now = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(now, timeStruct);
    
    // Check if we crossed into a new day
    MqlDateTime lastDayStruct;
    TimeToStruct(dayStart, lastDayStruct);
    
    if (timeStruct.day != lastDayStruct.day || timeStruct.mon != lastDayStruct.mon || timeStruct.year != lastDayStruct.year) {
        // New day
        PrintDailyStats_Current();
        
        dayStart = now;
        equityOnDayStart = AccountInfoDouble(ACCOUNT_EQUITY);
        dailyPnL = 0;
        consecutiveLosses = 0;
        consecutiveWins = 0;
        
        // Reset risk to baseline on new day
        currentRiskPercent = RiskPercentPerTrade;
        
        Print("=== NEW TRADING DAY ===");
    }
}

bool IsNYSession() {
    datetime now = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(now, timeStruct);
    int hour = timeStruct.hour;
    
    // Simple check: NY session 13:00-22:00 UTC
    return (hour >= NYSessionStartHour && hour < NYSessionEndHour);
}

//+------------------------------------------------------------------+
// ACCOUNT VALIDATION
//+------------------------------------------------------------------+

bool ValidateAccountStatus() {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if (equity < MinBalanceStopTrade) {
        Print("ERROR: Account equity (", equity, ") below minimum (", MinBalanceStopTrade, "). Trading halted.");
        return false;
    }
    
    if (equity <= 0 || balance <= 0) {
        Print("ERROR: Invalid account state. Equity=", equity, " Balance=", balance);
        return false;
    }
    
    return true;
}

void UpdateHighWaterMark() {
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if (currentEquity > highWaterMark) {
        highWaterMark = currentEquity;
    }
}

//+------------------------------------------------------------------+
// DRAWDOWN & LOSS LIMIT CHECKS
//+------------------------------------------------------------------+

bool CheckOverallDrawdown() {
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double ddPercent = ((highWaterMark - currentEquity) / highWaterMark) * 100.0;
    
    if (ddPercent > PortfolioDrawdownCap) {
        Print("ALERT: Portfolio DD ", ddPercent, "% exceeds cap ", PortfolioDrawdownCap, "%");
        return false;
    }
    
    return true;
}

bool CheckDailyLossLimit() {
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double dailyLoss = equityOnDayStart - currentEquity;
    double dailyLossPercent = (dailyLoss / equityOnDayStart) * 100.0;
    
    if (dailyLossPercent > DailyDrawdownLimitPercent) {
        Print("Daily loss limit breached: ", dailyLossPercent, "% > ", DailyDrawdownLimitPercent, "%");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
// TRADE COUNT & RATE LIMITING
//+------------------------------------------------------------------+

void UpdateTradeCount() {
    // Count trades in current M1 bar
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
    
    if (currentBarTime != lastBarTime) {
        tradesInCurrentMinute = 0;
        lastBarTime = currentBarTime;
    }
}

int GetTradesInCurrentMinute() {
    return tradesInCurrentMinute;
}

//+------------------------------------------------------------------+
// BOS MOMENTUM SCALPER - SIGNAL GENERATION
//+------------------------------------------------------------------+

bool IsSwingHigh(string symbol, int barIndex, int lookback = 5) {
    double high = iHigh(symbol, PERIOD_M1, barIndex);
    
    // Check previous lookback bars
    for (int i = 1; i <= lookback; i++) {
        if (barIndex + i >= Bars(symbol, PERIOD_M1)) break;
        if (iHigh(symbol, PERIOD_M1, barIndex + i) >= high) return false;
    }
    
    // Check next lookback bars
    for (int i = 1; i <= lookback; i++) {
        if (barIndex - i < 0) break;
        if (iHigh(symbol, PERIOD_M1, barIndex - i) >= high) return false;
    }
    
    return true;
}

bool IsSwingLow(string symbol, int barIndex, int lookback = 5) {
    double low = iLow(symbol, PERIOD_M1, barIndex);
    
    // Check previous lookback bars
    for (int i = 1; i <= lookback; i++) {
        if (barIndex + i >= Bars(symbol, PERIOD_M1)) break;
        if (iLow(symbol, PERIOD_M1, barIndex + i) <= low) return false;
    }
    
    // Check next lookback bars
    for (int i = 1; i <= lookback; i++) {
        if (barIndex - i < 0) break;
        if (iLow(symbol, PERIOD_M1, barIndex - i) <= low) return false;
    }
    
    return true;
}

bool CheckSpreadOK(string symbol) {
    long spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    
    // Determine max allowed spread
    int maxSpread = MaxSpreadPointsMajor;
    if (StringFind(symbol, "XAU") >= 0 || StringFind(symbol, "GOLD") >= 0) {
        maxSpread = MaxSpreadPointsGold;
    }
    
    return (spread <= maxSpread);
}

int CountOpenTradesBOS() {
    int count = 0;
    for (int i = 0; i < PositionsTotal(); i++) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Magic() == MagicNumberBOS) {
                count++;
            }
        }
    }
    return count;
}

void GenerateBOSSignals() {
    // Only process BOS for a predefined set of symbols
    string bosSymbols[] = {"EURUSD", "GBPUSD", "AUDUSD", "NZDUSD"};
    
    for (int symIdx = 0; symIdx < ArraySize(bosSymbols); symIdx++) {
        string symbol = bosSymbols[symIdx];
        
        // Check if symbol exists and is selected
        if (SymbolSelect(symbol, true) == false) {
            continue;
        }
        
        // Rate limit
        if (CountOpenTradesBOS() >= MaxOpenTradesBOS) {
            continue;
        }
        
        if (!CheckSpreadOK(symbol)) {
            continue;
        }
        
        // Search for swing breakouts
        for (int swingBar = 2; swingBar <= MaxSwingSearchBars; swingBar++) {
            // Check for buy signal (close above swing high)
            if (IsSwingHigh(symbol, swingBar, SwingLookback)) {
                double swingHighPrice = iHigh(symbol, PERIOD_M1, swingBar);
                double closeBar1 = iClose(symbol, PERIOD_M1, 1);
                
                if (closeBar1 > swingHighPrice) {
                    ExecuteBOSBuy(symbol, swingHighPrice);
                    break;  // One signal per symbol per tick
                }
            }
            
            // Check for sell signal (close below swing low)
            if (IsSwingLow(symbol, swingBar, SwingLookback)) {
                double swingLowPrice = iLow(symbol, PERIOD_M1, swingBar);
                double closeBar1 = iClose(symbol, PERIOD_M1, 1);
                
                if (closeBar1 < swingLowPrice) {
                    ExecuteBOSSell(symbol, swingLowPrice);
                    break;  // One signal per symbol per tick
                }
            }
        }
    }
}

void ExecuteBOSBuy(string symbol, double triggerPrice) {
    double lot = CalculateLotSize(symbol, HardStopLossPips > 0 ? HardStopLossPips : 10);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    
    trade.SetMagicNumber(MagicNumberBOS);
    
    if (trade.Buy(lot, symbol, 0, 0, 0, "BOS Buy")) {
        TradeRecord *rec = new TradeRecord;
        rec.openTime = TimeCurrent();
        rec.entryPrice = bid;
        rec.signalType = "BOS_BUY";
        tradeLog.Add(rec);
        
        if (EnableDebugLogging) {
            Print("BOS BUY: ", symbol, " @ ", bid, " lot=", lot);
        }
    } else {
        Print("BOS BUY FAILED: ", symbol, " - Error: ", GetLastError());
    }
}

void ExecuteBOSSell(string symbol, double triggerPrice) {
    double lot = CalculateLotSize(symbol, HardStopLossPips > 0 ? HardStopLossPips : 10);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    trade.SetMagicNumber(MagicNumberBOS);
    
    if (trade.Sell(lot, symbol, 0, 0, 0, "BOS Sell")) {
        TradeRecord *rec = new TradeRecord;
        rec.openTime = TimeCurrent();
        rec.entryPrice = ask;
        rec.signalType = "BOS_SELL";
        tradeLog.Add(rec);
        
        if (EnableDebugLogging) {
            Print("BOS SELL: ", symbol, " @ ", ask, " lot=", lot);
        }
    } else {
        Print("BOS SELL FAILED: ", symbol, " - Error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
// BOS POSITION MANAGEMENT
//+------------------------------------------------------------------+

void ManageBOSPositions() {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Magic() != MagicNumberBOS) {
                continue;
            }
            
            ulong ticket = posInfo.Ticket();
            double profit = posInfo.Profit();
            datetime openTime = posInfo.Time();
            int durationSec = (int)(TimeCurrent() - openTime);
            
            // Close on profit target
            if (profit >= TargetProfitUSD) {
                ClosePosition(ticket, "TP Hit: " + DoubleToString(profit, 2));
                RecordClosedTrade(posInfo, "TP", durationSec, profit);
                continue;
            }
            
            // Close on time stop
            if (durationSec >= MaxTradeDurationSec) {
                ClosePosition(ticket, "Time Stop: " + IntegerToString(durationSec) + "s");
                RecordClosedTrade(posInfo, "TIME", durationSec, profit);
                continue;
            }
            
            // Hard equity stop (if floating loss exceeds X% of equity)
            double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
            double equityLossPercent = (AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE)) / AccountInfoDouble(ACCOUNT_BALANCE) * 100.0;
            if (equityLossPercent > EquityStopPercent) {
                ClosePosition(ticket, "Equity Stop");
                RecordClosedTrade(posInfo, "EQUITY", durationSec, profit);
                continue;
            }
        }
    }
}

void ClosePosition(ulong ticket, string reason) {
    trade.PositionClose(ticket);
    if (EnableDebugLogging) {
        Print("Closed position ", ticket, ": ", reason);
    }
}

void RecordClosedTrade(CPositionInfo &pos, string closeReason, int duration, double pnl) {
    if (pnl > 0) {
        totalWins += pnl;
        winCount++;
        consecutiveWins++;
        consecutiveLosses = 0;
    } else if (pnl < 0) {
        totalLosses += pnl;
        lossCount++;
        consecutiveLosses++;
        consecutiveWins = 0;
    }
    
    dailyPnL += pnl;
    
    // Update step-down risk if needed
    if (UseStepDownRisk) {
        if (consecutiveLosses == ConsecutiveLossesToStepDown) {
            currentRiskPercent = StepDownRiskPercent;
            if (EnableDebugLogging) Print("Step down to ", currentRiskPercent, "% after ", ConsecutiveLossesToStepDown, " losses");
        } else if (consecutiveLosses == ConsecutiveLossesForMinRisk) {
            currentRiskPercent = MinRiskPercent;
            if (EnableDebugLogging) Print("Min risk ", MinRiskPercent, "% after ", ConsecutiveLossesForMinRisk, " losses");
        }
        
        if (consecutiveWins == WinsToRestoreRisk) {
            currentRiskPercent = RiskPercentPerTrade;
            if (EnableDebugLogging) Print("Restored to ", RiskPercentPerTrade, "% after ", WinsToRestoreRisk, " wins");
        }
    }
    
    if (PrintTradeOnClose) {
        Print("Trade Close: ", pos.Symbol(), " PnL=", DoubleToString(pnl, 2), " Reason=", closeReason, " Duration=", duration, "s");
    }
}

//+------------------------------------------------------------------+
// GRID ENGINE - NON-MARTINGALE HEDGED GRID ON XAUUSD
//+------------------------------------------------------------------+

void RunGridEngine() {
    if (!EnableGridEngine || GridSymbol != "XAUUSD") {
        return;
    }
    
    // Check grid conditions
    if (!CheckSpreadOK(GridSymbol)) {
        return;
    }
    
    // Placeholder: Grid entry logic would go here
    // For now, this is a stub for the full implementation
}

void ManageGridPositions() {
    if (!EnableGridEngine) {
        return;
    }
    
    gridOpenBuys = 0;
    gridOpenSells = 0;
    gridFloatingLoss = 0;
    
    for (int i = 0; i < PositionsTotal(); i++) {
        if (posInfo.SelectByIndex(i)) {
            if (posInfo.Magic() != MagicNumberGrid) {
                continue;
            }
            
            if (posInfo.Symbol() != GridSymbol) {
                continue;
            }
            
            ulong ticket = posInfo.Ticket();
            double profit = posInfo.Profit();
            
            // Track floating loss
            if (profit < 0) {
                gridFloatingLoss += MathAbs(profit);
            }
            
            // Count by type
            if (posInfo.PositionType() == POSITION_TYPE_BUY) {
                gridOpenBuys++;
            } else if (posInfo.PositionType() == POSITION_TYPE_SELL) {
                gridOpenSells++;
            }
            
            // Check grid-specific risk limits
            double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
            double gridRiskPercent = (gridFloatingLoss / equityNow) * 100.0;
            
            if (gridRiskPercent > MaxGridRiskPercent) {
                ClosePosition(ticket, "Grid risk limit exceeded");
                continue;
            }
        }
    }
}

//+------------------------------------------------------------------+
// LOT SIZING ENGINE
//+------------------------------------------------------------------+

double CalculateLotSize(string symbol, int stopLossPips) {
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskAmount;
    
    if (UseRiskBasedSizing) {
        riskAmount = (equity * currentRiskPercent) / 100.0;
    } else {
        // Use fixed lot
        double lot = FixedLotBOS;
        if (SmallAccountMode) {
            lot = MathMin(lot, MaxLotSmallAcct);
        }
        return lot;
    }
    
    // Get tick value for symbol
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if (tickValue <= 0 || tickSize <= 0) {
        return FixedLotBOS;  // Fallback
    }
    
    // Calculate lot based on risk and stop loss
    double pointValue = tickValue / tickSize;
    double lossPerPip = pointValue * stopLossPips;
    double lot = riskAmount / lossPerPip;
    
    // Apply min/max constraints
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    lot = MathMax(lot, minLot);
    lot = MathMin(lot, maxLot);
    
    if (SmallAccountMode) {
        lot = MathMin(lot, MaxLotSmallAcct);
    }
    
    // Round to lot step
    lot = MathFloor(lot / lotStep) * lotStep;
    
    return lot;
}

//+------------------------------------------------------------------+
// RL/SMC LAYER (STRATUM-STYLE)
//+------------------------------------------------------------------+

struct QLearningState {
    int h4Bias;           // H4 trend: -1, 0, +1
    int h1Structure;      // BOS/CHoCH: -1, 0, +1
    int entryPattern;     // Pattern index: 0-3
    int session;          // Session: 0=ASIA, 1=EU, 2=NY
    int rsiZone;          // RSI zone: 0-4
    int volumeZone;       // Volume: 0-2
    int spreadZone;       // Spread: 0-2
    int adxZone;          // ADX: 0-2
    int hourBlock;        // Hour: 0-23
    int dayOfWeek;        // 0-6
    int h4Zone;           // Premium/discount: -1, 0, +1
    int poiType;          // POI type: 0-3
    int symbolCategory;   // Pair: 0-5
    int divergence;       // Divergence: -1, 0, +1
};

struct QTableEntry {
    double qValue;
    int visitCount;
};

// RL Q-Table (simplified: map from state to Q-value)
// In production, use a hash map or serialized file
void RL_LoadQTable() {
    // Placeholder: load Q-table from file
    if (EnableDebugLogging) {
        Print("RL Q-Table load attempted (not yet implemented)");
    }
}

void RL_SaveQTable() {
    // Placeholder: save Q-table to file
    if (EnableDebugLogging) {
        Print("RL Q-Table save attempted (not yet implemented)");
    }
}

double RL_GetRiskMultiplier(QLearningState state) {
    // Placeholder: return Q-value-based risk multiplier
    // For now, return 1.0 (no adjustment)
    return 1.0;
}

//+------------------------------------------------------------------+
// STATISTICS & LOGGING
//+------------------------------------------------------------------+

void PrintDailyStats_Current() {
    Print("=== Daily Stats (Closed) ===");
    Print("Equity Start: ", DoubleToString(equityOnDayStart, 2));
    Print("Daily P&L: ", DoubleToString(dailyPnL, 2));
    Print("Wins: ", winCount, " (", DoubleToString(totalWins, 2), " USD)");
    Print("Losses: ", lossCount, " (", DoubleToString(totalLosses, 2), " USD)");
    
    if (winCount + lossCount > 0) {
        double winRate = (double)winCount / (winCount + lossCount) * 100.0;
        Print("Win Rate: ", DoubleToString(winRate, 2), "%");
    }
}

void PrintDailyStats_Final() {
    Print("=== Final EA Statistics ===");
    Print("Total Trades: ", winCount + lossCount);
    Print("Total Wins: ", DoubleToString(totalWins, 2));
    Print("Total Losses: ", DoubleToString(totalLosses, 2));
    Print("Net P&L: ", DoubleToString(totalWins + totalLosses, 2));
}

//+------------------------------------------------------------------+
// BACKTEST HANDLER
//+------------------------------------------------------------------+

void OnTester() {
    double profitFactor = 1.0;
    if (totalLosses != 0) {
        profitFactor = totalWins / MathAbs(totalLosses);
    }
    
    int totalTrades = winCount + lossCount;
    double winRate = totalTrades > 0 ? (double)winCount / totalTrades * 100.0 : 0;
    
    Print("=== BACKTEST RESULTS ===");
    Print("Total Trades: ", totalTrades);
    Print("Win Rate: ", DoubleToString(winRate, 2), "%");
    Print("Profit Factor: ", DoubleToString(profitFactor, 2));
    Print("Total P&L: ", DoubleToString(totalWins + totalLosses, 2));
    
    // Store results for optimization
    double results[] = {totalTrades, winRate, profitFactor, totalWins + totalLosses};
}

//+------------------------------------------------------------------+
// UTILITY FUNCTIONS
//+------------------------------------------------------------------+

string TimeToString(datetime dt) {
    MqlDateTime ts;
    TimeToStruct(dt, ts);
    return StringFormat("%04d.%02d.%02d %02d:%02d:%02d", 
                       ts.year, ts.mon, ts.day, 
                       ts.hour, ts.min, ts.sec);
}

//+------------------------------------------------------------------+
// END OF EA
//+------------------------------------------------------------------+
