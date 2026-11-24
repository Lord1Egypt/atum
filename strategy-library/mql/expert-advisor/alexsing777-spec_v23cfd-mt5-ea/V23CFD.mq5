//+------------------------------------------------------------------+
//| V23CFD.mq5                                                        |
//| 把Codex项目里的V2.3期货策略(外盘定方向/降仓避险/移动止损锁利)      |
//| 翻译成MQL5，用CFD代替品实时跑：黄金/白银/铜/镍/原油(5个，锡没有CFD)|
//| 每个品种独立判断，可同时持仓，总保证金占用不超账户净值50%(按     |
//| 当前有效信号数平分)。只做多。                                     |
//+------------------------------------------------------------------+
#property copyright "claudey"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

//──────────────────────────── 输入参数 ────────────────────────────
input string InpSymbols        = "XAUUSD,XAGUSD,XCUUSD,XNIUSD,USOIL";
input double InpTargetRate     = 0.50;   // 趋势持有时的目标保证金比例
input double InpProtectRate    = 0.20;   // 降仓避险时的目标保证金比例
input double InpMaxTotalMargin = 0.50;   // 全组合最多占净值这么多保证金
input double InpInitStopPct    = 0.10;   // 初始止损=开仓价跌10%（或MA32，取高者）
input double InpHighLockProfitPct = 0.50; // 单品种(影子账本)浮盈达到本金50%才启动"高位锁利"
input double InpProfitLockPct  = 0.15;   // 浮盈达到影子本金15%才可能触发profit_lock
input double InpProfitableFloor = 0.10;  // 影子浮盈达到10%才算"有正儿八经利润"
input double InpDivergenceFloor = 0.075; // 顶背离至少要有7.5%影子浮盈才算数
input int    InpMagicBase      = 20260720;

// 品种模式：写死对照 mode_for_market()
// XAU/XAG = entry_filter；OIL = trailing_only；XCU/XNI = staged_take_profit
enum V23Mode { MODE_ENTRY_FILTER, MODE_TRAILING_ONLY, MODE_STAGED_TP, MODE_DISABLED };

string   g_symbols[];
V23Mode  g_modes[];
int      g_hMa13[], g_hMa32[], g_hMa55[], g_hMa20[], g_hWMa13[], g_hMMa13[], g_hMacd[];
datetime g_lastRunDay = 0;
const double SHADOW_INIT_EQUITY = 1000000.0;

//+------------------------------------------------------------------+
V23Mode ModeForSymbol(string sym)
{
   if (StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0) return MODE_ENTRY_FILTER;
   if (StringFind(sym, "OIL") >= 0) return MODE_TRAILING_ONLY;
   if (StringFind(sym, "XCU") >= 0 || StringFind(sym, "XNI") >= 0) return MODE_STAGED_TP;
   return MODE_DISABLED;
}

int OnInit()
{
   int n = StringSplit(InpSymbols, ',', g_symbols);
   ArrayResize(g_modes, n);
   ArrayResize(g_hMa13, n); ArrayResize(g_hMa32, n); ArrayResize(g_hMa55, n);
   ArrayResize(g_hMa20, n); ArrayResize(g_hWMa13, n); ArrayResize(g_hMMa13, n); ArrayResize(g_hMacd, n);

   for (int i = 0; i < n; i++)
   {
      string s = g_symbols[i];
      g_modes[i] = ModeForSymbol(s);
      if (!SymbolSelect(s, true)) { Print("警告: 品种不可用 ", s); continue; }
      g_hMa13[i]  = iMA(s, PERIOD_D1, 13, 0, MODE_SMA, PRICE_CLOSE);
      g_hMa32[i]  = iMA(s, PERIOD_D1, 32, 0, MODE_SMA, PRICE_CLOSE);
      g_hMa55[i]  = iMA(s, PERIOD_D1, 55, 0, MODE_SMA, PRICE_CLOSE);
      g_hMa20[i]  = iMA(s, PERIOD_D1, 20, 0, MODE_SMA, PRICE_CLOSE);
      g_hWMa13[i] = iMA(s, PERIOD_W1, 13, 0, MODE_SMA, PRICE_CLOSE);
      g_hMMa13[i] = iMA(s, PERIOD_MN1,13, 0, MODE_SMA, PRICE_CLOSE);
      g_hMacd[i]  = iMACD(s, PERIOD_D1, 12, 26, 9, PRICE_CLOSE);

      if (GetShadowEquity(s) <= 0) SetShadowEquity(s, SHADOW_INIT_EQUITY);
   }
   EventSetTimer(3600);
   Print("V23CFD 初始化完成，标的数: ", n);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() {}

void OnTimer()
{
   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if (today == g_lastRunDay) return;
   if (TimeCurrent() - today < 60) return;
   g_lastRunDay = today;
   RunDaily();
}

//──────────────────────────── 影子账本(每品种独立,只为算%阈值用) ──
double GetShadowEquity(string sym)  { return GlobalVariableCheck("v23eq_"+sym)  ? GlobalVariableGet("v23eq_"+sym)  : 0; }
void   SetShadowEquity(string sym, double v) { GlobalVariableSet("v23eq_"+sym, v); }
double GetShadowPeak(string sym)    { return GlobalVariableCheck("v23pk_"+sym)  ? GlobalVariableGet("v23pk_"+sym)  : SHADOW_INIT_EQUITY; }
void   SetShadowPeak(string sym, double v)   { GlobalVariableSet("v23pk_"+sym, v); }
double GetEntryEquity(string sym)   { return GlobalVariableCheck("v23ee_"+sym)  ? GlobalVariableGet("v23ee_"+sym)  : 0; }
void   SetEntryEquity(string sym, double v)  { GlobalVariableSet("v23ee_"+sym, v); }
bool   GetHighLock(string sym)      { return GlobalVariableCheck("v23hl_"+sym)  ? GlobalVariableGet("v23hl_"+sym) > 0.5 : false; }
void   SetHighLock(string sym, bool v)       { GlobalVariableSet("v23hl_"+sym, v?1:0); }
bool   GetCycleLockout(string sym)  { return GlobalVariableCheck("v23cl_"+sym)  ? GlobalVariableGet("v23cl_"+sym) > 0.5 : false; }
void   SetCycleLockout(string sym, bool v)   { GlobalVariableSet("v23cl_"+sym, v?1:0); }
bool   GetDerisk(string sym)        { return GlobalVariableCheck("v23dr_"+sym)  ? GlobalVariableGet("v23dr_"+sym) > 0.5 : false; }
void   SetDerisk(string sym, bool v)         { GlobalVariableSet("v23dr_"+sym, v?1:0); }
double GetStopPrice(string sym)     { return GlobalVariableCheck("v23sp_"+sym)  ? GlobalVariableGet("v23sp_"+sym)  : 0; }
void   SetStopPrice(string sym, double v)    { GlobalVariableSet("v23sp_"+sym, v); }
double GetShadowContracts(string sym){ return GlobalVariableCheck("v23sc_"+sym) ? GlobalVariableGet("v23sc_"+sym) : 0; }
void   SetShadowContracts(string sym, double v){ GlobalVariableSet("v23sc_"+sym, v); }
double GetShadowPrevClose(string sym){ return GlobalVariableCheck("v23pc_"+sym) ? GlobalVariableGet("v23pc_"+sym) : 0; }
void   SetShadowPrevClose(string sym, double v){ GlobalVariableSet("v23pc_"+sym, v); }

// 影子账本按"昨天的目标rate"推演到今天收盘（先结算盈亏，再用新权益判断今天的信号）
void MarkShadowToMarket(string sym, double todayClose)
{
   double prevClose = GetShadowPrevClose(sym);
   double prevContracts = GetShadowContracts(sym);
   if (prevClose > 0 && prevContracts != 0)
   {
      double eq = GetShadowEquity(sym);
      eq += prevContracts * (todayClose - prevClose);
      SetShadowEquity(sym, eq);
   }
}

//+------------------------------------------------------------------+
struct V23Row
{
   double close, high, low;
   double ma13, ma32, ma55, ma20, wMa13, mMa13;
   double macdDif, macdDea, macdHist;
   double lwr1, lwr2, lwrd;
   int    baseStage;
   bool   paEntryConfirm, paTopRisk;
   bool   divergenceRaw;
   double prior20High;
   bool   ok;
};

bool CalcRow(int idx, string sym, V23Row &r)
{
   int need = 70; // 30(背离回看)+30(前置窗口)+若干warmup，留够
   double closeArr[], highArr[], lowArr[];
   double ma13a[], ma32a[], ma55a[], ma20a[], wma13a[], mma13a[], macdMainA[], macdSigA[];

   if (CopyClose(sym, PERIOD_D1, 0, need, closeArr) < need) return false;
   if (CopyHigh(sym, PERIOD_D1, 0, need, highArr) < need) return false;
   if (CopyLow(sym, PERIOD_D1, 0, need, lowArr) < need) return false;
   ArraySetAsSeries(closeArr, true); ArraySetAsSeries(highArr, true); ArraySetAsSeries(lowArr, true);

   if (CopyBuffer(g_hMa13[idx], 0, 0, need, ma13a) < need) return false;
   if (CopyBuffer(g_hMa32[idx], 0, 0, need, ma32a) < need) return false;
   if (CopyBuffer(g_hMa55[idx], 0, 0, need, ma55a) < need) return false;
   if (CopyBuffer(g_hMa20[idx], 0, 0, need, ma20a) < need) return false;
   if (CopyBuffer(g_hWMa13[idx], 0, 0,3, wma13a) < 3) return false;
   if (CopyBuffer(g_hMMa13[idx], 0, 0,3, mma13a) < 3) return false;
   if (CopyBuffer(g_hMacd[idx], 0, 0, need, macdMainA) < need) return false;
   if (CopyBuffer(g_hMacd[idx], 1, 0, need, macdSigA) < need) return false;
   ArraySetAsSeries(ma13a,true); ArraySetAsSeries(ma32a,true); ArraySetAsSeries(ma55a,true);
   ArraySetAsSeries(ma20a,true); ArraySetAsSeries(wma13a,true); ArraySetAsSeries(mma13a,true);
   ArraySetAsSeries(macdMainA,true); ArraySetAsSeries(macdSigA,true);

   r.close = closeArr[0]; r.high = highArr[0]; r.low = lowArr[0];
   r.ma13 = ma13a[0]; r.ma32 = ma32a[0]; r.ma55 = ma55a[0]; r.ma20 = ma20a[0];
   r.wMa13 = wma13a[0]; r.mMa13 = mma13a[0];
   r.macdDif = macdMainA[0]; r.macdDea = macdSigA[0]; r.macdHist = (r.macdDif - r.macdDea) * 2;

   // LWR：9日"收盘价"通道RSV，3次递归平滑(等价 (v+2*prev)/3)
   double hist_hi9[40], hist_lo9[40], rsv[40], lwr1a[40], lwr2a[40];
   for (int i = 0; i < 40; i++)
   {
      double hh = closeArr[i], ll = closeArr[i];
      for (int j = i; j < i+9 && j < need; j++) { if (closeArr[j] > hh) hh = closeArr[j]; if (closeArr[j] < ll) ll = closeArr[j]; }
      double rng = hh - ll;
      rsv[i] = (rng > 0) ? (closeArr[i]-hh)/rng*100.0 : 0.0; // 与python一致：price-high_n，通常<=0
   }
   lwr1a[39] = rsv[39];
   for (int i = 38; i >= 0; i--) lwr1a[i] = (rsv[i] + 2.0*lwr1a[i+1]) / 3.0;
   lwr2a[39] = lwr1a[39];
   for (int i = 38; i >= 0; i--) lwr2a[i] = (lwr1a[i] + 2.0*lwr2a[i+1]) / 3.0;
   r.lwr1 = lwr1a[0]; r.lwr2 = lwr2a[0]; r.lwrd = r.lwr1 - r.lwr2;

   bool weekBull  = r.close > r.wMa13;
   bool monthBull = r.close > r.mMa13;
   r.baseStage = (weekBull && monthBull) ? 3 : (weekBull || monthBull) ? 1 : 0;

   // prior 10/20 high/low（不含今天）
   double p10h=highArr[1], p10l=lowArr[1], p20h=highArr[1], p20l=lowArr[1];
   for (int i=1;i<=10 && i<need;i++){ if(highArr[i]>p10h)p10h=highArr[i]; if(lowArr[i]<p10l)p10l=lowArr[i]; }
   for (int i=1;i<=20 && i<need;i++){ if(highArr[i]>p20h)p20h=highArr[i]; if(lowArr[i]<p20l)p20l=lowArr[i]; }
   r.prior20High = p20h;
   double range10 = (p10h-p10l)/r.close;
   double p10h_1=highArr[2], p10l_1=lowArr[2], p20h_1=highArr[2], p20l_1=lowArr[2];
   for (int i=2;i<=11 && i<need;i++){ if(highArr[i]>p10h_1)p10h_1=highArr[i]; if(lowArr[i]<p10l_1)p10l_1=lowArr[i]; }
   for (int i=2;i<=21 && i<need;i++){ if(highArr[i]>p20h_1)p20h_1=highArr[i]; if(lowArr[i]<p20l_1)p20l_1=lowArr[i]; }
   double range20_shift1 = (p20h_1-p20l_1)/closeArr[1];

   bool bullStack = r.close > r.ma13 && r.ma13 > r.ma32 && r.ma32 > r.ma55;
   double demandLine = MathMax(r.ma13, r.ma32);
   bool demandRetest = bullStack && r.low <= demandLine*1.015 && r.close > demandLine;
   bool flagRetest = bullStack && r.close > p10h && range10 < range20_shift1;
   bool compressionBreakout = bullStack && range10 < 0.085 && r.close > p20h;
   bool ssrLong = bullStack && r.low <= p20h*1.018 && r.close > p20h;
   r.paEntryConfirm = demandRetest || flagRetest || compressionBreakout || ssrLong;

   bool stopHuntTop = r.high > p20h*1.005 && r.close < p20h;
   bool falseBreakTop = r.high > p10h*1.005 && r.close < p10h && r.close < closeArr[1];
   bool qmlTop = r.high > p20h*1.005 && r.close < p10l;
   r.paTopRisk = stopHuntTop || falseBreakTop || qmlTop;

   // 30日背离：今天创30日新高价，但MACD/DIF、lwrd、macd_hist没同步创新高
   double priorPriceHigh=closeArr[1], priorMacdHigh=macdMainA[1], priorHistHigh=(macdMainA[1]-macdSigA[1])*2;
   double priorLwrdHigh = -1e9;
   double lwrdArr[40];
   for (int i=0;i<40;i++) lwrdArr[i] = lwr1a[i]-lwr2a[i];
   for (int i=1;i<=30 && i<need;i++)
   {
      if (closeArr[i] > priorPriceHigh) priorPriceHigh = closeArr[i];
      if (macdMainA[i] > priorMacdHigh) priorMacdHigh = macdMainA[i];
      double h = (macdMainA[i]-macdSigA[i])*2;
      if (h > priorHistHigh) priorHistHigh = h;
      if (i < 40 && lwrdArr[i] > priorLwrdHigh) priorLwrdHigh = lwrdArr[i];
   }
   r.divergenceRaw = (r.close > priorPriceHigh) && (r.macdDif < priorMacdHigh) &&
                      (r.lwrd < priorLwrdHigh) && (r.macdHist < priorHistHigh);
   r.ok = true;
   return true;
}

//──────────────────────────── 止损相关(照抄python逻辑) ────────────
double InitialLongStop(double entry, double trendStop)
{
   double pctLine = entry * (1.0 - InpInitStopPct);
   if (trendStop <= 0 || trendStop > entry) return pctLine;
   return MathMax(pctLine, trendStop);
}
double UpdateLongStop(double prevStop, double trendStop, double curPrice)
{
   if (trendStop <= 0 || trendStop > curPrice) return prevStop;
   return MathMax(prevStop, trendStop);
}
double HighLockStop(double prevStop, double completedLow)
{
   return MathMax(prevStop, completedLow);
}

//──────────────────────────── 主流程 ───────────────────────────────
void RunDaily()
{
   Print("===== V23CFD 日更新 ", TimeToString(TimeCurrent()), " =====");
   int n = ArraySize(g_symbols);

   V23Row rows[]; ArrayResize(rows, n);
   bool valid[]; ArrayResize(valid, n);
   for (int i = 0; i < n; i++)
   {
      if (g_modes[i] == MODE_DISABLED) { valid[i] = false; continue; }
      valid[i] = CalcRow(i, g_symbols[i], rows[i]);
      if (!valid[i]) Print("  ", g_symbols[i], " 数据不足，跳过本轮");
   }

   // ── 第一步：每个品种独立走一遍V2.3状态机，算出目标rate(0/0.2/0.5) ──
   double rate[]; ArrayResize(rate, n);
   string reason[]; ArrayResize(reason, n);
   for (int i = 0; i < n; i++)
   {
      if (!valid[i]) { rate[i] = 0; continue; }
      string sym = g_symbols[i];
      V23Row r = rows[i];
      ulong ticket; string dummy;
      bool hasPos = FindPosition(sym, InpMagicBase + i, ticket);

      MarkShadowToMarket(sym, r.close);
      double shadowEq = GetShadowEquity(sym);
      double shadowPeak = GetShadowPeak(sym);
      double entryEq = hasPos ? GetEntryEquity(sym) : shadowEq;
      bool highLock = hasPos ? GetHighLock(sym) : false;
      bool cycleLockout = GetCycleLockout(sym);
      bool derisk = GetDerisk(sym);

      bool lwrDown = r.lwr1 < r.lwr2;
      bool rawActive = (r.baseStage > 0) && !(r.ma32 > 0 && r.close < r.ma32 && lwrDown);
      if (!rawActive) cycleLockout = false;
      bool active = rawActive && !cycleLockout;

      if (hasPos) shadowPeak = MathMax(shadowPeak, shadowEq);
      double maxProfit = MathMax(0.0, shadowPeak - entryEq);
      double curProfit = shadowEq - entryEq;
      double giveback = maxProfit - curProfit;
      bool profitLock = maxProfit >= entryEq*InpProfitLockPct && maxProfit > 0 && (giveback/MathMax(maxProfit,1e-9)) >= 0.35;
      bool weakTop = r.ma20 > 0 && r.ma13 > 0 && lwrDown && r.close < r.ma13 && r.close < r.ma20;
      bool divergence = r.divergenceRaw && maxProfit >= entryEq*InpDivergenceFloor;

      if (hasPos && maxProfit >= entryEq*InpHighLockProfitPct) highLock = true;
      bool profitable = maxProfit >= entryEq*InpProfitableFloor;

      // decide_policy
      int riskAction = 0; // 0=NONE 1=DERISK 2=TIGHTEN_STOP 3=TAKE_PROFIT
      bool waitEntryStructure = false;
      if (active)
      {
         waitEntryStructure = (g_modes[i]==MODE_ENTRY_FILTER && !hasPos && !r.paEntryConfirm);
         if (hasPos && r.paTopRisk && profitable)
         {
            if (g_modes[i]==MODE_TRAILING_ONLY) riskAction = 2;
            else if (g_modes[i]==MODE_STAGED_TP || g_modes[i]==MODE_ENTRY_FILTER) riskAction = highLock ? 3 : 1;
         }
      }

      if (!rawActive || cycleLockout || riskAction==3) derisk = false;
      else if (divergence || profitLock || weakTop || riskAction==1) derisk = true;

      bool readdRequiresStructure = (g_modes[i]==MODE_ENTRY_FILTER);
      bool readd = active && derisk && !divergence && riskAction==0 &&
                   r.ma13>0 && r.close > r.ma13 && r.close > r.prior20High &&
                   (!readdRequiresStructure || r.paEntryConfirm);
      if (readd) { derisk = false; shadowPeak = shadowEq; }

      if (riskAction == 3) { rate[i]=0; reason[i]="v23_take_profit"; }
      else if (cycleLockout && rawActive) { rate[i]=0; reason[i]="high_lock_rest"; }
      else if (!active) { rate[i]=0; reason[i]="full_exit"; }
      else if (waitEntryStructure) { rate[i]=0; reason[i]="wait_price_action"; }
      else if (derisk) { rate[i]=InpProtectRate; reason[i]="v23_derisk"; }
      else { rate[i]=InpTargetRate; reason[i]="trend_hold"; }

      SetShadowPeak(sym, shadowPeak);
      SetDerisk(sym, derisk);
      SetCycleLockout(sym, cycleLockout);
      if (hasPos) SetHighLock(sym, highLock);

      // 记下"今天"的影子仓位和收盘价，供明天开盘时结算盈亏用
      double shadowContracts = (r.close > 0) ? (shadowEq * rate[i]) / r.close : 0;
      SetShadowContracts(sym, shadowContracts);
      SetShadowPrevClose(sym, r.close);
   }

   // ── 第二步：组合层——统计当前有效信号数，按50%总保证金平分 ──
   int activeCount = 0;
   for (int i = 0; i < n; i++) if (valid[i] && rate[i] > 0) activeCount++;
   double perSignalCap = (activeCount > 0) ? (InpMaxTotalMargin / activeCount) : 0;

   for (int i = 0; i < n; i++)
   {
      if (!valid[i]) continue;
      string sym = g_symbols[i];
      int magic = InpMagicBase + i;
      ulong ticket;
      bool hasPos = FindPosition(sym, magic, ticket);
      double allocation = MathMin(rate[i], perSignalCap);

      ManageExit(sym, magic, rows[i], hasPos, ticket, reason[i]);
      hasPos = FindPosition(sym, magic, ticket); // 上面可能已经平仓，重新读一次

      if (!hasPos && allocation > 0)
         OpenPosition(sym, magic, rows[i], allocation);
      else if (hasPos)
         UpdateTrailingStop(sym, ticket, rows[i]);
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("净值=", eq, "  当前有效信号数=", activeCount, "  单信号上限=", perSignalCap);
}

bool FindPosition(string sym, int magic, ulong &ticket)
{
   for (int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if (!PositionSelectByTicket(tk)) continue;
      if (PositionGetString(POSITION_SYMBOL) == sym && (int)PositionGetInteger(POSITION_MAGIC) == magic)
      { ticket = tk; return true; }
   }
   return false;
}

void ManageExit(string sym, int magic, V23Row &r, bool hasPos, ulong ticket, string reason)
{
   if (!hasPos) return;
   if (!PositionSelectByTicket(ticket)) return;
   double stopPrice = GetStopPrice(sym);
   double low = r.low;

   bool stopHit = (stopPrice > 0 && low <= stopPrice);
   bool takeProfitExit = (reason == "v23_take_profit");

   if (stopHit || takeProfitExit)
   {
      double exitPrice = takeProfitExit ? r.close : MathMin(SymbolInfoDouble(sym, SYMBOL_BID), stopPrice);
      trade.PositionClose(ticket);
      bool wasHighLock = GetHighLock(sym);
      if (stopHit && wasHighLock) { SetCycleLockout(sym, true); Print("  [", sym, "] 高位止损离场，本轮趋势锁仓"); }
      else if (takeProfitExit) { SetCycleLockout(sym, true); Print("  [", sym, "] V23止盈清仓，本轮趋势锁仓"); }
      else Print("  [", sym, "] 普通止损离场");
      SetHighLock(sym, false);
      SetStopPrice(sym, 0);
   }
}

void OpenPosition(string sym, int magic, V23Row &r, double allocationRate)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if (ask <= 0) return;

   double marginPerLot = 0;
   if (!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, ask, marginPerLot) || marginPerLot <= 0) return;
   double lot = (equity * allocationRate) / marginPerLot;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   lot = MathRound(lot/step)*step;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   if (lot < minLot) { Print("  [", sym, "] 分配仓位太小，手数不够1手，跳过"); return; }

   double trendStop = r.ma32;
   double stop = InitialLongStop(ask, trendStop);

   trade.SetExpertMagicNumber(magic);
   if (trade.Buy(lot, sym, ask, stop, 0, "v23"))
   {
      SetEntryEquity(sym, GetShadowEquity(sym));
      SetShadowPeak(sym, GetShadowEquity(sym));
      SetHighLock(sym, false);
      SetStopPrice(sym, stop);
      Print("  [开仓] ", sym, " lot=", lot, " 价:", ask, " 止损:", stop, " 分配仓位:", allocationRate);
   }
   else Print("  [", sym, "] 下单失败 retcode=", trade.ResultRetcode());
}

void UpdateTrailingStop(string sym, ulong ticket, V23Row &r)
{
   if (!PositionSelectByTicket(ticket)) return;
   double stopPrice = GetStopPrice(sym);
   bool highLock = GetHighLock(sym);
   double newStop;
   if (highLock) newStop = HighLockStop(stopPrice, r.low);
   else          newStop = UpdateLongStop(stopPrice, r.ma32, r.close);

   if (newStop > stopPrice)
   {
      SetStopPrice(sym, newStop);
      trade.PositionModify(ticket, newStop, PositionGetDouble(POSITION_TP));
   }
}
