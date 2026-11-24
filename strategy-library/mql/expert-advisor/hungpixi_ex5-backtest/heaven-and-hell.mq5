//=== INPUT CƠ BẢN ====================================================
input double   BaseLot              = 0.10;     // Lot cơ bản
input double   RegionRange          = 10.0;     // Kích thước 1 vùng (USD)
input double   ProfitTarget         = 20.0;     // Mục tiêu lợi nhuận tổng (USD)
input double   ImbalanceCapV0       = 0.50;     // Giới hạn lệch lot vùng 0
input ENUM_TIMEFRAMES TradeTimeframe = PERIOD_M1;  // Khung thời gian giao dịch
input int      MaxRegionSpan        = 5;        // Số vùng hiển thị (±)
input long     MagicNumber          = 666999;    // Mã nhận diện EA (Magic)
input int      LabelFontSize        = 12;       // Cỡ chữ HUD hiển thị

#include <Trade/Trade.mqh>
 CTrade trade;
//=== Global Variables ==================================================
double  g_entry0 = 0.0;           // Entry price for region 0
double  g_prev_entry0 = 0.0;      // Previous entry0 to detect changes
bool    g_entry0_set = false;     // Flag for entry price set
int     g_prev_region = 0;        // Previous region
datetime g_last_bar_time = 0;     // Thời gian nến cuối cùng
bool    g_jump_up[201];           // Jump up flags
bool    g_jump_dn[201];           // Jump down flags
const int g_index_shift = 100;    // Index shift for region-to-index conversion
bool    g_reset_entry_done = false;
static double saved_entry0 = 0.0; // Lưu g_entry0 khi không có lệnh mở
//=== INPUT NGÀY HẾT HẠN ======================================
input string ExpiryDate = "2025.11.30";   // Định dạng: YYYY.MM.DD

//=== HÀM KIỂM TRA HẠN ========================================
bool CheckExpiry()
{
   datetime now_time = TimeCurrent();
   datetime expiry_time = StringToTime(ExpiryDate + " 23:59");

   if (now_time > expiry_time)
   {
      PrintFormat("⛔ EA expired on %s — please update version!", ExpiryDate);
      return false;
   }

   PrintFormat("🟢 EA active. Expiry: %s", ExpiryDate);
   return true;
}

//=== Utility Functions =================================================
double GetCurrentM1Open() {
   double o = iOpen(_Symbol, PERIOD_M1, 0);
   if (o == 0.0) o = (AskPrice() + BidPrice())/2.0; // fallback an toàn
   return o;
}

double BidPrice() { 
    double bid;
    SymbolInfoDouble(_Symbol, SYMBOL_BID, bid);
    return NormalizeDouble(bid, _Digits); // Thêm ; ở đây
}

double AskPrice() { 
    double ask;
    SymbolInfoDouble(_Symbol, SYMBOL_ASK, ask);
    return NormalizeDouble(ask, _Digits); // Thêm ; ở đây
}

double HalfRange() { 
   return RegionRange / 2.0; 
}

int RegionToIdx(int r) { 
   int idx = r + g_index_shift;
   return MathMax(0, MathMin(200, idx)); // Ensure within array bounds
}

double RegionMid(int r) { 
   return g_entry0 + r * RegionRange; 
}

double RegionLow(int r) { 
   return RegionMid(r) - HalfRange(); 
}

double RegionHigh(int r) { 
   return RegionMid(r) + HalfRange(); 
}

int DetectRegion(double price) {
   if (!g_entry0_set) return 0;
   double offset = price - (g_entry0 - HalfRange());
   return (int)MathFloor(offset / RegionRange);
}

int HalfSide(double price, int region) {
   double pos = price - RegionLow(region);
   return (pos < HalfRange()) ? 0 : 1; // 0=BUY-half, 1=SELL-half
}
//=== GlobalVariable hỗ trợ lưu entry0 giữa các lần reload EA ===
void SaveEntry0ToGlobal() {
   string name = _Symbol + "_ZoneEntry0";
   GlobalVariableSet(name, g_entry0);
   PrintFormat("💾 Saved entry0 to global var [%s] = %.5f", name, g_entry0);
}

//=== Lấy entry0 từ GlobalVariable hoặc fallback về open M1 ===
double LoadOrInitEntry0()
{
   string name = _Symbol + "_ZoneEntry0";
   double entry = 0.0;

   // Ưu tiên lấy từ GlobalVariable
   if (GlobalVariableCheck(name))
   {
      entry = GlobalVariableGet(name);
      if (entry != 0.0)
      {
         PrintFormat("♻️ Loaded entry0 from global var [%s] = %.5f", name, entry);
         return NormalizeDouble(entry, _Digits);
      }
   }

   // Nếu không có hoặc = 0.0 → fallback về open nến M1
   double m1open = iOpen(_Symbol, PERIOD_M1, 0);
   if (m1open == 0.0)  // phòng trường hợp nến chưa có dữ liệu
      m1open = (AskPrice() + BidPrice()) / 2.0;

   PrintFormat("🚀 Global var not found → entry0 init from M1 open = %.5f", m1open);
   GlobalVariableSet(name, m1open); // lưu lại luôn để lần sau load
   return NormalizeDouble(m1open, _Digits);
}
//=== load lock region ===================================================
void InitJumpLocksFromOrders()
{
   if (!g_entry0_set)
      return;

   double highest_buy_entry = -DBL_MAX;
   double lowest_sell_entry = DBL_MAX;

   // Quét toàn bộ lệnh hiện có
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);

      if (type == POSITION_TYPE_BUY && entry > highest_buy_entry)
         highest_buy_entry = entry;
      else if (type == POSITION_TYPE_SELL && entry < lowest_sell_entry)
         lowest_sell_entry = entry;
   }

   // ✅ Khóa các vùng phía dưới Buy cao nhất
   if (highest_buy_entry > -DBL_MAX)
   {
      int r_high = DetectRegion(highest_buy_entry);
      for (int r = -MaxRegionSpan; r < r_high; r++)
         g_jump_up[RegionToIdx(r)] = true;

      PrintFormat("🔒 Locked %d vùng dưới vùng BUY cao nhất (%d)", r_high, r_high);
   }

   // ✅ Khóa các vùng phía trên Sell thấp nhất
   if (lowest_sell_entry < DBL_MAX)
   {
      int r_low = DetectRegion(lowest_sell_entry);
      for (int r = r_low + 1; r <= MaxRegionSpan; r++)
         g_jump_dn[RegionToIdx(r)] = true;

      PrintFormat("🔒 Locked %d vùng trên vùng SELL thấp nhất (%d)", r_low, r_low);
   }
}

//=== Position Totals ===================================================
double TotalLots(int dir) {
   double sum = 0.0;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if (dir == 1 && type == POSITION_TYPE_BUY) 
         sum += PositionGetDouble(POSITION_VOLUME);
      if (dir == -1 && type == POSITION_TYPE_SELL) 
         sum += PositionGetDouble(POSITION_VOLUME);
   }
   return sum;
}

int ExtractRegion(const string &comment) {
   int pos = StringFind(comment, "vùng ");
   if (pos < 0) return INT_MIN;
   string rest = StringSubstr(comment, pos + 5);
   int space = StringFind(rest, " ");
   string txt = (space >= 0) ? StringSubstr(rest, 0, space) : rest;
   return (int)StringToInteger(txt);
}

//=== Update Entry0 ====================================================
void UpdateEntry0() {
   // ✅ Nếu entry0 đã set → không cập nhật lại
   if (g_entry0_set)
      return;

   double new_entry0 = 0.0;

   // Nếu chưa có lệnh → dùng open của nến M1 hiện tại
   if (PositionsTotal() == 0) {
      new_entry0 = NormalizeDouble(GetCurrentM1Open(), _Digits);
      saved_entry0 = new_entry0;
      g_entry0 = new_entry0;
      g_entry0_set = true;
      PrintFormat("✅ Entry0 khởi tạo theo open M1: %.5f", g_entry0);
      return;
   }

   // Nếu có lệnh và chưa có entry0 → vẫn ưu tiên open M1
   if (!g_entry0_set && PositionsTotal() > 0) {
      new_entry0 = NormalizeDouble(GetCurrentM1Open(), _Digits);
      saved_entry0 = new_entry0;
      g_entry0 = new_entry0;
      g_entry0_set = true;
      PrintFormat("✅ Entry0 thiết lập khi có lệnh đầu tiên: %.5f", g_entry0);
   }
}

//=== Trade Control ====================================================
bool AllowedThisInterval() {
   datetime current_bar_time = iTime(_Symbol, TradeTimeframe, 0);
   
   if (current_bar_time != g_last_bar_time) {
      g_last_bar_time = current_bar_time;
      Print("New ", EnumToString(TradeTimeframe), " candle at ", 
            TimeToString(current_bar_time, TIME_DATE|TIME_MINUTES));
      return true;  // Có nến mới → cho phép trade
   }
   
   return false;  // Không phải nến mới → chặn trade
}

double NormalizeLot(double lot) {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   return MathMax(minLot, MathMin(maxLot, MathRound(lot / step) * step));
}

bool OpenBuy(double lot, string comment) {
   lot = NormalizeLot(lot);
   if (lot <= 0) return false;
   double ask = AskPrice();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   if (trade.Buy(lot, _Symbol, ask, 0.0, 0.0, comment)) {
      if (trade.ResultRetcode() == TRADE_RETCODE_DONE) return true;
      Print("Buy order failed: ", trade.ResultComment());
   }
   return false;
}

bool OpenSell(double lot, string comment) {
   lot = NormalizeLot(lot);
   if (lot <= 0) return false;
   double bid = BidPrice();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   if (trade.Sell(lot, _Symbol, bid, 0.0, 0.0, comment)) {
      if (trade.ResultRetcode() == TRADE_RETCODE_DONE) return true;
      Print("Sell order failed: ", trade.ResultComment());
   }
   return false;
}

void CloseAll()
{
   // 🔹 Đếm tổng số lệnh đang có
   int total = PositionsTotal();
   if (total == 0)
   {
      Print("⚠️ Không có lệnh nào để đóng.");
      return;
   }

   PrintFormat("🔄 CloseAll: Bắt đầu đóng %d lệnh...", total);

   // 🔁 Duyệt ngược để tránh lỗi shift index khi đóng từng lệnh
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      if (!trade.PositionClose(ticket))
         Print("❌ Close fail ticket ", ticket, ": ", trade.ResultComment());
   }

   Print("✅ CloseAll completed: tất cả lệnh đã đóng.");

   // 🧠 Nếu thật sự không còn lệnh → reset entry0
   if (PositionsTotal() == 0)
   {
      double new_entry = NormalizeDouble(GetCurrentM1Open(), _Digits);
      g_entry0         = new_entry;
      g_prev_entry0    = new_entry;
      saved_entry0     = new_entry;
      g_entry0_set     = true;
      g_reset_entry_done = true;

      // 🔒 Lưu lại vào GlobalVariable để giữ cho lần khởi động sau
      string gv_name = _Symbol + "_ZoneEntry0";
      GlobalVariableSet(gv_name, g_entry0);

      // Reset toàn bộ vùng / trạng thái nhảy vùng
      g_prev_region = 0;
      ResetLocks();

      PrintFormat("🔄 Entry0 reset theo open M1 và đã lưu Global: %.5f", g_entry0);
   }
   else
   {
      Print("⚠️ Một số vị thế chưa đóng hết, chưa reset entry0.");
   }
}


void ResetLocks() {
   ArrayInitialize(g_jump_up, false);
   ArrayInitialize(g_jump_dn, false);
}

//=== Stop-Lock (SL) Management =========================================
void LockAfterJumpUp(int newRegion) {
   double targetSL = NormalizeDouble(RegionMid(newRegion - 1), _Digits); // 🧠 Dời tới vùng gần nhất
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if (type != POSITION_TYPE_BUY) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      int region = ExtractRegion(comment);

      if (region <= newRegion - 1) {
         double oldSL = PositionGetDouble(POSITION_SL);
         if (targetSL > oldSL) {
            if (!trade.PositionModify(ticket, targetSL, 0.0)) {
               Print("❌ Failed to modify SL for BUY ticket ", ticket, ": ", trade.ResultComment());
            } else {
               Print("✅ BUY SL moved to mid of region ", newRegion - 1, " @ ", targetSL);
            }
         }
      }
   }
}

void LockAfterJumpDown(int newRegion) {
   double targetSL = NormalizeDouble(RegionMid(newRegion + 1), _Digits); // 🧠 Dời tới vùng gần nhất
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      if (type != POSITION_TYPE_SELL) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      int region = ExtractRegion(comment);

      if (region >= newRegion + 1) {
         double oldSL = PositionGetDouble(POSITION_SL);
         if (targetSL < oldSL || oldSL == 0.0) {
            if (!trade.PositionModify(ticket, targetSL, 0.0)) {
               Print("❌ Failed to modify SL for SELL ticket ", ticket, ": ", trade.ResultComment());
            } else {
               Print("✅ SELL SL moved to mid of region ", newRegion + 1, " @ ", targetSL);
            }
         }
      }
   }
}

//=== Drawing Functions =================================================
string NameMid(int r) { 
   return "Z_MID_" + IntegerToString(r); 
}

string NameLow(int r) { 
   return "Z_LOW_" + IntegerToString(r); 
}

string NameHigh(int r) { 
   return "Z_HIGH_" + IntegerToString(r); 
}

string NameHUD() { 
   return "Z_HUD"; 
}

void DrawHUD(int curR) {
   long chart_id = ChartID();

   double equity_diff = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   double totB = TotalLots(1);
   double totS = TotalLots(-1);
   double lot_diff = totB - totS;

   // Xử lý trường hợp g_entry0 chưa được set
   string entry0_text = g_entry0_set ? StringFormat("Entry0: %.3f", g_entry0) : "Entry0: Not set";
   double low_price = g_entry0_set ? NormalizeDouble(RegionLow(curR), _Digits) : 0.0;
   double high_price = g_entry0_set ? NormalizeDouble(RegionHigh(curR), _Digits) : 0.0;

   string labels[4] = {
      entry0_text,
      g_entry0_set ? StringFormat("Region %d: Low %.3f | High %.3f", curR, low_price, high_price) : "Region: Not set",
      StringFormat("Lot Buy: %.2f | Lot Sell: %.2f | Diff: %.2f", totB, totS, lot_diff),
      StringFormat("Equity: %.2f", equity_diff)
   };

   color colors[4] = {
      clrYellow,
      clrYellow,
      clrLime,
      clrYellow,
   };
   int y_positions[4] = { 20, 35, 55, 70 };

   string hud = NameHUD();

   for (int i = 0; i < 4; i++) {
      string label_name = hud + "_" + IntegerToString(i);
      
      // ✅ SỬA: Kiểm tra chính xác object có tồn tại không
      if (ObjectFind(chart_id, label_name) == -1) {
         // Tạo mới nếu chưa có
         if (!ObjectCreate(chart_id, label_name, OBJ_LABEL, 0, 0, 0)) {
            Print("❌ Failed to create HUD label: ", label_name, ", Error: ", GetLastError());
            continue;
         }
         Print("✅ Created HUD label: ", label_name);
      }
      
      // Cập nhật thuộc tính
      ObjectSetInteger(chart_id, label_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, label_name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(chart_id, label_name, OBJPROP_YDISTANCE, y_positions[i]);
      ObjectSetInteger(chart_id, label_name, OBJPROP_FONTSIZE, LabelFontSize);
      ObjectSetString(chart_id, label_name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(chart_id, label_name, OBJPROP_COLOR, colors[i]);
      ObjectSetString(chart_id, label_name, OBJPROP_TEXT, labels[i]);
      ObjectSetInteger(chart_id, label_name, OBJPROP_SELECTABLE, false);
   }
   ChartRedraw(chart_id);
}

//=== Region Logic =====================================================
bool CheckCloseAll() {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (equity >= balance + ProfitTarget) {
      CloseAll();
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
//=== ONJUMP — hỗ trợ nhảy nhiều vùng (gap giá) ==========================
void OnJump(int prevR, int currR)
{
   if (prevR == currR) return;

   int step = (currR > prevR) ? 1 : -1;

   // 🧠 Nếu giá nhảy qua nhiều vùng, xử lý từng bước một
   while (prevR != currR)
   {
      int nextR = prevR + step;

      if (step > 0)
         HandleJumpUp(nextR);
      else
         HandleJumpDown(nextR);

      prevR = nextR;
   }
}

//=== Xử lý jump lên từng vùng ===========================================
void HandleJumpUp(int region)
{
   int idx = RegionToIdx(region);
   if (g_jump_up[idx]) return;

   // Chỉ cho Buy khi vùng dương
   if (region > 0)
   {
      double lot = 2 * TotalLots(-1);
      if (lot > 0)
      {
         string cmt = StringFormat("Buy vùng %d entry %.2f", region, AskPrice());
         if (OpenBuy(lot, cmt))
         {
            g_jump_up[idx] = true;
            LockAfterJumpUp(region);
            Print("✅ Buy opened on jump to region ", region);
         }
      }
      else
      {
         g_jump_up[idx] = true;
         Print("⚠️ No Buy opened (lot=0), region ", region);
      }
   }
   else
   {
      g_jump_up[idx] = true;
      Print("⚠️ Jump up ignored for non-positive region ", region);
   }
}

//=== Xử lý jump xuống từng vùng =========================================
void HandleJumpDown(int region)
{
   int idx = RegionToIdx(region);
   if (g_jump_dn[idx]) return;

   // Chỉ cho Sell khi vùng âm
   if (region < 0)
   {
      double lot = 2 * TotalLots(1);
      if (lot > 0)
      {
         string cmt = StringFormat("Sell vùng %d entry %.2f", region, BidPrice());
         if (OpenSell(lot, cmt))
         {
            g_jump_dn[idx] = true;
            LockAfterJumpDown(region);
            Print("✅ Sell opened on jump to region ", region);
         }
      }
      else
      {
         g_jump_dn[idx] = true;
         Print("⚠️ No Sell opened (lot=0), region ", region);
      }
   }
   else
   {
      g_jump_dn[idx] = true;
      Print("⚠️ Jump down ignored for non-negative region ", region);
   }
}

//=== OPEN TRADE ====================================================
void TryNormalTrade(int r, int half) {
   if (!AllowedThisInterval()) return;

   double plannedLot = NormalizeLot(BaseLot);
   if (plannedLot <= 0.0) return;

   double totB = TotalLots(1);
   double totS = TotalLots(-1);
   double entry = RegionMid(r);
   double ask = AskPrice();
   double bid = BidPrice();

   // ✅ Kiểm tra đúng nửa vùng
   if (half == 0) { // BUY-half
      if (ask >= entry) {
         Print("⛔ Buy blocked: Ask=", ask, " >= entry=", entry, ", region=", r);
         return;
      }
   } else { // SELL-half
      if (bid <= entry) {
         Print("⛔ Sell blocked: Bid=", bid, " <= entry=", entry, ", region=", r);
         return;
      }
   }

   double diff = totB - totS;

   // ✅ Điều kiện mới:
   // Nếu diff <= ImbalanceCapV0 → cho BUY
   // Nếu diff >= -ImbalanceCapV0 → cho SELL
   if (half == 0) { // BUY-half
      if (diff < ImbalanceCapV0) {
         string cmt = StringFormat("Buy vùng %d entry %.2f", r, ask);
         if (OpenBuy(plannedLot, cmt))
            Print("✅ Buy opened: lot=", plannedLot, ", region=", r);
      } else {
         Print("⚠️ Buy skipped: diff=", diff, " > ", ImbalanceCapV0);
      }
   } else { // SELL-half
      if (diff > -ImbalanceCapV0) {
         string cmt = StringFormat("Sell vùng %d entry %.2f", r, bid);
         if (OpenSell(plannedLot, cmt))
            Print("✅ Sell opened: lot=", plannedLot, ", region=", r);
      } else {
         Print("⚠️ Sell skipped: diff=", diff, " < -", ImbalanceCapV0);
      }
   }
}

//=== Main Functions ====================================================
int OnInit()
{
   // ⚠️ Kiểm tra hết hạn
   if (!CheckExpiry())
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   ResetLocks();

   //=== Ưu tiên load entry0 từ GlobalVariable, nếu chưa có thì lấy từ open nến M1 ===
   string gv_name = _Symbol + "_ZoneEntry0";
   double gv_value = 0.0;

   if (GlobalVariableCheck(gv_name))
      gv_value = GlobalVariableGet(gv_name);

   if (gv_value != 0.0)
   {
      g_entry0 = NormalizeDouble(gv_value, _Digits);
      PrintFormat("♻️ Loaded entry0 from GlobalVariable [%s] = %.5f", gv_name, g_entry0);
   }
   else
   {
      double m1open = iOpen(_Symbol, PERIOD_M1, 0);
      if (m1open == 0.0)
         m1open = (AskPrice() + BidPrice()) / 2.0;  // fallback nếu chưa có dữ liệu nến

      g_entry0 = NormalizeDouble(m1open, _Digits);
      GlobalVariableSet(gv_name, g_entry0);
      PrintFormat("🚀 No GlobalVariable found → entry0 set from M1 open = %.5f", g_entry0);
   }

   saved_entry0   = g_entry0;
   g_entry0_set   = true;
   g_prev_entry0  = g_entry0;

   int init_region = DetectRegion(BidPrice());
   g_prev_region   = init_region;

   DrawHUD(init_region);
   InitJumpLocksFromOrders();
   PrintFormat("✅ EA initialized with entry0 = %.5f", g_entry0);
   return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+

void OnTick()
{
   if (CheckCloseAll()) return;
   
   // ✅ Chỉ cập nhật entry0 lần đầu tiên khi chưa có
   if (PositionsTotal() > 0 && !g_entry0_set) {
      UpdateEntry0();
      g_entry0 = NormalizeDouble(g_entry0, _Digits);
      g_entry0_set = true;
   }

   double bid  = BidPrice();
   int region  = DetectRegion(bid);
   int half    = HalfSide(bid, region);
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (balance < 1.0)
      return;
   
   OnJump(g_prev_region, region);
   TryNormalTrade(region, half);

   bool entryChanged  = (MathAbs(g_entry0 - g_prev_entry0) > 1e-10);
   bool regionChanged = (region != g_prev_region);

   // ✅ Chỉ vẽ lại khi entry hoặc vùng thay đổi
   if (entryChanged || regionChanged)

   DrawHUD(region);

   g_prev_region = region;
   g_prev_entry0 = g_entry0;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   SaveEntry0ToGlobal(); // ✅ Lưu entry0 lại trước khi EA bị unload

   // Xóa tất cả objects khi EA bị remove
   long chart_id = ChartID();
   for (int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--) {
      string obj = ObjectName(0, i);
      if (StringFind(obj, "Z_") == 0) {
         ObjectDelete(chart_id, obj);
      }
   }
   ChartRedraw(chart_id);
   Print("✅ EA Deinitialized. All objects removed.");
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
