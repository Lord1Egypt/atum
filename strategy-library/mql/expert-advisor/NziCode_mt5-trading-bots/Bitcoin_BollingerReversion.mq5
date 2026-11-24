//+------------------------------------------------------------------+
//|  Bitcoin_BollingerReversion.mq5                                  |
//|  استراتژی: Bollinger Bands Mean Reversion + RSI Confirmation     |
//|  نماد: BTCUSD | تایم‌فریم: M5                                   |
//|                                                                   |
//|  منطق: بیت‌کوین بارها به میانگین برمی‌گرده. وقتی قیمت به       |
//|  باند بالا/پایین می‌رسه و RSI تأیید می‌کنه، برخلاف حرکت       |
//|  می‌کنیم (Mean Reversion)                                        |
//+------------------------------------------------------------------+
#property version "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "── استراتژی ──"
input int    InpBBPeriod       = 20;   // دوره Bollinger Bands
input double InpBBDeviation    = 2.0;  // انحراف معیار BB
input int    InpRSIPeriod      = 10;   // دوره RSI
input double InpRSIUpper       = 72;   // RSI اشباع خرید
input double InpRSILower       = 28;   // RSI اشباع فروش
input int    InpTrendEMA       = 100;  // EMA برای تشخیص روند کلی
input bool   InpTrendFilter    = true; // فقط در جهت روند کلی معامله

input group "── ریسک ──"
input double InpLotSize        = 0.01;
input double InpSLMult         = 1.5;  // ضریب BB Width برای SL
input double InpTPMult         = 1.0;  // TP = وسط باند (میانگین)
input double InpMaxDailyLoss   = 150;
input int    InpMaxTrades      = 12;
input int    InpMagic          = 222002;
input int    InpCooldown       = 3;

input group "── سرور ──"
input string InpServerURL      = "http://127.0.0.1:5000";

CTrade trade;
CPositionInfo posInfo;

int hBB, hRSI, hTrendEMA;
datetime lastBar=0, lastTradeBar=0, dayStart=0;
double dayStartBal=0;
int tradesToday=0;
bool dayLimitHit=false;
string openTickets[];
int lastPosCount=0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50); // بیت‌کوین اسپرد بیشتری داره

   hBB       = iBands(Symbol(), PERIOD_M5, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hRSI      = iRSI(Symbol(),   PERIOD_M5, InpRSIPeriod, PRICE_CLOSE);
   hTrendEMA = iMA(Symbol(),    PERIOD_M5, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hBB==INVALID_HANDLE||hRSI==INVALID_HANDLE||hTrendEMA==INVALID_HANDLE)
      return INIT_FAILED;

   ResetDay();
   SendToServer("startup","{\"bot\":\"Bitcoin_BollingerReversion\",\"symbol\":\"BTCUSD\",\"tf\":\"M5\"}");
   Print("Bitcoin Bollinger Reversion Bot started");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hBB);
   IndicatorRelease(hRSI);
   IndicatorRelease(hTrendEMA);
   SendToServer("shutdown","{\"bot\":\"Bitcoin_BollingerReversion\",\"reason\":"+IntegerToString(reason)+"}");
}

void OnTick()
{
   CheckPositionChanges();
   CheckDayReset();

   datetime curBar = iTime(Symbol(),PERIOD_M5,0);
   if(curBar==lastBar) return;
   lastBar=curBar;

   if(!RiskOK()) return;
   if(PositionsTotal() > 0) return;
   if(!CooldownOK()) return;

   double bbUpper[], bbLower[], bbMiddle[], rsi[], trendEMA[];
   ArraySetAsSeries(bbUpper,  true);
   ArraySetAsSeries(bbLower,  true);
   ArraySetAsSeries(bbMiddle, true);
   ArraySetAsSeries(rsi,      true);
   ArraySetAsSeries(trendEMA, true);

   if(CopyBuffer(hBB,0,0,3,bbMiddle) < 3) return;
   if(CopyBuffer(hBB,1,0,3,bbUpper)  < 3) return;
   if(CopyBuffer(hBB,2,0,3,bbLower)  < 3) return;
   if(CopyBuffer(hRSI,0,0,3,rsi)     < 3) return;
   if(CopyBuffer(hTrendEMA,0,0,3,trendEMA) < 3) return;

   double curClose  = iClose(Symbol(),PERIOD_M5,1);
   double prevClose = iClose(Symbol(),PERIOD_M5,2);
   double curRSI    = rsi[1];
   double bbWidth   = bbUpper[1] - bbLower[1];
   bool   bullTrend = curClose > trendEMA[1];

   // ── BUY: قیمت به باند پایین رسیده + RSI اشباع فروش + در روند صعودی ──
   bool buySignal = prevClose <= bbLower[2]
                    && curClose > bbLower[1]   // بازگشت از باند پایین
                    && curRSI < InpRSILower
                    && (!InpTrendFilter || bullTrend);

   // ── SELL: قیمت به باند بالا رسیده + RSI اشباع خرید + در روند نزولی ──
   bool sellSignal = prevClose >= bbUpper[2]
                     && curClose < bbUpper[1]   // بازگشت از باند بالا
                     && curRSI > InpRSIUpper
                     && (!InpTrendFilter || !bullTrend);

   if(buySignal)       OpenTrade(ORDER_TYPE_BUY,  bbMiddle[1], bbLower[1],  bbWidth);
   else if(sellSignal) OpenTrade(ORDER_TYPE_SELL, bbMiddle[1], bbUpper[1], bbWidth);
}

void OpenTrade(ENUM_ORDER_TYPE type, double bbMid, double bbEdge, double bbWidth)
{
   double price  = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(),SYMBOL_ASK)
                                           : SymbolInfoDouble(Symbol(),SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS);

   double sl, tp;
   if(type==ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(bbEdge - bbWidth*InpSLMult*0.1, digits);
      tp = NormalizeDouble(bbMid, digits);  // TP = میانگین باند
   }
   else
   {
      sl = NormalizeDouble(bbEdge + bbWidth*InpSLMult*0.1, digits);
      tp = NormalizeDouble(bbMid, digits);
   }

   bool ok = (type==ORDER_TYPE_BUY) ? trade.Buy(InpLotSize,Symbol(),price,sl,tp,"BTC_BB")
                                     : trade.Sell(InpLotSize,Symbol(),price,sl,tp,"BTC_BB");
   if(ok) { tradesToday++; lastTradeBar=iTime(Symbol(),PERIOD_M5,0); }
   else Print("Trade error: ", trade.ResultRetcodeDescription());
}

bool RiskOK()
{
   if(dayLimitHit) return false;
   double loss = dayStartBal - AccountInfoDouble(ACCOUNT_BALANCE);
   if(loss >= InpMaxDailyLoss) { dayLimitHit=true; return false; }
   if(tradesToday >= InpMaxTrades) return false;
   return true;
}

bool CooldownOK()
{
   if(lastTradeBar==0) return true;
   return Bars(Symbol(),PERIOD_M5,lastTradeBar,iTime(Symbol(),PERIOD_M5,0))-1 >= InpCooldown;
}

void ResetDay() { dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE); tradesToday=0; dayLimitHit=false; dayStart=StringToTime(TimeToString(TimeCurrent(),TIME_DATE)); }
void CheckDayReset() { datetime t=StringToTime(TimeToString(TimeCurrent(),TIME_DATE)); if(t>dayStart) ResetDay(); }

void CheckPositionChanges()
{
   int cur=PositionsTotal();
   if(cur>lastPosCount) for(int i=0;i<cur;i++) if(posInfo.SelectByIndex(i)){string t=IntegerToString(posInfo.Ticket());if(!Tracked(t)){AddT(t);ReportOpen(posInfo.Ticket());}}
   if(cur<lastPosCount) ReportClosedAll();
   lastPosCount=cur;
}

void ReportOpen(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;
   string d=(posInfo.PositionType()==POSITION_TYPE_BUY)?"BUY 📈":"SELL 📉";
   string j="{\"event\":\"open\",\"bot\":\"Bitcoin_BollingerReversion\",\"ticket\":"+IntegerToString(ticket)+",\"symbol\":\""+posInfo.Symbol()+"\",\"type\":\""+d+"\",\"lots\":"+DoubleToString(posInfo.Volume(),2)+",\"open_price\":"+DoubleToString(posInfo.PriceOpen(),5)+",\"sl\":"+DoubleToString(posInfo.StopLoss(),5)+",\"tp\":"+DoubleToString(posInfo.TakeProfit(),5)+"}";
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
      if(HistoryDealGetInteger(dt,DEAL_POSITION_ID)==(long)ticket&&HistoryDealGetInteger(dt,DEAL_ENTRY)==DEAL_ENTRY_OUT)
      {
         double p=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_COMMISSION)+HistoryDealGetDouble(dt,DEAL_SWAP);
         SendToServer("trade_close","{\"event\":\"close\",\"bot\":\"Bitcoin_BollingerReversion\",\"ticket\":"+IntegerToString(ticket)+",\"net_profit\":"+DoubleToString(p,2)+",\"emoji\":\""+(p>=0?"✅":"❌")+"\"}");
         break;
      }
   }
}

bool Tracked(string t){for(int i=0;i<ArraySize(openTickets);i++)if(openTickets[i]==t)return true;return false;}
void AddT(string t){int s=ArraySize(openTickets);ArrayResize(openTickets,s+1);openTickets[s]=t;}
bool SendToServer(string ev,string data){char post[],res[];string rh;StringToCharArray(data,post,0,StringLen(data));int r=WebRequest("POST",InpServerURL+"/mt5/"+ev,"Content-Type: application/json\r\n",5000,post,res,rh);return r!=-1;}
