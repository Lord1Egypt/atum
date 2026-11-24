//+------------------------------------------------------------------+
//|                        PHASE 404 EA                              |
//|         Smart Money Concepts — AMD + Liquidity + MSS + OTE       |
//|         Platform  : MetaTrader 5 (MQL5)                          |
//|         Risk Mgmt : Risk % of Balance + Dynamic Structure SL     |
//|         Take Profit: Opposite BSL / SSL Liquidity Level          |
//+------------------------------------------------------------------+
#property copyright "PHASE 404"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;
COrderInfo    orderInfo;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

// ── Risk Management ──────────────────────────────────────────────
input group "💰 Risk Management"
input double RiskPercent       = 1.0;    // Risk % per trade
input double MaxDailyLossPct   = 3.0;    // Max daily loss % before EA stops
input double MaxDailyProfitPct = 6.0;    // Max daily profit % — stop trading
input int    MaxTradesPerDay   = 3;      // Max trades per day
input double MinLotSize        = 0.01;   // Minimum lot size
input double MaxLotSize        = 10.0;   // Maximum lot size

// ── Structure & Liquidity ─────────────────────────────────────────
input group "📊 Market Structure"
input int    SwingLookback     = 10;     // Bars to detect swing high/low
input int    LiqLookback       = 50;     // Bars to scan for BSL/SSL
input double SweepBuffer       = 5.0;    // Pips buffer for liquidity sweep confirm
input int    MSSLookback       = 5;      // Bars for MSS swing detection

// ── OTE Zone ─────────────────────────────────────────────────────
input group "🎯 OTE Zone"
input double OTE_High          = 0.618;  // OTE upper Fib level
input double OTE_Low           = 0.786;  // OTE lower Fib level
input double EQ_Level          = 0.500;  // Equilibrium level

// ── Trade Execution ───────────────────────────────────────────────
input group "⚙️ Trade Execution"
input int    MagicNumber       = 404;    // EA Magic Number
input int    Slippage          = 3;      // Max slippage in points
input bool   UseKillZones      = true;   // Only trade during kill zones
input bool   UseLondonKZ       = true;   // Trade London Open KZ
input bool   UseNYKZ           = true;   // Trade NY Open KZ
input int    LondonKZ_Start    = 2;      // London KZ start hour (NY time)
input int    LondonKZ_End      = 5;      // London KZ end hour (NY time)
input int    NYKZ_Start        = 7;      // NY KZ start hour (NY time)
input int    NYKZ_End          = 10;     // NY KZ end hour (NY time)

// ── Stop Loss ─────────────────────────────────────────────────────
input group "🛡️ Stop Loss"
input double SL_BufferPips     = 3.0;    // Extra buffer beyond structure SL (pips)
input bool   UseBreakEven      = true;   // Move SL to break even
input double BreakEvenTrigger  = 1.5;    // RR ratio to trigger break even
input bool   UseTrailStop      = false;  // Enable trailing stop
input double TrailStopPips     = 15.0;   // Trailing stop distance (pips)

// ── Take Profit ───────────────────────────────────────────────────
input group "🎯 Take Profit"
input bool   UsePartialClose   = true;   // Close 50% at TP1
input double TP1_RR            = 1.5;    // TP1 Risk:Reward ratio (partial close)
input bool   TP2_Liquidity     = true;   // TP2 = opposite liquidity level

// ── Display ───────────────────────────────────────────────────────
input group "🖥️ Display"
input bool   ShowDashboard     = true;   // Show info panel
input bool   ShowStructure     = true;   // Draw structure on chart
input color  BullColor         = clrLime;
input color  BearColor         = clrRed;
input color  OTEColor          = clrDodgerBlue;
input color  LiqColor          = clrGold;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Pip value
double pipSize;
double pipValue;
int    digits;

// Liquidity levels
double bslLevel  = 0;   // Buy Side Liquidity (swing high)
double sslLevel  = 0;   // Sell Side Liquidity (swing low)
int    bslBar    = 0;
int    sslBar    = 0;
bool   bslSwept  = false;
bool   sslSwept  = false;

// MSS tracking
double mssSwingHigh = 0;
double mssSwingLow  = 0;
bool   bullishMSS   = false;
bool   bearishMSS   = false;

// OTE zone
double oteBullTop = 0;
double oteBullBot = 0;
double oteBearTop = 0;
double oteBearBot = 0;
bool   oteActive  = false;

// Trade state
int    tradesToday    = 0;
double dayStartBalance = 0;
datetime lastDayCheck  = 0;
bool   dailyLimitHit   = false;
string currentBias     = "NEUTRAL";

// Chart objects
string objPrefix = "P404_";

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set trade parameters
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage * 10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    // Detect pip size
    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    pipSize = (digits == 3 || digits == 5) ? 10 * _Point : _Point;

    // Init daily tracking
    dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    lastDayCheck    = TimeCurrent();

    Print("PHASE 404 EA initialized. Magic: ", MagicNumber,
          " | Risk: ", RiskPercent, "%",
          " | Symbol: ", _Symbol);

    // Draw kill zone backgrounds
    if(UseKillZones) DrawKillZoneLabels();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, objPrefix);
    Comment("");
    Print("PHASE 404 EA removed.");
}

//+------------------------------------------------------------------+
//| MAIN TICK FUNCTION                                                |
//+------------------------------------------------------------------+
void OnTick()
{
    // Only process on new bar close
    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBar == lastBar) 
    {
        // Still update dashboard and manage open trades on every tick
        if(ShowDashboard) UpdateDashboard();
        ManageOpenTrades();
        return;
    }
    lastBar = currentBar;

    // ── Daily reset ────────────────────────────────────────────────
    CheckDailyReset();
    if(dailyLimitHit) 
    {
        if(ShowDashboard) UpdateDashboard();
        return;
    }

    // ── Kill Zone check ────────────────────────────────────────────
    if(UseKillZones && !IsKillZone()) 
    {
        if(ShowDashboard) UpdateDashboard();
        return;
    }

    // ── Core analysis (runs on each new bar) ──────────────────────
    DetectLiquidity();
    DetectMSS();
    DetectOTEZone();

    // ── Entry logic ───────────────────────────────────────────────
    if(tradesToday < MaxTradesPerDay && CountOpenTrades() == 0)
        CheckEntrySignal();

    if(ShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| DAILY RESET & LIMIT CHECK                                         |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    MqlDateTime dtLast;
    TimeToStruct(lastDayCheck, dtLast);

    if(dt.day != dtLast.day)
    {
        tradesToday     = 0;
        dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        dailyLimitHit   = false;
        lastDayCheck    = TimeCurrent();
        bslSwept        = false;
        sslSwept        = false;
        bullishMSS      = false;
        bearishMSS      = false;
        oteActive       = false;
        Print("PHASE 404: New day — counters reset.");
    }

    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
    double dayPnL   = equity - dayStartBalance;
    double dayPnLPct = (dayPnL / dayStartBalance) * 100.0;

    if(dayPnLPct <= -MaxDailyLossPct)
    {
        dailyLimitHit = true;
        currentBias   = "DAILY LOSS LIMIT HIT";
        Print("PHASE 404: Daily loss limit reached (", DoubleToString(dayPnLPct, 2), "%). Stopping.");
    }

    if(dayPnLPct >= MaxDailyProfitPct)
    {
        dailyLimitHit = true;
        currentBias   = "DAILY PROFIT TARGET HIT";
        Print("PHASE 404: Daily profit target reached (", DoubleToString(dayPnLPct, 2), "%). Stopping.");
    }
}

//+------------------------------------------------------------------+
//| KILL ZONE CHECK                                                   |
//+------------------------------------------------------------------+
bool IsKillZone()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    // Convert server time to NY time (approximate — adjust offset for your broker)
    int nyHour = dt.hour; // Adjust if needed: (dt.hour - serverOffset + 24) % 24

    bool inLondon = UseLondonKZ && nyHour >= LondonKZ_Start && nyHour < LondonKZ_End;
    bool inNY     = UseNYKZ     && nyHour >= NYKZ_Start      && nyHour < NYKZ_End;

    return inLondon || inNY;
}

string GetKillZoneName()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int nyHour = dt.hour;
    if(UseLondonKZ && nyHour >= LondonKZ_Start && nyHour < LondonKZ_End) return "London KZ";
    if(UseNYKZ     && nyHour >= NYKZ_Start      && nyHour < NYKZ_End)     return "NY Open KZ";
    return "Outside KZ";
}

//+------------------------------------------------------------------+
//| DETECT LIQUIDITY (BSL / SSL)                                      |
//+------------------------------------------------------------------+
void DetectLiquidity()
{
    int bars = MathMin(LiqLookback, Bars(_Symbol, PERIOD_CURRENT) - 1);

    // Find highest high and lowest low in lookback = BSL & SSL
    double highestHigh = 0;
    double lowestLow   = DBL_MAX;
    int    highBar     = 0;
    int    lowBar      = 0;

    for(int i = SwingLookback; i < bars; i++)
    {
        double h = iHigh(_Symbol, PERIOD_CURRENT, i);
        double l = iLow(_Symbol,  PERIOD_CURRENT, i);

        // Swing high: higher than neighbours
        bool isSwingHigh = true;
        bool isSwingLow  = true;
        for(int j = 1; j <= SwingLookback; j++)
        {
            if(i + j < bars && iHigh(_Symbol, PERIOD_CURRENT, i+j) >= h) isSwingHigh = false;
            if(i - j >= 0   && iHigh(_Symbol, PERIOD_CURRENT, i-j) >= h) isSwingHigh = false;
            if(i + j < bars && iLow(_Symbol,  PERIOD_CURRENT, i+j) <= l) isSwingLow  = false;
            if(i - j >= 0   && iLow(_Symbol,  PERIOD_CURRENT, i-j) <= l) isSwingLow  = false;
        }

        if(isSwingHigh && h > highestHigh)
        {
            highestHigh = h;
            highBar     = i;
        }
        if(isSwingLow && l < lowestLow)
        {
            lowestLow = l;
            lowBar    = i;
        }
    }

    bslLevel = highestHigh;
    sslLevel = lowestLow;
    bslBar   = highBar;
    sslBar   = lowBar;

    // ── Detect sweep ──────────────────────────────────────────────
    double currentHigh  = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double currentLow   = iLow(_Symbol,  PERIOD_CURRENT, 1);
    double currentClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    double buffer       = SweepBuffer * pipSize;

    // BSL swept: wick above BSL but closed below it
    if(bslLevel > 0 && currentHigh > bslLevel + buffer && currentClose < bslLevel)
    {
        if(!bslSwept)
        {
            bslSwept = true;
            sslSwept = false;
            Print("PHASE 404: BSL Swept at ", DoubleToString(bslLevel, digits));
            if(ShowStructure) DrawSweepMarker(bslLevel, true);
        }
    }

    // SSL swept: wick below SSL but closed above it
    if(sslLevel > 0 && currentLow < sslLevel - buffer && currentClose > sslLevel)
    {
        if(!sslSwept)
        {
            sslSwept = true;
            bslSwept = false;
            Print("PHASE 404: SSL Swept at ", DoubleToString(sslLevel, digits));
            if(ShowStructure) DrawSweepMarker(sslLevel, false);
        }
    }

    // Draw liquidity levels
    if(ShowStructure)
    {
        DrawLiquidityLine("BSL", bslLevel, true);
        DrawLiquidityLine("SSL", sslLevel, false);
    }
}

//+------------------------------------------------------------------+
//| DETECT MARKET STRUCTURE SHIFT (MSS)                               |
//+------------------------------------------------------------------+
void DetectMSS()
{
    bullishMSS = false;
    bearishMSS = false;

    int bars = MathMin(LiqLookback, Bars(_Symbol, PERIOD_CURRENT) - 2);

    // Find recent swing high and swing low for MSS reference
    double swingHigh = 0;
    double swingLow  = DBL_MAX;

    for(int i = MSSLookback; i < bars; i++)
    {
        double h = iHigh(_Symbol, PERIOD_CURRENT, i);
        double l = iLow(_Symbol,  PERIOD_CURRENT, i);
        bool isSwingH = true, isSwingL = true;

        for(int j = 1; j <= MSSLookback; j++)
        {
            if(i+j < bars && iHigh(_Symbol, PERIOD_CURRENT, i+j) >= h) isSwingH = false;
            if(i-j >= 0   && iHigh(_Symbol, PERIOD_CURRENT, i-j) >= h) isSwingH = false;
            if(i+j < bars && iLow(_Symbol,  PERIOD_CURRENT, i+j) <= l) isSwingL = false;
            if(i-j >= 0   && iLow(_Symbol,  PERIOD_CURRENT, i-j) <= l) isSwingL = false;
        }
        if(isSwingH && h > swingHigh) { swingHigh = h; mssSwingHigh = h; }
        if(isSwingL && l < swingLow)  { swingLow  = l; mssSwingLow  = l; }
    }

    double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
    double currClose = iClose(_Symbol, PERIOD_CURRENT, 1);

    // Bullish MSS: after SSL swept, price breaks above recent swing high
    if(sslSwept && mssSwingHigh > 0 && currClose > mssSwingHigh && prevClose <= mssSwingHigh)
    {
        bullishMSS  = true;
        currentBias = "BULLISH";
        Print("PHASE 404: Bullish MSS confirmed at ", DoubleToString(mssSwingHigh, digits));
        if(ShowStructure) DrawMSSLine(mssSwingHigh, true);
    }

    // Bearish MSS: after BSL swept, price breaks below recent swing low
    if(bslSwept && mssSwingLow > 0 && mssSwingLow < DBL_MAX &&
       currClose < mssSwingLow && prevClose >= mssSwingLow)
    {
        bearishMSS  = true;
        currentBias = "BEARISH";
        Print("PHASE 404: Bearish MSS confirmed at ", DoubleToString(mssSwingLow, digits));
        if(ShowStructure) DrawMSSLine(mssSwingLow, false);
    }
}

//+------------------------------------------------------------------+
//| DETECT OTE ZONE (Fib 0.618 – 0.786)                              |
//+------------------------------------------------------------------+
void DetectOTEZone()
{
    double currClose = iClose(_Symbol, PERIOD_CURRENT, 1);

    // Bullish OTE: draw from SSL (manipulation low) up to MSS break point
    if(bullishMSS && sslLevel > 0 && mssSwingHigh > sslLevel)
    {
        double range   = mssSwingHigh - sslLevel;
        oteBullTop     = mssSwingHigh - range * OTE_High;  // 0.618 retracement
        oteBullBot     = mssSwingHigh - range * OTE_Low;   // 0.786 retracement
        oteActive      = true;

        Print("PHASE 404: Bullish OTE Zone | Top: ", DoubleToString(oteBullTop, digits),
              " | Bot: ", DoubleToString(oteBullBot, digits));

        if(ShowStructure) DrawOTEZone(oteBullTop, oteBullBot, true);
    }

    // Bearish OTE: draw from BSL (manipulation high) down to MSS break point
    if(bearishMSS && bslLevel > 0 && mssSwingLow < bslLevel)
    {
        double range   = bslLevel - mssSwingLow;
        oteBearBot     = mssSwingLow + range * OTE_High;   // 0.618 retracement up
        oteBearTop     = mssSwingLow + range * OTE_Low;    // 0.786 retracement up
        oteActive      = true;

        Print("PHASE 404: Bearish OTE Zone | Top: ", DoubleToString(oteBearTop, digits),
              " | Bot: ", DoubleToString(oteBearBot, digits));

        if(ShowStructure) DrawOTEZone(oteBearTop, oteBearBot, false);
    }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNAL                                                |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
    if(!oteActive) return;

    double currHigh  = iHigh(_Symbol,  PERIOD_CURRENT, 1);
    double currLow   = iLow(_Symbol,   PERIOD_CURRENT, 1);
    double currClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    double currOpen  = iOpen(_Symbol,  PERIOD_CURRENT, 1);
    double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread    = ask - bid;

    // ── LONG SIGNAL ───────────────────────────────────────────────
    // Conditions:
    // 1. SSL was swept (stop hunt below)
    // 2. Bullish MSS confirmed
    // 3. Price retraces into OTE zone (61.8–78.6%)
    // 4. Candle closes bullish inside or above OTE zone
    // 5. Inside kill zone
    bool longCondition = sslSwept          &&
                         currentBias == "BULLISH"  &&
                         oteBullTop > 0    &&
                         currLow  <= oteBullTop    &&
                         currClose >= oteBullBot   &&
                         currClose > currOpen;     // Bullish close

    // ── SHORT SIGNAL ──────────────────────────────────────────────
    // Conditions:
    // 1. BSL was swept (stop hunt above)
    // 2. Bearish MSS confirmed
    // 3. Price retraces into OTE zone (61.8–78.6%)
    // 4. Candle closes bearish inside or below OTE zone
    // 5. Inside kill zone
    bool shortCondition = bslSwept         &&
                          currentBias == "BEARISH" &&
                          oteBearBot > 0   &&
                          currHigh >= oteBearBot   &&
                          currClose <= oteBearTop  &&
                          currClose < currOpen;    // Bearish close

    if(longCondition)
    {
        double sl = CalculateLongSL();
        double tp = CalculateLongTP();
        if(sl > 0 && tp > 0)
            ExecuteLong(ask, sl, tp);
    }

    if(shortCondition)
    {
        double sl = CalculateShortSL();
        double tp = CalculateShortTP();
        if(sl > 0 && tp > 0)
            ExecuteShort(bid, sl, tp);
    }
}

//+------------------------------------------------------------------+
//| SL CALCULATIONS (Dynamic Structure-Based)                         |
//+------------------------------------------------------------------+

// Long SL: below the OTE zone bottom (786 level) + buffer, or below SSL sweep low
double CalculateLongSL()
{
    double structureLow = oteBullBot - (SL_BufferPips * pipSize);

    // Also consider the swept SSL level
    if(sslLevel > 0)
        structureLow = MathMin(structureLow, sslLevel - (SL_BufferPips * pipSize));

    // Final check: SL must be below current price
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(structureLow >= ask)
    {
        Print("PHASE 404: Long SL invalid (above ask). Skipping.");
        return 0;
    }

    return NormalizeDouble(structureLow, digits);
}

// Short SL: above the OTE zone top (786 level) + buffer, or above BSL sweep high
double CalculateShortSL()
{
    double structureHigh = oteBearTop + (SL_BufferPips * pipSize);

    // Also consider the swept BSL level
    if(bslLevel > 0)
        structureHigh = MathMax(structureHigh, bslLevel + (SL_BufferPips * pipSize));

    // Final check: SL must be above current price
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(structureHigh <= bid)
    {
        Print("PHASE 404: Short SL invalid (below bid). Skipping.");
        return 0;
    }

    return NormalizeDouble(structureHigh, digits);
}

//+------------------------------------------------------------------+
//| TP CALCULATIONS (Opposite Liquidity Level)                        |
//+------------------------------------------------------------------+

// Long TP: target is the BSL level (opposite liquidity)
double CalculateLongTP()
{
    if(bslLevel <= 0) return 0;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Ensure meaningful RR — TP must be above entry
    if(bslLevel <= ask)
    {
        Print("PHASE 404: BSL TP below entry. Skipping long.");
        return 0;
    }

    return NormalizeDouble(bslLevel, digits);
}

// Short TP: target is the SSL level (opposite liquidity)
double CalculateShortTP()
{
    if(sslLevel <= 0) return 0;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Ensure meaningful RR — TP must be below entry
    if(sslLevel >= bid)
    {
        Print("PHASE 404: SSL TP above entry. Skipping short.");
        return 0;
    }

    return NormalizeDouble(sslLevel, digits);
}

//+------------------------------------------------------------------+
//| LOT SIZE CALCULATION (Risk % of Balance)                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPrice)
{
    double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount  = balance * (RiskPercent / 100.0);
    double slPips      = MathAbs(entryPrice - slPrice) / pipSize;

    if(slPips <= 0)
    {
        Print("PHASE 404: SL pips = 0, cannot calculate lot size.");
        return MinLotSize;
    }

    // Get pip value for 1 standard lot
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pipVal    = (pipSize / tickSize) * tickValue;

    double lots = riskAmount / (slPips * pipVal);
    lots = NormalizeDouble(lots, 2);
    lots = MathMax(MinLotSize, MathMin(MaxLotSize, lots));

    // Round to broker's lot step
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lots = MathFloor(lots / lotStep) * lotStep;

    return lots;
}

//+------------------------------------------------------------------+
//| EXECUTE LONG TRADE                                                 |
//+------------------------------------------------------------------+
void ExecuteLong(double entry, double sl, double tp)
{
    double lots = CalculateLotSize(entry, sl);
    double slPips = MathAbs(entry - sl) / pipSize;
    double tpPips = MathAbs(tp - entry) / pipSize;
    double rr     = tpPips / slPips;

    Print("PHASE 404 LONG | Entry: ", DoubleToString(entry, digits),
          " | SL: ", DoubleToString(sl, digits),
          " | TP: ", DoubleToString(tp, digits),
          " | Lots: ", DoubleToString(lots, 2),
          " | SL pips: ", DoubleToString(slPips, 1),
          " | RR: 1:", DoubleToString(rr, 2));

    string comment = "P404_LONG_" + IntegerToString(MagicNumber);
    bool result = trade.Buy(lots, _Symbol, entry, sl, tp, comment);

    if(result)
    {
        tradesToday++;
        // Reset sweep flags after entry
        sslSwept   = false;
        oteActive  = false;
        Print("PHASE 404: LONG trade executed successfully. Ticket: ",
              trade.ResultOrder());
    }
    else
    {
        Print("PHASE 404: LONG trade FAILED. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| EXECUTE SHORT TRADE                                                |
//+------------------------------------------------------------------+
void ExecuteShort(double entry, double sl, double tp)
{
    double lots   = CalculateLotSize(entry, sl);
    double slPips = MathAbs(sl - entry) / pipSize;
    double tpPips = MathAbs(entry - tp) / pipSize;
    double rr     = tpPips / slPips;

    Print("PHASE 404 SHORT | Entry: ", DoubleToString(entry, digits),
          " | SL: ", DoubleToString(sl, digits),
          " | TP: ", DoubleToString(tp, digits),
          " | Lots: ", DoubleToString(lots, 2),
          " | SL pips: ", DoubleToString(slPips, 1),
          " | RR: 1:", DoubleToString(rr, 2));

    string comment = "P404_SHORT_" + IntegerToString(MagicNumber);
    bool result = trade.Sell(lots, _Symbol, entry, sl, tp, comment);

    if(result)
    {
        tradesToday++;
        // Reset sweep flags after entry
        bslSwept   = false;
        oteActive  = false;
        Print("PHASE 404: SHORT trade executed successfully. Ticket: ",
              trade.ResultOrder());
    }
    else
    {
        Print("PHASE 404: SHORT trade FAILED. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES (Break Even + Trail + Partial TP)              |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!posInfo.SelectByIndex(i)) continue;
        if(posInfo.Magic() != MagicNumber) continue;
        if(posInfo.Symbol() != _Symbol) continue;

        double openPrice = posInfo.PriceOpen();
        double currentSL = posInfo.StopLoss();
        double currentTP = posInfo.TakeProfit();
        double currentPrice = posInfo.PriceCurrent();
        ulong  ticket    = posInfo.Ticket();
        double lots      = posInfo.Volume();

        double slPips = MathAbs(openPrice - currentSL) / pipSize;
        double profitPips = 0;

        if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
            profitPips = (currentPrice - openPrice) / pipSize;

            // ── Break Even ───────────────────────────────────────
            if(UseBreakEven && profitPips >= slPips * BreakEvenTrigger)
            {
                double newSL = openPrice + (SL_BufferPips * pipSize);
                if(newSL > currentSL)
                {
                    trade.PositionModify(ticket, newSL, currentTP);
                    Print("PHASE 404: Break Even set on LONG ticket ", ticket);
                }
            }

            // ── Trailing Stop ─────────────────────────────────────
            if(UseTrailStop)
            {
                double trailSL = currentPrice - (TrailStopPips * pipSize);
                if(trailSL > currentSL && profitPips > TrailStopPips)
                {
                    trade.PositionModify(ticket, trailSL, currentTP);
                }
            }

            // ── Partial Close at TP1 ─────────────────────────────
            if(UsePartialClose && lots > MinLotSize * 2)
            {
                double tp1 = openPrice + slPips * TP1_RR * pipSize;
                if(currentPrice >= tp1 && lots > MinLotSize)
                {
                    double partialLots = NormalizeDouble(lots * 0.5, 2);
                    double lotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                    partialLots = MathFloor(partialLots / lotStep) * lotStep;
                    if(partialLots >= MinLotSize)
                    {
                        trade.PositionClosePartial(ticket, partialLots);
                        Print("PHASE 404: Partial close (50%) on LONG at TP1");
                    }
                }
            }
        }

        if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
            profitPips = (openPrice - currentPrice) / pipSize;

            // ── Break Even ────────────────────────────────────────
            if(UseBreakEven && profitPips >= slPips * BreakEvenTrigger)
            {
                double newSL = openPrice - (SL_BufferPips * pipSize);
                if(newSL < currentSL || currentSL == 0)
                {
                    trade.PositionModify(ticket, newSL, currentTP);
                    Print("PHASE 404: Break Even set on SHORT ticket ", ticket);
                }
            }

            // ── Trailing Stop ─────────────────────────────────────
            if(UseTrailStop)
            {
                double trailSL = currentPrice + (TrailStopPips * pipSize);
                if((trailSL < currentSL || currentSL == 0) && profitPips > TrailStopPips)
                {
                    trade.PositionModify(ticket, trailSL, currentTP);
                }
            }

            // ── Partial Close at TP1 ─────────────────────────────
            if(UsePartialClose && lots > MinLotSize * 2)
            {
                double tp1 = openPrice - slPips * TP1_RR * pipSize;
                if(currentPrice <= tp1 && lots > MinLotSize)
                {
                    double partialLots = NormalizeDouble(lots * 0.5, 2);
                    double lotStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                    partialLots = MathFloor(partialLots / lotStep) * lotStep;
                    if(partialLots >= MinLotSize)
                    {
                        trade.PositionClosePartial(ticket, partialLots);
                        Print("PHASE 404: Partial close (50%) on SHORT at TP1");
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| COUNT OPEN TRADES                                                  |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(posInfo.SelectByIndex(i) &&
           posInfo.Magic()  == MagicNumber &&
           posInfo.Symbol() == _Symbol)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| CHART DRAWING FUNCTIONS                                            |
//+------------------------------------------------------------------+

void DrawLiquidityLine(string name, double price, bool isBSL)
{
    string objName = objPrefix + name;
    color  col     = isBSL ? LiqColor : LiqColor;
    string txt     = isBSL ? "BSL" : "SSL";

    if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);
    ObjectCreate(0, objName, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, col);
    ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
    ObjectSetString(0,  objName, OBJPROP_TOOLTIP, txt + " @ " + DoubleToString(price, digits));
}

void DrawSweepMarker(double price, bool isBSL)
{
    string name = objPrefix + "Sweep_" + IntegerToString(TimeCurrent());
    ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBSL ? 242 : 241);
    ObjectSetInteger(0, name, OBJPROP_COLOR, isBSL ? BearColor : BullColor);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void DrawMSSLine(double price, bool isBull)
{
    string name = objPrefix + "MSS_" + IntegerToString(TimeCurrent());
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, isBull ? BullColor : BearColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetString(0,  name, OBJPROP_TOOLTIP, (isBull ? "Bullish MSS" : "Bearish MSS") +
                   " @ " + DoubleToString(price, digits));
}

void DrawOTEZone(double top, double bot, bool isBull)
{
    string name = objPrefix + "OTE_" + IntegerToString(TimeCurrent());
    datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 1);
    datetime t2 = t1 + PeriodSeconds(PERIOD_CURRENT) * 40;

    ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bot);
    ObjectSetInteger(0, name, OBJPROP_COLOR,   OTEColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE,   STYLE_SOLID);
    ObjectSetInteger(0, name, OBJPROP_WIDTH,   1);
    ObjectSetInteger(0, name, OBJPROP_FILL,    true);
    ObjectSetInteger(0, name, OBJPROP_BACK,    true);
    color fillCol = isBull ? clrDarkGreen : clrDarkRed;
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, ColorToARGB(fillCol, 40));
    ObjectSetString(0,  name, OBJPROP_TOOLTIP, "OTE Zone " + (isBull ? "LONG" : "SHORT"));
}

void DrawKillZoneLabels()
{
    // Note: background kill zone shading uses OnChartEvent or periodic drawing
    // Minimal label drawn at init
    Print("PHASE 404: Kill Zones active. London: ", LondonKZ_Start, ":00-",
          LondonKZ_End, ":00 | NY: ", NYKZ_Start, ":00-", NYKZ_End, ":00 (server time)");
}

//+------------------------------------------------------------------+
//| DASHBOARD (Comment panel)                                          |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    if(!ShowDashboard) return;

    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
    double dayPnL   = equity - dayStartBalance;
    double dayPnLPct= (dayPnL / dayStartBalance) * 100.0;
    string kzStatus = IsKillZone() ? ("✅ " + GetKillZoneName()) : "❌ Outside Kill Zone";

    string dashboard = "\n";
    dashboard += "╔══════════════════════════════╗\n";
    dashboard += "║     PHASE 404 SMART MONEY    ║\n";
    dashboard += "╠══════════════════════════════╣\n";
    dashboard += "║ Symbol  : " + _Symbol + "\n";
    dashboard += "║ Bias    : " + currentBias + "\n";
    dashboard += "║ KZ      : " + kzStatus + "\n";
    dashboard += "╠══════════════════════════════╣\n";
    dashboard += "║ BSL     : " + (bslLevel > 0 ? DoubleToString(bslLevel, digits) : "N/A") + (bslSwept ? " ✔ SWEPT" : "") + "\n";
    dashboard += "║ SSL     : " + (sslLevel > 0 ? DoubleToString(sslLevel, digits) : "N/A") + (sslSwept ? " ✔ SWEPT" : "") + "\n";
    dashboard += "║ MSS     : " + (bullishMSS ? "▲ BULL" : bearishMSS ? "▼ BEAR" : "Waiting") + "\n";
    dashboard += "║ OTE     : " + (oteActive ? "🎯 ACTIVE" : "Waiting") + "\n";
    dashboard += "╠══════════════════════════════╣\n";
    dashboard += "║ Trades  : " + IntegerToString(tradesToday) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
    dashboard += "║ Open    : " + IntegerToString(CountOpenTrades()) + "\n";
    dashboard += "║ Balance : " + DoubleToString(balance, 2) + "\n";
    dashboard += "║ Equity  : " + DoubleToString(equity, 2) + "\n";
    dashboard += "║ Day PnL : " + DoubleToString(dayPnLPct, 2) + "%" + "\n";
    dashboard += "╠══════════════════════════════╣\n";
    dashboard += "║ Risk    : " + DoubleToString(RiskPercent, 1) + "% | DD Limit: " + DoubleToString(MaxDailyLossPct, 1) + "%" + "\n";
    dashboard += "║ Status  : " + (dailyLimitHit ? "🔴 STOPPED" : "🟢 ACTIVE") + "\n";
    dashboard += "╚══════════════════════════════╝\n";

    Comment(dashboard);
}

//+------------------------------------------------------------------+
//| END OF EA                                                          |
//+------------------------------------------------------------------+
