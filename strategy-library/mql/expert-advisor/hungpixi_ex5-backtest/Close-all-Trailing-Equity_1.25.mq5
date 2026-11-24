//+------------------------------------------------------------------+
//|                                                CloseAllAndTrail  |
//|                  by ChatGPT + Gấu Xinh Đẹp Kiêu Sa Kiều Diễm 💖  |
//|   Close All + Trailing tổng lợi nhuận (portfolio) + Text HUD     |
//|   + Button CLOSE ALL (không dùng async)                           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.25"
#property description "EA đóng tất cả lệnh tài khoản và trailing theo tổng lợi nhuận.\nTính theo (USD/USC), KHÔNG phải pips.\nĐược làm bởi ChatGPT + Gấu Xinh Đẹp Kiêu Sa Kiều Diễm Vô Địch Khắp Vũ Trụ."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo pos;

//============================== INPUTS =============================
// ⚠️ Tất cả ngưỡng tiền tệ đều tính theo USD/USC (không phải pips)
input bool   UseEquityTrail       = true;   // True: trail theo Equity; False: trail theo Floating P/L
input double ActivateProfit       = 400.0;    // (USD/USC) kích hoạt trailing khi đạt mức này
input double TrailAmount          = 100.0;    // (USD/USC) tụt khỏi đỉnh quá mức này -> Close All
input double HardTakeProfit       = 1000.0;     // (USD/USC) 0=off; >0 → chốt cứng toàn bộ khi đạt ngưỡng này
input double HardStopLoss         = 0.0;     // (USD/USC) 0=off; <0 → cắt lỗ cứng;

input bool   FilterByMagic        = false;   // Bật lọc theo Magic
input string MagicListCSV         = "";      // Nhập vào magic cần lọc, Ví dụ: "0,12345,999" (0 = lệnh tay)
input bool   ClosePendingOrders   = true;    // Khi Close All sẽ xoá cả lệnh chờ
input int    CheckIntervalSec     = 1;       // Tần suất kiểm tra (giây)
input bool   PrintDebug           = true;    // In log chi tiết

// Hiển thị HUD bằng Comment
input bool   ShowTextHUD          = true;    // Bật/Tắt HUD text
input int    TextRefreshSec       = 1;       // Tần suất cập nhật HUD (giây)

// [ADD] Nút CLOSE ALL (chèn tối thiểu)
input bool   EnableButtons        = true;    // Hiển thị nút 🛑 CLOSE ALL
input int    BtnWidth             = 200;     // Rộng nút
input int    BtnHeight            = 50;      // Cao nút
input int    BtnX                 = 8;       // Vị trí X
input int    BtnY_CloseAll        = 1000;      // Vị trí Y
string       BTN_CLOSE_ALL        = "CloseAllAndTrail_btn_close_all"; // Tên object nút

//=========================== State variables ========================
double    g_peak          = -DBL_MAX;
bool      g_armed         = false;
long      g_account       = 0;
datetime  g_lastHudUpdate = 0;
double    g_todayProfit   = 0.0;
int       g_devPoints     = 0;     // deviation (points)

//============================== Utils ===============================
string Trim(const string s){ string t=s; StringTrimLeft(t); StringTrimRight(t); return t; }

bool ParseMagicsFromCSV(const string csv, long &arr[], int &count)
{
   count = 0; ArrayResize(arr, 0);
   if(StringLen(csv)==0) return false;
   string parts[]; int n = StringSplit(csv, ',', parts); if(n<=0) return false;
   for(int i=0;i<n;i++)
   {
      string s = Trim(parts[i]); if(StringLen(s)==0) continue;
      long m = (long)StringToInteger(s);
      int newSize = ArraySize(arr)+1; ArrayResize(arr,newSize); arr[newSize-1]=m;
   }
   count = ArraySize(arr); return (count>0);
}

bool MagicAllowed(long magic, const long &arr[], int count)
{
   if(!FilterByMagic) return true;
   for(int i=0;i<count;i++) if(arr[i]==magic) return true;
   return false;
}

string JoinMagicsStr(const long &arr[], int count)
{
   if(!FilterByMagic || count<=0) return "(ALL)";
   string s=""; for(int i=0;i<count;i++){ s += (string)arr[i]; if(i<count-1) s += ","; }
   return s;
}

//===================== Portfolio metrics (floating P/L) =============
double TotalOpenProfitFiltered(const long &arr[], int count)
{
   double sum = 0.0;
   int total = PositionsTotal();
   for(int i=0;i<total;i++)
   {
      if(!pos.SelectByIndex(i)) continue;
      long magic = (long)pos.Magic();
      if(!MagicAllowed(magic, arr, count)) continue;
      sum += pos.Profit(); // đã gồm commission & swap
   }
   return sum;
}

//===================== Realized Profit Today ========================
double GetTodayClosedProfit()
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE)); // 00:00 server time
   HistorySelect(dayStart, TimeCurrent());

   double profit = 0.0;
   int totalDeals = (int)HistoryDealsTotal();
   for(int i=0; i<totalDeals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;

      long entryType = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      if(entryType == DEAL_ENTRY_OUT)
         profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
   }
   return profit;
}

void RefreshTick(){ MqlTick t; SymbolInfoTick(_Symbol, t); }

//============================= CLOSE HELPERS ==============================
bool TryCloseSymbol(const string sym)
{
   for(int k=0;k<3;k++)
   {
      // Thử đóng
      if(trade.PositionClose(sym))
         return true;

      // Lấy retcode từ server & xử lý theo retcode (không dùng ERR_*)
      uint rc = trade.ResultRetcode();

      // --- Requote/OffPrice/InvalidPrice → nới deviation & thử lại ---
      if(rc==TRADE_RETCODE_REQUOTE ||
         rc==TRADE_RETCODE_PRICE_OFF ||
         rc==TRADE_RETCODE_INVALID_PRICE)
      {
         int spreadPts = (int)SymbolInfoInteger(sym, SYMBOL_SPREAD);
         int maxDev    = (int)(10 * spreadPts);
         int newDev    = (int)MathCeil(g_devPoints * 1.5);
         g_devPoints   = (newDev > maxDev ? maxDev : newDev);
         trade.SetDeviationInPoints(g_devPoints);
         Sleep(50); RefreshTick();
         continue;
      }

      // --- Context bận (server khoá) → đợi ngắn & thử lại ---
      if(rc==TRADE_RETCODE_LOCKED)
      {
         Sleep(100); RefreshTick();
         continue;
      }

      // --- Các mã thành công hiếm (server báo DONE/PLACED) ---
      if(rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_PLACED)
         return true;

      // Các lỗi khác: dừng thử
      break;
   }
   return false;
}

// reason: HardTP / HardSL / TrailingBaseline / ManualButton
bool CloseAllPositionsFiltered(const long &arr[], int count, const string reason)
{
   ulong  t0_us      = GetMicrosecondCount();
   int    closedPos  = 0;
   int    deletedOrd = 0;
   double bal_before = AccountInfoDouble(ACCOUNT_BALANCE);

   // Close positions
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(!MagicAllowed((long)pos.Magic(), arr, count)) continue;
      if(TryCloseSymbol(pos.Symbol())) closedPos++;
      else if(PrintDebug) PrintFormat("Close thất bại %I64u (%s). Ret=%u", pos.Ticket(), pos.Symbol(), trade.ResultRetcode());
   }

   // Delete pendings
   if(ClosePendingOrders)
   {
      for(int j=OrdersTotal()-1;j>=0;j--)
      {
         ulong ticket = OrderGetTicket(j); if(ticket==0) continue;
         if(!OrderSelect(ticket)) continue;
         if(!MagicAllowed((long)OrderGetInteger(ORDER_MAGIC), arr, count)) continue;
         if(trade.OrderDelete(ticket)) deletedOrd++;
      }
   }

   double bal_after         = AccountInfoDouble(ACCOUNT_BALANCE);
   double realized_this_run = bal_after - bal_before;
   double elapsed_ms        = (double)(GetMicrosecondCount() - t0_us) / 1000.0;

   PrintFormat("[CloseAll:%s] Realized This Run: %.2f | Duration: %.0f ms | ClosedPos=%d | DeletedPend=%d",
               reason, realized_this_run, elapsed_ms, closedPos, deletedOrd);
   return true;
}

//=========================== TRAILING CONTROL =========================
void ArmIfReady(const long &arr[], int count)
{
   double base = UseEquityTrail
                 ? (AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE))
                 : TotalOpenProfitFiltered(arr,count);

   if(!g_armed && base >= ActivateProfit)
   {
      g_armed = true;
      g_peak  = UseEquityTrail ? AccountInfoDouble(ACCOUNT_EQUITY) : base;
      if(PrintDebug) PrintFormat("TRAILING ARMED. ActivateProfit=%.2f | Peak=%.2f | Mode=%s",
                                 ActivateProfit, g_peak, UseEquityTrail?"Equity":"Open P/L");
   }
}

void UpdatePeak(const long &arr[], int count)
{
   if(!g_armed) return;
   double cur = UseEquityTrail
                ? AccountInfoDouble(ACCOUNT_EQUITY)
                : TotalOpenProfitFiltered(arr,count);
   if(cur > g_peak) g_peak = cur;
}

//============================ HUD (Comment) =========================
void UpdateTextHUD()
{
   if(!ShowTextHUD) { Comment(""); return; }

   long magics[]; int mcount=0; ParseMagicsFromCSV(MagicListCSV, magics, mcount);
   string magicStr = JoinMagicsStr(magics, mcount);

   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double fl  = TotalOpenProfitFiltered(magics, mcount);
   double cur = UseEquityTrail ? (eq - bal) : fl;

   string peakStr = g_armed ? StringFormat("%.2f", g_peak) : "-";
   string baseStr = g_armed ? StringFormat("%.2f", g_peak - TrailAmount) : "-";
   g_todayProfit  = GetTodayClosedProfit();

   string txt;
   txt  = "=== CloseAll + Trail (Portfolio) ===\n";
   txt += StringFormat("Mode: %s | Activate %.2f | Trail %.2f\n", UseEquityTrail?"Equity":"Floating", ActivateProfit, TrailAmount);
   txt += StringFormat("Current: %.2f | Peak: %s | Base: %s\n", cur, peakStr, baseStr);
   txt += StringFormat("Profit Today: %.2f | Eq: %.2f | Bal: %.2f | Float: %.2f\n", g_todayProfit, eq, bal, fl);
   txt += StringFormat("Timer: %ds | Magic: %s\n", CheckIntervalSec, magicStr);
   txt += StringFormat("Status: %s", g_armed?"ARMED":"WAIT");
   Comment(txt);
}

void MaybeRefreshText()
{
   if(TimeCurrent() - g_lastHudUpdate >= MathMax(1, TextRefreshSec))
   { UpdateTextHUD(); g_lastHudUpdate = TimeCurrent(); }
}

//============================ BUTTONS ===============================
void EnsureButtons()
{
   if(!EnableButtons) return;
   if(ObjectFind(0, BTN_CLOSE_ALL) < 0)
   {
      ObjectCreate(0, BTN_CLOSE_ALL, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_XDISTANCE, BtnX);
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_YDISTANCE, BtnY_CloseAll);
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_XSIZE,     BtnWidth);
      ObjectSetInteger(0, BTN_CLOSE_ALL, OBJPROP_YSIZE,     BtnHeight);
      ObjectSetString (0, BTN_CLOSE_ALL, OBJPROP_TEXT,      "🛑 CLOSE ALL");
   }
}

//============================ LIFECYCLE =============================
int OnInit()
{
   EventSetTimer(CheckIntervalSec);
   g_account   = (long)AccountInfoInteger(ACCOUNT_LOGIN);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Khởi tạo deviation theo spread
   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   g_devPoints   = (int)MathMax(5, 2*spreadPts);
   trade.SetDeviationInPoints(g_devPoints);

   EnsureButtons();     // [ADD] tạo nút
   UpdateTextHUD();

   if(PrintDebug) PrintFormat("EA start. Account=%I64d", g_account);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Comment("");
   if(EnableButtons) ObjectDelete(0, BTN_CLOSE_ALL); // [ADD] xoá nút khi unload
}

void OnTick(){ MaybeRefreshText(); }

void OnTimer()
{
   long magics[]; int mcount=0; ParseMagicsFromCSV(MagicListCSV, magics, mcount);

   if(PositionsTotal()==0){ MaybeRefreshText(); return; }

   // Hard TP/SL
   double metric = UseEquityTrail
                   ? (AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE))
                   : TotalOpenProfitFiltered(magics,mcount);

   if(HardTakeProfit>0.0 && metric >= HardTakeProfit)
   { CloseAllPositionsFiltered(magics,mcount,"HardTP"); g_armed=false; g_peak=-DBL_MAX; MaybeRefreshText(); return; }

   if(HardStopLoss!=0.0)
   {
      // ✅ Dù bạn nhập SL âm hay dương, bot đều hiểu là ngưỡng âm
      double sl_threshold = (HardStopLoss<0.0 ? HardStopLoss : -MathAbs(HardStopLoss));
      if(metric <= sl_threshold)
      { CloseAllPositionsFiltered(magics,mcount,"HardSL"); g_armed=false; g_peak=-DBL_MAX; MaybeRefreshText(); return; }
   }

   // Trailing
   ArmIfReady(magics,mcount);
   UpdatePeak(magics,mcount);
   if(g_armed && metric <= (g_peak - TrailAmount))
   {
      CloseAllPositionsFiltered(magics,mcount,"TrailingBaseline");
      g_armed=false; g_peak=-DBL_MAX;
   }

   MaybeRefreshText();
}

//=========================== CHART EVENTS ==========================
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==BTN_CLOSE_ALL)
   {
      long magics[]; int mcount=0; ParseMagicsFromCSV(MagicListCSV, magics, mcount);
      CloseAllPositionsFiltered(magics, mcount, "ManualButton");
      g_armed=false; g_peak=-DBL_MAX;
      if(PrintDebug) Print("Button CLOSE ALL pressed.");
      MaybeRefreshText();
   }
}
//+------------------------------------------------------------------+

double OnTester()
{
   if(!MQLInfoInteger(MQL_TESTER)) return 0;

   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DD_RELATIVE);

   if(dd > 0.0001) return profit / dd;
   return profit;
}
