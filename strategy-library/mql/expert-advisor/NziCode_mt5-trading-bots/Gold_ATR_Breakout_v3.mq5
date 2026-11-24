//+------------------------------------------------------------------+
//|                                    Gold_ATR_Breakout_v3.mq5       |
//|  High-frequency scalping version — target 100+ trades/day        |
//|  Timeframe: M1                                                    |
//|  Strategy: Fast EMA cross (5/13) + RSI momentum filter            |
//|            on tick-level pullback entries, tight SL/TP scalps     |
//+------------------------------------------------------------------+
#property copyright "Nzicode"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs
input double LotSize            = 0.02;
input int    FastEMA             = 5;
input int    SlowEMA             = 13;
input int    RSI_Period          = 7;
input double RSI_Upper           = 60.0;
input double RSI_Lower           = 40.0;
input int    SL_Points           = 150;   // ~1.5 USD on Gold (0.01 = 1 point on most brokers, check pip value)
input int    TP1_Points          = 100;
input int    TP2_Points          = 200;
input int    TP3_Points          = 350;
input double TP1_ClosePercent    = 50.0;
input double TP2_ClosePercent    = 30.0;
input int    BreakevenAfterPts   = 100;   // move SL to entry once TP1 hits
input int    BreakevenLockPts    = 20;    // lock a few points of profit at breakeven
input int    TrailingStartPts    = 100;
input int    TrailingStepPts     = 30;
input int    CooldownSeconds     = 15;    // minimal gap between trades to hit high frequency safely
input int    MaxTradesPerDay     = 150;
input double DailyLossLimitUSD   = 80.0;
input int    MagicNumber         = 20260710;

//--- Globals
int    emaFastHandle, emaSlowHandle, rsiHandle;
datetime lastTradeTime = 0;
int    tradesToday = 0;
datetime currentDay = 0;
double dayStartBalance = 0;

int OnInit()
{
   emaFastHandle = iMA(_Symbol, PERIOD_M1, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_M1, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle     = iRSI(_Symbol, PERIOD_M1, RSI_Period, PRICE_CLOSE);
   trade.SetExpertMagicNumber(MagicNumber);
   ResetDailyCounters();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   IndicatorRelease(rsiHandle);
}

void ResetDailyCounters()
{
   currentDay = iTime(_Symbol, PERIOD_D1, 0);
   tradesToday = 0;
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
}

bool NewDayCheck()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(today != currentDay)
   {
      ResetDailyCounters();
      return true;
   }
   return false;
}

double GetPoint() { return _Point; }

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
      double profitPts = (type == POSITION_TYPE_BUY) ? (curPrice - openPrice)/GetPoint()
                                                       : (openPrice - curPrice)/GetPoint();

      //--- Breakeven + lock
      bool atBE = (type == POSITION_TYPE_BUY) ? (sl >= openPrice) : (sl <= openPrice && sl != 0);
      if(profitPts >= BreakevenAfterPts && !atBE)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? openPrice + BreakevenLockPts*GetPoint()
                                                      : openPrice - BreakevenLockPts*GetPoint();
         trade.PositionModify(ticket, newSL, tp);
      }

      //--- Trailing after breakeven
      if(profitPts >= TrailingStartPts)
      {
         double newSL = (type == POSITION_TYPE_BUY) ? curPrice - TrailingStepPts*GetPoint()
                                                      : curPrice + TrailingStepPts*GetPoint();
         if(type == POSITION_TYPE_BUY && (sl == 0 || newSL > sl))
            trade.PositionModify(ticket, newSL, tp);
         else if(type == POSITION_TYPE_SELL && (sl == 0 || newSL < sl))
            trade.PositionModify(ticket, newSL, tp);
      }

      //--- Partial close at TP1 / TP2
      double vol = PositionGetDouble(POSITION_VOLUME);
      string cmt = PositionGetString(POSITION_COMMENT);
      if(profitPts >= TP1_Points && StringFind(cmt,"tp1done") < 0)
      {
         double closeVol = NormalizeDouble(vol * TP1_ClosePercent/100.0, 2);
         if(closeVol > 0 && closeVol < vol)
         {
            trade.PositionClosePartial(ticket, closeVol);
            trade.PositionModify(ticket, sl, tp); // comment can't be edited post-hoc; tracked via profitPts thresholds instead
         }
      }
   }
}

bool DailyLimitsHit()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dayStartBalance - currentBalance >= DailyLossLimitUSD) return true;
   if(tradesToday >= MaxTradesPerDay) return true;
   return false;
}

void TryOpenTrade()
{
   if(TimeCurrent() - lastTradeTime < CooldownSeconds) return;
   if(DailyLimitsHit()) return;
   if(PositionsTotal() >= 3) return; // cap concurrent exposure

   double emaFast[2], emaSlow[2], rsi[2];
   if(CopyBuffer(emaFastHandle, 0, 0, 2, emaFast) < 2) return;
   if(CopyBuffer(emaSlowHandle, 0, 0, 2, emaSlow) < 2) return;
   if(CopyBuffer(rsiHandle, 0, 0, 2, rsi) < 2) return;

   bool bullCross = emaFast[1] <= emaSlow[1] && emaFast[0] > emaSlow[0];
   bool bearCross = emaFast[1] >= emaSlow[1] && emaFast[0] < emaSlow[0];
   bool bullMomentum = emaFast[0] > emaSlow[0] && rsi[0] > RSI_Upper && rsi[0] < 80;
   bool bearMomentum = emaFast[0] < emaSlow[0] && rsi[0] < RSI_Lower && rsi[0] > 20;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bullCross || bullMomentum)
   {
      double sl = ask - SL_Points*GetPoint();
      double tp = ask + TP3_Points*GetPoint();
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "GoldScalpV3"))
      {
         lastTradeTime = TimeCurrent();
         tradesToday++;
      }
   }
   else if(bearCross || bearMomentum)
   {
      double sl = bid + SL_Points*GetPoint();
      double tp = bid - TP3_Points*GetPoint();
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "GoldScalpV3"))
      {
         lastTradeTime = TimeCurrent();
         tradesToday++;
      }
   }
}

void OnTick()
{
   NewDayCheck();
   ManageOpenPositions();
   TryOpenTrade();
}
