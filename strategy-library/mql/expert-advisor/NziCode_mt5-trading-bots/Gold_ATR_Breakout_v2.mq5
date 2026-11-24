//+------------------------------------------------------------------+
//| Gold_ATR_Breakout_v2.mq5                                         |
//| ATR Breakout + EMA Trend | Multi-TP + Risk-Free + Trailing       |
//+------------------------------------------------------------------+
#property copyright "mt5-trading-bots"
#property version   "2.00"
#include <Trade\Trade.mqh>

input double LotSize         = 0.1;
input int    ATR_Period      = 14;
input double ATR_Multiplier  = 1.2;    // lowered from 1.5 → more signals
input int    EMA_Fast        = 21;
input int    EMA_Slow        = 89;
input int    BreakoutBars    = 20;     // recent high/low lookback
input double SL_ATR_Mult     = 1.0;   // SL = 1x ATR
input double TP1_ATR_Mult    = 1.5;   // TP1 = 1.5x ATR
input double TP2_ATR_Mult    = 2.5;   // TP2 = 2.5x ATR
input double TP3_ATR_Mult    = 3.5;   // TP3 = 3.5x ATR
input double TrailingATR     = 1.2;   // trailing distance in ATR
input int    MaxTradesPerDay = 2;
input double MaxDailyLoss    = 50.0;
input int    CooldownBars    = 4;
input bool   UseNewsFilter   = false;
input string NewsFilterURL   = "http://127.0.0.1:5000/news_safe";
input int    Magic           = 20001;

CTrade trade;
int hATR, hEmaFast, hEmaSlow;
datetime lastBarTime = 0;
int tradeCountToday  = 0;
datetime lastTradeDay = 0;
int barsSinceLastTrade = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   hATR     = iATR(_Symbol, PERIOD_M15, ATR_Period);
   hEmaFast = iMA(_Symbol, PERIOD_M15, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow = iMA(_Symbol, PERIOD_M15, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   if(hATR==INVALID_HANDLE || hEmaFast==INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hATR);
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
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
   lastBarTime = t[0];
   barsSinceLastTrade++;
   return true;
}

bool NewsFilterSafe()
{
   if(!UseNewsFilter) return true;
   char result[], post[];
   string headers = "Content-Type: application/json\r\n";
   int res = WebRequest("GET", NewsFilterURL, headers, 3000, post, result, headers);
   return (res == 200) ? StringFind(CharArrayToString(result), "true") >= 0 : true;
}

void ManagePositions()
{
   double atr[];
   if(CopyBuffer(hATR, 0, 0, 1, atr) < 1) return;
   double atrVal = atr[0];

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

      double profitDist = (posType == POSITION_TYPE_BUY)
                          ? curPrice - openPrice
                          : openPrice - curPrice;

      // TP1 → breakeven + partial close 40%
      if(profitDist >= TP1_ATR_Mult * atrVal)
      {
         double newSL = (posType == POSITION_TYPE_BUY)
                        ? openPrice + 5*_Point
                        : openPrice - 5*_Point;
         if((posType == POSITION_TYPE_BUY && newSL > sl) ||
            (posType == POSITION_TYPE_SELL && (sl == 0 || newSL < sl)))
            trade.PositionModify(ticket, newSL, tp);
         double cv = NormalizeDouble(lots * 0.4, 2);
         if(cv >= 0.01) trade.PositionClosePartial(ticket, cv);
      }

      // TP2 → partial close another 30%
      if(profitDist >= TP2_ATR_Mult * atrVal)
      {
         double cv = NormalizeDouble(lots * 0.43, 2);
         if(cv >= 0.01) trade.PositionClosePartial(ticket, cv);
      }

      // Trailing stop
      if(profitDist >= TP1_ATR_Mult * atrVal)
      {
         double trailDist = TrailingATR * atrVal;
         double trailSL;
         if(posType == POSITION_TYPE_BUY)
         {
            trailSL = curPrice - trailDist;
            if(trailSL > sl) trade.PositionModify(ticket, trailSL, tp);
         }
         else
         {
            trailSL = curPrice + trailDist;
            if(sl == 0 || trailSL < sl) trade.PositionModify(ticket, trailSL, tp);
         }
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
   if(!NewsFilterSafe()) return;

   int ownPos = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)) &&
         PositionGetInteger(POSITION_MAGIC) == Magic) ownPos++;
   if(ownPos >= 1) return;

   double atr[], emaFast[], emaSlow[];
   if(CopyBuffer(hATR,     0, 0, 2, atr)     < 2) return;
   if(CopyBuffer(hEmaFast, 0, 0, 2, emaFast) < 2) return;
   if(CopyBuffer(hEmaSlow, 0, 0, 2, emaSlow) < 2) return;

   double atrVal = atr[0];

   // Recent high/low
   double highs[], lows[];
   if(CopyHigh(_Symbol, PERIOD_M15, 1, BreakoutBars, highs) < BreakoutBars) return;
   if(CopyLow (_Symbol, PERIOD_M15, 1, BreakoutBars, lows)  < BreakoutBars) return;
   double recentHigh = highs[ArrayMaximum(highs)];
   double recentLow  = lows [ArrayMinimum(lows)];

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool trendUp   = emaFast[0] > emaSlow[0];
   bool trendDown = emaFast[0] < emaSlow[0];

   // Breakout BUY: price breaks above recent high + ATR confirms volatility
   if(trendUp && close1 > recentHigh && atrVal > ATR_Multiplier * iATR(_Symbol, PERIOD_M15, ATR_Period*3))
   {
      // compare current ATR vs longer-period ATR as volatility filter
      double sl = ask - SL_ATR_Mult * atrVal;
      double tp = ask + TP3_ATR_Mult * atrVal;
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp))
      { tradeCountToday++; barsSinceLastTrade = 0; }
   }
   else if(trendDown && close1 < recentLow && atrVal > ATR_Multiplier * iATR(_Symbol, PERIOD_M15, ATR_Period*3))
   {
      double sl = bid + SL_ATR_Mult * atrVal;
      double tp = bid - TP3_ATR_Mult * atrVal;
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp))
      { tradeCountToday++; barsSinceLastTrade = 0; }
   }
}
