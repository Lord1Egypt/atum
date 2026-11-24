//+------------------------------------------------------------------+
//|                                     SingleIchi_PropFirm.mq5      |
//|               Ichimoku Cloud Break - Single Order - Institutional  |
//|               Version 7.0 - Apex Proprietary Firm Standard       |
//+------------------------------------------------------------------+
#property copyright "Comarai EA - SingleIchi v7.0 Apex"
#property link      "https://comarai.com"
#property version   "7.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

enum ENUM_TRADE_DIR { DIR_BOTH=0, DIR_BUY=1, DIR_SELL=2 };
enum ENUM_LOT_MODE { LOT_FIXED=0, LOT_RISK=1 };
enum ENUM_SL_MODE { SL_FIXED_PIPS=0, SL_KIJUN_SEN=1, SL_ATR_BASED=2, SL_RECENT_SWING=3 };
enum ENUM_TP_MODE { TP_FIXED_PIPS=0, TP_RR_MULTIPLIER=1, TP_TRAILING_ONLY=2 };

input int      InpMagicID           = 9196;       
input ENUM_TRADE_DIR InpTradeDir    = DIR_BOTH;   

input string   _sec_sl      = "--- DYNAMIC STOPLOSS ---";
input ENUM_SL_MODE InpSLMode        = SL_RECENT_SWING; 
input double   InpSLFixedPips       = 30.0;       
input double   InpSLATRMult         = 1.5;        
input int      InpSLSwingBars       = 10;         
input double   InpSLBufferPips      = 2.0;        

input string   _sec_rp      = "--- RISK & LOT SIZING ---";
input ENUM_LOT_MODE InpLotMode      = LOT_RISK;   
input double   InpRiskPercent       = 1.0;        // Mỗi lệnh rủi ro x%
input double   InpLots              = 0.01;       

input string   _sec_tp      = "--- TAKE PROFIT & SCALE OUT ---";
input ENUM_TP_MODE InpTPMode        = TP_RR_MULTIPLIER; 
input double   InpTPFixedPips       = 60.0;       
input double   InpRRMult            = 2.0;        // Ăn 2R (Gấp đôi SL) 
input bool     InpUseScaleOut       = true;       // [Scale Out]
input double   InpScaleOutRR        = 1.0;        
input double   InpScaleOutPct       = 50.0;       
input bool     InpMoveBE_After      = true;       
input double   InpBE_OffsetPips     = 1.0;        

input string   _sec_ichi    = "--- ICHIMOKU & FILTERS ---";
input int      InpIchiTenkan        = 9;          
input int      InpIchiKijun         = 26;         
input int      InpIchiSenkou        = 52;         
input double   InpMinBreakoutBody   = 0.5;        // Thân nến xuyên mây tối thiểu (ATR Mult)

input string   _sec_adx     = "--- CHOPPY MARKET FILTER (ADX) ---";
input bool     InpUseADX            = true;       
input ENUM_TIMEFRAMES InpADXTF      = PERIOD_CURRENT;
input int      InpADXPeriod         = 14;
input double   InpADXMinLevel       = 22.0;       

input string   _sec_ema     = "--- EMA TREND FILTER ---";
input bool     InpUseEMAFilter      = true;       
input ENUM_TIMEFRAMES InpTFEMAFilter = PERIOD_CURRENT; 
input int      InpEMAFast           = 34;         
input int      InpEMASlow           = 89;         

input string   _sec_trail   = "--- SMART TRAILING STOP ---";
input bool     InpUseTrailing       = true;        
input bool     InpTrailOnBarClose   = true;       
input double   InpTrailStartPips    = 15.0;       
input bool     InpUseATRTrail       = true;       
input double   InpTrailFixStep      = 5.0;        
input bool     InpUseKijunTrail     = true;       // [NEW] Trailing bám theo Kijun-Sen (Cực kỳ mạnh)
input ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_CURRENT; 
input int      InpATRPeriod         = 14;          
input double   InpATRMultiplier     = 1.5;         

input string   _sec_risk    = "--- DAILY PROP FIRM LIMITS ---";
input double   InpMaxSpread         = 3.0;        
input double   InpMaxDrawdownMoney  = 0.0;        
input double   InpMaxDrawdownPct    = 0.0;        
input double   InpDailyLossLimit    = 0.0;        
input double   InpDailyProfitTarget = 0.0;        
input int      InpMaxOrdersPerDay   = 5;          

input string   _sec_cb      = "--- CIRCUIT BREAKER (NEW) ---";
input int      InpMaxConsecutiveLoss= 3;          
input int      InpCooldownMinutes   = 120;        

input string   _sec_time    = "--- TIME & FRIDAY CLOSE ---";
input bool     InpUseTradingTime    = false;
input string   InpStartTime         = "08:00";
input string   InpEndTime           = "22:00";
input bool     InpCloseFriday       = false;
input int      InpCloseFridayHour   = 20;

input bool     InpAntiDetect        = true;       
input int      InpMinDelaySeconds   = 3;          
input int      InpMaxDelaySeconds   = 15;         

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_posInfo;

int            g_handleIchi   = INVALID_HANDLE;
int            g_handleEMAF   = INVALID_HANDLE;
int            g_handleEMAS   = INVALID_HANDLE;
int            g_handleATR    = INVALID_HANDLE;
int            g_handleADX    = INVALID_HANDLE;

datetime       g_lastOrderTime      = 0;
int            g_ordersOpenedToday  = 0;
int            g_lastDay            = -1;
double         g_dailyStartBalance  = 0;
datetime       g_nextAllowedTime    = 0;
datetime       g_lastBarTime        = 0;  
int            g_cachedSignal       = 0;  
int            g_ordersCount        = 0;

int            g_consecutiveLosses  = 0;
datetime       g_cooldownUntil      = 0;

ulong          g_activeTicket       = 0;
double         g_initialSL          = 0;  
bool           g_scaleOutDone       = false; 
double         g_currentTrailSL     = 0;

string         g_comments[];

//+------------------------------------------------------------------+
//| EXPERT INIT                                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagicID);
   g_trade.SetDeviationInPoints(10);
   
   // DYNAMIC FILLING MODE (Sửa lỗi 10030)
   int fill = (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill & SYMBOL_FILLING_FOK) != 0) g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fill & SYMBOL_FILLING_IOC) != 0) g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   
   g_handleIchi = iIchimoku(_Symbol, PERIOD_CURRENT, InpIchiTenkan, InpIchiKijun, InpIchiSenkou);
   g_handleATR = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
   if(InpUseEMAFilter) {
      ENUM_TIMEFRAMES emaTF = (InpTFEMAFilter == PERIOD_CURRENT) ? PERIOD_CURRENT : InpTFEMAFilter;
      g_handleEMAF = iMA(_Symbol, emaTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
      g_handleEMAS = iMA(_Symbol, emaTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   }
   if(InpUseADX) g_handleADX = iADX(_Symbol, InpADXTF, InpADXPeriod);
   
   InitCommentPool();
   LoadState();
   
   g_dailyStartBalance = GetStartOfDayBalance();
   MqlDateTime dt; TimeCurrent(dt);
   g_lastDay = dt.day;
   g_ordersOpenedToday = 0;
   
   Print("== SingleIchi PropFirm v7.0 Apex Institutional == ALGO REVISED");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_handleIchi != INVALID_HANDLE) IndicatorRelease(g_handleIchi);
   if(g_handleEMAF != INVALID_HANDLE) IndicatorRelease(g_handleEMAF);
   if(g_handleEMAS != INVALID_HANDLE) IndicatorRelease(g_handleEMAS);
   if(g_handleATR  != INVALID_HANDLE) IndicatorRelease(g_handleATR);
   if(g_handleADX  != INVALID_HANDLE) IndicatorRelease(g_handleADX);
}

//+------------------------------------------------------------------+
//| STATE RECOVERY (Chống khởi động lại mất Scale-Out)               |
//+------------------------------------------------------------------+
void SaveState() {
   GlobalVariableSet("SI_IniSL_" + _Symbol + "_" + IntegerToString(InpMagicID), g_initialSL);
   GlobalVariableSet("SI_Scale_" + _Symbol + "_" + IntegerToString(InpMagicID), g_scaleOutDone ? 1 : 0);
   GlobalVariableSet("SI_Tick_" + _Symbol + "_" + IntegerToString(InpMagicID), g_activeTicket);
}

void LoadState() {
   string n1 = "SI_IniSL_" + _Symbol + "_" + IntegerToString(InpMagicID);
   string n2 = "SI_Scale_" + _Symbol + "_" + IntegerToString(InpMagicID);
   string n3 = "SI_Tick_" + _Symbol + "_" + IntegerToString(InpMagicID);
   if(GlobalVariableCheck(n1)) g_initialSL = GlobalVariableGet(n1);
   if(GlobalVariableCheck(n2)) g_scaleOutDone = (GlobalVariableGet(n2) > 0);
   if(GlobalVariableCheck(n3)) g_activeTicket = (ulong)GlobalVariableGet(n3);
}

double GetStartOfDayBalance() {
   string gvName = "SI_StartBal_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string gvDay = "SI_StartDay_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   MqlDateTime dt; TimeCurrent(dt);
   
   if(GlobalVariableCheck(gvDay) && GlobalVariableCheck(gvName)) {
      if(GlobalVariableGet(gvDay) == dt.day) return GlobalVariableGet(gvName);
   }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   GlobalVariableSet(gvName, bal);
   GlobalVariableSet(gvDay, dt.day);
   return bal;
}

double GetSafeStopLevel() {
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if (stopLevel == 0) stopLevel = MathMax(10.0, (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point * 2.0);
   return stopLevel * _Point;
}

//+------------------------------------------------------------------+
//| HELPER LOGIC                                                     |
//+------------------------------------------------------------------+
void InitCommentPool() {
   ArrayResize(g_comments, 10);
   g_comments[0] = "manual entry";      g_comments[1] = "swing target";
   g_comments[2] = "cloud setup";       g_comments[3] = "trend fol";
   g_comments[4] = "vol filter";        g_comments[5] = "pos";
   g_comments[6] = "dip hit";           g_comments[7] = "rally fade";
   g_comments[8] = "breakout";          g_comments[9] = "htf align";
}

string GetRandomComment() {
   if(!InpAntiDetect) return "SingleIchi";
   return g_comments[MathRand() % ArraySize(g_comments)];
}

double GetPipPoint() {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits <= 3) {
      if(digits == 2 || digits == 3) return 0.1; 
      if(digits == 1) return 1.0; 
      return _Point;
   }
   if(digits == 5) return _Point * 10;
   if(digits == 4) return _Point;
   return _Point;
}

double NormLots(double lots) {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return NormalizeDouble(MathRound(lots / step) * step, 2);
}

int CountAllOrders() {
   int count = 0;
   ulong latestTicket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(g_posInfo.SelectByIndex(i) && g_posInfo.Symbol() == _Symbol && g_posInfo.Magic() == InpMagicID) {
         count++;
         latestTicket = g_posInfo.Ticket();
      }
   }
   if(count == 0) {
       g_activeTicket = 0;
       g_scaleOutDone = false;
       g_initialSL = 0;
       SaveState();
   } else if (count == 1 && g_activeTicket != latestTicket) {
       // Thẩm định: Map lại Ticket ID mới khi sàn tự ý cắt sửa/Scale Out lệnh
       g_activeTicket = latestTicket;
       if(g_initialSL == 0) g_initialSL = g_posInfo.StopLoss();
       SaveState();
   }
   return count;
}

void CloseAllOrders(string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(g_posInfo.SelectByIndex(i) && g_posInfo.Symbol() == _Symbol && g_posInfo.Magic() == InpMagicID) {
         Print("*** FORCED CLOSE: ", reason, " ***");
         g_trade.PositionClose(g_posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| CONSECUTIVE LOSS TRACKING (Tối ưu Memory / CPU)                  |
//+------------------------------------------------------------------+
void UpdateCircuitBreaker()
{
   if(InpMaxConsecutiveLoss <= 0) return;
   
   static int lastDealsTotal = -1;
   static int cachedConsecutiveLoss = 0;
   
   MqlDateTime dt; TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime startOfDay = StructToTime(dt);
   
   if(!HistorySelect(startOfDay, TimeCurrent())) return;
   
   int currentDealsTotal = HistoryDealsTotal();
   
   if(currentDealsTotal == lastDealsTotal) {
      g_consecutiveLosses = cachedConsecutiveLoss; 
      return; 
   }
   
   lastDealsTotal = currentDealsTotal;
   
   int consecLoss = 0;
   for(int i = currentDealsTotal - 1; i >= 0; i--) {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket > 0) {
         long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         string sym = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
         long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         
         if(magic == InpMagicID && sym == _Symbol && (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)) {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            if(profit < 0) consecLoss++; else break;
         }
      }
   }
   g_consecutiveLosses = consecLoss;
   cachedConsecutiveLoss = consecLoss;
   
   if(g_consecutiveLosses >= InpMaxConsecutiveLoss && g_cooldownUntil <= TimeCurrent()) {
      g_cooldownUntil = TimeCurrent() + (InpCooldownMinutes * 60);
      Print("!!! CIRCUIT BREAKER: Hit ", g_consecutiveLosses, " losses. Cooldown until ", TimeToString(g_cooldownUntil));
   }
}

//+------------------------------------------------------------------+
//| DYNAMIC CALCULATORS (INSTITUTIONAL GRADE)                        |
//+------------------------------------------------------------------+
double CalculateSL(ENUM_POSITION_TYPE type, double entryPrice) {
   double pip = GetPipPoint();
   double buffer = InpSLBufferPips * pip;
   double slPrice = 0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(InpSLMode == SL_FIXED_PIPS) {
      if(InpSLFixedPips <= 0) return 0;
      slPrice = (type == POSITION_TYPE_BUY) ? entryPrice - InpSLFixedPips * pip : entryPrice + InpSLFixedPips * pip;
   }
   else if(InpSLMode == SL_KIJUN_SEN) {
      double kijun[]; ArraySetAsSeries(kijun, true);
      if(CopyBuffer(g_handleIchi, 1, 1, 1, kijun) > 0 && kijun[0] > 0) {
         slPrice = (type == POSITION_TYPE_BUY) ? kijun[0] - buffer : kijun[0] + buffer;
      } else slPrice = (type == POSITION_TYPE_BUY) ? entryPrice - InpSLFixedPips * pip : entryPrice + InpSLFixedPips * pip;
   }
   else if(InpSLMode == SL_ATR_BASED) {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_handleATR, 0, 1, 1, atr) > 0) {
         double dist = atr[0] * InpSLATRMult + buffer;
         slPrice = (type == POSITION_TYPE_BUY) ? entryPrice - dist : entryPrice + dist;
      } else slPrice = (type == POSITION_TYPE_BUY) ? entryPrice - InpSLFixedPips * pip : entryPrice + InpSLFixedPips * pip;
   }
   else if(InpSLMode == SL_RECENT_SWING) {
      if(type == POSITION_TYPE_BUY) {
         double low[]; ArraySetAsSeries(low, true);
         if(CopyLow(_Symbol, PERIOD_CURRENT, 1, InpSLSwingBars, low) > 0) {
            slPrice = low[ArrayMinimum(low)] - buffer;
         } else slPrice = entryPrice - InpSLFixedPips * pip;
      } else {
         double high[]; ArraySetAsSeries(high, true);
         if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, InpSLSwingBars, high) > 0) {
            slPrice = high[ArrayMaximum(high)] + buffer;
         } else slPrice = entryPrice + InpSLFixedPips * pip;
      }
   }
   
   if (type == POSITION_TYPE_BUY && slPrice >= entryPrice) slPrice = entryPrice - InpSLFixedPips * pip;
   if (type == POSITION_TYPE_SELL && slPrice <= entryPrice) slPrice = entryPrice + InpSLFixedPips * pip;

   return NormalizeDouble(slPrice, digits);
}

double CalculateTP(ENUM_POSITION_TYPE type, double entryPrice, double slPrice) {
   if(InpTPMode == TP_TRAILING_ONLY) return 0;
   double pip = GetPipPoint();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   if(InpTPMode == TP_FIXED_PIPS) {
      if(InpTPFixedPips <= 0) return 0;
      return (type == POSITION_TYPE_BUY) ? NormalizeDouble(entryPrice + InpTPFixedPips * pip, digits) : NormalizeDouble(entryPrice - InpTPFixedPips * pip, digits);
   }
   else if(InpTPMode == TP_RR_MULTIPLIER) {
      if(slPrice <= 0) return 0; 
      double dist = MathAbs(entryPrice - slPrice);
      return (type == POSITION_TYPE_BUY) ? NormalizeDouble(entryPrice + dist * InpRRMult, digits) : NormalizeDouble(entryPrice - dist * InpRRMult, digits);
   }
   return 0;
}

double CalculateLotSize(double entryPrice, double slPrice) {
   if(InpLotMode == LOT_FIXED || InpRiskPercent <= 0 || slPrice <= 0) return InpLots;
   
   double slDistPrice = MathAbs(entryPrice - slPrice);
   if(slDistPrice <= 0) return InpLots;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue == 0 || tickSize == 0) return InpLots;
   
   double moneyRiskPerLot = (slDistPrice / tickSize) * tickValue;
   if(moneyRiskPerLot <= 0) return InpLots;
   
   // FIX CHÍ MẠNG: Ở quỹ Prop Firm (VD: FTMO, Apex), Tick Value có thể bị ảo khi Symbol là CFD/Crypto,
   // Dẫn đến moneyRiskPerLot sai lệch. Backup calculation:
   double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double backupRiskPerLot = (slDistPrice / pointValue) * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   if (backupRiskPerLot > 0 && MathAbs(moneyRiskPerLot - backupRiskPerLot) > moneyRiskPerLot * 0.5) {
      moneyRiskPerLot = backupRiskPerLot; // Use backup if difference is huge
   }

   double finalLot = NormLots(riskAmount / moneyRiskPerLot);
   
   // Bọc an toàn Prop Firm (Không xả quá giới hạn Max Lot của Symbol)
   double maxLotAllowed = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(finalLot > maxLotAllowed) finalLot = maxLotAllowed;
   if(finalLot > 50.0) finalLot = 50.0; // Hard cap chống bão (Fat Finger)
   
   return finalLot;
}

//+------------------------------------------------------------------+
//| SIGNAL & FILTERS                                                 |
//+------------------------------------------------------------------+
bool IsTrending_ADX() {
   if(!InpUseADX) return true;
   double adx[]; ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_handleADX, 0, 1, 1, adx) > 0) return adx[0] >= InpADXMinLevel;
   return false;
}

int GetEMATrend() {
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true); ArraySetAsSeries(emaSlow, true);
   if(CopyBuffer(g_handleEMAF, 0, 1, 1, emaFast) > 0 && CopyBuffer(g_handleEMAS, 0, 1, 1, emaSlow) > 0) {
      if(emaFast[0] > emaSlow[0]) return +1;
      if(emaFast[0] < emaSlow[0]) return -1;
   }
   return 0;
}

int GetIchimokuSignal() {
   double tenkan[], kijun[], spanA[], spanB[];
   ArraySetAsSeries(tenkan, true); ArraySetAsSeries(kijun, true);
   ArraySetAsSeries(spanA, true); ArraySetAsSeries(spanB, true);
   
   if(CopyBuffer(g_handleIchi, 0, 0, 4, tenkan) < 4) return 0;
   if(CopyBuffer(g_handleIchi, 1, 0, 4, kijun)  < 4) return 0;
   if(CopyBuffer(g_handleIchi, 2, 0, 4, spanA)  < 4) return 0;
   if(CopyBuffer(g_handleIchi, 3, 0, 4, spanB)  < 4) return 0;
   
   double open[], close[], high[], low[];
   ArraySetAsSeries(open, true); ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, 4, open) < 4 || CopyClose(_Symbol, PERIOD_CURRENT, 0, 4, close) < 4 || CopyHigh(_Symbol, PERIOD_CURRENT, 0, 4, high) < 4 || CopyLow(_Symbol, PERIOD_CURRENT, 0, 4, low) < 4) return 0;
   
   double bodySize = MathAbs(close[1] - open[1]);
   double minReqBody = 0;
   if(InpMinBreakoutBody > 0 && g_handleATR != INVALID_HANDLE) {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_handleATR, 0, 1, 1, atr) > 0) minReqBody = atr[0] * InpMinBreakoutBody;
   }
   
   double cloudTop2 = MathMax(spanA[2], spanB[2]);
   double cloudBot2 = MathMin(spanA[2], spanB[2]);
   double cloudTop1 = MathMax(spanA[1], spanB[1]);
   double cloudBot1 = MathMin(spanA[1], spanB[1]);
   
   // ALGO V7 CHỐNG LỖ: Cải tiến Breakout bằng Price Action Khắt Khe Hơn
   // 1. Chỉ vào lệnh khi Kijun-Sen ĐANG DỐC LÊN/XUỐNG (Trend Direction Confirm)
   bool kijunUp = (kijun[1] > kijun[3]);
   bool kijunDown = (kijun[1] < kijun[3]);
   
   // 2. Chống nến Pinbar (Rút râu ngược) ở ngay quả Breakout (Tín hiệu Fakey)
   double topTailBuy = high[1] - close[1];
   bool noBuyRejection = (topTailBuy < bodySize); // Râu trên không được dài hơn Thân nến
   
   double botTailSell = close[1] - low[1];
   bool noSellRejection = (botTailSell < bodySize); // Râu dưới không được dài hơn Thân nến
   
   // 3. Breakout phải RÕ RÀNG: close nến [1] phải cách Top/Bot Cloud ít nhất 2 point (chống bám biên)
   
   bool buyBreak = (close[2] <= cloudTop2) && (close[1] > cloudTop1 + (2 * _Point));
   bool buyTrend = (tenkan[1] > kijun[1]) && kijunUp;
   bool buyBody = (bodySize >= minReqBody) && noBuyRejection;
   if(buyBreak && buyTrend && buyBody) return +1;
   
   bool sellBreak = (close[2] >= cloudBot2) && (close[1] < cloudBot1 - (2 * _Point));
   bool sellTrend = (tenkan[1] < kijun[1]) && kijunDown;
   bool sellBody = (bodySize >= minReqBody) && noSellRejection;
   if(sellBreak && sellTrend && sellBody) return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| TRADE FILTERS (RISK, TIME, SPREAD)                               |
//+------------------------------------------------------------------+
bool IsTradingTimeOK()
{
   MqlDateTime dt; TimeCurrent(dt);
   if(InpCloseFriday && dt.day_of_week == 5 && dt.hour >= InpCloseFridayHour) return false;
   if(!InpUseTradingTime) return true;
   string currentTime = StringFormat("%02d:%02d", dt.hour, dt.min);
   return (currentTime >= InpStartTime && currentTime <= InpEndTime);
}

void CheckFridayClose()
{
   if(!InpCloseFriday) return;
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.day_of_week == 5 && dt.hour >= InpCloseFridayHour) {
      if(g_ordersCount > 0) {
         CloseAllOrders("FRIDAY CLOSE");
         g_ordersCount = 0; // FIX: Cập nhật ngay lập tức để vòng lặp dưới không bị kẹt process
      }
   }
}

bool IsRiskBreached()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   bool breached = false;
   
   double maxDdmoney = InpMaxDrawdownMoney > 0 ? InpMaxDrawdownMoney : 999999999;
   double accountHigh = GlobalVariableCheck("SI_HighBal_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))) ? GlobalVariableGet("SI_HighBal_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))) : g_dailyStartBalance;
   
   // Cập nhật High Watermark liên tục (chuẩn Quỹ Trailing Drawdown)
   if (balance > accountHigh) {
      accountHigh = balance;
      GlobalVariableSet("SI_HighBal_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), accountHigh);
   }

   string breachReason = "";
   if(InpDailyLossLimit > 0 && (equity - g_dailyStartBalance <= -InpDailyLossLimit)) {
      breachReason = "DAILY LOSS LIMIT"; breached = true;
   }
   else if(InpDailyProfitTarget > 0 && (equity - g_dailyStartBalance >= InpDailyProfitTarget)) {
      breachReason = "DAILY PROFIT TARGET"; breached = true;
   }
   // FIX: Tính Max Drawdown dựa trên High Watermark thay vì Balance hiện tại để tuân thủ luật Trailing Drawdown
   else if(InpMaxDrawdownMoney > 0 && (accountHigh - equity >= InpMaxDrawdownMoney)) {
      breachReason = "MAX DRAWDOWN MONEY"; breached = true;
   }
   else if(InpMaxDrawdownPct > 0 && accountHigh > 0 && ((accountHigh - equity) / accountHigh * 100.0 >= InpMaxDrawdownPct)) {
      breachReason = "MAX DRAWDOWN PCT"; breached = true;
   }
   
   if(breached) {
      static datetime lastLogTime = 0;
      if (TimeCurrent() - lastLogTime > 3600) { 
         Print("!!! RISK BREACHED: ", breachReason, " !!! TRADING HALTED.");
         lastLogTime = TimeCurrent();
      }
      if(g_ordersCount > 0) CloseAllOrders("RISK BREACHED: " + breachReason);
      g_cachedSignal = 0;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT: SCALE OUT & TRAILING                           |
//+------------------------------------------------------------------+
void ProcessScaleOut()
{
   if(!InpUseScaleOut || g_scaleOutDone || g_ordersCount == 0 || g_initialSL <= 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByIndex(i) || g_posInfo.Symbol() != _Symbol || g_posInfo.Magic() != InpMagicID) continue;
      
      double openPrice = g_posInfo.PriceOpen();
      double slDist = MathAbs(openPrice - g_initialSL);
      if(slDist <= 0) return;
      
      double currentPrice = (g_posInfo.PositionType() == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // FIX FATAL CAUGHT BY QUANTS: Tính Profit Distance chuẩn theo hướng lệnh, KO DÙNG MathAbs
      double profitDist = 0;
      if (g_posInfo.PositionType() == POSITION_TYPE_BUY) profitDist = currentPrice - openPrice;
      else profitDist = openPrice - currentPrice;
      
      double targetDist = slDist * InpScaleOutRR;
      
      if(profitDist >= targetDist && targetDist > 0) 
      {
         double vol = g_posInfo.Volume();
         double closeVol = NormLots(vol * (InpScaleOutPct / 100.0));
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         
         if(closeVol >= minLot && (vol - closeVol) >= minLot)
         {
            if(g_trade.PositionClosePartial(g_posInfo.Ticket(), closeVol))
            {
               g_scaleOutDone = true;
               Print(">>> SCALE OUT: Locked partial profit at ", InpScaleOutRR, " R");
               
               if(InpMoveBE_After)
               {
                  int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                  double pip = GetPipPoint();
                  double stopLevelPips = GetSafeStopLevel();
                  double curPrice = (g_posInfo.PositionType() == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                  double beSL = 0;
                  
                  if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
                  {
                     beSL = NormalizeDouble(openPrice + InpBE_OffsetPips * pip, digits);
                     if(curPrice - beSL > stopLevelPips)
                     {
                        g_trade.PositionModify(g_posInfo.Ticket(), beSL, g_posInfo.TakeProfit());
                        g_currentTrailSL = beSL; 
                     }
                  }
                  else
                  {
                     beSL = NormalizeDouble(openPrice - InpBE_OffsetPips * pip, digits);
                     if(beSL - curPrice > stopLevelPips)
                     {
                        g_trade.PositionModify(g_posInfo.Ticket(), beSL, g_posInfo.TakeProfit());
                        g_currentTrailSL = beSL; 
                     }
                  }
               }
               SaveState();
            }
         }
         else {
             g_scaleOutDone = true; SaveState(); 
         }
      }
   }
}

void ProcessTrailingStop()
{
   if(!InpUseTrailing || g_ordersCount == 0) return;
   
   double pip = GetPipPoint();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double stopLevelPips = GetSafeStopLevel();
   
   double trailDist = InpTrailFixStep * pip;
   
   // ALGO V7: Kijun-sen Trailing. Thoát lệnh khi trend thực sự gãy (Bám Trend siêu cứng)
   double kijunLevel = 0;
   double kijun[]; ArraySetAsSeries(kijun, true);
   if(InpUseKijunTrail && CopyBuffer(g_handleIchi, 1, 1, 1, kijun) > 0) {
      kijunLevel = kijun[0];
   }
   
   if(InpUseATRTrail && g_handleATR != INVALID_HANDLE) {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_handleATR, 0, 1, 1, atr) > 0) trailDist = atr[0] * InpATRMultiplier;
   }
   
   double trailStartDist = InpTrailStartPips * pip;
   if(trailDist < stopLevelPips * 1.5) trailDist = stopLevelPips * 1.5; // Bảo vệ lỗi 10016
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByIndex(i) || g_posInfo.Symbol() != _Symbol || g_posInfo.Magic() != InpMagicID) continue;
      
      double openPrice = g_posInfo.PriceOpen();
      double currentSL = g_posInfo.StopLoss();
      
      if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(InpTrailOnBarClose) {
            double close[]; CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close); 
            currentPrice = close[0]; 
         }
         
         if(currentPrice - openPrice >= trailStartDist)
         {
            double proposedSL = NormalizeDouble(currentPrice - trailDist, digits);
            if(InpUseKijunTrail && kijunLevel > 0) proposedSL = MathMax(proposedSL, kijunLevel - stopLevelPips); // Uư tiên Kijun nếu nó cao hơn
            
            if(g_currentTrailSL == 0) g_currentTrailSL = currentSL; 
            if(proposedSL > g_currentTrailSL && proposedSL > currentSL)
            {
               // Thẩm định: Cần check thêm g_currentTrailSL để không tạo Request liên tục do chênh lệch 1-2 point
               if(proposedSL <= currentPrice - stopLevelPips && (proposedSL - g_currentTrailSL) >= InpTrailFixStep * pip * 0.5)
               {
                  g_currentTrailSL = proposedSL;
                  g_trade.PositionModify(g_posInfo.Ticket(), proposedSL, g_posInfo.TakeProfit());
               }
            }
         }
      }
      else if(g_posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(InpTrailOnBarClose) {
            double close[]; CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close);
            currentPrice = close[0];
         }
         
         if(openPrice - currentPrice >= trailStartDist)
         {
            double proposedSL = NormalizeDouble(currentPrice + trailDist, digits);
            if(InpUseKijunTrail && kijunLevel > 0) proposedSL = MathMin(proposedSL, kijunLevel + stopLevelPips); // Uư tiên Kijun nếu nó thấp hơn
            
            if(g_currentTrailSL == 0) g_currentTrailSL = currentSL; 
            if(currentSL == 0 || g_currentTrailSL >= openPrice * 2.0) g_currentTrailSL = openPrice + 99999; 
            
            if(proposedSL < g_currentTrailSL && (currentSL == 0 || proposedSL < currentSL))
            {
               if(proposedSL >= currentPrice + stopLevelPips && (g_currentTrailSL - proposedSL) >= InpTrailFixStep * pip * 0.5)
               {
                  g_currentTrailSL = proposedSL;
                  g_trade.PositionModify(g_posInfo.Ticket(), proposedSL, g_posInfo.TakeProfit());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CORE CONTROL & ON TICK LOGIC                                     |
//+------------------------------------------------------------------+
bool IsNewBar() {
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(barTime == 0) return false;
   if(barTime != g_lastBarTime) { g_lastBarTime = barTime; return true; }
   return false;
}

bool ProcessNewOrder()
{
   if(g_ordersCount > 0) return false; 
   if(!IsTradingTimeOK() || TimeCurrent() < g_cooldownUntil) return false; 
   
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(InpMaxSpread > 0 && spread / GetPipPoint() > InpMaxSpread) return false; 
   
   if(InpAntiDetect && (g_ordersOpenedToday >= InpMaxOrdersPerDay || TimeCurrent() < g_nextAllowedTime)) { g_cachedSignal = 0; return false; }
   
   int emaTrend = InpUseEMAFilter ? GetEMATrend() : 999;
   if(!IsTrending_ADX() || (InpUseEMAFilter && emaTrend == 0)) { g_cachedSignal = 0; return false; } 
   
   int signal = g_cachedSignal; 
   if(signal == 0) return false;
   
   bool entered = false;
   if(signal > 0 && (emaTrend == 999 || emaTrend >= 0) && (InpTradeDir == DIR_BOTH || InpTradeDir == DIR_BUY))
   {
      double pPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double pSL = CalculateSL(POSITION_TYPE_BUY, pPrice);
      if(pSL <= 0 && InpLotMode == LOT_RISK) return false; 
      
      double pTP = CalculateTP(POSITION_TYPE_BUY, pPrice, pSL);
      double pLot = CalculateLotSize(pPrice, pSL);
      
      // BẢO VỆ STOPS_LEVEL CHỐNG LỖI 10016 (Slippage/Gap cực đoan)
      double stopLevelPips = GetSafeStopLevel();
      double minGap = stopLevelPips + (InpMaxSpread * GetPipPoint()); 
      if (pPrice - pSL < minGap) pSL = NormalizeDouble(pPrice - minGap, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      
      if(g_trade.Buy(pLot, _Symbol, pPrice, pSL, pTP, GetRandomComment()))
      {
         Print("+++ BUY. Risk Lot=", pLot, " SL_Mode=", EnumToString(InpSLMode));
         g_initialSL = pSL;
         g_scaleOutDone = false;
         g_currentTrailSL = 0;
         g_ordersOpenedToday++;
         g_lastOrderTime = TimeCurrent();
         g_activeTicket = g_trade.ResultDeal();
         SaveState();
         
         if(InpAntiDetect) g_nextAllowedTime = TimeCurrent() + InpMinDelaySeconds + (MathRand() % (InpMaxDelaySeconds - InpMinDelaySeconds + 1));
         entered = true;
      }
   }
   
   if(signal < 0 && (emaTrend == 999 || emaTrend <= 0) && (InpTradeDir == DIR_BOTH || InpTradeDir == DIR_SELL))
   {
      double pPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double pSL = CalculateSL(POSITION_TYPE_SELL, pPrice);
      if(pSL <= 0 && InpLotMode == LOT_RISK) return false; 
      
      double pTP = CalculateTP(POSITION_TYPE_SELL, pPrice, pSL);
      double pLot = CalculateLotSize(pPrice, pSL);
      
      // BẢO VỆ STOPS_LEVEL CHỐNG LỖI 10016 (Slippage/Gap cực đoan)
      double stopLevelPips = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      double minGap = stopLevelPips + (InpMaxSpread * GetPipPoint()); 
      if (pSL - pPrice < minGap) pSL = NormalizeDouble(pPrice + minGap, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      
      if(g_trade.Sell(pLot, _Symbol, pPrice, pSL, pTP, GetRandomComment()))
      {
         Print("--- SELL. Risk Lot=", pLot, " SL_Mode=", EnumToString(InpSLMode));
         g_initialSL = pSL;
         g_scaleOutDone = false;
         g_currentTrailSL = 0;
         g_ordersOpenedToday++;
         g_lastOrderTime = TimeCurrent();
         g_activeTicket = g_trade.ResultDeal();
         SaveState();
         
         if(InpAntiDetect) g_nextAllowedTime = TimeCurrent() + InpMinDelaySeconds + (MathRand() % (InpMaxDelaySeconds - InpMinDelaySeconds + 1));
         entered = true;
      }
   }
   return entered;
}

void DisplayPanel()
{
   static datetime lastUpdate = 0;
   if(TimeCurrent() - lastUpdate < 3) return;
   lastUpdate = TimeCurrent();
   
   string info = "SingleIchi EA APEX v7.0 Institutional | " + _Symbol + "\n";
   if(InpLotMode == LOT_RISK) info += "Mode: RISK " + DoubleToString(InpRiskPercent, 1) + "%\n";
   else info += "Mode: FIXED " + DoubleToString(InpLots, 2) + " Lots\n";
   
   if(InpMaxConsecutiveLoss > 0) info += "Loss Chain: " + IntegerToString(g_consecutiveLosses) + "/" + IntegerToString(InpMaxConsecutiveLoss) + "\n";
   if(TimeCurrent() < g_cooldownUntil) info += "[COOLDOWN ACTIVE]\n";
   
   Comment(info);
}

void OnTick()
{
   MqlDateTime dt; TimeCurrent(dt);
   if(dt.day != g_lastDay) {
      g_lastDay = dt.day;
      g_ordersOpenedToday = 0;
      g_dailyStartBalance = GetStartOfDayBalance();
      g_consecutiveLosses = 0; 
   }
   
   g_ordersCount = CountAllOrders();
   DisplayPanel();
   if(IsRiskBreached()) return;
   CheckFridayClose();
   
   if(g_ordersCount == 0) {
      UpdateCircuitBreaker(); 
   } else {
      ProcessScaleOut();
   }
   
   if(IsNewBar()) {
      if(InpTrailOnBarClose) ProcessTrailingStop(); 
      g_cachedSignal = GetIchimokuSignal(); 
   }
   
   // Chống trễ tín hiệu do giãn Spread ở đầu nến
   if(g_cachedSignal != 0) {
      if(ProcessNewOrder()) { g_cachedSignal = 0; g_ordersCount = 1; }
   }
   
   if(!InpTrailOnBarClose) ProcessTrailingStop(); 
}

double OnTester()
{
   return (MQLInfoInteger(MQL_TESTER) && TesterStatistics(STAT_EQUITY_DD_RELATIVE) > 0.0001) ? TesterStatistics(STAT_PROFIT) / TesterStatistics(STAT_EQUITY_DD_RELATIVE) : TesterStatistics(STAT_PROFIT);
}
