//+------------------------------------------------------------------+
//|                                     IchiDCA_CCBSN_PropFirm.mq5   |
//|                   DCA Ichimoku Cloud Break - CCBSN - Prop Firm    |
//|                   Version 2.0 - Partial Close + Trailing          |
//+------------------------------------------------------------------+
#property copyright "IchiDCA CCBSN PropFirm EA v2.0"
#property link      ""
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Semi-Auto Mode (Dashboard manual buttons)
input bool InpSemiAutoMode = false; // Chế độ Semi-Auto (bật nút Buy/Sell/Close trên Dashboard)
bool g_btnBuyClicked      = false;
bool g_btnSellClicked     = false;
bool g_btnCloseAllClicked = false;

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_TRADE_DIR
{
   DIR_BOTH = 0,   // Buy & Sell
   DIR_BUY  = 1,   // Chỉ Buy
   DIR_SELL = 2    // Chỉ Sell
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
// === Cơ bản ===
input int      InpMagicID           = 9196;       // Magic Number
input double   InpLots              = 0.01;       // Lot Size
input ENUM_TRADE_DIR InpTradeDir    = DIR_BOTH;   // Hướng trade

// === Ichimoku ===
input int      InpIchiTenkan        = 9;          // Ichimoku Tenkan-sen
input int      InpIchiKijun         = 26;         // Ichimoku Kijun-sen
input int      InpIchiSenkou        = 52;         // Ichimoku Senkou Span B

// === EMA Trend Filter ===
input bool     InpUseEMAFilter      = true;       // Dùng EMA Filter
input ENUM_TIMEFRAMES InpTFEMAFilter = PERIOD_CURRENT; // Timeframe EMA Filter
input int      InpEMAFast           = 34;         // EMA nhanh (xu hướng)
input int      InpEMASlow           = 89;         // EMA chậm (xu hướng)

// === MACD Trend Filter ===
input bool     InpUseMACDFilter     = false;      // Dùng MACD Filter
input ENUM_TIMEFRAMES InpTFMACDFilter = PERIOD_CURRENT; // Timeframe MACD Filter
input int      InpFastEMAMACD       = 30;         // MACD Fast EMA
input int      InpSlowEMAMACD       = 50;         // MACD Slow EMA
input int      InpSMAMACD           = 5;          // MACD Signal SMA
input ENUM_APPLIED_PRICE InpAppliedPriceMACD = PRICE_WEIGHTED; // MACD Applied Price

// === DCA ===
input bool     InpUseDCA            = true;       // Bật DCA
input double   InpDCADistance       = 10.0;       // Khoảng cách DCA (pips)
input double   InpDCADistMulti      = 1.2;        // Hệ số nhân khoảng cách DCA
input int      InpMaxDCAOrders      = 5;          // Số lệnh DCA tối đa
input double   InpDCALotMulti       = 1.0;        // Hệ số nhân lot DCA (1.0 = lot cố định)
input double   InpDCATPPips         = 50.0;       // TP chuỗi DCA (pips)
input bool     InpDCANeedSignal     = true;       // DCA phải cùng trend Ichimoku
input bool     InpDCAOutTime        = true;       // Cho DCA ngoài giờ trade

// === Sniper (Tỉa lệnh) ===
input bool     InpUseSniper         = true;       // Bật Sniper tỉa lệnh
input int      InpOrders2StartSniper = 20;        // Số lệnh kích hoạt Sniper
input int      InpFirstOrdersSniper = 2;          // Số lệnh đầu chuỗi để tỉa
input double   InpPercentSniper     = 10.0;       // % profit tối thiểu để tỉa
input double   InpTPSniper          = 5.0;        // TP pips sau khi tỉa

// === Quản lý rủi ro (tất cả qua input, không hardcode) ===
input double   InpMaxSpread         = 3.0;        // Max Spread (pips)
input double   InpMaxDrawdownMoney  = 0.0;        // Max DD tiền ($, 0=tắt)
input double   InpMaxDrawdownPct    = 0.0;        // Max DD % (0=tắt)
input double   InpDailyLossLimit    = 0.0;        // Giới hạn lỗ ngày ($, 0=tắt)
input double   InpDailyProfitTarget = 0.0;        // Mục tiêu lời ngày ($, 0=tắt)
input double   InpTPPips            = 10.0;       // TP lệnh đơn (pips)
input double   InpSLPips            = 0.0;        // SL lệnh đơn (pips, 0=không SL)

// === Equity Trailing ===
input bool     InpUseEquityTrail    = false;      // Bật Equity Trailing
input double   InpEquityTrailStart  = 15.0;       // Equity trail kích hoạt ($)
input double   InpEquityTrailStep   = 5.0;        // Equity trail step ($)

// === CCBSN: Chốt Cắt Bán Sớm Nửa + Gồng Trailing ===
input bool     InpUsePartialClose   = true;       // Bật chốt nửa (CCBSN)
input double   InpPartialPercent    = 50.0;       // % lot chốt (50 = nửa)
input bool     InpMoveSLToBE        = true;        // Move SL breakeven sau chốt
input double   InpBEOffsetPips      = 1.0;         // Offset BE (pips, >0 = lock lời)

// === Trailing cho phần còn lại ===
input bool     InpUseTrailing       = true;        // Bật Trailing phần còn lại
input double   InpTrailStartPips    = 10.0;        // Pips profit kích hoạt trail
input double   InpTrailStepPips     = 5.0;         // Trailing step (pips)
input bool     InpUseATRTrail       = false;       // Dùng ATR thay pips cố định
input ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_M15; // TF cho ATR
input int      InpATRPeriod         = 14;          // ATR Period
input double   InpATRMultiplier     = 1.5;         // ATR × multiplier = trail dist

// === Anti-Detect (Prop Firm) ===
input bool     InpAntiDetect        = true;       // Bật Anti-Detect
input int      InpMinDelaySeconds   = 3;          // Delay tối thiểu (giây)
input int      InpMaxDelaySeconds   = 15;         // Delay tối đa (giây)
input int      InpMaxOrdersPerDay   = 10;         // Max lệnh mở mới/ngày
input int      InpDelayAfterClose   = 60;         // Delay sau khi đóng chuỗi (giây)

// === Thời gian trade ===
input bool     InpUseTradingTime    = false;      // Giới hạn thời gian trade
input string   InpStartTime         = "08:00";    // Giờ bắt đầu
input string   InpEndTime           = "22:00";    // Giờ kết thúc
input bool     InpCloseFriday       = false;      // Đóng hết vào thứ 6
input int      InpCloseFridayHour   = 20;         // Giờ đóng thứ 6

// === Rollover Filter ===
input int      InpFilterStartHour   = 1;          // Giờ bắt đầu trade (server)
input int      InpFilterEndHour     = 23;         // Giờ kết thúc trade (server)

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_posInfo;

// Indicator handles  
int            g_handleIchi   = INVALID_HANDLE;
int            g_handleEMAF   = INVALID_HANDLE;
int            g_handleEMAS   = INVALID_HANDLE;
int            g_handleMACD   = INVALID_HANDLE;

// State
datetime       g_lastOrderTime     = 0;
datetime       g_lastCloseTime     = 0;
int            g_ordersOpenedToday  = 0;
int            g_lastDay            = -1;
double         g_dailyStartBalance  = 0;
double         g_maxEquity          = 0;
datetime       g_nextAllowedTime    = 0;
datetime       g_lastBarTime        = 0;  // New bar detection
int            g_cachedSignal       = 0;  // Cache signal per bar

// CCBSN State
int            g_handleATR          = INVALID_HANDLE;
bool           g_buyPartialDone     = false;   // Đã chốt nửa Buy
bool           g_sellPartialDone    = false;   // Đã chốt nửa Sell
double         g_buyTrailSL         = 0;       // SL trailing Buy
double         g_sellTrailSL        = 0;       // SL trailing Sell
double         g_buyAvgAfterPartial = 0;       // Giá avg sau partial close
double         g_sellAvgAfterPartial = 0;      // Giá avg sau partial close

// Anti-detect: comment pool
string         g_comments[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Trade setup
   g_trade.SetExpertMagicNumber(InpMagicID);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   // Ichimoku
   g_handleIchi = iIchimoku(_Symbol, PERIOD_M5, InpIchiTenkan, InpIchiKijun, InpIchiSenkou);
   if(g_handleIchi == INVALID_HANDLE)
   {
      Print("FATAL: Failed to create Ichimoku indicator!");
      return INIT_FAILED;
   }
   
   // ATR for CCBSN trailing
   if(InpUseATRTrail)
   {
      g_handleATR = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
      if(g_handleATR == INVALID_HANDLE)
      {
         Print("WARNING: Failed to create ATR indicator! Using fixed trail.");
      }
   }
   
   // EMA Filter (dùng TF riêng)
   if(InpUseEMAFilter)
   {
      ENUM_TIMEFRAMES emaTF = (InpTFEMAFilter == PERIOD_CURRENT) ? PERIOD_M5 : InpTFEMAFilter;
      g_handleEMAF = iMA(_Symbol, emaTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
      g_handleEMAS = iMA(_Symbol, emaTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
      if(g_handleEMAF == INVALID_HANDLE || g_handleEMAS == INVALID_HANDLE)
      {
         Print("FATAL: Failed to create EMA indicators!");
         return INIT_FAILED;
      }
   }
   
   // MACD Filter (dùng TF riêng)
   if(InpUseMACDFilter)
   {
      ENUM_TIMEFRAMES macdTF = (InpTFMACDFilter == PERIOD_CURRENT) ? PERIOD_M5 : InpTFMACDFilter;
      g_handleMACD = iMACD(_Symbol, macdTF, InpFastEMAMACD, InpSlowEMAMACD, InpSMAMACD, InpAppliedPriceMACD);
      if(g_handleMACD == INVALID_HANDLE)
      {
         Print("FATAL: Failed to create MACD indicator!");
         return INIT_FAILED;
      }
   }
   
   // Init comment pool for anti-detect
   InitCommentPool();
   
   // Reset daily counters
   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   MqlDateTime dt;
   TimeCurrent(dt);
   g_lastDay = dt.day;
   g_ordersOpenedToday = 0;
   
   Print("===========================================");
   Print("IchiDCA CCBSN PropFirm EA v2.0 initialized");
   Print("Symbol: ", _Symbol, " | Magic: ", InpMagicID);
   Print("Lots: ", InpLots, " | DCA Max: ", InpMaxDCAOrders);
   Print("CCBSN: ", InpUsePartialClose ? "ON" : "OFF", " | Partial: ", InpPartialPercent, "%");
   Print("Trailing: ", InpUseTrailing ? "ON" : "OFF", " | ATR: ", InpUseATRTrail ? "ON" : "OFF");
   Print("Anti-Detect: ", InpAntiDetect ? "ON" : "OFF");
   Print("===========================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_handleIchi != INVALID_HANDLE) IndicatorRelease(g_handleIchi);
   if(g_handleEMAF != INVALID_HANDLE) IndicatorRelease(g_handleEMAF);
   if(g_handleEMAS != INVALID_HANDLE) IndicatorRelease(g_handleEMAS);
   if(g_handleMACD != INVALID_HANDLE) IndicatorRelease(g_handleMACD);
   if(g_handleATR  != INVALID_HANDLE) IndicatorRelease(g_handleATR);
   
   Print("IchiDCA CCBSN PropFirm EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Initialize random comment pool                                   |
//+------------------------------------------------------------------+
void InitCommentPool()
{
   ArrayResize(g_comments, 12);
   g_comments[0]  = "manual trade";
   g_comments[1]  = "scalp entry";
   g_comments[2]  = "trend follow";
   g_comments[3]  = "breakout";
   g_comments[4]  = "pullback";
   g_comments[5]  = "retest";
   g_comments[6]  = "momentum";
   g_comments[7]  = "swing";
   g_comments[8]  = "position";
   g_comments[9]  = "dip buy";
   g_comments[10] = "rally sell";
   g_comments[11] = "range trade";
}

//+------------------------------------------------------------------+
//| Get random comment (anti-detect)                                 |
//+------------------------------------------------------------------+
string GetRandomComment()
{
   if(!InpAntiDetect) return "IchiDCA";
   int idx = MathRand() % ArraySize(g_comments);
   return g_comments[idx];
}

//+------------------------------------------------------------------+
//| Get point value adjusted for broker digits                       |
//| Forex 4-digit: 1 pip = 0.0001 (_Point)                          |
//| Forex 5-digit: 1 pip = 0.0001 (_Point*10)                       |
//| XAUUSD 2-digit: 1 pip = 0.1 (_Point*10)                         |
//| XAUUSD 3-digit: 1 pip = 0.1 (_Point*100)                        |
//+------------------------------------------------------------------+
double GetPipPoint()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Detect metals/gold (typically 2 or 3 digits)
   if(digits <= 3)
   {
      // XAUUSD, XAGUSD, etc. - 1 pip = 0.1
      if(digits == 2) return 0.1;    // 2850.00 -> pip = 0.1
      if(digits == 3) return 0.1;    // 2850.000 -> pip = 0.1
      if(digits == 1) return 1.0;    // JPY pairs or similar
   }
   
   // Forex pairs (4 or 5 digits)
   if(digits == 5) return _Point * 10;  // 1.12345 -> pip = 0.0001
   if(digits == 4) return _Point;       // 1.1234 -> pip = 0.0001
   
   return _Point;
}

//+------------------------------------------------------------------+
//| Get current spread in pips                                       |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (ask - bid) / GetPipPoint();
}

//+------------------------------------------------------------------+
//| Normalize lot size                                               |
//+------------------------------------------------------------------+
double NormLots(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   lots = MathRound(lots / step) * step;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count orders by type (our magic only)                            |
//+------------------------------------------------------------------+
int CountOrders(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         if(g_posInfo.PositionType() == type) count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count all our orders                                             |
//+------------------------------------------------------------------+
int CountAllOrders()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get floating profit of our orders                                |
//+------------------------------------------------------------------+
double GetFloatingProfit(ENUM_POSITION_TYPE type = -1)
{
   double total = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         if(type != -1 && g_posInfo.PositionType() != type) continue;
         total += g_posInfo.Profit() + g_posInfo.Swap() + g_posInfo.Commission();
      }
   }
   return total;
}

//+------------------------------------------------------------------+
//| Get average entry price of orders                                |
//+------------------------------------------------------------------+
double GetAveragePrice(ENUM_POSITION_TYPE type)
{
   double totalLots = 0;
   double totalValue = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         if(g_posInfo.PositionType() != type) continue;
         
         totalLots += g_posInfo.Volume();
         totalValue += g_posInfo.PriceOpen() * g_posInfo.Volume();
      }
   }
   
   if(totalLots > 0) return totalValue / totalLots;
   return 0;
}

//+------------------------------------------------------------------+
//| Get last entry price                                             |
//+------------------------------------------------------------------+
double GetLastEntryPrice(ENUM_POSITION_TYPE type)
{
   datetime lastTime = 0;
   double lastPrice = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         if(g_posInfo.PositionType() != type) continue;
         
         if(g_posInfo.Time() > lastTime)
         {
            lastTime = g_posInfo.Time();
            lastPrice = g_posInfo.PriceOpen();
         }
      }
   }
   return lastPrice;
}

//+------------------------------------------------------------------+
//| Close all orders of a type                                       |
//+------------------------------------------------------------------+
void CloseAllByType(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         if(g_posInfo.PositionType() != type) continue;
         
         g_trade.PositionClose(g_posInfo.Ticket());
      }
   }
   g_lastCloseTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Close ALL orders                                                 |
//+------------------------------------------------------------------+
void CloseAllOrders()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         
         g_trade.PositionClose(g_posInfo.Ticket());
      }
   }
   g_lastCloseTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| CCBSN: Get ATR-based trail distance in price                     |
//+------------------------------------------------------------------+
double GetATRTrailDistance()
{
   if(!InpUseATRTrail || g_handleATR == INVALID_HANDLE)
      return InpTrailStepPips * GetPipPoint(); // fallback to fixed
   
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_handleATR, 0, 0, 2, atr) < 2)
      return InpTrailStepPips * GetPipPoint(); // fallback
   
   return atr[1] * InpATRMultiplier;
}

//+------------------------------------------------------------------+
//| CCBSN: Partial close X% lot of each position in a chain          |
//+------------------------------------------------------------------+
void PartialCloseByType(ENUM_POSITION_TYPE type)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int closedCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByIndex(i)) continue;
      if(g_posInfo.Symbol() != _Symbol) continue;
      if(g_posInfo.Magic() != InpMagicID) continue;
      if(g_posInfo.PositionType() != type) continue;
      
      double currentLots = g_posInfo.Volume();
      double closeLots = currentLots * InpPartialPercent / 100.0;
      
      // Round to lot step
      closeLots = MathFloor(closeLots / lotStep) * lotStep;
      closeLots = NormalizeDouble(closeLots, 2);
      
      // Ensure minimum lot remains after close
      if(closeLots < minLot)
      {
         // Lot quá nhỏ, không thể partial close → skip
         Print("CCBSN: Lot too small for partial close. Ticket=", g_posInfo.Ticket(),
               " current=", currentLots, " closeLots=", closeLots);
         continue;
      }
      
      // Ensure remaining lot >= minLot
      double remainLots = currentLots - closeLots;
      if(remainLots < minLot)
      {
         // Adjust: close less so remaining >= minLot
         closeLots = currentLots - minLot;
         closeLots = MathFloor(closeLots / lotStep) * lotStep;
         closeLots = NormalizeDouble(closeLots, 2);
         if(closeLots < minLot) continue; // skip if not possible
      }
      
      ulong ticket = g_posInfo.Ticket();
      if(g_trade.PositionClosePartial(ticket, closeLots))
      {
         closedCount++;
         Print(">>> CCBSN PARTIAL CLOSE: ticket=", ticket, 
               " closed=", closeLots, " remain=", NormalizeDouble(currentLots - closeLots, 2));
      }
      else
      {
         Print("CCBSN PARTIAL CLOSE FAILED: ticket=", ticket,
               " error=", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
      }
   }
   
   if(closedCount > 0)
   {
      // Mark partial close done
      if(type == POSITION_TYPE_BUY)
      {
         g_buyPartialDone = true;
         g_buyAvgAfterPartial = GetAveragePrice(POSITION_TYPE_BUY);
         Print(">>> CCBSN BUY: Partial close done. Avg after=", 
               DoubleToString(g_buyAvgAfterPartial, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
      }
      else
      {
         g_sellPartialDone = true;
         g_sellAvgAfterPartial = GetAveragePrice(POSITION_TYPE_SELL);
         Print(">>> CCBSN SELL: Partial close done. Avg after=", 
               DoubleToString(g_sellAvgAfterPartial, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
      }
      
      // Move SL to breakeven
      if(InpMoveSLToBE)
         MoveSLToBreakeven(type);
   }
}

//+------------------------------------------------------------------+
//| CCBSN: Move SL to breakeven (avg price + offset) for remaining   |
//+------------------------------------------------------------------+
void MoveSLToBreakeven(ENUM_POSITION_TYPE type)
{
   double pip = GetPipPoint();
   double avgPrice = (type == POSITION_TYPE_BUY) ? g_buyAvgAfterPartial : g_sellAvgAfterPartial;
   if(avgPrice <= 0) avgPrice = GetAveragePrice(type);
   
   double newSL;
   if(type == POSITION_TYPE_BUY)
      newSL = avgPrice + InpBEOffsetPips * pip; // SL trên avg = lock lời nhẹ
   else
      newSL = avgPrice - InpBEOffsetPips * pip; // SL dưới avg = lock lời nhẹ
   
   newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_posInfo.SelectByIndex(i)) continue;
      if(g_posInfo.Symbol() != _Symbol) continue;
      if(g_posInfo.Magic() != InpMagicID) continue;
      if(g_posInfo.PositionType() != type) continue;
      
      double currentSL = g_posInfo.StopLoss();
      double currentTP = g_posInfo.TakeProfit();
      
      // Chỉ move SL nếu SL mới tốt hơn (gần giá hơn = bảo vệ tốt hơn)
      bool shouldModify = false;
      if(type == POSITION_TYPE_BUY)
         shouldModify = (currentSL < newSL || currentSL == 0);
      else
         shouldModify = (currentSL > newSL || currentSL == 0);
      
      if(shouldModify)
      {
         if(g_trade.PositionModify(g_posInfo.Ticket(), newSL, 0)) // TP=0 để trailing quản lý
         {
            Print(">>> CCBSN BE: ticket=", g_posInfo.Ticket(), " SL=", DoubleToString(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
         }
         else
         {
            Print("CCBSN BE FAILED: ticket=", g_posInfo.Ticket(),
                  " error=", g_trade.ResultRetcode(), " - ", g_trade.ResultRetcodeDescription());
         }
      }
   }
   
   // Initialize trail SL
   if(type == POSITION_TYPE_BUY)
      g_buyTrailSL = newSL;
   else
      g_sellTrailSL = newSL;
}

//+------------------------------------------------------------------+
//| CCBSN: Trailing Stop for remaining positions after partial close  |
//+------------------------------------------------------------------+
void ProcessTrailingStop()
{
   if(!InpUseTrailing) return;
   
   // BẢO VỆ TIN TỨC: Không Trailing nếu Spread > Max Spread cho phép
   if(GetSpreadPips() > InpMaxSpread) {
      Print("Spread too high, disabling trailing stop update.");
      return; 
   }
   
   double pip = GetPipPoint();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double trailDist = GetATRTrailDistance();
   double trailStartDist = InpTrailStartPips * pip;
   
   // === Trailing BUY ===
   if(g_buyPartialDone)
   {
      int buyCount = CountOrders(POSITION_TYPE_BUY);
      if(buyCount == 0)
      {
         // Tất cả lệnh đã đóng (trailing SL hit hoặc manual)
         ResetCCBSNState(POSITION_TYPE_BUY);
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double avgPrice = g_buyAvgAfterPartial;
         double profitDist = bid - avgPrice;
         
         // Kích hoạt trailing khi profit đủ xa
         if(profitDist >= trailStartDist)
         {
            double proposedSL = NormalizeDouble(bid - trailDist, digits);
            
            // Chỉ nâng SL, không hạ
            if(proposedSL > g_buyTrailSL)
            {
               g_buyTrailSL = proposedSL;
               
               // Update SL cho tất cả lệnh Buy
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  if(!g_posInfo.SelectByIndex(i)) continue;
                  if(g_posInfo.Symbol() != _Symbol) continue;
                  if(g_posInfo.Magic() != InpMagicID) continue;
                  if(g_posInfo.PositionType() != POSITION_TYPE_BUY) continue;
                  
                  if(g_posInfo.StopLoss() < proposedSL || g_posInfo.StopLoss() == 0)
                  {
                     g_trade.PositionModify(g_posInfo.Ticket(), proposedSL, 0);
                  }
               }
               
               Print(">>> CCBSN TRAIL BUY: SL=", DoubleToString(proposedSL, digits),
                     " bid=", DoubleToString(bid, digits), " dist=", DoubleToString(trailDist/pip, 1), "p");
            }
         }
      }
   }
   
   // === Trailing SELL ===
   if(g_sellPartialDone)
   {
      int sellCount = CountOrders(POSITION_TYPE_SELL);
      if(sellCount == 0)
      {
         ResetCCBSNState(POSITION_TYPE_SELL);
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double avgPrice = g_sellAvgAfterPartial;
         double profitDist = avgPrice - ask;
         
         if(profitDist >= trailStartDist)
         {
            double proposedSL = NormalizeDouble(ask + trailDist, digits);
            
            // Chỉ hạ SL (cho Sell, SL thấp hơn = tốt hơn)
            if(g_sellTrailSL == 0 || proposedSL < g_sellTrailSL)
            {
               g_sellTrailSL = proposedSL;
               
               for(int i = PositionsTotal() - 1; i >= 0; i--)
               {
                  if(!g_posInfo.SelectByIndex(i)) continue;
                  if(g_posInfo.Symbol() != _Symbol) continue;
                  if(g_posInfo.Magic() != InpMagicID) continue;
                  if(g_posInfo.PositionType() != POSITION_TYPE_SELL) continue;
                  
                  if(g_posInfo.StopLoss() > proposedSL || g_posInfo.StopLoss() == 0)
                  {
                     g_trade.PositionModify(g_posInfo.Ticket(), proposedSL, 0);
                  }
               }
               
               Print(">>> CCBSN TRAIL SELL: SL=", DoubleToString(proposedSL, digits),
                     " ask=", DoubleToString(ask, digits), " dist=", DoubleToString(trailDist/pip, 1), "p");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| CCBSN: Reset state when all positions of a type are closed        |
//+------------------------------------------------------------------+
void ResetCCBSNState(ENUM_POSITION_TYPE type)
{
   if(type == POSITION_TYPE_BUY)
   {
      g_buyPartialDone = false;
      g_buyTrailSL = 0;
      g_buyAvgAfterPartial = 0;
      Print(">>> CCBSN BUY: Chain closed. State reset.");
   }
   else
   {
      g_sellPartialDone = false;
      g_sellTrailSL = 0;
      g_sellAvgAfterPartial = 0;
      Print(">>> CCBSN SELL: Chain closed. State reset.");
   }
   g_lastCloseTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Open order with anti-detect features and Retry Slippage          |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_POSITION_TYPE type, double lots, double tpPips, double slPips, string comment)
{
   lots = NormLots(lots);
   double pip = GetPipPoint();
   double price, tp = 0, sl = 0;
   
   int maxRetries = 3;
   for(int i = 0; i < maxRetries; i++)
   {
      // RefreshRates() removed: MQL4-only function, not needed in MQL5 (SymbolInfoDouble auto-refreshes)
      if(type == POSITION_TYPE_BUY) price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      else price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      if(tpPips > 0) tp = (type == POSITION_TYPE_BUY) ? price + tpPips * pip : price - tpPips * pip;
      if(slPips > 0) sl = (type == POSITION_TYPE_BUY) ? price - slPips * pip : price + slPips * pip;
      
      bool success = (type == POSITION_TYPE_BUY) ? g_trade.Buy(lots, _Symbol, price, sl, tp, comment) : g_trade.Sell(lots, _Symbol, price, sl, tp, comment);
      
      if(success)
      {
         g_lastOrderTime = TimeCurrent();
         g_ordersOpenedToday++;
         
         Print((type == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
            " opened: lots=", lots, " tp=", tpPips, "p sl=", slPips, "p");
         return true;
      }
      
      uint retcode = g_trade.ResultRetcode();
      if(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_CONNECTION || retcode == TRADE_RETCODE_TIMEOUT || retcode == TRADE_RETCODE_PRICE_CHANGED)
      {
         Print("ORDER FAILED. Retrying ", i+1, "/", maxRetries, "...");
         Sleep(150); // Pause before retry
      }
      else break; // Fatal errors (No money, invalid stops) -> don't retry
   }
   return false;
}

//+------------------------------------------------------------------+
//| ICHIMOKU SIGNAL: Cloud Break + Continuation Detection            |
//+------------------------------------------------------------------+
// Returns: +1 = BUY signal, -1 = SELL signal, 0 = no signal
int GetIchimokuSignal()
{
   // Ichimoku buffers:
   // 0 = Tenkan-sen, 1 = Kijun-sen
   // 2 = Senkou Span A, 3 = Senkou Span B
   // 4 = Chikou Span
   
   double tenkan[], kijun[], spanA[], spanB[];
   ArraySetAsSeries(tenkan, true);
   ArraySetAsSeries(kijun, true);
   ArraySetAsSeries(spanA, true);
   ArraySetAsSeries(spanB, true);
   
   if(CopyBuffer(g_handleIchi, 0, 0, 3, tenkan) < 3) return 0;
   if(CopyBuffer(g_handleIchi, 1, 0, 3, kijun)  < 3) return 0;
   if(CopyBuffer(g_handleIchi, 2, 0, 3, spanA)  < 3) return 0;
   if(CopyBuffer(g_handleIchi, 3, 0, 3, spanB)  < 3) return 0;
   
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, PERIOD_M5, 0, 3, close) < 3) return 0;
   
   // Xác định mây (cloud) - mây trên và mây dưới
   double cloudTop1 = MathMax(spanA[1], spanB[1]);
   double cloudBot1 = MathMin(spanA[1], spanB[1]);
   double cloudTop2 = MathMax(spanA[2], spanB[2]);
   double cloudBot2 = MathMin(spanA[2], spanB[2]);
   
   // === BUY SIGNAL ===
   // Nến trước trong/dưới mây → nến hiện tại đóng TRÊN mây
   // + Tenkan > Kijun (uptrend confirmation)
   bool buyBreak = (close[2] <= cloudTop2) && (close[1] > cloudTop1);
   bool buyTrend = (tenkan[1] > kijun[1]);
   
   if(buyBreak && buyTrend) return +1;
   
   // === SELL SIGNAL ===
   // Nến trước trong/trên mây → nến hiện tại đóng DƯỚI mây
   // + Tenkan < Kijun (downtrend confirmation)
   bool sellBreak = (close[2] >= cloudBot2) && (close[1] < cloudBot1);
   bool sellTrend = (tenkan[1] < kijun[1]);
   
   if(sellBreak && sellTrend) return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check Ichimoku trend (for DCA filter)                            |
//| Returns: +1 = uptrend, -1 = downtrend, 0 = no clear trend       |
//+------------------------------------------------------------------+
int GetIchimokuTrend()
{
   double spanA[], spanB[], close[];
   ArraySetAsSeries(spanA, true);
   ArraySetAsSeries(spanB, true);
   ArraySetAsSeries(close, true);
   
   if(CopyBuffer(g_handleIchi, 2, 0, 2, spanA) < 2) return 0;
   if(CopyBuffer(g_handleIchi, 3, 0, 2, spanB) < 2) return 0;
   if(CopyClose(_Symbol, PERIOD_M5, 0, 2, close) < 2) return 0;
   
   double cloudTop = MathMax(spanA[1], spanB[1]);
   double cloudBot = MathMin(spanA[1], spanB[1]);
   
   if(close[1] > cloudTop) return +1;  // Trên mây = uptrend
   if(close[1] < cloudBot) return -1;  // Dưới mây = downtrend
   return 0;                           // Trong mây = sideway
}

//+------------------------------------------------------------------+
//| EMA TREND FILTER                                                 |
//| Returns: +1 = uptrend, -1 = downtrend, 0 = no filter/neutral    |
//+------------------------------------------------------------------+
int GetEMATrend()
{
   if(!InpUseEMAFilter) return 0; // Bypass
   
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   
   if(CopyBuffer(g_handleEMAF, 0, 0, 2, emaFast) < 2) return 0;
   if(CopyBuffer(g_handleEMAS, 0, 0, 2, emaSlow) < 2) return 0;
   
   if(emaFast[1] > emaSlow[1]) return +1;
   if(emaFast[1] < emaSlow[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| MACD TREND FILTER                                                |
//| Returns: +1 = bullish, -1 = bearish, 0 = neutral/off            |
//+------------------------------------------------------------------+
int GetMACDTrend()
{
   if(!InpUseMACDFilter) return 0; // Bypass
   if(g_handleMACD == INVALID_HANDLE) return 0;
   
   double macdMain[], macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   
   if(CopyBuffer(g_handleMACD, 0, 0, 2, macdMain) < 2) return 0;
   if(CopyBuffer(g_handleMACD, 1, 0, 2, macdSignal) < 2) return 0;
   
   // MACD > Signal = bullish, MACD < Signal = bearish
   if(macdMain[1] > macdSignal[1]) return +1;
   if(macdMain[1] < macdSignal[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| CHECK SPREAD                                                     |
//+------------------------------------------------------------------+
bool IsSpreadOK()
{
   return (GetSpreadPips() <= InpMaxSpread);
}

//+------------------------------------------------------------------+
//| CHECK TRADING TIME                                               |
//+------------------------------------------------------------------+
bool IsTradingTimeOK()
{
   // Rollover filter
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour < InpFilterStartHour || dt.hour > InpFilterEndHour)
      return false;
   
   // Custom time window
   if(!InpUseTradingTime) return true;
   
   string currentTime = StringFormat("%02d:%02d", dt.hour, dt.min);
   return (currentTime >= InpStartTime && currentTime <= InpEndTime);
}

//+------------------------------------------------------------------+
//| ANTI-DETECT: Check if we can open new order                      |
//+------------------------------------------------------------------+
bool CanOpenNewOrder()
{
   if(!InpAntiDetect) return true;
   
   // Daily order limit
   if(g_ordersOpenedToday >= InpMaxOrdersPerDay)
   {
      return false;
   }
   
   // Random delay between orders
   if(TimeCurrent() < g_nextAllowedTime)
   {
      return false;
   }
   
   // Delay after closing chain
   if(g_lastCloseTime > 0 && (TimeCurrent() - g_lastCloseTime) < InpDelayAfterClose)
   {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| ANTI-DETECT: Set random delay for next order                     |
//+------------------------------------------------------------------+
void SetRandomDelay()
{
   if(!InpAntiDetect) return;
   int delay = InpMinDelaySeconds + (MathRand() % (InpMaxDelaySeconds - InpMinDelaySeconds + 1));
   g_nextAllowedTime = TimeCurrent() + delay;
}

//+------------------------------------------------------------------+
//| CHECK DAILY COUNTERS & RESET                                     |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day != g_lastDay)
   {
      g_lastDay = dt.day;
      g_ordersOpenedToday = 0;
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("NEW DAY: Reset counters. Balance start: $", DoubleToString(g_dailyStartBalance, 2));
   }
}

//+------------------------------------------------------------------+
//| CHECK RISK: Daily loss & Max drawdown                            |
//| Returns true if trading should STOP                              |
//+------------------------------------------------------------------+
bool IsRiskBreached()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Daily loss limit
   if(InpDailyLossLimit > 0)
   {
      double dailyPnL = equity - g_dailyStartBalance;
      if(dailyPnL <= -InpDailyLossLimit)
      {
         Print("!!! DAILY LOSS LIMIT REACHED: $", DoubleToString(-dailyPnL, 2), " >= $", DoubleToString(InpDailyLossLimit, 2));
         return true;
      }
   }
   
   // Max drawdown (money)
   if(InpMaxDrawdownMoney > 0)
   {
      double dd = balance - equity;
      if(dd >= InpMaxDrawdownMoney)
      {
         Print("!!! MAX DD MONEY: $", DoubleToString(dd, 2), " >= $", DoubleToString(InpMaxDrawdownMoney, 2), " -> CUT ALL");
         CloseAllOrders();
         return true;
      }
   }
   
   // Max drawdown (percent)
   if(InpMaxDrawdownPct > 0 && balance > 0)
   {
      double ddPct = (balance - equity) / balance * 100.0;
      if(ddPct >= InpMaxDrawdownPct)
      {
         Print("!!! MAX DD %: ", DoubleToString(ddPct, 2), "% >= ", DoubleToString(InpMaxDrawdownPct, 2), "% -> CUT ALL");
         CloseAllOrders();
         return true;
      }
   }
   
   // Daily profit target
   if(InpDailyProfitTarget > 0)
   {
      double dailyPnL = equity - g_dailyStartBalance;
      if(dailyPnL >= InpDailyProfitTarget)
      {
         Print("DAILY PROFIT TARGET REACHED: $", DoubleToString(dailyPnL, 2));
         return true; // Stop trading, don't close (keep profitable positions)
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| EQUITY TRAILING                                                  |
//+------------------------------------------------------------------+
void ProcessEquityTrailing()
{
   if(!InpUseEquityTrail) return;
   
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Kích hoạt khi lời đủ
   if(equity >= balance + InpEquityTrailStart)
   {
      if(g_maxEquity == 0 || equity > g_maxEquity)
         g_maxEquity = equity;
   }
   
   // Chốt khi tụt lùi
   if(g_maxEquity > 0)
   {
      if(equity <= g_maxEquity - InpEquityTrailStep)
      {
         Print(">>> EQUITY TRAILING: Max=", DoubleToString(g_maxEquity, 2), " Now=", DoubleToString(equity, 2));
         CloseAllOrders();
         g_maxEquity = 0;
      }
      
      if(CountAllOrders() == 0) g_maxEquity = 0;
   }
}

//+------------------------------------------------------------------+
//| CHECK DCA TP: Close chain or trigger CCBSN partial close         |
//+------------------------------------------------------------------+
void CheckDCATP()
{
   if(InpDCATPPips <= 0) return;
   double pip = GetPipPoint();
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Check BUY chain (chỉ khi chưa partial close)
   int buyCount = CountOrders(POSITION_TYPE_BUY);
   if(buyCount > 0 && !g_buyPartialDone)
   {
      double avgPrice = GetAveragePrice(POSITION_TYPE_BUY);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double profitPips = (bid - avgPrice) / pip;
      
      double tpTarget = (buyCount > 1) ? InpDCATPPips : InpTPPips;
      if(tpTarget <= 0) tpTarget = InpDCATPPips;
      
      if(profitPips >= tpTarget)
      {
         Print(">>> TP BUY: orders=", buyCount, " avg=", DoubleToString(avgPrice, digits),
               " bid=", DoubleToString(bid, digits),
               " profit=", DoubleToString(profitPips, 1), "p target=", DoubleToString(tpTarget, 1));
         
         // CCBSN: partial close thay vì close all
         if(InpUsePartialClose)
         {
            Print(">>> CCBSN: Partial close BUY ", InpPartialPercent, "% + Trailing");
            PartialCloseByType(POSITION_TYPE_BUY);
         }
         else
         {
            CloseAllByType(POSITION_TYPE_BUY);
         }
         SetRandomDelay();
      }
   }
   
   // Check SELL chain (chỉ khi chưa partial close)
   int sellCount = CountOrders(POSITION_TYPE_SELL);
   if(sellCount > 0 && !g_sellPartialDone)
   {
      double avgPrice = GetAveragePrice(POSITION_TYPE_SELL);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (avgPrice - ask) / pip;
      
      double tpTarget = (sellCount > 1) ? InpDCATPPips : InpTPPips;
      if(tpTarget <= 0) tpTarget = InpDCATPPips;
      
      if(profitPips >= tpTarget)
      {
         Print(">>> TP SELL: orders=", sellCount, " avg=", DoubleToString(avgPrice, digits),
               " ask=", DoubleToString(ask, digits),
               " profit=", DoubleToString(profitPips, 1), "p target=", DoubleToString(tpTarget, 1));
         
         if(InpUsePartialClose)
         {
            Print(">>> CCBSN: Partial close SELL ", InpPartialPercent, "% + Trailing");
            PartialCloseByType(POSITION_TYPE_SELL);
         }
         else
         {
            CloseAllByType(POSITION_TYPE_SELL);
         }
         SetRandomDelay();
      }
   }
}

//+------------------------------------------------------------------+
//| PROCESS DCA: Add to position when conditions met                 |
//+------------------------------------------------------------------+
void ProcessDCA()
{
   if(!InpUseDCA) return;
   

   // CCBSN: Khong DCA khi dang trailing sau partial close

   if(g_buyPartialDone || g_sellPartialDone) return;

   if(!IsSpreadOK()) return;
   if(!CanOpenNewOrder()) return;
   
   // Check giờ trade (cho phép DCA ngoài giờ nếu InpDCAOutTime=true)
   if(!InpDCAOutTime && !IsTradingTimeOK()) return;
   
   double pip = GetPipPoint();
   
   // DCA BUY
   int buyCount = CountOrders(POSITION_TYPE_BUY);
   if(buyCount > 0 && buyCount < InpMaxDCAOrders + 1) // +1 vì lệnh đầu không tính DCA
   {
      if(InpTradeDir != DIR_SELL) // Không DCA buy nếu chỉ cho sell
      {
         // Check DCA cùng trend (Ichimoku + EMA)
         bool dcaBuyOK = true;
         if(InpDCANeedSignal)
         {
            int trend = GetIchimokuTrend();
            if(trend != +1) dcaBuyOK = false;
            // Dừng DCA khi EMA đảo chiều
            int emaTrend = GetEMATrend();
            if(emaTrend == -1) dcaBuyOK = false;
         }
         
         if(dcaBuyOK)
         {
            double lastPrice = GetLastEntryPrice(POSITION_TYPE_BUY);
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            
            // Tính khoảng cách DCA (tăng dần theo hệ số)
            double distance = InpDCADistance;
            for(int i = 1; i < buyCount; i++)
               distance *= InpDCADistMulti;
            
            // Giá đi xuống đủ xa so với lệnh cuối -> DCA
            if(lastPrice - ask >= distance * pip)
            {
               double dcaLots = InpLots;
               // Tính lot DCA (nếu có multiplier)
               for(int i = 0; i < buyCount; i++)
                  dcaLots *= InpDCALotMulti;
               
               string comment = GetRandomComment();
               Print(">>> DCA BUY #", buyCount + 1, " lots=", NormLots(dcaLots), " dist=", DoubleToString(distance, 1));
               PlaceOrder(POSITION_TYPE_BUY, dcaLots, 0, InpSLPips, comment); // TP=0 vì dùng TP chuỗi
               SetRandomDelay();
            }
         }
      }
   }
   
   // DCA SELL
   int sellCount = CountOrders(POSITION_TYPE_SELL);
   if(sellCount > 0 && sellCount < InpMaxDCAOrders + 1)
   {
      if(InpTradeDir != DIR_BUY) // Không DCA sell nếu chỉ cho buy
      {
         // Check DCA cùng trend (Ichimoku + EMA)
         bool dcaSellOK = true;
         if(InpDCANeedSignal)
         {
            int trend = GetIchimokuTrend();
            if(trend != -1) dcaSellOK = false;
            // Dừng DCA khi EMA đảo chiều
            int emaTrend = GetEMATrend();
            if(emaTrend == +1) dcaSellOK = false;
         }
         if(!dcaSellOK) return;
         
         double lastPrice = GetLastEntryPrice(POSITION_TYPE_SELL);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         double distance = InpDCADistance;
         for(int i = 1; i < sellCount; i++)
            distance *= InpDCADistMulti;
         
         // Giá đi lên đủ xa so với lệnh cuối -> DCA
         if(bid - lastPrice >= distance * pip)
         {
            double dcaLots = InpLots;
            for(int i = 0; i < sellCount; i++)
               dcaLots *= InpDCALotMulti;
            
            string comment = GetRandomComment();
            Print(">>> DCA SELL #", sellCount + 1, " lots=", NormLots(dcaLots), " dist=", DoubleToString(distance, 1));
            PlaceOrder(POSITION_TYPE_SELL, dcaLots, 0, InpSLPips, comment);
            SetRandomDelay();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PROCESS FIRST ORDER (NEW ENTRY)                                  |
//+------------------------------------------------------------------+
void ProcessFirstOrder()
{
   int buyCount  = CountOrders(POSITION_TYPE_BUY);
   int sellCount = CountOrders(POSITION_TYPE_SELL);
   
   // Chỉ mở lệnh mới khi chưa có chuỗi nào
   if(buyCount > 0 || sellCount > 0) return;
   
   // Debug log mỗi 60 giây
   static datetime lastDebug = 0;
   bool doDebug = (TimeCurrent() - lastDebug >= 60);
   
   // Kiểm tra điều kiện
   if(!IsSpreadOK())
   {
      if(doDebug) { Print("DEBUG: Spread blocked. Current=", DoubleToString(GetSpreadPips(),1), " Max=", InpMaxSpread); lastDebug=TimeCurrent(); }
      return;
   }
   if(!IsTradingTimeOK())
   {
      if(doDebug) { Print("DEBUG: Trading time blocked."); lastDebug=TimeCurrent(); }
      return;
   }
   if(!CanOpenNewOrder())
   {
      if(doDebug) { Print("DEBUG: CanOpenNewOrder blocked. OrdersToday=", g_ordersOpenedToday); lastDebug=TimeCurrent(); }
      return;
   }
   if(IsRiskBreached()) return;
   
   // Lấy tín hiệu Ichimoku (đã cache từ bar open)
   int signal = g_cachedSignal;
   if(signal == 0)
   {
      if(doDebug) { Print("DEBUG: No Ichimoku signal."); lastDebug=TimeCurrent(); }
      return;
   }
   
   // Kiểm tra EMA trend filter
   int emaTrend = GetEMATrend();
   
   // Kiểm tra MACD trend filter
   int macdTrend = GetMACDTrend();
   
   // BUY: signal > 0 && EMA uptrend (hoặc bypass) && MACD bullish (hoặc bypass)
   if(signal > 0 && (emaTrend >= 0) && (macdTrend >= 0))
   {
      if(InpTradeDir == DIR_BOTH || InpTradeDir == DIR_BUY)
      {
         double tp = InpTPPips;
         // Nếu dùng DCA, lệnh đầu không có TP riêng (chờ TP chuỗi)
         if(InpUseDCA) tp = 0;
         
         string comment = GetRandomComment();
         Print(">>> SIGNAL BUY: Ichimoku Cloud Break Up + EMA OK");
         PlaceOrder(POSITION_TYPE_BUY, InpLots, tp, InpSLPips, comment);
         SetRandomDelay();
      }
   }
   
   // SELL: signal < 0 && EMA downtrend (hoặc bypass) && MACD bearish (hoặc bypass)
   if(signal < 0 && (emaTrend <= 0) && (macdTrend <= 0))
   {
      if(InpTradeDir == DIR_BOTH || InpTradeDir == DIR_SELL)
      {
         double tp = InpTPPips;
         if(InpUseDCA) tp = 0;
         
         string comment = GetRandomComment();
         Print(">>> SIGNAL SELL: Ichimoku Cloud Break Down + EMA OK");
         PlaceOrder(POSITION_TYPE_SELL, InpLots, tp, InpSLPips, comment);
         SetRandomDelay();
      }
   }
}

//+------------------------------------------------------------------+
//| PROCESS SNIPER: Tỉa lệnh đầu chuỗi khi DCA quá nhiều           |
//+------------------------------------------------------------------+
void ProcessSniper()
{
   if(!InpUseSniper) return;
   
   // Check BUY chain
   int buyCount = CountOrders(POSITION_TYPE_BUY);
   if(buyCount >= InpOrders2StartSniper)
      SniperForType(POSITION_TYPE_BUY, buyCount);
   
   // Check SELL chain
   int sellCount = CountOrders(POSITION_TYPE_SELL);
   if(sellCount >= InpOrders2StartSniper)
      SniperForType(POSITION_TYPE_SELL, sellCount);
}

//+------------------------------------------------------------------+
//| Sniper: Tỉa N lệnh đầu (lỗ nặng nhất) của 1 loại              |
//+------------------------------------------------------------------+
void SniperForType(ENUM_POSITION_TYPE type, int totalOrders)
{
   // Tính tổng floating profit của chuỗi
   double floatingProfit = GetFloatingProfit(type);
   
   // Chỉ tỉa khi tổng floating profit đủ điều kiện
   // Ví dụ: floating = -100$, cần >= 10% → cần floating >= -90$ (giảm lỗ 10%)
   // Logic: đóng lệnh lỗ nặng nhất khi giá hồi đủ %
   if(floatingProfit >= 0) return; // Chuỗi đang lời → không cần tỉa
   
   // Thu thập thông tin lệnh
   struct OrderInfo
   {
      ulong ticket;
      double profit;
      datetime openTime;
   };
   
   OrderInfo orders[];
   ArrayResize(orders, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol) continue;
         if(g_posInfo.Magic() != InpMagicID) continue;
         if(g_posInfo.PositionType() != type) continue;
         
         int size = ArraySize(orders);
         ArrayResize(orders, size + 1);
         orders[size].ticket = g_posInfo.Ticket();
         orders[size].profit = g_posInfo.Profit() + g_posInfo.Swap() + g_posInfo.Commission();
         orders[size].openTime = g_posInfo.Time();
      }
   }
   
   if(ArraySize(orders) < InpOrders2StartSniper) return;
   
   // Sort by openTime (lệnh cũ nhất trước) - bubble sort đơn giản
   for(int i = 0; i < ArraySize(orders) - 1; i++)
   {
      for(int j = i + 1; j < ArraySize(orders); j++)
      {
         if(orders[j].openTime < orders[i].openTime)
         {
            OrderInfo temp = orders[i];
            orders[i] = orders[j];
            orders[j] = temp;
         }
      }
   }
   
   // Kiểm tra: tổng profit của N lệnh đầu cần tỉa
   double firstOrdersProfit = 0;
   int trimCount = MathMin(InpFirstOrdersSniper, ArraySize(orders));
   for(int i = 0; i < trimCount; i++)
      firstOrdersProfit += orders[i].profit;
   
   // Tổng profit còn lại (sau khi tỉa)
   double remainProfit = floatingProfit - firstOrdersProfit;
   
   // Điều kiện: phần còn lại phải >= InpPercentSniper% so với floating hiện tại
   // Nghĩa là sau khi tỉa, lỗ phải giảm đi đáng kể
   double threshold = MathAbs(floatingProfit) * InpPercentSniper / 100.0;
   
   if(MathAbs(firstOrdersProfit) <= threshold)
   {
      // Đóng các lệnh đầu
      for(int i = 0; i < trimCount; i++)
      {
         g_trade.PositionClose(orders[i].ticket);
         Print(">>> SNIPER: Closed ticket ", orders[i].ticket, " profit=", 
               DoubleToString(orders[i].profit, 2));
      }
      
      Print(">>> SNIPER: Trimmed ", trimCount, " orders. Old float=", 
            DoubleToString(floatingProfit, 2), " Est remain=", DoubleToString(remainProfit, 2));
   }
}

//+------------------------------------------------------------------+
//| DISPLAY PANEL                                                    |
//+------------------------------------------------------------------+
void DisplayPanel()
{
   static datetime lastUpdate = 0;
   if(TimeCurrent() - lastUpdate < 3) return;
   lastUpdate = TimeCurrent();
   
   int buyN  = CountOrders(POSITION_TYPE_BUY);
   int sellN = CountOrders(POSITION_TYPE_SELL);
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   string info = "";
   info += "IchiDCA CCBSN v2.0 | " + _Symbol + "\n";
   info += "Magic: " + IntegerToString(InpMagicID) + " | Spread: " + DoubleToString(GetSpreadPips(), 1) + "p\n";
   info += "Buy: " + IntegerToString(buyN) + " | Sell: " + IntegerToString(sellN) + "\n";
   info += "Float: $" + DoubleToString(GetFloatingProfit(), 2) + "\n";
   info += "Orders today: " + IntegerToString(g_ordersOpenedToday) + "/" + IntegerToString(InpMaxOrdersPerDay) + "\n";
   
   if(buyN > 1)
      info += "BUY avg: " + DoubleToString(GetAveragePrice(POSITION_TYPE_BUY), digits) + "\n";
   if(sellN > 1)
      info += "SELL avg: " + DoubleToString(GetAveragePrice(POSITION_TYPE_SELL), digits) + "\n";
   
   // CCBSN Status
   if(g_buyPartialDone)
      info += "[CCBSN BUY] Trail SL: " + DoubleToString(g_buyTrailSL, digits) + "\n";
   if(g_sellPartialDone)
      info += "[CCBSN SELL] Trail SL: " + DoubleToString(g_sellTrailSL, digits) + "\n";
   
   if(!IsTradingTimeOK()) info += "[OUT OF TIME]\n";
   if(InpAntiDetect) info += "[STEALTH MODE]\n";
   
   Comment(info);
}

//+------------------------------------------------------------------+
//| CHECK FRIDAY CLOSE                                               |
//+------------------------------------------------------------------+
void CheckFridayClose()
{
   if(!InpCloseFriday) return;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_week == 5 && dt.hour >= InpCloseFridayHour)
   {
      if(CountAllOrders() > 0)
      {
         Print("FRIDAY EXIT: Closing all positions before weekend.");
         CloseAllOrders();
      }
   }
}

//+------------------------------------------------------------------+
//| Check if new M5 bar has formed                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
   if(barTime == 0) return false;
   
   if(barTime != g_lastBarTime)
   {
      g_lastBarTime = barTime;
      return true;
   }
   return false;
}

// Global Cache for OnTick
int g_cacheBuyCount = 0;
int g_cacheSellCount = 0;
double g_cacheBuyProfit = 0;
double g_cacheSellProfit = 0;

void CachePositions()
{
   g_cacheBuyCount = 0;
   g_cacheSellCount = 0;
   g_cacheBuyProfit = 0;
   g_cacheSellProfit = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Symbol() != _Symbol || g_posInfo.Magic() != InpMagicID) continue;
         
         double profit = g_posInfo.Profit() + g_posInfo.Swap() + g_posInfo.Commission();
         if(g_posInfo.PositionType() == POSITION_TYPE_BUY) {
            g_cacheBuyCount++;
            g_cacheBuyProfit += profit;
         } else if(g_posInfo.PositionType() == POSITION_TYPE_SELL) {
            g_cacheSellCount++;
            g_cacheSellProfit += profit;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manual Dashboard overrides
   if(InpSemiAutoMode)
   {
      if(g_btnBuyClicked) {
         PlaceOrder(POSITION_TYPE_BUY, InpLots, InpTPPips, InpSLPips, "Manual BUY Dashboard");
         g_btnBuyClicked = false;
      }
      if(g_btnSellClicked) {
         PlaceOrder(POSITION_TYPE_SELL, InpLots, InpTPPips, InpSLPips, "Manual SELL Dashboard");
         g_btnSellClicked = false;
      }
      if(g_btnCloseAllClicked) {
         CloseAllOrders();
         g_btnCloseAllClicked = false;
      }
   }

   // Panel (throttled internally)
   DisplayPanel();
   
   // 1. CACHE POSITIONS ONCE PER TICK
   CachePositions();
   
   // Daily reset
   CheckDailyReset();
   
   // === MỖI TICK: Risk & TP (phản ứng nhanh) ===
   
   // Risk check (closes all if breached)
   if(IsRiskBreached()) return;
   
   // Equity Trailing (cần check mỗi tick)
   ProcessEquityTrailing();
   
   // Friday close
   CheckFridayClose();
   
   // DCA TP check (đóng chuỗi ngay khi đạt target hoặc CCBSN partial close)
   CheckDCATP();
   
   // CCBSN: Trailing Stop cho phần còn lại (cần check mỗi tick)
   ProcessTrailingStop();
   
   // CCBSN: Reset state nếu tất cả lệnh đã đóng
   if(g_buyPartialDone && g_cacheBuyCount == 0) ResetCCBSNState(POSITION_TYPE_BUY);
   if(g_sellPartialDone && g_cacheSellCount == 0) ResetCCBSNState(POSITION_TYPE_SELL);
   
   // === CHỈ KHI NẾN MỚI: Signal, DCA, Sniper ===
   if(!IsNewBar()) return;
   
   // Cache signal cho bar này
   g_cachedSignal = GetIchimokuSignal();
   
   // Sniper: tỉa lệnh khi chuỗi quá dài
   ProcessSniper();
   
   // DCA: thêm lệnh vào chuỗi hiện có
   ProcessDCA();
   
   // Mở lệnh mới (chỉ khi không có chuỗi nào đang chạy)
   ProcessFirstOrder();
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
{
   if(!MQLInfoInteger(MQL_TESTER)) return 0;
   
   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   
   if(dd > 0.0001) return profit / dd;
   return profit;
}
//+------------------------------------------------------------------+
