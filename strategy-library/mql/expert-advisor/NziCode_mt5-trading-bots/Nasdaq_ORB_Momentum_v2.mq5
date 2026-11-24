//+------------------------------------------------------------------+
//| Nasdaq_ORB_Momentum_v2.mq5                                       |
//| Opening Range Breakout | Multi-TP + Risk-Free + Trailing         |
//+------------------------------------------------------------------+
#property copyright "mt5-trading-bots"
#property version   "2.00"
#include <Trade\Trade.mqh>

input double LotSize         = 0.1;
input int    ORB_StartHour   = 14;     // 14:30 UTC (NY open)
input int    ORB_StartMin    = 30;
input int    ORB_Mins        = 15;     // reduced from 30 → faster signal
input int    TradingEndHour  = 20;
input double SL_Pct          = 0.004;  // 0.4% SL
input double TP1_Pct         = 0.005;  // TP1
input double TP2_Pct         = 0.009;  // TP2
input double TP3_Pct         = 0.014;  // TP3
input double TrailingPct     = 0.004;
input int    MaxTradesPerDay = 2;
input double MaxDailyLoss    = 100.0;
input int    Magic           = 20004;

CTrade trade;
datetime lastBarTime = 0;
int tradeCountToday  = 0;
datetime lastTradeDay = 0;
double orbHigh = 0, orbLow = 0;
bool orbSet = false, tradedToday = false;

int OnInit() { trade.SetExpertMagicNumber(Magic); return INIT_SUCCEEDED; }

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
   lastBarTime = t[0]; return true;
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;

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
         if((posType==POSITION_TYPE_BUY && newSL>sl)||(posType==POSITION_TYPE_SELL&&(sl==0||newSL<sl)))
            trade.PositionModify(ticket, newSL, tp);
         double cv = NormalizeDouble(lots*0.4, 2);
         if(cv >= 0.01) trade.PositionClosePartial(ticket, cv);
      }
      if(profitPct >= TP2_Pct)
      {
         double cv = NormalizeDouble(lots*0.43, 2);
         if(cv >= 0.01) trade.PositionClosePartial(ticket, cv);
      }
      if(profitPct >= TP1_Pct)
      {
         double trailDist = openPrice * TrailingPct;
         double trailSL;
         if(posType==POSITION_TYPE_BUY){ trailSL=curPrice-trailDist; if(trailSL>sl) trade.PositionModify(ticket,trailSL,tp); }
         else { trailSL=curPrice+trailDist; if(sl==0||trailSL<sl) trade.PositionModify(ticket,trailSL,tp); }
      }
   }
}

void OnTick()
{
   ManagePositions();
   if(!IsNewBar()) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != lastTradeDay)
   { tradeCountToday=0; lastTradeDay=today; orbSet=false; orbHigh=0; orbLow=0; tradedToday=false; }

   if(tradeCountToday >= MaxTradesPerDay) return;
   if(GetDailyPnL() <= -MaxDailyLoss) return;

   int curHour = dt.hour, curMin = dt.min;
   int orbEndHour = ORB_StartHour + (ORB_StartMin + ORB_Mins) / 60;
   int orbEndMin  = (ORB_StartMin + ORB_Mins) % 60;

   // Build ORB range
   if(!orbSet)
   {
      bool inORB = (curHour == ORB_StartHour && curMin >= ORB_StartMin) ||
                   (curHour == orbEndHour && curMin < orbEndMin);
      if(inORB)
      {
         double h[], l[];
         int barsInRange = ORB_Mins / 15 + 1;
         if(CopyHigh(_Symbol, PERIOD_M15, 0, barsInRange, h) < barsInRange) return;
         if(CopyLow (_Symbol, PERIOD_M15, 0, barsInRange, l) < barsInRange) return;
         orbHigh = h[ArrayMaximum(h)];
         orbLow  = l[ArrayMinimum(l)];
      }
      bool pastORB = (curHour > orbEndHour) || (curHour == orbEndHour && curMin >= orbEndMin);
      if(pastORB && orbHigh > 0) orbSet = true;
   }

   if(!orbSet) return;
   if(curHour >= TradingEndHour) return;
   if(tradedToday) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Breakout above ORB high
   if(ask > orbHigh)
   {
      double sl = ask * (1 - SL_Pct);
      double tp = ask * (1 + TP3_Pct);
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp))
      { tradeCountToday++; tradedToday=true; }
   }
   // Breakdown below ORB low
   else if(bid < orbLow)
   {
      double sl = bid * (1 + SL_Pct);
      double tp = bid * (1 - TP3_Pct);
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp))
      { tradeCountToday++; tradedToday=true; }
   }
}
