//+------------------------------------------------------------------+
//| Gold_ProfitGuard_Monitor.mq5                                     |
//| مانیتور: تریلینگ استاپ پله‌ای هر 50 پیپ (بدون بستن کامل)          |
//+------------------------------------------------------------------+
#property copyright "nzicode"
#property version   "3.00"
#property strict

input group "=== General ==="
input long     MagicFilter        = 0;        // 0 = همه پوزیشن‌های نماد، غیر صفر = فقط این Magic
input bool     OnlyThisSymbol     = true;     // فقط پوزیشن‌های نماد فعلی چک بشه

input group "=== Stepped Trailing Stop ==="
input double   PipSize            = 10;       // هر پیپ چند پوینت است؟
input double   StepPips           = 50;       // هر چند پیپ سود، یک پله جلو بره
input double   BufferPips         = 0;        // بافر اضافه روی سطح قفل‌شده (اختیاری)
// منطق: در StepPips ام سود (مثلاً 50) -> SL = Breakeven (0 پیپ سود)
//        در 2*StepPips (100) -> SL = 1*StepPips سود (50)
//        در 3*StepPips (150) -> SL = 2*StepPips سود (100)
//        و الی آخر...

input group "=== Logging ==="
input bool     ShowChartComment   = true;
input bool     PrintJournalOnChange = true;
input int      JournalHeartbeatSec = 30;

datetime lastHeartbeat = 0;

// وضعیت هر پوزیشن: آخرین پله‌ای که اجرا شده (0 = هنوز هیچ پله‌ای اجرا نشده)
struct PosStatus
  {
   ulong  ticket;
   int    lastStepDone;   // مثلاً 1 یعنی پله اول (Breakeven) انجام شده، 2 یعنی پله دوم و ...
  };
PosStatus lastStatus[];

int FindStatusIndex(ulong ticket)
  {
   for(int i=0;i<ArraySize(lastStatus);i++)
      if(lastStatus[i].ticket==ticket) return i;
   return -1;
  }

int EnsureStatus(ulong ticket)
  {
   int idx = FindStatusIndex(ticket);
   if(idx>=0) return idx;
   int n=ArraySize(lastStatus);
   ArrayResize(lastStatus,n+1);
   lastStatus[n].ticket=ticket;
   lastStatus[n].lastStepDone=0;
   return n;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   Print("Gold ProfitGuard Monitor v3 (Trailing پله‌ای هر ",StepPips," پیپ) راه‌اندازی شد.");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
string TypeStr(long posType){ return (posType==POSITION_TYPE_BUY)?"BUY":"SELL"; }

//+------------------------------------------------------------------+
bool ModifySL(ulong ticket,double newSL,double currentTP)
  {
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.sl       = newSL;
   req.tp       = currentTP;

   if(!OrderSend(req,res))
     {
      Print("❌ خطا در تغییر SL پوزیشن #",ticket," - retcode:",res.retcode);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void CheckAllPositions()
  {
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double pipVal = PipSize*point;
   double stepPrice = StepPips * pipVal;
   double bufferPrice = BufferPips * pipVal;

   MqlTick tick; SymbolInfoTick(_Symbol,tick);

   string chartText = "=== Gold ProfitGuard Monitor v3 (Trailing) ===\n";
   chartText += "زمان: "+TimeToString(TimeCurrent())+"\n";
   chartText += "پله: هر "+DoubleToString(StepPips,0)+" پیپ سود -> SL یک پله عقب‌تر\n";
   chartText += "----------------------------------\n";

   bool heartbeat = (JournalHeartbeatSec>0 && (TimeCurrent()-lastHeartbeat)>=JournalHeartbeatSec);
   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(OnlyThisSymbol && PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(MagicFilter!=0 && PositionGetInteger(POSITION_MAGIC)!=MagicFilter) continue;

      count++;
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL     = PositionGetDouble(POSITION_SL);
      double curTP     = PositionGetDouble(POSITION_TP);
      long   posType   = PositionGetInteger(POSITION_TYPE);

      double priceMove;
      if(posType==POSITION_TYPE_BUY)
         priceMove = tick.bid - openPrice;
      else
         priceMove = openPrice - tick.ask;

      double pipsInProfit = priceMove / pipVal;

      int idx = EnsureStatus(ticket);

      // پله فعلی که سود بهش رسیده (مثلا سود 170 پیپ با StepPips=50 -> currentStep=3)
      int currentStep = (int)MathFloor(priceMove / stepPrice);

      if(currentStep > lastStatus[idx].lastStepDone && currentStep >= 1)
        {
         // سطحی که باید قفل بشه: (currentStep-1) پله پایین‌تر
         double lockPipsAmount = (currentStep-1) * StepPips; // پله 1 -> 0 (Breakeven) | پله 2 -> 50 | پله 3 -> 100 ...
         double lockPrice = lockPipsAmount * pipVal;

         double newSL = (posType==POSITION_TYPE_BUY)
                         ? openPrice + lockPrice + bufferPrice
                         : openPrice - lockPrice - bufferPrice;

         bool better = (posType==POSITION_TYPE_BUY) ? (curSL<newSL || curSL==0) : (curSL>newSL || curSL==0);

         if(better && ModifySL(ticket,newSL,curTP))
           {
            lastStatus[idx].lastStepDone = currentStep;
            curSL = newSL;
            string label = (lockPipsAmount==0) ? "Breakeven" : DoubleToString(lockPipsAmount,0)+"پیپ قفل";
            Print("🟢 پوزیشن #",ticket," پله ",currentStep," فعال شد -> SL روی [",label,"] : ",DoubleToString(newSL,_Digits),
                  " (سود فعلی: ",DoubleToString(pipsInProfit,1)," پیپ)");
           }
        }

      string statusLine = "#"+(string)ticket+" "+TypeStr(posType)+" حجم:"+DoubleToString(volume,2)+
                           " | سود: "+DoubleToString(pipsInProfit,1)+" پیپ"+
                           " | SL: "+DoubleToString(curSL,_Digits)+
                           " | پله فعلی: "+(string)lastStatus[idx].lastStepDone+
                           " | پله بعدی در: "+DoubleToString((lastStatus[idx].lastStepDone+1)*StepPips,0)+" پیپ";
      chartText += statusLine+"\n";

      if(heartbeat)
         Print(statusLine);

      count = count; // no-op keep
     }

   if(count==0)
      chartText += "پوزیشن باز مچ‌شونده‌ای یافت نشد.\n";

   if(heartbeat) lastHeartbeat = TimeCurrent();
   if(ShowChartComment) Comment(chartText);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   CheckAllPositions();
  }
//+------------------------------------------------------------------+
