#property strict
#property copyright "Copyright 2022, Shigosag"
#property version   "6.0"
#property description "Shigosag EMA Crossover Expert Advisor"

#define MACROSS_MAGIC_NUM 2022420
#define MACROSS_OPEN_BUY_SIGNAL 1
#define MACROSS_OPEN_SELL_SIGNAL -1
#define MACROSS_NO_SIGNAL 0

//--- Strategy Settings
extern int    ShortMaPeriod       = 5;
extern int    MiddleMaPeriod1     = 7;
extern int    MiddleMaPeriod2     = 13;
extern int    LongMaPeriod        = 21;

//--- Risk Management Settings
extern bool   UseRiskPercent      = true;  // true = auto-calculate lots from risk %
extern double RiskPercent         = 1.0;   // Risk 1% of account equity per trade
extern double FixedLots           = 0.01;  // Used if UseRiskPercent = false
extern double MaxDailyLossPercent = 3.0;   // Circuit breaker: halt trading if lost >= 3% today
extern double StopLoss            = 30.0;  // In Pips
extern double TakeProfit          = 40.0;  // In Pips
extern double TrailingStop        = 15.0;  // In Pips
extern double MaxSpread           = 3.0;   // In Pips
extern int    Slippage            = 3;     // In Pips
extern bool   AllowMultipleOrders = false;

//--- Trading Sessions (Broker Server Time)
extern int    StartHour           = 3;
extern int    EndHour             = 6;
extern int    StartHour1          = 11;
extern int    EndHour1            = 14;
extern int    StartHour2          = 19;
extern int    EndHour2            = 21;

//--- Days
extern bool   Monday              = true;
extern bool   Tuesday             = true;
extern bool   Wednesday           = true;
extern bool   Thursday            = true;
extern bool   Friday              = true;

extern string ExpertName          = "Shigosag_EMA_Crossover_EA_V6";

datetime lastBarTime       = 0;
double   dailyStartEquity  = 0;
int      currentDay        = -1;

//+------------------------------------------------------------------+
//| Universal Pip Calculator (Forex, Metals, Indices, Crypto)        |
//+------------------------------------------------------------------+
double GetPipValue(string sym)
{
   int dig = (int)MarketInfo(sym, MODE_DIGITS);
   double pt = MarketInfo(sym, MODE_POINT);

   // 3 & 5 digit Forex pairs
   if(dig == 3 || dig == 5) return pt * 10.0;

   // Gold / Metals (often 2 digits on XAUUSD, where 0.1 or 0.01 is a point)
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
      return (dig == 2) ? 0.10 : pt * 10.0;

   // Default (Indices, 2/4-digit FX)
   return pt;
}

int GetPipPoints(string sym)
{
   int dig = (int)MarketInfo(sym, MODE_DIGITS);
   if(dig == 3 || dig == 5) return 10;
   return 1;
}

//+------------------------------------------------------------------+
//| Equity-Based Dynamic Lot Sizing                                  |
//+------------------------------------------------------------------+
double CalculateLots(string sym, double slPips)
{
   double minLot  = MarketInfo(sym, MODE_MINLOT);
   double maxLot  = MarketInfo(sym, MODE_MAXLOT);
   double lotStep = MarketInfo(sym, MODE_LOTSTEP);

   if(!UseRiskPercent || slPips <= 0)
   {
      double fixed = MathMax(minLot, MathMin(maxLot, FixedLots));
      return NormalizeDouble(MathFloor(fixed / lotStep) * lotStep, 2);
   }

   double riskMoney   = AccountEquity() * (RiskPercent / 100.0);
   double tickValue   = MarketInfo(sym, MODE_TICKVALUE);
   double tickSize    = MarketInfo(sym, MODE_TICKSIZE);
   double pipVal      = GetPipValue(sym);

   if(tickSize <= 0 || tickValue <= 0) return minLot;

   double lossPerLot  = (slPips * pipVal / tickSize) * tickValue;
   if(lossPerLot <= 0) return minLot;

   double calculatedLots = riskMoney / lossPerLot;
   calculatedLots = MathMax(minLot, MathMin(maxLot, calculatedLots));

   int stepDec = (lotStep > 0) ? (int)MathCeil(MathAbs(MathLog10(lotStep))) : 2;
   return NormalizeDouble(MathFloor(calculatedLots / lotStep) * lotStep, stepDec);
}

//+------------------------------------------------------------------+
//| Daily Loss Circuit Breaker                                       |
//+------------------------------------------------------------------+
bool IsDailyLossExceeded()
{
   if(Day() != currentDay)
   {
      currentDay       = Day();
      dailyStartEquity = AccountEquity();
   }

   if(MaxDailyLossPercent <= 0) return false;

   double maxAllowedLoss = dailyStartEquity * (MaxDailyLossPercent / 100.0);
   if((dailyStartEquity - AccountEquity()) >= maxAllowedLoss)
   {
      Print("DAILY LOSS HIT: Trading locked for the day.");
      return true;
   }
   return false;
}

double GetSafeBrokerDistance(string sym)
{
   double pt          = MarketInfo(sym, MODE_POINT);
   double stopLevel   = MarketInfo(sym, MODE_STOPLEVEL) * pt;
   double freezeLevel = MarketInfo(sym, MODE_FREEZELEVEL) * pt;
   return MathMax(stopLevel, freezeLevel) + (2.0 * pt);
}

bool IsNewBar()
{
   if(Time[0] != lastBarTime)
   {
      lastBarTime = Time[0];
      return true;
   }
   return false;
}

bool HasOpenOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MACROSS_MAGIC_NUM)
            return true;
      }
   }
   return false;
}

bool IsAllowedTime()
{
   switch(DayOfWeek())
   {
      case 1: if(!Monday)    return false; break;
      case 2: if(!Tuesday)   return false; break;
      case 3: if(!Wednesday) return false; break;
      case 4: if(!Thursday)  return false; break;
      case 5: if(!Friday)    return false; break;
      default: return false;
   }

   int hour = Hour();
   return ((hour >= StartHour  && hour <= EndHour)  ||
           (hour >= StartHour1 && hour <= EndHour1) ||
           (hour >= StartHour2 && hour <= EndHour2));
}

int OpenSignal()
{
   double sMa1  = iMA(NULL, 0, ShortMaPeriod,   0, MODE_EMA, PRICE_CLOSE, 1);
   double m1Ma1 = iMA(NULL, 0, MiddleMaPeriod1, 0, MODE_EMA, PRICE_CLOSE, 1);
   double m2Ma1 = iMA(NULL, 0, MiddleMaPeriod2, 0, MODE_EMA, PRICE_CLOSE, 1);
   double lMa1  = iMA(NULL, 0, LongMaPeriod,    0, MODE_EMA, PRICE_CLOSE, 1);

   double m2Ma2 = iMA(NULL, 0, MiddleMaPeriod2, 0, MODE_EMA, PRICE_CLOSE, 2);
   double lMa2  = iMA(NULL, 0, LongMaPeriod,    0, MODE_EMA, PRICE_CLOSE, 2);

   bool buyCross  = (m2Ma2 <= lMa2 && m2Ma1 > lMa1);
   bool buyStack  = (sMa1 > m1Ma1 && m1Ma1 > m2Ma1 && m2Ma1 > lMa1);
   if(buyCross && buyStack) return MACROSS_OPEN_BUY_SIGNAL;

   bool sellCross = (m2Ma2 >= lMa2 && m2Ma1 < lMa1);
   bool sellStack = (sMa1 < m1Ma1 && m1Ma1 < m2Ma1 && m2Ma1 < lMa1);
   if(sellCross && sellStack) return MACROSS_OPEN_SELL_SIGNAL;

   return MACROSS_NO_SIGNAL;
}

//+------------------------------------------------------------------+
//| Robust Trade Execution                                           |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
   RefreshRates();

   string sym = Symbol();
   double pipVal = GetPipValue(sym);
   int pipPts = GetPipPoints(sym);

   double currentSpreadPips = MarketInfo(sym, MODE_SPREAD) / (double)pipPts;
   if(MaxSpread >= 0 && currentSpreadPips > MaxSpread) return;

   double safeMinDist     = GetSafeBrokerDistance(sym);
   double requestedSlDist = StopLoss * pipVal;
   double requestedTpDist = TakeProfit * pipVal;

   if((StopLoss > 0 && requestedSlDist < safeMinDist) || (TakeProfit > 0 && requestedTpDist < safeMinDist))
   {
      Print("Trade aborted: Broker stop-distance exceeds SL/TP setup.");
      return;
   }

   double lotSize = CalculateLots(sym, StopLoss);
   int slip = Slippage * pipPts;
   double price = 0, sl = 0, tp = 0;
   int cmd = -1;

   if(signal == MACROSS_OPEN_BUY_SIGNAL)
   {
      cmd   = OP_BUY;
      price = Ask;
      if(StopLoss > 0)   sl = NormalizeDouble(price - requestedSlDist, Digits);
      if(TakeProfit > 0) tp = NormalizeDouble(price + requestedTpDist, Digits);
   }
   else if(signal == MACROSS_OPEN_SELL_SIGNAL)
   {
      cmd   = OP_SELL;
      price = Bid;
      if(StopLoss > 0)   sl = NormalizeDouble(price + requestedSlDist, Digits);
      if(TakeProfit > 0) tp = NormalizeDouble(price - requestedTpDist, Digits);
   }

   ResetLastError();
   int ticket = OrderSend(sym, cmd, lotSize, price, slip, sl, tp, ExpertName, MACROSS_MAGIC_NUM, 0, (cmd == OP_BUY ? clrGreen : clrRed));
   
   // ECN fallback only when Error 130 is returned
   if(ticket < 0 && GetLastError() == 130)
   {
      ResetLastError();
      ticket = OrderSend(sym, cmd, lotSize, price, slip, 0, 0, ExpertName, MACROSS_MAGIC_NUM, 0, (cmd == OP_BUY ? clrGreen : clrRed));
      
      if(ticket > 0 && OrderSelect(ticket, SELECT_BY_TICKET))
      {
         RefreshRates();
         double fillPrice = OrderOpenPrice();
         double fillSl = (cmd == OP_BUY) ? NormalizeDouble(fillPrice - requestedSlDist, Digits)
                                         : NormalizeDouble(fillPrice + requestedSlDist, Digits);
         double fillTp = (cmd == OP_BUY) ? NormalizeDouble(fillPrice + requestedTpDist, Digits)
                                         : NormalizeDouble(fillPrice - requestedTpDist, Digits);

         if(!OrderModify(ticket, fillPrice, fillSl, fillTp, 0, clrBlue))
         {
            Print("CRITICAL: ECN SL/TP attachment failed for #", ticket, " Error: ", GetLastError());
            Alert("WARNING: Order #", ticket, " has no stop-loss. Close manually if needed!");
         }
      }
   }

   if(ticket < 0)
      Print("OrderSend failed. Error: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Manage Trailing Stops & Missing SL Safeguard                     |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   RefreshRates();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MACROSS_MAGIC_NUM) continue;

      string sym = OrderSymbol();
      double safeMinDist = GetSafeBrokerDistance(sym);
      double symPipVal   = GetPipValue(sym);
      double pt          = MarketInfo(sym, MODE_POINT);
      int dig            = (int)MarketInfo(sym, MODE_DIGITS);

      // Trailing Stop Logic
      if(TrailingStop <= 0) continue;

      if(OrderType() == OP_BUY)
      {
         if(Bid - OrderOpenPrice() > TrailingStop * symPipVal)
         {
            double newStop = NormalizeDouble(Bid - TrailingStop * symPipVal, dig);
            if((Bid - newStop >= safeMinDist) && (OrderStopLoss() == 0 || newStop > OrderStopLoss() + pt))
            {
               ResetLastError();
               if(!OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrGreen))
                  Print("Trailing stop failed on BUY #", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
      else if(OrderType() == OP_SELL)
      {
         if(OrderOpenPrice() - Ask > TrailingStop * symPipVal)
         {
            double newStop = NormalizeDouble(Ask + TrailingStop * symPipVal, dig);
            if((newStop - Ask >= safeMinDist) && (OrderStopLoss() == 0 || newStop < OrderStopLoss() - pt))
            {
               ResetLastError();
               if(!OrderModify(OrderTicket(), OrderOpenPrice(), newStop, OrderTakeProfit(), 0, clrRed))
                  Print("Trailing stop failed on SELL #", OrderTicket(), " Error: ", GetLastError());
            }
         }
      }
   }
}

int OnInit()
{
   lastBarTime      = Time[0];
   currentDay       = Day();
   dailyStartEquity = AccountEquity();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick()
{
   ManageOpenTrades();

   if(IsNewBar())
   {
      if(IsDailyLossExceeded()) return;
      if(!AllowMultipleOrders && HasOpenOrder()) return;

      if(IsAllowedTime())
      {
         int signal = OpenSignal();
         if(signal != MACROSS_NO_SIGNAL)
            ExecuteTrade(signal);
      }
   }
}
