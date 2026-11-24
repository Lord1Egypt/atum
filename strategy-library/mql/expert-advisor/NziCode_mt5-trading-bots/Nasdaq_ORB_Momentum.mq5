//+------------------------------------------------------------------+
//|  Nasdaq_ORB_Momentum.mq5                                         |
//|  استراتژی: Opening Range Breakout + Momentum Filter              |
//|  نماد: US100/NASDAQ | تایم‌فریم: M5                             |
//|                                                                   |
//|  منطق: نزدک در ۳۰ دقیقه اول بازار آمریکا (۱۳:۳۰ تا ۱۴:۰۰ UTC) |
//|  یه محدوده می‌سازه. شکست از این محدوده + تأیید مومنتوم          |
//|  قوی‌ترین سیگنال روزانه رو می‌ده                                |
//+------------------------------------------------------------------+
#property version "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "── استراتژی ORB ──"
input int    InpORBStartHour   = 13;   // ساعت شروع بازار آمریکا (UTC)
input int    InpORBStartMin    = 30;   // دقیقه شروع
input int    InpORBDuration    = 30;   // مدت ORB (دقیقه)
input int    InpTradeEndHour   = 20;   // ساعت پایان معاملات (UTC)
input double InpBreakoutBuffer = 0.2;  // بافر بریک‌اوت (% از محدوده)
input int    InpMomPeriod      = 14;   // دوره مومنتوم
input int    InpVolEMA         = 20;   // EMA حجم برای تأیید

input group "── ریسک ──"
input double InpLotSize        = 0.01;
input double InpRRRatio        = 2.0;  // نسبت ریسک به ریوارد
input double InpMaxDailyLoss   = 120;
input int    InpMaxTrades      = 6;    // نزدک محدودتر — کیفیت به کمیت
input int    InpMagic          = 444004;

input group "── سرور ──"
input string InpServerURL      = "http://127.0.0.1:5000";

CTrade trade;
CPositionInfo posInfo;

int hMom, hVolEMA;
datetime lastBar=0, dayStart=0;
double dayStartBal=0;
int tradesToday=0;
bool dayLimitHit=false;
string openTickets[];
int lastPosCount=0;

// متغیرهای ORB
double orbHigh = 0, orbLow = DBL_MAX;
bool   orbBuilt = false;
bool   boughtToday = false, soldToday = false;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);

   hMom    = iMomentum(Symbol(),PERIOD_M5,InpMomPeriod,PRICE_CLOSE);
   hVolEMA = iMA(Symbol(),PERIOD_M5,InpVolEMA,0,MODE_EMA,PRICE_CLOSE);

   if(hMom==INVALID_HANDLE||hVolEMA==INVALID_HANDLE)
      return INIT_FAILED;

   ResetDay();
   SendToServer("startup","{\"bot\":\"Nasdaq_ORB_Momentum\",\"symbol\":\"NASDAQ\",\"tf\":\"M5\"}");
   Print("Nasdaq ORB Momentum Bot started");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hMom);
   IndicatorRelease(hVolEMA);
   SendToServer("shutdown","{\"bot\":\"Nasdaq_ORB_Momentum\",\"reason\":"+IntegerToString(reason)+"}");
}

void OnTick()
{
   CheckPositionChanges();
   CheckDayReset();

   datetime curBar=iTime(Symbol(),PERIOD_M5,0);
   if(curBar==lastBar) return;
   lastBar=curBar;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int nowMins = dt.hour*60 + dt.min;
   int orbStart = InpORBStartHour*60 + InpORBStartMin;
   int orbEnd   = orbStart + InpORBDuration;
   int tradeEnd = InpTradeEndHour*60;

   // ── ریست روزانه ──
   if(nowMins == orbStart) { orbHigh=0; orbLow=DBL_MAX; orbBuilt=false; boughtToday=false; soldToday=false; }

   // ── ساخت ORB در ۳۰ دقیقه اول ──
   if(nowMins >= orbStart && nowMins < orbEnd)
   {
      for(int i=1; i<=6; i++)  // ۶ کندل M5 = ۳۰ دقیقه
      {
         double h = iHigh(Symbol(),PERIOD_M5,i);
         double l = iLow(Symbol(),PERIOD_M5,i);
         if(h > orbHigh) orbHigh = h;
         if(l < orbLow)  orbLow  = l;
      }
      return;  // در حین ساخت ORB، معامله نکن
   }

   // ORB کامل شد
   if(!orbBuilt && nowMins >= orbEnd && orbHigh > 0 && orbLow < DBL_MAX)
   {
      orbBuilt = true;
      Print("ORB Built: High=", orbHigh, " Low=", orbLow, " Range=", orbHigh-orbLow);
   }

   if(!orbBuilt) return;
   if(!RiskOK()) return;
   if(nowMins >= tradeEnd) return;  // بعد از ساعت معاملاتی، وارد نشو
   if(PositionsTotal() > 0) return;

   double orbRange  = orbHigh - orbLow;
   double buffer    = orbRange * InpBreakoutBuffer;
   double curClose  = iClose(Symbol(),PERIOD_M5,1);

   double mom[], volEMA[];
   ArraySetAsSeries(mom,    true);
   ArraySetAsSeries(volEMA, true);
   if(CopyBuffer(hMom,0,0,3,mom)    < 3) return;
   if(CopyBuffer(hVolEMA,0,0,3,volEMA) < 3) return;

   bool momBull = mom[1] > 100 && mom[1] > mom[2];  // مومنتوم صعودی
   bool momBear = mom[1] < 100 && mom[1] < mom[2];  // مومنتوم نزولی

   // ── BUY: شکست سقف ORB + مومنتوم صعودی ──
   bool buySignal = !boughtToday
                    && curClose > orbHigh + buffer
                    && momBull;

   // ── SELL: شکست کف ORB + مومنتوم نزولی ──
   bool sellSignal = !soldToday
                     && curClose < orbLow - buffer
                     && momBear;

   if(buySignal)       { OpenTrade(ORDER_TYPE_BUY, orbRange);  boughtToday=true; }
   else if(sellSignal) { OpenTrade(ORDER_TYPE_SELL, orbRange); soldToday=true;   }
}

void OpenTrade(ENUM_ORDER_TYPE type, double orbRange)
{
   double price  = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(),SYMBOL_ASK)
                                           : SymbolInfoDouble(Symbol(),SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS);

   // SL = داخل ORB (نقطه بی‌اعتباری)
   double slDist = orbRange * 0.5;
   double tpDist = slDist * InpRRRatio;

   double sl = NormalizeDouble((type==ORDER_TYPE_BUY) ? price-slDist : price+slDist, digits);
   double tp = NormalizeDouble((type==ORDER_TYPE_BUY) ? price+tpDist : price-tpDist, digits);

   bool ok = (type==ORDER_TYPE_BUY) ? trade.Buy(InpLotSize,Symbol(),price,sl,tp,"NQ_ORB")
                                     : trade.Sell(InpLotSize,Symbol(),price,sl,tp,"NQ_ORB");
   if(ok) { tradesToday++; Print("ORB Trade: ",EnumToString(type)," @ ",price," SL=",sl," TP=",tp); }
   else Print("Trade error: ", trade.ResultRetcodeDescription());
}

bool RiskOK()
{
   if(dayLimitHit) return false;
   double loss=dayStartBal-AccountInfoDouble(ACCOUNT_BALANCE);
   if(loss>=InpMaxDailyLoss){dayLimitHit=true;return false;}
   if(tradesToday>=InpMaxTrades) return false;
   return true;
}

void ResetDay(){dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);tradesToday=0;dayLimitHit=false;orbHigh=0;orbLow=DBL_MAX;orbBuilt=false;boughtToday=false;soldToday=false;dayStart=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));}
void CheckDayReset(){datetime t=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));if(t>dayStart)ResetDay();}
void CheckPositionChanges(){int cur=PositionsTotal();if(cur>lastPosCount)for(int i=0;i<cur;i++)if(posInfo.SelectByIndex(i)){string t=IntegerToString(posInfo.Ticket());if(!Tracked(t)){AddT(t);ReportOpen(posInfo.Ticket());}}if(cur<lastPosCount)ReportClosedAll();lastPosCount=cur;}
void ReportOpen(ulong ticket){if(!posInfo.SelectByTicket(ticket))return;string d=(posInfo.PositionType()==POSITION_TYPE_BUY)?"BUY 📈":"SELL 📉";string j="{\"event\":\"open\",\"bot\":\"Nasdaq_ORB\",\"ticket\":"+IntegerToString(ticket)+",\"symbol\":\""+posInfo.Symbol()+"\",\"type\":\""+d+"\",\"lots\":"+DoubleToString(posInfo.Volume(),2)+",\"open_price\":"+DoubleToString(posInfo.PriceOpen(),5)+",\"sl\":"+DoubleToString(posInfo.StopLoss(),5)+",\"tp\":"+DoubleToString(posInfo.TakeProfit(),5)+"}";SendToServer("trade_open",j);}
void ReportClosedAll(){string newT[];int cur=PositionsTotal();for(int i=0;i<cur;i++)if(posInfo.SelectByIndex(i)){int s=ArraySize(newT);ArrayResize(newT,s+1);newT[s]=IntegerToString(posInfo.Ticket());}for(int i=0;i<ArraySize(openTickets);i++){bool f=false;for(int j=0;j<ArraySize(newT);j++)if(openTickets[i]==newT[j]){f=true;break;}if(!f)ReportClose(StringToInteger(openTickets[i]));}ArrayCopy(openTickets,newT);}
void ReportClose(ulong ticket){HistorySelect(TimeCurrent()-86400,TimeCurrent());for(int i=HistoryDealsTotal()-1;i>=0;i--){ulong dt=HistoryDealGetTicket(i);if(HistoryDealGetInteger(dt,DEAL_POSITION_ID)==(long)ticket&&HistoryDealGetInteger(dt,DEAL_ENTRY)==DEAL_ENTRY_OUT){double p=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_COMMISSION)+HistoryDealGetDouble(dt,DEAL_SWAP);SendToServer("trade_close","{\"event\":\"close\",\"bot\":\"Nasdaq_ORB\",\"ticket\":"+IntegerToString(ticket)+",\"net_profit\":"+DoubleToString(p,2)+",\"emoji\":\""+(p>=0?"✅":"❌")+"\"}");break;}}}
bool Tracked(string t){for(int i=0;i<ArraySize(openTickets);i++)if(openTickets[i]==t)return true;return false;}
void AddT(string t){int s=ArraySize(openTickets);ArrayResize(openTickets,s+1);openTickets[s]=t;}
bool SendToServer(string ev,string data){char post[],res[];string rh;StringToCharArray(data,post,0,StringLen(data));int r=WebRequest("POST",InpServerURL+"/mt5/"+ev,"Content-Type: application/json\r\n",5000,post,res,rh);return r!=-1;}
