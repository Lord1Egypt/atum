//+------------------------------------------------------------------+
//|                                    MomoTrendHybrid_EA_v3.mq5     |
//|                    PROFESSIONAL SCALPING EA - VERSION 3.0        |
//|                    Smart Entry with Price Action Confirmation    |
//+------------------------------------------------------------------+
#property copyright "Momo-Trend Hybrid Strategy 2025"
#property link      ""
#property version   "3.00"
#property description "Smart Entry: Pullback + Candlestick + Momentum Confluence"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input group "=== QUẢN LÝ RỦI RO ==="
input double   RiskPercent = 1.0;
input double   MaxDailyLossPercent = 3.0;
input int      MaxDailyTrades = 10;

input group "=== STOP LOSS & TAKE PROFIT ==="
input double   SL_Pips = 15.0;
input double   TP_Pips = 30.0;
input bool     UseATR_SL = true;
input double   ATR_Multiplier = 2.0;
input int      ATR_Period = 14;

input group "=== TRAILING & BREAK EVEN ==="
input bool     UseBreakEven = true;
input double   BE_TriggerPips = 10.0;
input double   BE_ProfitPips = 2.0;
input bool     UseTrailing = true;
input double   TrailStartPips = 15.0;
input double   TrailStepPips = 5.0;

input group "=== TREND SETTINGS ==="
input int      EMA_Fast = 8;
input int      EMA_Slow = 21;
input int      EMA_Trend = 50;
input int      ADX_Period = 14;
input int      ADX_Threshold = 20;

input group "=== MOMENTUM SETTINGS ==="
input int      RSI_Period = 14;
input int      Stoch_K = 14;
input int      Stoch_D = 3;
input int      Stoch_Slow = 3;

input group "=== FILTERS ==="
input double   MaxSpreadPips = 3.0;
input bool     UseTimeFilter = true;
input int      StartHour = 7;
input int      EndHour = 20;

input group "=== KHÁC ==="
input ulong    MagicNumber = 202503;
input string   TradeComment = "MomoV3";

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   accountInfo;

// Indicator handles
int h_EMA_Fast, h_EMA_Slow, h_EMA_Trend;
int h_RSI, h_Stoch, h_ATR, h_ADX;

// Buffers
double buf_EMA_Fast[], buf_EMA_Slow[], buf_EMA_Trend[];
double buf_RSI[];
double buf_Stoch_K[], buf_Stoch_D[];
double buf_ATR[];
double buf_ADX[], buf_ADX_Plus[], buf_ADX_Minus[];

// Tracking
int      g_dailyTrades = 0;
double   g_dailyStartEquity = 0;
datetime g_lastTradeDate = 0;
datetime g_lastBarTime = 0;
double   g_pipValue = 0;

//+------------------------------------------------------------------+
//| PRICE ACTION STRUCTURES                                           |
//+------------------------------------------------------------------+
struct CandleInfo
{
   double open;
   double high;
   double low;
   double close;
   double body;      // |close - open|
   double upperWick; // high - max(open, close)
   double lowerWick; // min(open, close) - low
   double range;     // high - low
   bool   isBullish;
   bool   isBearish;
};

//+------------------------------------------------------------------+
//| Get Candle Information                                            |
//+------------------------------------------------------------------+
CandleInfo GetCandle(int shift)
{
   CandleInfo candle;
   candle.open = iOpen(_Symbol, PERIOD_M5, shift);
   candle.high = iHigh(_Symbol, PERIOD_M5, shift);
   candle.low = iLow(_Symbol, PERIOD_M5, shift);
   candle.close = iClose(_Symbol, PERIOD_M5, shift);
   candle.body = MathAbs(candle.close - candle.open);
   candle.upperWick = candle.high - MathMax(candle.open, candle.close);
   candle.lowerWick = MathMin(candle.open, candle.close) - candle.low;
   candle.range = candle.high - candle.low;
   candle.isBullish = (candle.close > candle.open);
   candle.isBearish = (candle.close < candle.open);
   return candle;
}

//+------------------------------------------------------------------+
//| Calculate Pip Value                                               |
//+------------------------------------------------------------------+
void CalculatePipValue()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0)
      g_pipValue = 0.1;
   else if(digits == 5 || digits == 3)
      g_pipValue = _Point * 10;
   else
      g_pipValue = _Point;
}

double PipsToPrice(double pips) { return pips * g_pipValue; }
double PriceToEPips(double price) { return price / g_pipValue; }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   CalculatePipValue();
   
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Create handles
   h_EMA_Fast = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Slow = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_EMA_Trend = iMA(_Symbol, PERIOD_H1, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   h_RSI = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   h_Stoch = iStochastic(_Symbol, PERIOD_M5, Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, STO_LOWHIGH);
   h_ATR = iATR(_Symbol, PERIOD_M5, ATR_Period);
   h_ADX = iADX(_Symbol, PERIOD_M5, ADX_Period);
   
   if(h_EMA_Fast == INVALID_HANDLE || h_EMA_Slow == INVALID_HANDLE || 
      h_EMA_Trend == INVALID_HANDLE || h_RSI == INVALID_HANDLE || 
      h_Stoch == INVALID_HANDLE || h_ATR == INVALID_HANDLE || h_ADX == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicators!");
      return INIT_FAILED;
   }
   
   // Setup arrays
   ArraySetAsSeries(buf_EMA_Fast, true);
   ArraySetAsSeries(buf_EMA_Slow, true);
   ArraySetAsSeries(buf_EMA_Trend, true);
   ArraySetAsSeries(buf_RSI, true);
   ArraySetAsSeries(buf_Stoch_K, true);
   ArraySetAsSeries(buf_Stoch_D, true);
   ArraySetAsSeries(buf_ATR, true);
   ArraySetAsSeries(buf_ADX, true);
   ArraySetAsSeries(buf_ADX_Plus, true);
   ArraySetAsSeries(buf_ADX_Minus, true);
   
   g_dailyStartEquity = accountInfo.Equity();
   g_lastTradeDate = TimeCurrent();
   g_dailyTrades = CountTodayTrades();
   
   Print("=== MomoTrend v3.0 - Smart Entry Logic ===");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_EMA_Fast);
   IndicatorRelease(h_EMA_Slow);
   IndicatorRelease(h_EMA_Trend);
   IndicatorRelease(h_RSI);
   IndicatorRelease(h_Stoch);
   IndicatorRelease(h_ATR);
   IndicatorRelease(h_ADX);
   Comment("");
}

//+------------------------------------------------------------------+
//| Check New Bar                                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentTime = iTime(_Symbol, PERIOD_M5, 0);
   if(g_lastBarTime != currentTime)
   {
      g_lastBarTime = currentTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();
   
   if(!IsNewBar()) return;
   
   CheckNewDay();
   
   if(IsDailyLossExceeded() || g_dailyTrades >= MaxDailyTrades || HasOpenPosition())
      return;
   
   if(UseTimeFilter && !IsTradeTime()) return;
   if(!IsSpreadOK()) return;
   if(!UpdateData()) return;
   
   // ========== SMART ENTRY LOGIC ==========
   int signal = AnalyzeEntry();
   
   if(signal == 1) OpenBuy();
   else if(signal == -1) OpenSell();
   
   DisplayInfo(signal);
}

//+------------------------------------------------------------------+
//| Update Indicator Data                                             |
//+------------------------------------------------------------------+
bool UpdateData()
{
   if(CopyBuffer(h_EMA_Fast, 0, 0, 10, buf_EMA_Fast) < 10) return false;
   if(CopyBuffer(h_EMA_Slow, 0, 0, 10, buf_EMA_Slow) < 10) return false;
   if(CopyBuffer(h_EMA_Trend, 0, 0, 5, buf_EMA_Trend) < 5) return false;
   if(CopyBuffer(h_RSI, 0, 0, 10, buf_RSI) < 10) return false;
   if(CopyBuffer(h_Stoch, 0, 0, 5, buf_Stoch_K) < 5) return false;
   if(CopyBuffer(h_Stoch, 1, 0, 5, buf_Stoch_D) < 5) return false;
   if(CopyBuffer(h_ATR, 0, 0, 5, buf_ATR) < 5) return false;
   if(CopyBuffer(h_ADX, 0, 0, 5, buf_ADX) < 5) return false;
   if(CopyBuffer(h_ADX, 1, 0, 5, buf_ADX_Plus) < 5) return false;
   if(CopyBuffer(h_ADX, 2, 0, 5, buf_ADX_Minus) < 5) return false;
   return true;
}

//+------------------------------------------------------------------+
//| ============ CORE SMART ENTRY ANALYSIS ============               |
//+------------------------------------------------------------------+
int AnalyzeEntry()
{
   // Get candle data
   CandleInfo candle1 = GetCandle(1);  // Completed candle
   CandleInfo candle2 = GetCandle(2);
   CandleInfo candle3 = GetCandle(3);
   
   // Get H1 trend
   double closeH1 = iClose(_Symbol, PERIOD_H1, 1);
   double emaH1 = buf_EMA_Trend[1];
   bool uptrend = (closeH1 > emaH1);
   bool downtrend = (closeH1 < emaH1);
   
   // Check trend strength with ADX
   bool strongTrend = (buf_ADX[1] >= ADX_Threshold);
   
   // =============== BUY ANALYSIS ===============
   if(uptrend)
   {
      int buyScore = 0;
      string buyReasons = "";
      
      // 1. EMA Structure: Fast > Slow (bullish alignment)
      if(buf_EMA_Fast[1] > buf_EMA_Slow[1])
      {
         buyScore += 1;
         buyReasons += "EMA+ ";
      }
      
      // 2. PULLBACK DETECTION: Price pulled back to EMA zone then bounced
      bool pullbackToBuy = IsBullishPullback(candle1, candle2, candle3);
      if(pullbackToBuy)
      {
         buyScore += 2;  // Higher weight for pullback
         buyReasons += "Pullback+ ";
      }
      
      // 3. BULLISH CANDLESTICK PATTERN
      bool bullishPattern = IsBullishCandlePattern(candle1, candle2);
      if(bullishPattern)
      {
         buyScore += 2;
         buyReasons += "CandlePattern+ ";
      }
      
      // 4. MOMENTUM CONFIRMATION: RSI rising from oversold area
      bool rsiConfirm = CheckRSI_BuySetup();
      if(rsiConfirm)
      {
         buyScore += 1;
         buyReasons += "RSI+ ";
      }
      
      // 5. STOCHASTIC: Cross up from oversold
      bool stochConfirm = CheckStoch_BuySetup();
      if(stochConfirm)
      {
         buyScore += 1;
         buyReasons += "Stoch+ ";
      }
      
      // 6. ADX CONFIRMATION: DI+ > DI- and strong trend
      if(strongTrend && buf_ADX_Plus[1] > buf_ADX_Minus[1])
      {
         buyScore += 1;
         buyReasons += "ADX+ ";
      }
      
      // 7. PRICE ABOVE KEY EMA
      if(candle1.close > buf_EMA_Fast[1])
      {
         buyScore += 1;
         buyReasons += "AboveEMA+ ";
      }
      
      // ====== DECISION: Need at least 5 points AND must have pullback OR pattern ======
      if(buyScore >= 5 && (pullbackToBuy || bullishPattern))
      {
         Print("✅ BUY Signal Score: ", buyScore, "/8 | Reasons: ", buyReasons);
         return 1;
      }
   }
   
   // =============== SELL ANALYSIS ===============
   if(downtrend)
   {
      int sellScore = 0;
      string sellReasons = "";
      
      // 1. EMA Structure: Fast < Slow (bearish alignment)
      if(buf_EMA_Fast[1] < buf_EMA_Slow[1])
      {
         sellScore += 1;
         sellReasons += "EMA+ ";
      }
      
      // 2. PULLBACK DETECTION: Price pulled back to EMA zone then rejected
      bool pullbackToSell = IsBearishPullback(candle1, candle2, candle3);
      if(pullbackToSell)
      {
         sellScore += 2;
         sellReasons += "Pullback+ ";
      }
      
      // 3. BEARISH CANDLESTICK PATTERN
      bool bearishPattern = IsBearishCandlePattern(candle1, candle2);
      if(bearishPattern)
      {
         sellScore += 2;
         sellReasons += "CandlePattern+ ";
      }
      
      // 4. MOMENTUM CONFIRMATION: RSI falling from overbought
      bool rsiConfirm = CheckRSI_SellSetup();
      if(rsiConfirm)
      {
         sellScore += 1;
         sellReasons += "RSI+ ";
      }
      
      // 5. STOCHASTIC: Cross down from overbought
      bool stochConfirm = CheckStoch_SellSetup();
      if(stochConfirm)
      {
         sellScore += 1;
         sellReasons += "Stoch+ ";
      }
      
      // 6. ADX CONFIRMATION: DI- > DI+ and strong trend
      if(strongTrend && buf_ADX_Minus[1] > buf_ADX_Plus[1])
      {
         sellScore += 1;
         sellReasons += "ADX+ ";
      }
      
      // 7. PRICE BELOW KEY EMA
      if(candle1.close < buf_EMA_Fast[1])
      {
         sellScore += 1;
         sellReasons += "BelowEMA+ ";
      }
      
      // ====== DECISION ======
      if(sellScore >= 5 && (pullbackToSell || bearishPattern))
      {
         Print("✅ SELL Signal Score: ", sellScore, "/8 | Reasons: ", sellReasons);
         return -1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| PULLBACK DETECTION - Bullish                                      |
//| Pattern: Price dipped to EMA zone then bounced with bullish close |
//+------------------------------------------------------------------+
bool IsBullishPullback(CandleInfo &c1, CandleInfo &c2, CandleInfo &c3)
{
   double emaFast = buf_EMA_Fast[1];
   double emaSlow = buf_EMA_Slow[1];
   
   // Check if recent candles touched or came close to EMA
   double emaZoneHigh = MathMax(emaFast, emaSlow) + PipsToPrice(3);
   double emaZoneLow = MathMin(emaFast, emaSlow) - PipsToPrice(3);
   
   // Condition: One of the recent candles touched the EMA zone
   bool touchedEMA = (c2.low <= emaZoneHigh && c2.low >= emaZoneLow) ||
                     (c3.low <= emaZoneHigh && c3.low >= emaZoneLow);
   
   // Condition: Current candle is bullish and closed above EMA
   bool bullishBounce = c1.isBullish && (c1.close > emaFast);
   
   // Condition: The low of current candle is above EMA (rejection)
   bool rejectedAtEMA = (c1.low >= emaZoneLow);
   
   return touchedEMA && bullishBounce && rejectedAtEMA;
}

//+------------------------------------------------------------------+
//| PULLBACK DETECTION - Bearish                                      |
//+------------------------------------------------------------------+
bool IsBearishPullback(CandleInfo &c1, CandleInfo &c2, CandleInfo &c3)
{
   double emaFast = buf_EMA_Fast[1];
   double emaSlow = buf_EMA_Slow[1];
   
   double emaZoneHigh = MathMax(emaFast, emaSlow) + PipsToPrice(3);
   double emaZoneLow = MathMin(emaFast, emaSlow) - PipsToPrice(3);
   
   bool touchedEMA = (c2.high >= emaZoneLow && c2.high <= emaZoneHigh) ||
                     (c3.high >= emaZoneLow && c3.high <= emaZoneHigh);
   
   bool bearishBounce = c1.isBearish && (c1.close < emaFast);
   bool rejectedAtEMA = (c1.high <= emaZoneHigh);
   
   return touchedEMA && bearishBounce && rejectedAtEMA;
}

//+------------------------------------------------------------------+
//| BULLISH CANDLESTICK PATTERNS                                      |
//+------------------------------------------------------------------+
bool IsBullishCandlePattern(CandleInfo &c1, CandleInfo &c2)
{
   double avgRange = buf_ATR[1];
   
   // 1. BULLISH ENGULFING: Current bullish candle engulfs previous bearish
   bool engulfing = c2.isBearish && c1.isBullish &&
                    (c1.close > c2.open) && (c1.open < c2.close) &&
                    (c1.body > c2.body);
   if(engulfing) return true;
   
   // 2. HAMMER / PIN BAR: Long lower wick, small body at top
   bool hammer = c1.isBullish &&
                 (c1.lowerWick >= c1.body * 2) &&
                 (c1.upperWick < c1.body * 0.5) &&
                 (c1.range >= avgRange * 0.5);
   if(hammer) return true;
   
   // 3. BULLISH PIERCING: Strong bullish candle closing above 50% of prev bearish
   bool piercing = c2.isBearish && c1.isBullish &&
                   (c1.open < c2.close) &&
                   (c1.close > (c2.open + c2.close) / 2) &&
                   (c1.body >= avgRange * 0.5);
   if(piercing) return true;
   
   // 4. STRONG BULLISH CANDLE: Large body, small wicks
   bool strongBull = c1.isBullish &&
                     (c1.body >= avgRange * 0.7) &&
                     (c1.upperWick < c1.body * 0.3) &&
                     (c1.lowerWick < c1.body * 0.3);
   if(strongBull) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| BEARISH CANDLESTICK PATTERNS                                      |
//+------------------------------------------------------------------+
bool IsBearishCandlePattern(CandleInfo &c1, CandleInfo &c2)
{
   double avgRange = buf_ATR[1];
   
   // 1. BEARISH ENGULFING
   bool engulfing = c2.isBullish && c1.isBearish &&
                    (c1.close < c2.open) && (c1.open > c2.close) &&
                    (c1.body > c2.body);
   if(engulfing) return true;
   
   // 2. SHOOTING STAR / INVERTED PIN BAR
   bool shootingStar = c1.isBearish &&
                       (c1.upperWick >= c1.body * 2) &&
                       (c1.lowerWick < c1.body * 0.5) &&
                       (c1.range >= avgRange * 0.5);
   if(shootingStar) return true;
   
   // 3. DARK CLOUD COVER
   bool darkCloud = c2.isBullish && c1.isBearish &&
                    (c1.open > c2.close) &&
                    (c1.close < (c2.open + c2.close) / 2) &&
                    (c1.body >= avgRange * 0.5);
   if(darkCloud) return true;
   
   // 4. STRONG BEARISH CANDLE
   bool strongBear = c1.isBearish &&
                     (c1.body >= avgRange * 0.7) &&
                     (c1.upperWick < c1.body * 0.3) &&
                     (c1.lowerWick < c1.body * 0.3);
   if(strongBear) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| RSI BUY SETUP: Rising from oversold or bullish divergence zone   |
//+------------------------------------------------------------------+
bool CheckRSI_BuySetup()
{
   double rsi1 = buf_RSI[1];
   double rsi2 = buf_RSI[2];
   double rsi3 = buf_RSI[3];
   
   // RSI between 40-60 and rising (momentum building)
   bool inBuyZone = (rsi1 >= 40 && rsi1 <= 65);
   bool rising = (rsi1 > rsi2);
   
   // Or: RSI was oversold and now recovering
   bool fromOversold = (rsi3 < 35 || rsi2 < 35) && (rsi1 > 35);
   
   return (inBuyZone && rising) || fromOversold;
}

//+------------------------------------------------------------------+
//| RSI SELL SETUP                                                    |
//+------------------------------------------------------------------+
bool CheckRSI_SellSetup()
{
   double rsi1 = buf_RSI[1];
   double rsi2 = buf_RSI[2];
   double rsi3 = buf_RSI[3];
   
   bool inSellZone = (rsi1 >= 35 && rsi1 <= 60);
   bool falling = (rsi1 < rsi2);
   bool fromOverbought = (rsi3 > 65 || rsi2 > 65) && (rsi1 < 65);
   
   return (inSellZone && falling) || fromOverbought;
}

//+------------------------------------------------------------------+
//| STOCHASTIC BUY SETUP: Cross up from oversold                      |
//+------------------------------------------------------------------+
bool CheckStoch_BuySetup()
{
   double k1 = buf_Stoch_K[1];
   double d1 = buf_Stoch_D[1];
   double k2 = buf_Stoch_K[2];
   double d2 = buf_Stoch_D[2];
   
   // Cross up: K was below D, now K above D, and in lower zone
   bool crossUp = (k2 <= d2) && (k1 > d1);
   bool wasOversold = (k2 < 30 || d2 < 30);
   bool rising = (k1 > k2);
   
   return (crossUp && wasOversold) || (wasOversold && rising && k1 < 50);
}

//+------------------------------------------------------------------+
//| STOCHASTIC SELL SETUP                                             |
//+------------------------------------------------------------------+
bool CheckStoch_SellSetup()
{
   double k1 = buf_Stoch_K[1];
   double d1 = buf_Stoch_D[1];
   double k2 = buf_Stoch_K[2];
   double d2 = buf_Stoch_D[2];
   
   bool crossDown = (k2 >= d2) && (k1 < d1);
   bool wasOverbought = (k2 > 70 || d2 > 70);
   bool falling = (k1 < k2);
   
   return (crossDown && wasOverbought) || (wasOverbought && falling && k1 > 50);
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss                                       |
//+------------------------------------------------------------------+
double GetDynamicSL()
{
   if(UseATR_SL)
   {
      double atr = buf_ATR[1];
      double atrPips = atr / g_pipValue;
      double dynamicSL = atrPips * ATR_Multiplier;
      return MathMax(dynamicSL, SL_Pips * 0.5);  // Min 50% of fixed SL
   }
   return SL_Pips;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                    |
//+------------------------------------------------------------------+
void OpenBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double slPips = GetDynamicSL();
   double tpPips = TP_Pips;
   
   // Use swing low for SL if better
   double swingLow = FindSwingLow(10);
   double swingSlPips = (ask - swingLow) / g_pipValue + 2;  // +2 pips buffer
   if(swingSlPips > 5 && swingSlPips < slPips)
      slPips = swingSlPips;
   
   double sl = ask - PipsToPrice(slPips);
   double tp = ask + PipsToPrice(tpPips);
   
   double lotSize = CalculateLotSize(slPips);
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   if(trade.Buy(lotSize, _Symbol, ask, sl, tp, TradeComment))
   {
      g_dailyTrades++;
      Print("✅ BUY: Lot=", lotSize, " SL=", DoubleToString(slPips, 1), "p TP=", DoubleToString(tpPips, 1), "p");
   }
   else
      Print("❌ BUY Failed: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                   |
//+------------------------------------------------------------------+
void OpenSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPips = GetDynamicSL();
   double tpPips = TP_Pips;
   
   // Use swing high for SL if better
   double swingHigh = FindSwingHigh(10);
   double swingSlPips = (swingHigh - bid) / g_pipValue + 2;
   if(swingSlPips > 5 && swingSlPips < slPips)
      slPips = swingSlPips;
   
   double sl = bid + PipsToPrice(slPips);
   double tp = bid - PipsToPrice(tpPips);
   
   double lotSize = CalculateLotSize(slPips);
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   if(trade.Sell(lotSize, _Symbol, bid, sl, tp, TradeComment))
   {
      g_dailyTrades++;
      Print("✅ SELL: Lot=", lotSize, " SL=", DoubleToString(slPips, 1), "p TP=", DoubleToString(tpPips, 1), "p");
   }
   else
      Print("❌ SELL Failed: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Find Swing Low                                                    |
//+------------------------------------------------------------------+
double FindSwingLow(int lookback)
{
   double lowest = iLow(_Symbol, PERIOD_M5, 1);
   for(int i = 2; i <= lookback; i++)
   {
      double low = iLow(_Symbol, PERIOD_M5, i);
      if(low < lowest) lowest = low;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Find Swing High                                                   |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookback)
{
   double highest = iHigh(_Symbol, PERIOD_M5, 1);
   for(int i = 2; i <= lookback; i++)
   {
      double high = iHigh(_Symbol, PERIOD_M5, i);
      if(high > highest) highest = high;
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   double equity = accountInfo.Equity();
   double riskAmount = equity * (RiskPercent / 100.0);
   
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   double slPoints = slPips * g_pipValue / _Point;
   double pointValue = tickValue / (tickSize / _Point);
   double lotSize = riskAmount / (slPoints * pointValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
//| Manage Positions - Break Even & Trailing                          |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber) continue;
      
      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      double currentTP = posInfo.TakeProfit();
      ulong ticket = posInfo.Ticket();
      
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitPips = (bid - openPrice) / g_pipValue;
         
         // Break Even
         if(UseBreakEven && profitPips >= BE_TriggerPips)
         {
            double newSL = openPrice + PipsToPrice(BE_ProfitPips);
            if(currentSL < newSL)
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), currentTP);
         }
         
         // Trailing
         if(UseTrailing && profitPips >= TrailStartPips)
         {
            double trailSL = bid - PipsToPrice(TrailStartPips);
            if(trailSL > currentSL + PipsToPrice(TrailStepPips))
               trade.PositionModify(ticket, NormalizeDouble(trailSL, _Digits), currentTP);
         }
      }
      else // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPips = (openPrice - ask) / g_pipValue;
         
         if(UseBreakEven && profitPips >= BE_TriggerPips)
         {
            double newSL = openPrice - PipsToPrice(BE_ProfitPips);
            if(currentSL == 0 || currentSL > newSL)
               trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), currentTP);
         }
         
         if(UseTrailing && profitPips >= TrailStartPips)
         {
            double trailSL = ask + PipsToPrice(TrailStartPips);
            if(currentSL == 0 || trailSL < currentSL - PipsToPrice(TrailStepPips))
               trade.PositionModify(ticket, NormalizeDouble(trailSL, _Digits), currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Utility Functions                                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == MagicNumber)
            return true;
   }
   return false;
}

int CountTodayTrades()
{
   int count = 0;
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(today, TimeCurrent());
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) == (long)MagicNumber &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         count++;
   }
   return count;
}

void CheckNewDay()
{
   MqlDateTime now, last;
   TimeToStruct(TimeCurrent(), now);
   TimeToStruct(g_lastTradeDate, last);
   
   if(now.day != last.day)
   {
      g_dailyTrades = 0;
      g_dailyStartEquity = accountInfo.Equity();
      g_lastTradeDate = TimeCurrent();
   }
}

bool IsDailyLossExceeded()
{
   double loss = g_dailyStartEquity - accountInfo.Equity();
   return (loss >= g_dailyStartEquity * (MaxDailyLossPercent / 100.0));
}

bool IsTradeTime()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return (StartHour < EndHour) ? 
          (now.hour >= StartHour && now.hour < EndHour) :
          (now.hour >= StartHour || now.hour < EndHour);
}

double GetSpreadPips()
{
   return (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point / g_pipValue;
}

bool IsSpreadOK() { return GetSpreadPips() <= MaxSpreadPips; }

//+------------------------------------------------------------------+
//| Display Info                                                      |
//+------------------------------------------------------------------+
void DisplayInfo(int signal)
{
   double equity = accountInfo.Equity();
   double dailyPL = equity - g_dailyStartEquity;
   
   string signalStr = (signal == 1) ? "🟢 BUY" : (signal == -1) ? "🔴 SELL" : "⚪ WAIT";
   double closeH1 = iClose(_Symbol, PERIOD_H1, 1);
   string trendStr = (closeH1 > buf_EMA_Trend[1]) ? "📈 UPTREND" : "📉 DOWNTREND";
   
   string info = "";
   info += "╔════════════════════════════════════════╗\n";
   info += "║     MOMO-TREND v3.0 - SMART ENTRY      ║\n";
   info += "╠════════════════════════════════════════╣\n";
   info += StringFormat("║ 💰 Equity: $%.2f | PL: %+.2f\n", equity, dailyPL);
   info += StringFormat("║ 📊 Trades: %d/%d | Spread: %.1f\n", g_dailyTrades, MaxDailyTrades, GetSpreadPips());
   info += "╠════════════════════════════════════════╣\n";
   info += StringFormat("║ 🎯 Signal: %s\n", signalStr);
   info += StringFormat("║ 📈 H1: %s\n", trendStr);
   info += StringFormat("║ 📊 ADX: %.1f | RSI: %.1f\n", buf_ADX[1], buf_RSI[1]);
   info += StringFormat("║ 📉 Stoch: K=%.1f D=%.1f\n", buf_Stoch_K[1], buf_Stoch_D[1]);
   info += "╚════════════════════════════════════════╝\n";
   
   Comment(info);
}

void OnTrade() { g_dailyTrades = CountTodayTrades(); }
//+------------------------------------------------------------------+

double OnTester()
{
   if(!MQLInfoInteger(MQL_TESTER)) return 0;

   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DD_RELATIVE);

   if(dd > 0.0001) return profit / dd;
   return profit;
}
