//+------------------------------------------------------------------+
//| EURUSD_PriceAction_Stoch_v2.mq5                                  |
//| Multi-TP + Risk-Free + Trailing Stop                             |
//+------------------------------------------------------------------+
#property copyright "mt5-trading-bots"
#property version   "2.00"
#include <Trade\Trade.mqh>

//--- Inputs
input double LotSize          = 0.1;
input int    StochK           = 5;
input int    StochD           = 3;
input int    StochSlowing     = 3;
input int    EMA_Fast         = 21;
input int    EMA_Mid          = 50;
input int    EMA_Slow         = 200;
input int    SwingLookback    = 10;
input double SL_Pips          = 15.0;
input double TP1_Pips         = 20.0;   // 40% close → breakeven
input double TP2_Pips         = 35.0;   // 30% close → trailing
input double TP3_Pips         = 55.0;   // 30% close → full exit
input double TrailingStep     = 10.0;
input double TrailingStart    = 35.0;   // start trailing after X pips profit
input int    MaxTradesPerDay  = 3;
input double MaxDailyLoss     = 30.0;
input int    CooldownBars     = 3;
input bool   UseNewsFilter    = false;
input string NewsFilterURL    = "http://127.0.0.1:5000/news_safe";
input int    Magic            = 20002;

CTrade trade;
int hStoch, hEmaFast, hEmaMid, hEmaSlow;
datetime lastBarTime = 0;
int tradeCountToday = 0;
datetime lastTradeDay = 0;
int barsSinceLastTrade = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   hStoch   = iStochastic(_Symbol, PERIOD_M15, StochK, StochD, StochSlowing, MODE_SMA, STO_LOWHIGH);
   hEmaFast = iMA(_Symbol, PERIOD_M15, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaMid  = iMA(_Symbol, PERIOD_M15, EMA_Mid,  0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow = iMA(_Symbol, PERIOD_M15, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   if(hStoch==INVALID_HANDLE || hEmaFast==INVALID_HANDLE) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hStoch);
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaMid);
   IndicatorRelease(hEmaSlow);
}

//+------------------------------------------------------------------+
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
   // Add open positions floating
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionGetInteger(POSITION_MAGIC) == Magic)
         pnl += PositionGetDouble(POSITION_PROFIT);
   return pnl;
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t[];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, t) < 1) return false;
   if(t[0] == lastBarTime) return false;
   lastBarTime = t[0];
   barsSinceLastTrade++;
   return true;
}

//+------------------------------------------------------------------+
bool NewsFilterSafe()
{
   if(!UseNewsFilter) return true;
   char result[];
   string headers = "Content-Type: application/json\r\n";
   int res = WebRequest("GET", NewsFilterURL, headers, 3000, result, result, headers);
   if(res == 200)
   {
      string resp = CharArrayToString(result);
      return StringFind(resp, "true") >= 0;
   }
   return true; // fail open
}

//+------------------------------------------------------------------+
bool SwingHigh(int idx)
{
   double h[];
   if(CopyHigh(_Symbol, PERIOD_M15, idx-SwingLookback, SwingLookback*2+1, h) < 0) return false;
   double peak = h[SwingLookback];
   for(int i = 0; i < SwingLookback*2+1; i++)
      if(i != SwingLookback && h[i] >= peak) return false;
   return true;
}

bool SwingLow(int idx)
{
   double l[];
   if(CopyLow(_Symbol, PERIOD_M15, idx-SwingLookback, SwingLookback*2+1, l) < 0) return false;
   double trough = l[SwingLookback];
   for(int i = 0; i < SwingLookback*2+1; i++)
      if(i != SwingLookback && l[i] <= trough) return false;
   return true;
}

//+------------------------------------------------------------------+
void ManagePositions()
{
   double pip = 10 * _Point;
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(PositionGetTicket(i))) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      ulong   ticket    = PositionGetInteger(POSITION_TICKET);
      double  openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double  sl        = PositionGetDouble(POSITION_SL);
      double  tp        = PositionGetDouble(POSITION_TP);
      double  curPrice  = PositionGetDouble(POSITION_PRICE_CURRENT);
      int     posType   = (int)PositionGetInteger(POSITION_TYPE);
      double  lots      = PositionGetDouble(POSITION_VOLUME);
      string  comment   = PositionGetString(POSITION_COMMENT);
      
      double profitPips = (posType == POSITION_TYPE_BUY) 
                          ? (curPrice - openPrice) / pip
                          : (openPrice - curPrice) / pip;
      
      // TP1 hit → move SL to breakeven + partial close
      if(profitPips >= TP1_Pips && StringFind(comment,"tp1done") < 0)
      {
         double newSL = (posType == POSITION_TYPE_BUY) 
                        ? openPrice + 2*_Point 
                        : openPrice - 2*_Point;
         if((posType == POSITION_TYPE_BUY && newSL > sl) || 
            (posType == POSITION_TYPE_SELL && (sl == 0 || newSL < sl)))
            trade.PositionModify(ticket, newSL, tp);
         // partial close 40%
         double closeVol = NormalizeDouble(lots * 0.4, 2);
         if(closeVol >= 0.01)
            trade.PositionClosePartial(ticket, closeVol);
      }
      
      // TP2 hit → partial close + start trailing
      if(profitPips >= TP2_Pips && StringFind(comment,"tp2done") < 0)
      {
         double closeVol = NormalizeDouble(lots * 0.43, 2); // ~30% of original
         if(closeVol >= 0.01)
            trade.PositionClosePartial(ticket, closeVol);
      }
      
      // Trailing stop after TrailingStart pips
      if(profitPips >= TrailingStart)
      {
         double trailSL;
         if(posType == POSITION_TYPE_BUY)
         {
            trailSL = curPrice - TrailingStep * pip;
            if(trailSL > sl) trade.PositionModify(ticket, trailSL, tp);
         }
         else
         {
            trailSL = curPrice + TrailingStep * pip;
            if(sl == 0 || trailSL < sl) trade.PositionModify(ticket, trailSL, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();
   if(!IsNewBar()) return;

   // Daily reset
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != lastTradeDay) { tradeCountToday = 0; lastTradeDay = today; }

   if(tradeCountToday >= MaxTradesPerDay) return;
   if(GetDailyPnL() <= -MaxDailyLoss) return;
   if(barsSinceLastTrade < CooldownBars) return;
   if(PositionsTotal() > 0) { /* check if our positions */ }

   // Count own positions
   int ownPos = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(PositionSelectByTicket(PositionGetTicket(i)) && 
         PositionGetInteger(POSITION_MAGIC) == Magic) ownPos++;
   if(ownPos >= 2) return;

   if(!NewsFilterSafe()) return;

   // Get indicator values
   double stochMain[], stochSignal[], emaFast[], emaMid[], emaSlow[];
   if(CopyBuffer(hStoch,   0, 0, 3, stochMain)   < 3) return;
   if(CopyBuffer(hStoch,   1, 0, 3, stochSignal) < 3) return;
   if(CopyBuffer(hEmaFast, 0, 0, 3, emaFast)     < 3) return;
   if(CopyBuffer(hEmaMid,  0, 0, 3, emaMid)      < 3) return;
   if(CopyBuffer(hEmaSlow, 0, 0, 3, emaSlow)     < 3) return;

   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double pip    = 10 * _Point;
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool trendUp   = emaFast[0] > emaMid[0] && emaMid[0] > emaSlow[0];
   bool trendDown = emaFast[0] < emaMid[0] && emaMid[0] < emaSlow[0];
   bool stochBuy  = stochMain[1] < 20 && stochMain[0] > stochSignal[0];
   bool stochSell = stochMain[1] > 80 && stochMain[0] < stochSignal[0];
   bool swLow     = SwingLow(1);
   bool swHigh    = SwingHigh(1);

   // BUY
   if(trendUp && stochBuy && swLow)
   {
      double sl = ask - SL_Pips * pip;
      double tp = ask + TP3_Pips * pip;
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp))
      { tradeCountToday++; barsSinceLastTrade = 0; }
   }
   // SELL
   else if(trendDown && stochSell && swHigh)
   {
      double sl = bid + SL_Pips * pip;
      double tp = bid - TP3_Pips * pip;
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp))
      { tradeCountToday++; barsSinceLastTrade = 0; }
   }
}
