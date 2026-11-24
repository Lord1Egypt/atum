//+------------------------------------------------------------------+
//|  Gold_ATR_Breakout.mq5                                           |
//|  استراتژی: ATR Volatility Breakout + Trend Confirmation          |
//|  نماد: XAUUSD | تایم‌فریم: M5                                   |
//|                                                                   |
//|  منطق: طلا وقتی از محدوده نوسان ATR خودش بیرون میزنه          |
//|  و روند تأیید میشه، قوی‌ترین حرکت رو داره                      |
//+------------------------------------------------------------------+
#property version "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "── استراتژی ──"
input int    InpATRPeriod      = 10;    // دوره ATR
input double InpBreakoutMult   = 0.8;  // ضریب بریک‌اوت از ATR
input int    InpTrendEMA       = 34;   // EMA روند
input int    InpFastEMA        = 5;    // EMA سریع تأیید
input int    InpLookback       = 8;    // کندل‌های گذشته برای محاسبه محدوده

input group "── ریسک ──"
input double InpLotSize        = 0.01;
input double InpSLMult         = 1.0;  // ضریب ATR برای SL
input double InpTPMult         = 2.2;  // ضریب ATR برای TP  (R:R = 1:2.2)
input double InpMaxDailyLoss   = 100;
input int    InpMaxTrades      = 10;
input int    InpMagic          = 111001;
input int    InpCooldown       = 4;    // کندل انتظار بین معاملات

input group "── سرور ──"
input string InpServerURL      = "http://127.0.0.1:5000";

CTrade trade;
CPositionInfo posInfo;

int hATR, hTrendEMA, hFastEMA;
datetime lastBar = 0, lastTradeBar = 0, dayStart = 0;
double dayStartBalance = 0;
int tradesToday = 0;
bool dayLimitHit = false;
string openTickets[];
int lastPosCount = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);

   hATR      = iATR(Symbol(), PERIOD_M5, InpATRPeriod);
   hTrendEMA = iMA(Symbol(), PERIOD_M5, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hFastEMA  = iMA(Symbol(), PERIOD_M5, InpFastEMA,  0, MODE_EMA, PRICE_CLOSE);

   if(hATR==INVALID_HANDLE||hTrendEMA==INVALID_HANDLE||hFastEMA==INVALID_HANDLE)
      return INIT_FAILED;

   ResetDay();
   SendToServer("startup", "{\"bot\":\"Gold_ATR_Breakout\",\"symbol\":\"XAUUSD\",\"tf\":\"M5\"}");
   Print("Gold ATR Breakout Bot started");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hATR);
   IndicatorRelease(hTrendEMA);
   IndicatorRelease(hFastEMA);
   SendToServer("shutdown", "{\"bot\":\"Gold_ATR_Breakout\",\"reason\":" + IntegerToString(reason) + "}");
}

void OnTick()
{
   CheckPositionChanges();
   CheckDayReset();

   datetime curBar = iTime(Symbol(), PERIOD_M5, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   if(!RiskOK()) return;
   if(PositionsTotal() > 0) return;
   if(!CooldownOK()) return;

   double atr[], trendEMA[], fastEMA[];
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(trendEMA, true);
   ArraySetAsSeries(fastEMA, true);

   if(CopyBuffer(hATR, 0, 0, InpLookback+2, atr) < InpLookback+2) return;
   if(CopyBuffer(hTrendEMA, 0, 0, 3, trendEMA) < 3) return;
   if(CopyBuffer(hFastEMA,  0, 0, 3, fastEMA)  < 3) return;

   // محاسبه محدوده LookBack کندل اخیر
   double highRange = 0, lowRange = DBL_MAX;
   for(int i = 1; i <= InpLookback; i++)
   {
      double h = iHigh(Symbol(), PERIOD_M5, i);
      double l = iLow(Symbol(), PERIOD_M5, i);
      if(h > highRange) highRange = h;
      if(l < lowRange)  lowRange  = l;
   }

   double curATR   = atr[1];
   double curClose = iClose(Symbol(), PERIOD_M5, 1);
   double curHigh  = iHigh(Symbol(), PERIOD_M5, 1);
   double curLow   = iLow(Symbol(), PERIOD_M5, 1);

   // بریک‌اوت رو به بالا + تأیید روند صعودی
   bool buyBreak  = curHigh > highRange + curATR * InpBreakoutMult
                    && fastEMA[1] > trendEMA[1]
                    && trendEMA[1] > trendEMA[2];

   // بریک‌اوت رو به پایین + تأیید روند نزولی
   bool sellBreak = curLow < lowRange - curATR * InpBreakoutMult
                    && fastEMA[1] < trendEMA[1]
                    && trendEMA[1] < trendEMA[2];

   if(buyBreak)  OpenTrade(ORDER_TYPE_BUY,  curATR);
   else if(sellBreak) OpenTrade(ORDER_TYPE_SELL, curATR);
}

void OpenTrade(ENUM_ORDER_TYPE type, double atr)
{
   double price  = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(),SYMBOL_ASK)
                                           : SymbolInfoDouble(Symbol(),SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS);
   double sl = NormalizeDouble((type==ORDER_TYPE_BUY) ? price-atr*InpSLMult : price+atr*InpSLMult, digits);
   double tp = NormalizeDouble((type==ORDER_TYPE_BUY) ? price+atr*InpTPMult : price-atr*InpTPMult, digits);

   bool ok = (type==ORDER_TYPE_BUY) ? trade.Buy(InpLotSize,Symbol(),price,sl,tp,"Gold_Break")
                                     : trade.Sell(InpLotSize,Symbol(),price,sl,tp,"Gold_Break");
   if(ok) { tradesToday++; lastTradeBar = iTime(Symbol(),PERIOD_M5,0); }
   else Print("Trade error: ", trade.ResultRetcodeDescription());
}

bool RiskOK()
{
   if(dayLimitHit) return false;
   double loss = dayStartBalance - AccountInfoDouble(ACCOUNT_BALANCE);
   if(loss >= InpMaxDailyLoss) { dayLimitHit=true; return false; }
   if(tradesToday >= InpMaxTrades) return false;
   return true;
}

bool CooldownOK()
{
   if(lastTradeBar==0) return true;
   return Bars(Symbol(),PERIOD_M5,lastTradeBar,iTime(Symbol(),PERIOD_M5,0))-1 >= InpCooldown;
}

void ResetDay()
{
   dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   tradesToday=0; dayLimitHit=false;
   dayStart = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
}

void CheckDayReset()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(today > dayStart) ResetDay();
}

void CheckPositionChanges()
{
   int cur = PositionsTotal();
   if(cur > lastPosCount)
      for(int i=0;i<cur;i++)
         if(posInfo.SelectByIndex(i)) { string t=IntegerToString(posInfo.Ticket()); if(!Tracked(t)){AddT(t); ReportOpen(posInfo.Ticket());} }
   if(cur < lastPosCount) ReportClosedAll();
   lastPosCount = cur;
}

void ReportOpen(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;
   string d=(posInfo.PositionType()==POSITION_TYPE_BUY)?"BUY 📈":"SELL 📉";
   string j="{\"event\":\"open\",\"bot\":\"Gold_ATR_Breakout\",\"ticket\":"+IntegerToString(ticket)+
             ",\"symbol\":\""+posInfo.Symbol()+"\",\"type\":\""+d+"\",\"lots\":"+DoubleToString(posInfo.Volume(),2)+
             ",\"open_price\":"+DoubleToString(posInfo.PriceOpen(),5)+
             ",\"sl\":"+DoubleToString(posInfo.StopLoss(),5)+
             ",\"tp\":"+DoubleToString(posInfo.TakeProfit(),5)+"}";
   SendToServer("trade_open",j);
}

void ReportClosedAll()
{
   string newT[]; int cur=PositionsTotal();
   for(int i=0;i<cur;i++) if(posInfo.SelectByIndex(i)){int s=ArraySize(newT);ArrayResize(newT,s+1);newT[s]=IntegerToString(posInfo.Ticket());}
   for(int i=0;i<ArraySize(openTickets);i++){bool f=false;for(int j=0;j<ArraySize(newT);j++)if(openTickets[i]==newT[j]){f=true;break;}if(!f)ReportClose(StringToInteger(openTickets[i]));}
   ArrayCopy(openTickets,newT);
}

void ReportClose(ulong ticket)
{
   HistorySelect(TimeCurrent()-86400,TimeCurrent());
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong dt=HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(dt,DEAL_POSITION_ID)==(long)ticket && HistoryDealGetInteger(dt,DEAL_ENTRY)==DEAL_ENTRY_OUT)
      {
         double p=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_COMMISSION)+HistoryDealGetDouble(dt,DEAL_SWAP);
         string j="{\"event\":\"close\",\"bot\":\"Gold_ATR_Breakout\",\"ticket\":"+IntegerToString(ticket)+
                   ",\"net_profit\":"+DoubleToString(p,2)+",\"emoji\":\""+(p>=0?"✅":"❌")+"\"}";
         SendToServer("trade_close",j); break;
      }
   }
}

bool Tracked(string t){for(int i=0;i<ArraySize(openTickets);i++)if(openTickets[i]==t)return true;return false;}
void AddT(string t){int s=ArraySize(openTickets);ArrayResize(openTickets,s+1);openTickets[s]=t;}

bool SendToServer(string ev, string data)
{
   char post[],res[]; string rh;
   StringToCharArray(data,post,0,StringLen(data));
   int r=WebRequest("POST",InpServerURL+"/mt5/"+ev,"Content-Type: application/json\r\n",5000,post,res,rh);
   return r!=-1;
}
