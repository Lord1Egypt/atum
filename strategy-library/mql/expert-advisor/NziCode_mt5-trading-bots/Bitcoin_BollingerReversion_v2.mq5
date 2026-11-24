//+------------------------------------------------------------------+
//| Bitcoin_BollingerReversion_v2.mq5                                |
//| Bollinger + RSI + EMA | Multi-TP + Risk-Free + Trailing          |
//+------------------------------------------------------------------+
#property copyright "mt5-trading-bots"
#property version   "2.00"
#include <Trade\Trade.mqh>

input double LotSize         = 0.1;
input int    BB_Period       = 20;
input double BB_Dev          = 2.0;
input int    RSI_Period      = 14;
input double RSI_OB          = 65.0;   // lowered from 70 → more signals
input double RSI_OS          = 35.0;   // raised from 30
input int    EMA_Trend       = 100;
input double SL_Pct          = 0.008;  // 0.8% SL
input double TP1_Pct         = 0.010;  // TP1 1.0%
input double TP2_Pct         = 0.018;  // TP2 1.8%
input double TP3_Pct         = 0.028;  // TP3 2.8%
input double TrailingPct     = 0.008;  // trailing distance 0.8%
input int    MaxTradesPerDay = 3;
input double MaxDailyLoss    = 80.0;
input int    CooldownBars    = 5;
input int    Magic           = 20003;

CTrade trade;
int hBB, hRSI, hEma;
datetime lastBarTime = 0;
int tradeCountToday  = 0;
datetime lastTradeDay = 0;
int barsSinceLastTrade = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   hBB  = iBands(_Symbol, PERIOD_M15, BB_Period, 0, BB_Dev, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_M15, RSI_Period, PRICE_CLOSE);
   hEma = iMA(_Symbol, PERIOD_M15, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   if(hBB==INVALID_HANDLE || hRSI==INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hBB); IndicatorRelease(hRSI); IndicatorRelease(hEma);
}

double GetDailyPnL()
{
   double pnl = 0;
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(dayStart, TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic)
         pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
   }
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionGetInteger(POSITION_MAGIC) == Magic)
         pnl += PositionGetDouble(POSITION_PROFIT);
   return pnl;
}

bool IsNewBar()
{
   datetime t[];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t) < 1) return false;
   if(t[0] == lastBarTime) return false;
   lastBarTime = t[0]; barsSinceLastTrade++;
   return true;
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double curPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
      int    posType   = (int)PositionGetInteger(POSITION_TYPE);
      double lots      = PositionGetDouble(POSITION_VOLUME);

      double profitPct = (posType == POSITION_TYPE_BUY)
                         ? (curPrice - openPrice) / openPrice
                         : (openPrice - curPrice) / openPrice;

      if(profitPct >= TP1_Pct)
      {
         double newSL = (posType == POSITION_TYPE_BUY) ? openPrice * 1.001 : openPrice * 0.999;
         if((posType == POSITION_TYPE_BUY && newSL > sl) ||
            (posType == POSITION_TYPE_SELL && (sl == 0 || newSL < sl)))
            trade.PositionModify(ticket, newSL, tp);
         double cv = NormalizeDouble(lots * 0.4, 2);
         if(cv >= 0.01) trade.PositionClosePartial(ticket, cv);
      }
      if(profitPct >= TP2_Pct)
      {
         double cv = NormalizeDouble(lots * 0.43, 2);
         if(cv >= 0.01) trade.PositionClosePartial(ticket, cv);
      }
      if(profitPct >= TP1_Pct)
      {
         double trailDist = openPrice * TrailingPct;
         double trailSL;
         if(posType == POSITION_TYPE_BUY) { trailSL = curPrice - trailDist; if(trailSL > sl) trade.PositionModify(ticket, trailSL, tp); }
         else { trailSL = curPrice + trailDist; if(sl==0||trailSL<sl) trade.PositionModify(ticket, trailSL, tp); }
      }
   }
}

void OnTick()
{
   ManagePositions();
   if(!IsNewBar()) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != lastTradeDay) { tradeCountToday = 0; lastTradeDay = today; }

   if(tradeCountToday >= MaxTradesPerDay) return;
   if(GetDailyPnL() <= -MaxDailyLoss) return;
   if(barsSinceLastTrade < CooldownBars) return;

   int ownPos = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC)==Magic) ownPos++;
   if(ownPos >= 1) return;

   double upper[], lower[], middle[], rsi[], ema[];
   if(CopyBuffer(hBB,  1, 0, 2, upper)  < 2) return;
   if(CopyBuffer(hBB,  2, 0, 2, lower)  < 2) return;
   if(CopyBuffer(hBB,  0, 0, 2, middle) < 2) return;
   if(CopyBuffer(hRSI, 0, 0, 2, rsi)    < 2) return;
   if(CopyBuffer(hEma, 0, 0, 2, ema)    < 2) return;

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Buy: price touched lower band + RSI oversold + above EMA trend + RSI turning up
   if(close1 <= lower[1] && rsi[0] < RSI_OS && close1 > ema[0] && rsi[0] > rsi[1])
   {
      double sl = ask * (1 - SL_Pct);
      double tp = ask * (1 + TP3_Pct);
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp))
      { tradeCountToday++; barsSinceLastTrade = 0; }
   }
   // Sell: price touched upper band + RSI overbought + below EMA + RSI turning down
   else if(close1 >= upper[1] && rsi[0] > RSI_OB && close1 < ema[0] && rsi[0] < rsi[1])
   {
      double sl = bid * (1 + SL_Pct);
      double tp = bid * (1 - TP3_Pct);
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp))
      { tradeCountToday++; barsSinceLastTrade = 0; }
   }
}
