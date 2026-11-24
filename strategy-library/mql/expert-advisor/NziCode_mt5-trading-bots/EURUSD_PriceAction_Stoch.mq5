//+------------------------------------------------------------------+
//|  EURUSD_PriceAction_Stoch.mq5                                    |
//|  استراتژی: Price Action Swing + Stochastic Divergence            |
//|  نماد: EURUSD | تایم‌فریم: M5                                   |
//|                                                                   |
//|  منطق: یورو/دلار روندهای مشخص و سوئینگ‌های منظم داره.           |
//|  با شناسایی سقف/کف محلی و تأیید Stochastic وارد میشیم          |
//+------------------------------------------------------------------+
#property version "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "── استراتژی ──"
input int    InpSwingLookback  = 5;    // کندل برای شناسایی سوئینگ
input int    InpStochK         = 5;    // Stochastic %K
input int    InpStochD         = 3;    // Stochastic %D
input int    InpStochSlowing   = 3;    // Stochastic Slowing
input double InpStochUpper     = 80;   // سطح اشباع خرید
input double InpStochLower     = 20;   // سطح اشباع فروش
input int    InpEMATrend1      = 21;   // EMA کوتاه‌مدت
input int    InpEMATrend2      = 55;   // EMA میان‌مدت
input int    InpEMATrend3      = 200;  // EMA روند کلی

input group "── ریسک ──"
input double InpLotSize        = 0.01;
input int    InpFixedSLPips    = 12;   // SL ثابت (پیپ)
input int    InpFixedTPPips    = 22;   // TP ثابت (پیپ) — R:R تقریبی 1:1.8
input double InpMaxDailyLoss   = 80;
input int    InpMaxTrades      = 15;
input int    InpMagic          = 333003;
input int    InpCooldown       = 2;

input group "── سرور ──"
input string InpServerURL      = "http://127.0.0.1:5000";

CTrade trade;
CPositionInfo posInfo;

int hStoch, hEMA1, hEMA2, hEMA3;
datetime lastBar=0, lastTradeBar=0, dayStart=0;
double dayStartBal=0;
int tradesToday=0;
bool dayLimitHit=false;
string openTickets[];
int lastPosCount=0;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);

   hStoch = iStochastic(Symbol(),PERIOD_M5,InpStochK,InpStochD,InpStochSlowing,MODE_SMA,STO_LOWHIGH);
   hEMA1  = iMA(Symbol(),PERIOD_M5,InpEMATrend1,0,MODE_EMA,PRICE_CLOSE);
   hEMA2  = iMA(Symbol(),PERIOD_M5,InpEMATrend2,0,MODE_EMA,PRICE_CLOSE);
   hEMA3  = iMA(Symbol(),PERIOD_M5,InpEMATrend3,0,MODE_EMA,PRICE_CLOSE);

   if(hStoch==INVALID_HANDLE||hEMA1==INVALID_HANDLE||hEMA2==INVALID_HANDLE||hEMA3==INVALID_HANDLE)
      return INIT_FAILED;

   ResetDay();
   SendToServer("startup","{\"bot\":\"EURUSD_PriceAction_Stoch\",\"symbol\":\"EURUSD\",\"tf\":\"M5\"}");
   Print("EURUSD Price Action Stoch Bot started");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hStoch);
   IndicatorRelease(hEMA1);
   IndicatorRelease(hEMA2);
   IndicatorRelease(hEMA3);
   SendToServer("shutdown","{\"bot\":\"EURUSD_PriceAction_Stoch\",\"reason\":"+IntegerToString(reason)+"}");
}

void OnTick()
{
   CheckPositionChanges();
   CheckDayReset();

   datetime curBar=iTime(Symbol(),PERIOD_M5,0);
   if(curBar==lastBar) return;
   lastBar=curBar;

   if(!RiskOK()) return;
   if(PositionsTotal() > 0) return;
   if(!CooldownOK()) return;

   double stochMain[], stochSignal[], ema1[], ema2[], ema3[];
   ArraySetAsSeries(stochMain,   true);
   ArraySetAsSeries(stochSignal, true);
   ArraySetAsSeries(ema1, true);
   ArraySetAsSeries(ema2, true);
   ArraySetAsSeries(ema3, true);

   int lb = InpSwingLookback + 3;
   if(CopyBuffer(hStoch,0,0,lb,stochMain)   < lb) return;
   if(CopyBuffer(hStoch,1,0,lb,stochSignal) < lb) return;
   if(CopyBuffer(hEMA1,0,0,3,ema1) < 3) return;
   if(CopyBuffer(hEMA2,0,0,3,ema2) < 3) return;
   if(CopyBuffer(hEMA3,0,0,3,ema3) < 3) return;

   double curClose = iClose(Symbol(),PERIOD_M5,1);
   double point    = SymbolInfoDouble(Symbol(),SYMBOL_POINT);

   // ── شناسایی سوئینگ لو (کف محلی) ──
   bool isSwingLow = true;
   for(int i=2; i<=InpSwingLookback+1; i++)
   {
      if(iLow(Symbol(),PERIOD_M5,1) >= iLow(Symbol(),PERIOD_M5,i)) { isSwingLow=false; break; }
   }

   // ── شناسایی سوئینگ های (سقف محلی) ──
   bool isSwingHigh = true;
   for(int i=2; i<=InpSwingLookback+1; i++)
   {
      if(iHigh(Symbol(),PERIOD_M5,1) <= iHigh(Symbol(),PERIOD_M5,i)) { isSwingHigh=false; break; }
   }

   // ── فیلتر روند: EMA1 > EMA2 > EMA3 = صعودی ──
   bool upTrend   = ema1[1]>ema2[1] && ema2[1]>ema3[1];
   bool downTrend = ema1[1]<ema2[1] && ema2[1]<ema3[1];

   // ── BUY: سوئینگ لو + روند صعودی + Stochastic از منطقه اشباع فروش برگشته ──
   bool buySignal = isSwingLow
                    && upTrend
                    && stochMain[2] < InpStochLower
                    && stochMain[1] > stochSignal[1]  // %K از %D رد شد رو به بالا
                    && stochMain[1] > stochMain[2];   // در حال صعود

   // ── SELL: سوئینگ های + روند نزولی + Stochastic از منطقه اشباع خرید برگشته ──
   bool sellSignal = isSwingHigh
                     && downTrend
                     && stochMain[2] > InpStochUpper
                     && stochMain[1] < stochSignal[1]
                     && stochMain[1] < stochMain[2];

   if(buySignal)       OpenTrade(ORDER_TYPE_BUY,  point);
   else if(sellSignal) OpenTrade(ORDER_TYPE_SELL, point);
}

void OpenTrade(ENUM_ORDER_TYPE type, double point)
{
   double price  = (type==ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(),SYMBOL_ASK)
                                           : SymbolInfoDouble(Symbol(),SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(Symbol(),SYMBOL_DIGITS);
   double pipVal = point * 10;

   double sl = NormalizeDouble((type==ORDER_TYPE_BUY) ? price-InpFixedSLPips*pipVal
                                                       : price+InpFixedSLPips*pipVal, digits);
   double tp = NormalizeDouble((type==ORDER_TYPE_BUY) ? price+InpFixedTPPips*pipVal
                                                       : price-InpFixedTPPips*pipVal, digits);

   bool ok = (type==ORDER_TYPE_BUY) ? trade.Buy(InpLotSize,Symbol(),price,sl,tp,"EU_PA")
                                     : trade.Sell(InpLotSize,Symbol(),price,sl,tp,"EU_PA");
   if(ok) { tradesToday++; lastTradeBar=iTime(Symbol(),PERIOD_M5,0); }
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

bool CooldownOK()
{
   if(lastTradeBar==0) return true;
   return Bars(Symbol(),PERIOD_M5,lastTradeBar,iTime(Symbol(),PERIOD_M5,0))-1>=InpCooldown;
}

void ResetDay(){dayStartBal=AccountInfoDouble(ACCOUNT_BALANCE);tradesToday=0;dayLimitHit=false;dayStart=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));}
void CheckDayReset(){datetime t=StringToTime(TimeToString(TimeCurrent(),TIME_DATE));if(t>dayStart)ResetDay();}
void CheckPositionChanges(){int cur=PositionsTotal();if(cur>lastPosCount)for(int i=0;i<cur;i++)if(posInfo.SelectByIndex(i)){string t=IntegerToString(posInfo.Ticket());if(!Tracked(t)){AddT(t);ReportOpen(posInfo.Ticket());}}if(cur<lastPosCount)ReportClosedAll();lastPosCount=cur;}
void ReportOpen(ulong ticket){if(!posInfo.SelectByTicket(ticket))return;string d=(posInfo.PositionType()==POSITION_TYPE_BUY)?"BUY 📈":"SELL 📉";string j="{\"event\":\"open\",\"bot\":\"EURUSD_PA_Stoch\",\"ticket\":"+IntegerToString(ticket)+",\"symbol\":\""+posInfo.Symbol()+"\",\"type\":\""+d+"\",\"lots\":"+DoubleToString(posInfo.Volume(),2)+",\"open_price\":"+DoubleToString(posInfo.PriceOpen(),5)+",\"sl\":"+DoubleToString(posInfo.StopLoss(),5)+",\"tp\":"+DoubleToString(posInfo.TakeProfit(),5)+"}";SendToServer("trade_open",j);}
void ReportClosedAll(){string newT[];int cur=PositionsTotal();for(int i=0;i<cur;i++)if(posInfo.SelectByIndex(i)){int s=ArraySize(newT);ArrayResize(newT,s+1);newT[s]=IntegerToString(posInfo.Ticket());}for(int i=0;i<ArraySize(openTickets);i++){bool f=false;for(int j=0;j<ArraySize(newT);j++)if(openTickets[i]==newT[j]){f=true;break;}if(!f)ReportClose(StringToInteger(openTickets[i]));}ArrayCopy(openTickets,newT);}
void ReportClose(ulong ticket){HistorySelect(TimeCurrent()-86400,TimeCurrent());for(int i=HistoryDealsTotal()-1;i>=0;i--){ulong dt=HistoryDealGetTicket(i);if(HistoryDealGetInteger(dt,DEAL_POSITION_ID)==(long)ticket&&HistoryDealGetInteger(dt,DEAL_ENTRY)==DEAL_ENTRY_OUT){double p=HistoryDealGetDouble(dt,DEAL_PROFIT)+HistoryDealGetDouble(dt,DEAL_COMMISSION)+HistoryDealGetDouble(dt,DEAL_SWAP);SendToServer("trade_close","{\"event\":\"close\",\"bot\":\"EURUSD_PA_Stoch\",\"ticket\":"+IntegerToString(ticket)+",\"net_profit\":"+DoubleToString(p,2)+",\"emoji\":\""+(p>=0?"✅":"❌")+"\"}");break;}}}
bool Tracked(string t){for(int i=0;i<ArraySize(openTickets);i++)if(openTickets[i]==t)return true;return false;}
void AddT(string t){int s=ArraySize(openTickets);ArrayResize(openTickets,s+1);openTickets[s]=t;}
bool SendToServer(string ev,string data){char post[],res[];string rh;StringToCharArray(data,post,0,StringLen(data));int r=WebRequest("POST",InpServerURL+"/mt5/"+ev,"Content-Type: application/json\r\n",5000,post,res,rh);return r!=-1;}
