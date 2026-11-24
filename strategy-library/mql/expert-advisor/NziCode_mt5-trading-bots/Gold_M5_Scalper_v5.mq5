//+------------------------------------------------------------------+
//|                                    Gold_M5_Scalper_v5.mq5         |
//|  M5 scalping EA — lower noise than M1                             |
//|  Strategy: EMA9/EMA21 cross for direction + RSI(14) OB/OS filter  |
//|  Risk: SL behind last swing high/low, R:R >= 1:2, risk % sizing   |
//|  Session filter: London/New York overlap only                    |
//+------------------------------------------------------------------+
#property copyright "Nzicode"
#property version   "5.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Core strategy inputs
input int    EMA_Fast             = 9;
input int    EMA_Slow             = 21;
input int    RSI_Period           = 14;
input double RSI_OverboughtLevel  = 70.0;   // avoid new buys above this
input double RSI_OversoldLevel    = 30.0;   // avoid new sells below this

//--- Swing detection (for SL placement)
input int    SwingLookbackBars    = 10;     // how many bars back to find the swing high/low
input double SwingBufferPoints    = 30;     // extra buffer beyond the swing point

//--- Risk management
input double RiskPercent          = 1.0;    // % of balance risked per trade (1-2% recommended)
input double MinRR                = 2.0;    // minimum reward:risk ratio (TP = SL_distance * MinRR)
input double MaxLotSize            = 1.0;    // safety cap regardless of calculated size

//--- Trade management
input int    BreakevenAfterRR     = 1;      // move to breakeven once price moves 1x the SL distance in profit
input int    BreakevenLockPoints  = 20;
input bool   UseTrailing          = true;
input int    TrailingStartRR      = 1;      // start trailing once 1x SL distance in profit
input double TrailingATRMultiple  = 1.5;
input int    ATR_Period           = 14;

//--- Session filter (BROKER/SERVER time, not Tehran time — check your broker's GMT offset
//    and adjust these hours so they correspond to ~11:00-20:00 Tehran time / London-NY overlap)
input bool   UseSessionFilter     = true;
input int    SessionStartHour     = 8;      // server-time hour session opens
input int    SessionEndHour       = 17;     // server-time hour session closes

//--- General
input int    CooldownSeconds      = 60;
input int    MaxConcurrentPositions = 2;
input int    MaxTradesPerDay      = 20;
input double DailyLossLimitUSD    = 100.0;
input int    MagicNumber          = 20260712;
input bool   DebugLogging         = true;

//--- Globals
int    emaFastHandle, emaSlowHandle, rsiHandle, atrHandle;
datetime lastTradeTime = 0;
int      tradesToday = 0;
datetime currentDay = 0;
double   dayRealizedPL = 0;

int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_M5, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M5, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle     = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   atrHandle     = iATR(_Symbol, PERIOD_M5, ATR_Period);
   trade.SetExpertMagicNumber(MagicNumber);
   ResetDailyCounters();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
}

void RecalculateDailyStatsFromHistory()
{
   dayRealizedPL = 0;
   tradesToday   = 0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(!HistorySelect(dayStart, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;

      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                     + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                     + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      dayRealizedPL += profit;
      if(entry == DEAL_ENTRY_IN) tradesToday++;
   }
}

void ResetDailyCounters()
{
   currentDay = iTime(_Symbol, PERIOD_D1, 0);
   RecalculateDailyStatsFromHistory();
}

bool NewDayCheck()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != currentDay) { ResetDailyCounters(); return true; }
   return false;
}

double GetPoint() { return _Point; }

bool InSession()
{
   if(!UseSessionFilter) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int h = t.hour;
   if(SessionStartHour <= SessionEndHour)
      return (h >= SessionStartHour && h < SessionEndHour);
   else // overnight session wrap
      return (h >= SessionStartHour || h < SessionEndHour);
}

int CountOwnOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      count++;
   }
   return count;
}

//--- Find the most recent swing low over the lookback window (for BUY stop-loss placement)
double FindSwingLow(int bars)
{
   int idx = iLowest(_Symbol, PERIOD_M5, MODE_LOW, bars, 1);
   if(idx < 0) return 0;
   return iLow(_Symbol, PERIOD_M5, idx);
}

//--- Find the most recent swing high over the lookback window (for SELL stop-loss placement)
double FindSwingHigh(int bars)
{
   int idx = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, bars, 1);
   if(idx < 0) return 0;
   return iHigh(_Symbol, PERIOD_M5, idx);
}

//--- Calculate lot size so that (SL distance in price) * (lot * tick value) ~= risk amount
double CalculateLotSize(double slDistancePrice)
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lots = riskAmount / lossPerLot;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = MathMin(MaxLotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lotMin, MathMin(lotMax, lots));
   return NormalizeDouble(lots, 2);
}

void ManageOpenPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                      : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double originalSLDistance = MathAbs(openPrice - sl); // distance at open; sl may have moved since
      // Recompute the "1R" distance from TP and open price instead, since sl may already be at BE
      double riskUnit = MathAbs(tp - openPrice) / MinRR; // 1R in price terms
      if(riskUnit <= 0) continue;

      double profitPrice = (type == POSITION_TYPE_BUY) ? (curPrice - openPrice) : (openPrice - curPrice);
      double profitR = profitPrice / riskUnit;

      bool atBE = (type == POSITION_TYPE_BUY) ? (sl >= openPrice) : (sl != 0 && sl <= openPrice);
      if(profitR >= BreakevenAfterRR && !atBE)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? openPrice + BreakevenLockPoints*GetPoint()
                                                      : openPrice - BreakevenLockPoints*GetPoint();
         trade.PositionModify(ticket, newSL, tp);
      }

      if(UseTrailing && profitR >= TrailingStartRR)
      {
         double atr[1];
         if(CopyBuffer(atrHandle, 0, 0, 1, atr) == 1)
         {
            double trailDist = atr[0] * TrailingATRMultiple;
            double newSL = (type == POSITION_TYPE_BUY) ? curPrice - trailDist : curPrice + trailDist;
            if(type == POSITION_TYPE_BUY && (sl == 0 || newSL > sl))
               trade.PositionModify(ticket, newSL, tp);
            else if(type == POSITION_TYPE_SELL && (sl == 0 || newSL < sl))
               trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

bool DailyLimitsHit()
{
   if(dayRealizedPL <= -MathAbs(DailyLossLimitUSD)) return true;
   if(tradesToday >= MaxTradesPerDay) return true;
   return false;
}

void TryOpenTrade()
{
   if(!InSession()) { if(DebugLogging) Print("SKIP: outside session"); return; }
   if(TimeCurrent() - lastTradeTime < CooldownSeconds) return;
   if(DailyLimitsHit()) { if(DebugLogging) Print("SKIP: daily limit hit"); return; }
   if(CountOwnOpenPositions() >= MaxConcurrentPositions) return;

   double emaFast[2], emaSlow[2], rsi[1];
   if(CopyBuffer(emaFastHandle, 0, 0, 2, emaFast) < 2) return;
   if(CopyBuffer(emaSlowHandle, 0, 0, 2, emaSlow) < 2) return;
   if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) < 1) return;

   bool bullTrend = emaFast[0] > emaSlow[0];
   bool bearTrend = emaFast[0] < emaSlow[0];
   bool bullCrossJustHappened = emaFast[1] <= emaSlow[1] && emaFast[0] > emaSlow[0];
   bool bearCrossJustHappened = emaFast[1] >= emaSlow[1] && emaFast[0] < emaSlow[0];

   bool rsiOkForBuy  = rsi[0] < RSI_OverboughtLevel;
   bool rsiOkForSell = rsi[0] > RSI_OversoldLevel;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- BUY: fresh bullish cross (or established uptrend), RSI not overbought
   if((bullCrossJustHappened || bullTrend) && rsiOkForBuy)
   {
      double swingLow = FindSwingLow(SwingLookbackBars);
      if(swingLow <= 0) { if(DebugLogging) Print("SKIP: no valid swing low"); return; }
      double sl = swingLow - SwingBufferPoints*GetPoint();
      double slDist = ask - sl;
      if(slDist <= 0) { if(DebugLogging) Print("SKIP: invalid SL distance (swing too close/above price)"); return; }
      double tp = ask + slDist * MinRR;

      double lots = CalculateLotSize(slDist);
      if(trade.Buy(lots, _Symbol, ask, sl, tp, "GoldM5v5"))
      {
         lastTradeTime = TimeCurrent();
         tradesToday++;
         if(DebugLogging) Print("BUY opened lots=",lots," sl=",sl," tp=",tp);
      }
      else if(DebugLogging) Print("BUY FAILED retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      return;
   }

   //--- SELL: fresh bearish cross (or established downtrend), RSI not oversold
   if((bearCrossJustHappened || bearTrend) && rsiOkForSell)
   {
      double swingHigh = FindSwingHigh(SwingLookbackBars);
      if(swingHigh <= 0) { if(DebugLogging) Print("SKIP: no valid swing high"); return; }
      double sl = swingHigh + SwingBufferPoints*GetPoint();
      double slDist = sl - bid;
      if(slDist <= 0) { if(DebugLogging) Print("SKIP: invalid SL distance (swing too close/below price)"); return; }
      double tp = bid - slDist * MinRR;

      double lots = CalculateLotSize(slDist);
      if(trade.Sell(lots, _Symbol, bid, sl, tp, "GoldM5v5"))
      {
         lastTradeTime = TimeCurrent();
         tradesToday++;
         if(DebugLogging) Print("SELL opened lots=",lots," sl=",sl," tp=",tp);
      }
      else if(DebugLogging) Print("SELL FAILED retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      return;
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      RecalculateDailyStatsFromHistory();
}

void OnTick()
{
   NewDayCheck();
   ManageOpenPositions();
   TryOpenTrade();
}
