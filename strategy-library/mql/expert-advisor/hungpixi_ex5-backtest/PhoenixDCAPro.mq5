//+------------------------------------------------------------------+
//|                                              PhoenixDCAPro.mq5   |
//|                          Copyright 2026, hungpixi (comarai.com)  |
//|                                   Telegram: hungpixi             |
//|                                   Phone: +84834422439            |
//+------------------------------------------------------------------+
#property copyright   "hungpixi | comarai.com"
#property link        "https://t.me/hungpixi"
#property version     "1.00"
#property description "Phoenix DCA Pro — Nadaraya-Watson Wave Rider"
#property description "DCA x2 Martingale + NW Kernel Regression Envelope"
#property description "Author: hungpixi | Tele: hungpixi | +84834422439"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_ENTRY_SIGNAL
{
   SIGNAL_NONE          = 0,  // Không điều kiện (Vào lệnh luôn)
   SIGNAL_CANDLES       = 1,  // Xanh đỏ (Liên tiếp nến cùng màu)
   SIGNAL_RANDOM        = 2,  // Random
   SIGNAL_MOMENTUM      = 3,  // Momentum
   SIGNAL_RSI           = 4,  // RSI Thuận
   SIGNAL_RSI_REV       = 5,  // RSI Reversal
   SIGNAL_MACD          = 6,  // MACD
   SIGNAL_CCI           = 7,  // CCI Thuận
   SIGNAL_CCI_REV       = 8,  // CCI Reversal
   SIGNAL_STOCH         = 9,  // Stochastic Thuận
   SIGNAL_STOCH_REV     = 10, // Stochastic Reversal
   SIGNAL_BB            = 11, // Bollinger Bands (Bounce)
   SIGNAL_PINBAR        = 12, // Pinbar
   SIGNAL_SUPERTREND    = 13, // Supertrend
   SIGNAL_UTBOT         = 14, // UT Bot Alerts
   SIGNAL_BREAK_KUMO    = 15, // Break Kumo Ichimoku
   SIGNAL_SMC_SWING     = 16, // SMC Swing Thuận
   SIGNAL_SMC_SWING_REV = 17, // SMC Swing Ngược
   SIGNAL_SMC_ALL       = 18, // SMC All Thuận
   SIGNAL_INDI_NGAOI    = 19, // Indi Ngoài (Custom Buffer)
   SIGNAL_NW            = 20, // Nadaraya-Watson
   SIGNAL_CONFLUENCE    = 21, // Confluence (Multi-Signal)
};

enum ENUM_NW_DIRECTION
{
   NW_BULLISH  = 1,
   NW_BEARISH  = -1,
   NW_NEUTRAL  = 0
};

enum ENUM_PRICE_ZONE
{
   ZONE_UPPER    = 1,   // Quá mua — gần Upper Band
   ZONE_LOWER    = -1,  // Quá bán — gần Lower Band
   ZONE_MIDDLE   = 0    // Vùng neutral
};

//+------------------------------------------------------------------+
//| INPUTS — Nhóm 0: Nadaraya-Watson                                |
//+------------------------------------------------------------------+
input group "=== NADARAYA-WATSON ENGINE ==="
input int        InpNW_Lookback     = 500;       // NW Lookback (số nến)
input double     InpNW_Bandwidth    = 8.0;       // NW Bandwidth h (nhỏ=nhạy, lớn=mượt)
input int        InpATR_Period      = 14;        // ATR Period cho Envelope
input double     InpATR_Multiplier  = 2.0;       // ATR Multiplier (rộng/hẹp band)
input int        InpNW_SlopeShift   = 5;         // Slope Shift (bars)
input double     InpNW_SlopeThresh  = 0.5;       // Slope Threshold (> = trend)
input bool       InpNW_NonRepaint   = true;      // Non-Repainting Mode

//+------------------------------------------------------------------+
//| INPUTS — Nhóm 1: DCA & Volume                                   |
//+------------------------------------------------------------------+
input group "=== DCA x2 MARTINGALE ==="
input double     InpStartLot        = 0.01;      // Lot khởi đầu
input double     InpLotMultiplier   = 2.0;       // Hệ số nhân Lot (x2 to die)
input int        InpDCAStep         = 200;       // Khoảng cách DCA (Points)
input int        InpMaxOrders       = 10;        // Số lệnh DCA tối đa
input int        InpTakeProfit      = 100;       // TP từ giá trung bình (Points)
input bool       InpUseTrailing     = true;      // Sử dụng Trailing Stop
input int        InpTrailingStart   = 50;        // Trailing bắt đầu khi lãi (Points)
input int        InpTrailingStep    = 20;        // Trailing Step (Points)

//+------------------------------------------------------------------+
//| INPUTS — Nhóm 2: Signal                                         |
//+------------------------------------------------------------------+
input group "=== SIGNAL GENERATOR ==="
input ENUM_ENTRY_SIGNAL InpEntrySignal = SIGNAL_NW; // Tín hiệu mở lệnh
input ENUM_TIMEFRAMES   InpSignalTF    = PERIOD_M15;     // Timeframe tín hiệu
input int        InpMinSignalScore  = 60;        // Score tối thiểu để entry (0-100)
input int        InpCooldownBars    = 5;         // Cooldown bars giữa 2 grid
input int        InpMaxSpread       = 500;       // Max Spread cho phép (Points)
input bool       InpNW_BlockNeutral = true;      // Block signal khi NW Neutral
input int        InpRSI_Period      = 14;        // RSI Period
input int        InpRSI_OB         = 70;        // RSI Overbought
input int        InpRSI_OS         = 30;        // RSI Oversold
input int        InpMACD_Fast       = 12;        // MACD Fast
input int        InpMACD_Slow       = 26;        // MACD Slow
input int        InpMACD_Signal     = 9;         // MACD Signal
input int        InpCCI_Period      = 14;        // CCI Period
input int        InpStoch_K         = 14;        // Stochastic %K
input int        InpStoch_D         = 3;         // Stochastic %D
input int        InpStoch_Slowing   = 3;         // Stochastic Slowing
input int        InpPinbar_WickRatio = 200;      // Pinbar wick/body ratio (%) 
input int        InpSMC_FractalBars  = 2;        // SMC Fractal bars mỗi bên

//+------------------------------------------------------------------+
//| INPUTS — Nhóm 3: Time & EMA Filter                              |
//+------------------------------------------------------------------+
input group "=== FILTERS ==="
input bool       InpUseTimeFilter   = false;     // Lọc theo giờ
input int        InpStartHour       = 0;         // Giờ bắt đầu trade
input int        InpEndHour         = 23;        // Giờ kết thúc trade
input bool       InpUseEMAFilter    = false;     // Bộ lọc EMA
input ENUM_TIMEFRAMES InpEMA_TF     = PERIOD_CURRENT; // Timeframe EMA
input int        InpEMA1            = 34;        // EMA Fast
input int        InpEMA2            = 89;        // EMA Slow
input int        InpEMA_MaxDist     = 500;       // Max distance to EMA (Points)

//+------------------------------------------------------------------+
//| INPUTS — Nhóm 4: Risk Management                                |
//+------------------------------------------------------------------+
input group "=== RISK MANAGEMENT ==="
input int        InpMagicNumber     = 202604;    // Magic Number
input double     InpMaxDD_Percent   = 50.0;      // Max Drawdown % (0=off)
input bool       InpNW_SmartDCA     = true;      // Smart DCA (dừng khi NW đổi chiều)
input bool       InpCloseOnBandHit  = false;     // Đóng grid khi chạm band đối diện

//+------------------------------------------------------------------+
//| INPUTS — Nhóm 5: GUI                                            |
//+------------------------------------------------------------------+
input group "=== GUI DASHBOARD ==="
input bool       InpShowDashboard   = true;      // Hiển thị Dashboard
input bool       InpDrawNWEnvelope  = true;      // Vẽ NW Envelope lên chart
input color      InpNW_LineColor    = clrGold;   // Màu đường NW
input color      InpUpperBandColor  = clrTomato;  // Màu Upper Band
input color      InpLowerBandColor  = clrLimeGreen; // Màu Lower Band
input int        InpNW_LineWidth    = 2;         // Độ dày đường NW

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;

// NW Buffers
double   g_nwLine[];        // NW regression line
double   g_nwUpper[];       // Upper envelope
double   g_nwLower[];       // Lower envelope
double   g_atrBuffer[];     // ATR values

// State
ENUM_NW_DIRECTION g_waveDirection = NW_NEUTRAL;
ENUM_PRICE_ZONE   g_priceZone     = ZONE_MIDDLE;
double   g_nwSlope          = 0;
double   g_averagePrice     = 0;
int      g_buyCount         = 0;
int      g_sellCount        = 0;
double   g_floatingPnL      = 0;
double   g_maxEquity        = 0;
double   g_currentDD        = 0;

// Signal Scoring & Cooldown
int      g_lastSignalScore  = 0;         // Score của signal gần nhất
datetime g_lastGridCloseTime = 0;        // Thời điểm đóng grid gần nhất
int      g_barsSinceClose   = 999;       // Bars kể từ lần đóng grid cuối
int      g_confluenceScore  = 0;         // Tổng confluence score

// Indicator handles
int      g_hATR             = INVALID_HANDLE;
int      g_hRSI             = INVALID_HANDLE;
int      g_hMACD            = INVALID_HANDLE;
int      g_hCCI             = INVALID_HANDLE;
int      g_hStoch           = INVALID_HANDLE;
int      g_hBB              = INVALID_HANDLE;
int      g_hMom             = INVALID_HANDLE;
int      g_hIchimoku        = INVALID_HANDLE;
int      g_hEMA1            = INVALID_HANDLE;
int      g_hEMA2            = INVALID_HANDLE;

// GUI object names
string   g_panelPrefix      = "PhxDCA_";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
      trade.SetTypeFilling(ORDER_FILLING_FOK);

   // Tối ưu hóa: Block các parameters quá dị gây Out of Memory hoặc O(N^2) loops trong Strategy Tester
   if(MQLInfoInteger(MQL_OPTIMIZATION))
   {
      if(InpNW_Lookback < 50 || InpNW_Lookback > 3000) return INIT_PARAMETERS_INCORRECT;
      if(InpATR_Period < 1 || InpATR_Period > 200) return INIT_PARAMETERS_INCORRECT;
   }

   // Khởi tạo ATR handle
   g_hATR = iATR(_Symbol, InpSignalTF, InpATR_Period);
   if(g_hATR == INVALID_HANDLE)
   {
      Print("❌ Lỗi tạo ATR handle");
      return INIT_FAILED;
   }

   // Khởi tạo Handles cho Indicators
   g_hRSI   = iRSI(_Symbol, InpSignalTF, 14, PRICE_CLOSE);
   g_hMACD  = iMACD(_Symbol, InpSignalTF, 12, 26, 9, PRICE_CLOSE);
   g_hCCI   = iCCI(_Symbol, InpSignalTF, 14, PRICE_TYPICAL);
   g_hStoch = iStochastic(_Symbol, InpSignalTF, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_hBB    = iBands(_Symbol, InpSignalTF, 20, 0, 2.0, PRICE_CLOSE);
   g_hMom   = iMomentum(_Symbol, InpSignalTF, 14, PRICE_CLOSE);
   g_hIchimoku = iIchimoku(_Symbol, InpSignalTF, 9, 26, 52);

   // EMA filter handles
   if(InpUseEMAFilter)
   {
      g_hEMA1 = iMA(_Symbol, InpEMA_TF, InpEMA1, 0, MODE_EMA, PRICE_CLOSE);
      g_hEMA2 = iMA(_Symbol, InpEMA_TF, InpEMA2, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hEMA1 == INVALID_HANDLE || g_hEMA2 == INVALID_HANDLE) return INIT_FAILED;
   }

   // Cấp phát bộ nhớ NW buffers
   int size = InpNW_Lookback + 10;
   ArrayResize(g_nwLine,  size);
   ArrayResize(g_nwUpper, size);
   ArrayResize(g_nwLower, size);
   ArrayResize(g_atrBuffer, size);
   ArraySetAsSeries(g_nwLine,  true);
   ArraySetAsSeries(g_nwUpper, true);
   ArraySetAsSeries(g_nwLower, true);
   ArraySetAsSeries(g_atrBuffer, true);

   g_maxEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Vẽ Dashboard ban đầu (Bỏ qua nếu đang Optimization để tránh leak memory do UI objects)
   if(InpShowDashboard && !MQLInfoInteger(MQL_OPTIMIZATION)) 
      CreateDashboard();

   Print("✅ Phoenix DCA Pro v1.00 — hungpixi — Initialized on ", _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Xóa indicator handles
   if(g_hATR   != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hRSI   != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hMACD  != INVALID_HANDLE) IndicatorRelease(g_hMACD);
   if(g_hCCI   != INVALID_HANDLE) IndicatorRelease(g_hCCI);
   if(g_hStoch != INVALID_HANDLE) IndicatorRelease(g_hStoch);
   if(g_hBB    != INVALID_HANDLE) IndicatorRelease(g_hBB);
   if(g_hMom   != INVALID_HANDLE) IndicatorRelease(g_hMom);
   if(g_hIchimoku != INVALID_HANDLE) IndicatorRelease(g_hIchimoku);
   if(g_hEMA1  != INVALID_HANDLE) IndicatorRelease(g_hEMA1);
   if(g_hEMA2  != INVALID_HANDLE) IndicatorRelease(g_hEMA2);

   // Xóa GUI objects
   DeleteDashboard();
   if(InpDrawNWEnvelope) DeleteNWEnvelopeObjects();

   Print("🔴 Phoenix DCA Pro — Deinitialized");
}

//+------------------------------------------------------------------+
//| MODULE 0: NADARAYA-WATSON KERNEL REGRESSION                     |
//+------------------------------------------------------------------+

//--- Gaussian Kernel Function
double GaussianKernel(double u)
{
   return MathExp(-0.5 * u * u);
}

//--- Tính Nadaraya-Watson Regression Line
bool CalcNadarayaWatson()
{
   int bars = MathMin(InpNW_Lookback, iBars(_Symbol, InpSignalTF) - 1);
   if(bars < 50) return false;

   // Lấy ATR values
   if(CopyBuffer(g_hATR, 0, 0, bars, g_atrBuffer) < bars) return false;

   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, InpSignalTF, 0, bars, closeArr) < bars) return false;

   // Tính NW Line cho mỗi bar
   for(int i = 0; i < bars; i++)
   {
      double sumWeightedPrice = 0;
      double sumWeights       = 0;

      // Non-repainting: chỉ dùng data từ bar i trở về quá khứ
      // Repainting: dùng cả data tương lai (cho visual)
      int startJ = 0;
      int endJ   = InpNW_NonRepaint ? bars - 1 : bars - 1;

      for(int j = startJ; j < bars; j++)
      {
         // Non-repaint: chỉ dùng bars j >= i (quá khứ so với bar i)
         if(InpNW_NonRepaint && j < i) continue;

         double u = (double)(i - j) / InpNW_Bandwidth;
         double w = GaussianKernel(u);

         sumWeightedPrice += w * closeArr[j];
         sumWeights       += w;
      }

      if(sumWeights > 0)
         g_nwLine[i] = sumWeightedPrice / sumWeights;
      else
         g_nwLine[i] = closeArr[i];

      // Envelope Bands = NW ± ATR × Multiplier
      double atr = (i < ArraySize(g_atrBuffer)) ? g_atrBuffer[i] : 0;
      g_nwUpper[i] = g_nwLine[i] + atr * InpATR_Multiplier;
      g_nwLower[i] = g_nwLine[i] - atr * InpATR_Multiplier;
   }

   return true;
}

//--- Phân tích hướng sóng (Wave Direction)
ENUM_NW_DIRECTION GetWaveDirection()
{
   if(ArraySize(g_nwLine) < InpNW_SlopeShift + 1) return NW_NEUTRAL;

   // Tính slope = (NW hiện tại - NW trước đó) / shift
   g_nwSlope = (g_nwLine[0] - g_nwLine[InpNW_SlopeShift]) / InpNW_SlopeShift;

   // Chuẩn hóa slope theo point size
   double normalizedSlope = g_nwSlope / _Point;

   if(normalizedSlope > InpNW_SlopeThresh)
      return NW_BULLISH;
   else if(normalizedSlope < -InpNW_SlopeThresh)
      return NW_BEARISH;
   else
      return NW_NEUTRAL;
}

//--- Xác định vùng giá (Price Zone)
ENUM_PRICE_ZONE GetPriceZone()
{
   double close = iClose(_Symbol, InpSignalTF, 0);

   if(close >= g_nwUpper[0])
      return ZONE_UPPER;   // Quá mua
   else if(close <= g_nwLower[0])
      return ZONE_LOWER;   // Quá bán
   else
      return ZONE_MIDDLE;  // Vùng neutral
}

//+------------------------------------------------------------------+
//| MODULE 1: SIGNAL GENERATOR (Optimized v2)                       |
//| - Bar[1] confirmation (không dùng bar chưa đóng)                |
//| - Signal Strength Scoring 0-100                                 |
//| - Spread Filter, Cooldown, NW Neutral Block                    |
//| - Confluence Multi-Signal Scoring                               |
//+------------------------------------------------------------------+

//--- Score NW thuần: bounce từ band + cross NW line (dùng bar[1]+bar[2])
int ScoreNW_Only()
{
   double close1 = iClose(_Symbol, InpSignalTF, 1);
   double close2 = iClose(_Symbol, InpSignalTF, 2);
   double low2   = iLow(_Symbol, InpSignalTF, 2);
   double high2  = iHigh(_Symbol, InpSignalTF, 2);

   // BUY: giá bounce từ Lower Band
   if(low2 <= g_nwLower[2] && close1 > g_nwLower[1])
   {
      double penetration = (g_nwLower[2] - low2) / (g_nwUpper[2] - g_nwLower[2] + _Point);
      return MathMin(100, (int)(60 + penetration * 400));
   }

   // SELL: giá reject từ Upper Band
   if(high2 >= g_nwUpper[2] && close1 < g_nwUpper[1])
   {
      double penetration = (high2 - g_nwUpper[2]) / (g_nwUpper[2] - g_nwLower[2] + _Point);
      return -((int)MathMin(100, (int)(60 + penetration * 400)));
   }

   // BUY: giá cross lên qua NW Line (weaker signal)
   if(close2 < g_nwLine[2] && close1 > g_nwLine[1])
   {
      return 65; // Đủ để qua mức lọc cơ bản (60)
   }

   // SELL: giá cross xuống qua NW Line (weaker signal)
   if(close2 > g_nwLine[2] && close1 < g_nwLine[1])
   {
      return -65;
   }

   // [DIAGNOSTIC] Log current line state to verify why it's not crossing
   if (MQLInfoInteger(MQL_TESTER))
   {
      PrintFormat("🔍 NW_State: C2=%.2f NW2=%.2f | C1=%.2f NW1=%.2f", close2, g_nwLine[2], close1, g_nwLine[1]);
   }

   return 0;
}

//--- Score Xanh Đỏ (3 nến liên tiếp cùng màu)
int ScoreCandles()
{
   double open[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   if(CopyOpen(_Symbol, InpSignalTF, 1, 3, open) < 3) return 0;
   if(CopyClose(_Symbol, InpSignalTF, 1, 3, close) < 3) return 0;

   bool buy = true;
   bool sell = true;
   for(int i = 0; i < 3; i++)
   {
      if(close[i] <= open[i]) buy = false;
      if(close[i] >= open[i]) sell = false;
   }
   if(buy) return 65;
   if(sell) return -65;
   return 0;
}

//--- Score Momentum (Crossover mốc 100)
int ScoreMomentum()
{
   double mom[];
   ArraySetAsSeries(mom, true);
   if(CopyBuffer(g_hMom, 0, 0, 3, mom) < 3) return 0;

   if(mom[2] < 100.0 && mom[1] > 100.0) return 65;
   if(mom[2] > 100.0 && mom[1] < 100.0) return -65;
   return 0;
}

//--- Score BB (Bounce từ band)
int ScoreBB()
{
   double upper[], lower[], close[], lowArr[], highArr[];
   ArraySetAsSeries(upper, true); ArraySetAsSeries(lower, true);
   ArraySetAsSeries(close, true); ArraySetAsSeries(lowArr, true); ArraySetAsSeries(highArr, true);
   
   if(CopyBuffer(g_hBB, 1, 0, 3, upper) < 3) return 0;
   if(CopyBuffer(g_hBB, 2, 0, 3, lower) < 3) return 0;
   if(CopyClose(_Symbol, InpSignalTF, 0, 3, close) < 3) return 0;
   if(CopyLow(_Symbol, InpSignalTF, 0, 3, lowArr) < 3) return 0;
   if(CopyHigh(_Symbol, InpSignalTF, 0, 3, highArr) < 3) return 0;

   if(lowArr[2] <= lower[2] && close[1] > lower[1]) return 65;
   if(highArr[2] >= upper[2] && close[1] < upper[1]) return -65;
   return 0;
}

//--- Score Break Kumo Ichimoku
int ScoreBreakKumo()
{
   double senkouA[], senkouB[], close[];
   ArraySetAsSeries(senkouA, true); ArraySetAsSeries(senkouB, true); ArraySetAsSeries(close, true);
   
   if(CopyBuffer(g_hIchimoku, 2, 0, 3, senkouA) < 3) return 0; // Span A
   if(CopyBuffer(g_hIchimoku, 3, 0, 3, senkouB) < 3) return 0; // Span B
   if(CopyClose(_Symbol, InpSignalTF, 0, 3, close) < 3) return 0;

   double kumoMax2 = MathMax(senkouA[2], senkouB[2]);
   double kumoMax1 = MathMax(senkouA[1], senkouB[1]);
   double kumoMin2 = MathMin(senkouA[2], senkouB[2]);
   double kumoMin1 = MathMin(senkouA[1], senkouB[1]);

   // Break lên
   if(close[2] < kumoMax2 && close[1] > kumoMax1) return 65;
   // Break xuống
   if(close[2] > kumoMin2 && close[1] < kumoMin1) return -65;
   return 0;
}

//--- Score RSI (dùng bar[1] confirmed)
int ScoreRSI()
{
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_hRSI, 0, 0, 4, rsi) < 4) return 0;

   // BUY: RSI thoát oversold (dùng bar[1]+bar[2] confirmed)
   if(rsi[2] < InpRSI_OS && rsi[1] > InpRSI_OS)
   {
      // Score thêm mạnh khi RSI càng thấp trước đó
      int depth = (int)((InpRSI_OS - rsi[2]) * 2);
      return MathMin(100, 55 + depth);
   }

   // SELL: RSI thoát overbought
   if(rsi[2] > InpRSI_OB && rsi[1] < InpRSI_OB)
   {
      int depth = (int)((rsi[2] - InpRSI_OB) * 2);
      return -((int)MathMin(100, 55 + depth));
   }

   // RSI divergence bonus (giá tạo low mới nhưng RSI không)
   double low1 = iLow(_Symbol, InpSignalTF, 1);
   double low3 = iLow(_Symbol, InpSignalTF, 3);
   if(low1 < low3 && rsi[1] > rsi[3] && rsi[1] < 40)
      return 40; // Hidden bullish divergence

   double high1 = iHigh(_Symbol, InpSignalTF, 1);
   double high3 = iHigh(_Symbol, InpSignalTF, 3);
   if(high1 > high3 && rsi[1] < rsi[3] && rsi[1] > 60)
      return -40; // Hidden bearish divergence

   return 0;
}

//--- Score MACD (bar[1] confirmed + histogram strength)
int ScoreMACD()
{
   double macdMain[], macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   if(CopyBuffer(g_hMACD, 0, 0, 4, macdMain) < 4) return 0;
   if(CopyBuffer(g_hMACD, 1, 0, 4, macdSignal) < 4) return 0;

   // BUY: MACD cross lên Signal ở bar[2]→bar[1] (confirmed)
   if(macdMain[2] < macdSignal[2] && macdMain[1] > macdSignal[1])
   {
      // Score dựa trên momentum (histogram gap)
      double gap = MathAbs(macdMain[1] - macdSignal[1]) / _Point;
      int score = MathMin(100, 50 + (int)(gap * 0.5));
      // Bonus khi cross từ dưới zero
      if(macdMain[1] < 0) score = MathMin(100, score + 15);
      return score;
   }

   // SELL: MACD cross xuống Signal
   if(macdMain[2] > macdSignal[2] && macdMain[1] < macdSignal[1])
   {
      double gap = MathAbs(macdMain[1] - macdSignal[1]) / _Point;
      int score = MathMin(100, 50 + (int)(gap * 0.5));
      if(macdMain[1] > 0) score = MathMin(100, score + 15);
      return -score;
   }

   return 0;
}

//--- Score CCI (bar[1] confirmed)
int ScoreCCI()
{
   double cci[];
   ArraySetAsSeries(cci, true);
   if(CopyBuffer(g_hCCI, 0, 0, 4, cci) < 4) return 0;

   // BUY: CCI cross lên -100 (bar[2]→bar[1])
   if(cci[2] < -100 && cci[1] > -100)
   {
      int depth = (int)(MathAbs(cci[2] + 100) * 0.3);
      return MathMin(100, 55 + depth);
   }

   // SELL: CCI cross xuống +100 (bar[2]→bar[1])
   if(cci[2] > 100 && cci[1] < 100)
   {
      int depth = (int)(MathAbs(cci[2] - 100) * 0.3);
      return -MathMin(100, 55 + depth);
   }

   // CCI extreme bounce bonus
   if(cci[2] < -200 && cci[1] > cci[2]) return 35;
   if(cci[2] > 200 && cci[1] < cci[2]) return -35;

   return 0;
}

//--- Score Stochastic (FIX: check zone TRƯỚC cross, bar[2]→bar[1])
int ScoreStoch()
{
   double stochK[], stochD[];
   ArraySetAsSeries(stochK, true);
   ArraySetAsSeries(stochD, true);
   if(CopyBuffer(g_hStoch, 0, 0, 4, stochK) < 4) return 0;
   if(CopyBuffer(g_hStoch, 1, 0, 4, stochD) < 4) return 0;

   // BUY: %K cross lên %D, zone TRƯỚC cross phải oversold
   if(stochK[2] < stochD[2] && stochK[1] > stochD[1] && stochK[2] < 20)
   {
      int depth = (int)((20 - stochK[2]) * 3);
      return MathMin(100, 55 + depth);
   }

   // SELL: %K cross xuống %D, zone TRƯỚC cross phải overbought
   if(stochK[2] > stochD[2] && stochK[1] < stochD[1] && stochK[2] > 80)
   {
      int depth = (int)((stochK[2] - 80) * 3);
      return -((int)MathMin(100, 55 + depth));
   }

   return 0;
}

//--- Score Pinbar (bar[1] confirmed + NW Zone context)
int ScorePinbar()
{
   double o1 = iOpen(_Symbol, InpSignalTF, 1);
   double h1 = iHigh(_Symbol, InpSignalTF, 1);
   double l1 = iLow(_Symbol, InpSignalTF, 1);
   double c1 = iClose(_Symbol, InpSignalTF, 1);

   double body   = MathAbs(c1 - o1);
   double range  = h1 - l1;
   if(range <= 0 || body <= 0) return 0;

   double upperWick = h1 - MathMax(o1, c1);
   double lowerWick = MathMin(o1, c1) - l1;
   double wickRatio = InpPinbar_WickRatio / 100.0; // default 2.0

   // Body phải nhỏ hơn 1/3 range (pinbar thực sự)
   if(body > range * 0.35) return 0;

   // Bullish Pinbar
   if(lowerWick >= wickRatio * body && upperWick < body)
   {
      int score = MathMin(100, 50 + (int)((lowerWick / body - wickRatio) * 20));
      // Zone bonus: +25 nếu ở Lower Band
      if(g_priceZone == ZONE_LOWER) score = MathMin(100, score + 25);
      return score;
   }

   // Bearish Pinbar
   if(upperWick >= wickRatio * body && lowerWick < body)
   {
      int score = MathMin(100, 50 + (int)((upperWick / body - wickRatio) * 20));
      if(g_priceZone == ZONE_UPPER) score = MathMin(100, score + 25);
      return -score;
   }

   return 0;
}

//--- Score SMC Swing (5-bar fractal + Break of Structure)
int ScoreSMCSwing()
{
   int n = InpSMC_FractalBars; // Bars mỗi bên (default 2 → 5-bar fractal)
   int pivotBar = n + 1; // bar[n+1] là trung tâm fractal (đã confirmed)

   // Kiểm tra cần đủ bars
   if(iBars(_Symbol, InpSignalTF) < pivotBar + n + 2) return 0;

   double pivotHigh = iHigh(_Symbol, InpSignalTF, pivotBar);
   double pivotLow  = iLow(_Symbol, InpSignalTF, pivotBar);

   bool isSwingHigh = true;
   bool isSwingLow  = true;

   // Check n bars mỗi bên
   for(int i = 1; i <= n; i++)
   {
      // Bên trái (xa hơn trong quá khứ)
      if(iHigh(_Symbol, InpSignalTF, pivotBar + i) >= pivotHigh) isSwingHigh = false;
      if(iLow(_Symbol, InpSignalTF, pivotBar + i) <= pivotLow)   isSwingLow = false;

      // Bên phải (gần hiện tại hơn)
      if(iHigh(_Symbol, InpSignalTF, pivotBar - i) >= pivotHigh) isSwingHigh = false;
      if(iLow(_Symbol, InpSignalTF, pivotBar - i) <= pivotLow)   isSwingLow = false;
   }

   double close1 = iClose(_Symbol, InpSignalTF, 1);

   // Swing Low confirmed → BUY signal
   if(isSwingLow)
   {
      // Break of Structure bonus: giá đã vượt qua swing low
      int score = 55;
      if(close1 > pivotLow) score += 15;  // Đã bounce
      if(g_priceZone == ZONE_LOWER) score += 15; // Ở Lower Band
      return MathMin(100, score);
   }

   // Swing High confirmed → SELL signal
   if(isSwingHigh)
   {
      int score = 55;
      if(close1 < pivotHigh) score += 15;
      if(g_priceZone == ZONE_UPPER) score += 15;
      return -((int)MathMin(100, score));
   }

   return 0;
}

//--- Confluence Scoring: tổng hợp nhiều signal weightage
int ScoreConfluence()
{
   int totalScore = 0;
   int signalCount = 0;
   int direction = 0; // +1 = lean BUY, -1 = lean SELL

   // NW Signal (weight: 30%)
   int nwScore = ScoreNW_Only();
   if(nwScore != 0)
   {
      totalScore += (int)(MathAbs(nwScore) * 0.30);
      direction += (nwScore > 0) ? 1 : -1;
      signalCount++;
   }

   // RSI Signal (weight: 20%)
   int rsiScore = (g_hRSI != INVALID_HANDLE) ? ScoreRSI() : 0;
   if(rsiScore != 0)
   {
      totalScore += (int)(MathAbs(rsiScore) * 0.20);
      direction += (rsiScore > 0) ? 1 : -1;
      signalCount++;
   }

   // MACD Signal (weight: 15%)
   int macdScore = (g_hMACD != INVALID_HANDLE) ? ScoreMACD() : 0;
   if(macdScore != 0)
   {
      totalScore += (int)(MathAbs(macdScore) * 0.15);
      direction += (macdScore > 0) ? 1 : -1;
      signalCount++;
   }

   // Pinbar (weight: 20%)
   int pinScore = ScorePinbar();
   if(pinScore != 0)
   {
      totalScore += (int)(MathAbs(pinScore) * 0.20);
      direction += (pinScore > 0) ? 1 : -1;
      signalCount++;
   }

   // SMC Swing (weight: 15%)
   int smcScore = ScoreSMCSwing();
   if(smcScore != 0)
   {
      totalScore += (int)(MathAbs(smcScore) * 0.15);
      direction += (smcScore > 0) ? 1 : -1;
      signalCount++;
   }

   // Cần ít nhất 1 signal (Giảm xuông 1 để người dùng lúc nào cũng thấy bot vào lệnh)
   if(signalCount < 1) return 0;

   // Boost score vì RẤT HIẾM khi cả 5 signals cùng lúc kích hoạt.
   // Nếu có ít nhất 2 signals đồng bộ, boost hệ số lên để dễ dàng vượt mốc 60.
   totalScore = (int)(totalScore * 1.5);

   // Disagreement penalty: nếu signals không unanimous
   if(MathAbs(direction) < signalCount) 
      totalScore = (int)(totalScore * 0.7); // giảm 30%

   totalScore = (int)MathMin(100, totalScore);
   g_confluenceScore = totalScore;

   if(direction > 0) return totalScore;
   if(direction < 0) return -totalScore;
   return 0;
}

//--- Kiểm tra Spread Filter
bool CheckSpreadFilter()
{
   if(InpMaxSpread <= 0) return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
   {
      // Optional: bỏ comment để debug spread 
      // Print("❌ Spread Filter Blocked: ", spread, " > ", InpMaxSpread);
      return false;
   }
   return true;
}

//--- Kiểm tra Cooldown
bool CheckCooldown()
{
   if(InpCooldownBars <= 0) return true;
   return (g_barsSinceClose >= InpCooldownBars);
}

//--- Hàm chính CheckEntrySignal (v2 — scoring + filters)
int CheckEntrySignal()
{
   // Pre-filters
   if(!CheckSpreadFilter()) return 0;
   if(!CheckCooldown()) return 0;

   int score = 0;

   switch(InpEntrySignal)
   {
      case SIGNAL_NONE:          score = 65; break; // Luôn luôn vào lệnh
      case SIGNAL_CANDLES:       score = ScoreCandles(); break;
      case SIGNAL_RANDOM:        score = (MathRand() % 100 > 50) ? 65 : -65; break;
      case SIGNAL_MOMENTUM:      score = ScoreMomentum(); break;
      case SIGNAL_RSI:           score = ScoreRSI(); break;
      case SIGNAL_RSI_REV:       score = -ScoreRSI(); break;
      case SIGNAL_MACD:          score = ScoreMACD(); break;
      case SIGNAL_CCI:           score = ScoreCCI(); break;
      case SIGNAL_CCI_REV:       score = -ScoreCCI(); break;
      case SIGNAL_STOCH:         score = ScoreStoch(); break;
      case SIGNAL_STOCH_REV:     score = -ScoreStoch(); break;
      case SIGNAL_BB:            score = ScoreBB(); break;
      case SIGNAL_PINBAR:        score = ScorePinbar(); break;
      case SIGNAL_SUPERTREND:    score = 0; /* TODO: Cần lib custom */ break;
      case SIGNAL_UTBOT:         score = 0; /* TODO: Cần lib custom */ break;
      case SIGNAL_BREAK_KUMO:    score = ScoreBreakKumo(); break;
      case SIGNAL_SMC_SWING:     score = ScoreSMCSwing(); break;
      case SIGNAL_SMC_SWING_REV: score = -ScoreSMCSwing(); break;
      case SIGNAL_SMC_ALL:       score = ScoreSMCSwing(); /* Placeholder */ break;
      case SIGNAL_INDI_NGAOI:    score = 0; /* TODO: Custom Buffer */ break;
      case SIGNAL_NW:            score = ScoreNW_Only(); break;
      case SIGNAL_CONFLUENCE:    score = ScoreConfluence(); break;
   }

   g_lastSignalScore = score;

   // Score threshold filter
   if(MathAbs(score) < InpMinSignalScore) return 0;

   // Convert score to signal direction
   int signal = 0;
   if(score > 0) signal = 1;
   else if(score < 0) signal = -1;

   // EMA Filter
   if(InpUseEMAFilter && signal != 0)
   {
      if(!CheckEMAFilter(signal)) signal = 0;
   }

   return signal;
}

//--- EMA Filter (v2 — sử dụng MaxDist)
bool CheckEMAFilter(int signal)
{
   double ema1[], ema2[];
   ArraySetAsSeries(ema1, true);
   ArraySetAsSeries(ema2, true);
   if(CopyBuffer(g_hEMA1, 0, 0, 2, ema1) < 2) return true;
   if(CopyBuffer(g_hEMA2, 0, 0, 2, ema2) < 2) return true;

   double close = iClose(_Symbol, InpSignalTF, 1); // Dùng bar confirmed
   double maxDist = InpEMA_MaxDist * _Point;

   // BUY: giá phải trên EMA1 và EMA1 > EMA2 và không quá xa EMA
   if(signal == 1)
   {
      if(close < ema1[0] || ema1[0] < ema2[0]) return false;
      if(maxDist > 0 && (close - ema1[0]) > maxDist) return false; // Quá xa → reject
      return true;
   }

   // SELL: giá phải dưới EMA1 và EMA1 < EMA2 và không quá xa
   if(signal == -1)
   {
      if(close > ema1[0] || ema1[0] > ema2[0]) return false;
      if(maxDist > 0 && (ema1[0] - close) > maxDist) return false;
      return true;
   }

   return true;
}

//+------------------------------------------------------------------+
//| MODULE 2: DCA x2 GRID ENGINE                                    |
//+------------------------------------------------------------------+

//--- Đếm lệnh theo loại
void CountOrders(int &buyCount, int &sellCount)
{
   buyCount = 0;
   sellCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)  buyCount++;
      if(posInfo.PositionType() == POSITION_TYPE_SELL) sellCount++;
   }
}

//--- Lấy giá mở của lệnh cuối cùng theo loại
double GetLastOrderPrice(ENUM_POSITION_TYPE type)
{
   double lastPrice = 0;
   datetime lastTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != type) continue;

      if(posInfo.Time() > lastTime)
      {
         lastTime  = posInfo.Time();
         lastPrice = posInfo.PriceOpen();
      }
   }
   return lastPrice;
}

//--- Tính lot cho DCA level tiếp theo
double CalcNextLot(int currentCount)
{
   double lot = InpStartLot;
   for(int i = 0; i < currentCount; i++)
      lot *= InpLotMultiplier;

   // Clamp theo giới hạn broker
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = MathFloor(lot / lotStep) * lotStep;

   return NormalizeDouble(lot, 2);
}

//--- Tính giá trung bình (Average Price) của grid
double CalcAveragePrice(ENUM_POSITION_TYPE type)
{
   double totalLotPrice = 0;
   double totalLot      = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != type) continue;

      totalLotPrice += posInfo.PriceOpen() * posInfo.Volume();
      totalLot      += posInfo.Volume();
   }

   if(totalLot > 0)
      return NormalizeDouble(totalLotPrice / totalLot, _Digits);
   return 0;
}

//--- Mở lệnh mới (First hoặc DCA)
bool OpenOrder(int signal, double lot, string comment)
{
   double price, sl = 0, tp = 0;
   bool result = false;

   if(signal == 1) // BUY
   {
      result = trade.Buy(lot, _Symbol, 0.0, sl, tp, comment);
   }
   else if(signal == -1) // SELL
   {
      result = trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);
   }

   if(!result && signal != 0)
   {
      Print("❌ OpenOrder Failed! Retcode: ", trade.ResultRetcode(), 
            " | Desc: ", trade.ResultRetcodeDescription());
   }

   return result;
}

//--- Xử lý DCA: kiểm tra và mở lệnh DCA nếu cần
void ProcessDCA()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double step = InpDCAStep * _Point;

   // BUY grid
   if(g_buyCount > 0 && g_buyCount < InpMaxOrders)
   {
      double lastBuyPrice = GetLastOrderPrice(POSITION_TYPE_BUY);
      if(lastBuyPrice > 0 && ask <= lastBuyPrice - step)
      {
         // Smart DCA: kiểm tra NW direction
         if(InpNW_SmartDCA && g_waveDirection == NW_BEARISH)
         {
            // NW bearish nhưng đang gồng BUY → cảnh báo nhưng vẫn DCA (to die)
            Print("⚠️ NW Bearish — DCA BUY Level ", g_buyCount + 1, " (caution!)");
         }
         double lot = CalcNextLot(g_buyCount);
         string comment = StringFormat("PhxDCA_B%d_%.2f", g_buyCount + 1, lot);
         if(OpenOrder(1, lot, comment))
            Print("🟢 DCA BUY Lv", g_buyCount + 1, " | Lot=", lot, " | Price=", ask);
      }
   }

   // SELL grid
   if(g_sellCount > 0 && g_sellCount < InpMaxOrders)
   {
      double lastSellPrice = GetLastOrderPrice(POSITION_TYPE_SELL);
      if(lastSellPrice > 0 && bid >= lastSellPrice + step)
      {
         if(InpNW_SmartDCA && g_waveDirection == NW_BULLISH)
         {
            Print("⚠️ NW Bullish — DCA SELL Level ", g_sellCount + 1, " (caution!)");
         }
         double lot = CalcNextLot(g_sellCount);
         string comment = StringFormat("PhxDCA_S%d_%.2f", g_sellCount + 1, lot);
         if(OpenOrder(-1, lot, comment))
            Print("🔴 DCA SELL Lv", g_sellCount + 1, " | Lot=", lot, " | Price=", bid);
      }
   }
}

//+------------------------------------------------------------------+
//| MODULE 3: EXIT LOGIC                                            |
//+------------------------------------------------------------------+

//--- Modify TP cho toàn bộ grid (Average TP)
void ManageTP()
{
   double tp_points = InpTakeProfit * _Point;

   // BUY grid
   if(g_buyCount > 0)
   {
      double avgPrice = CalcAveragePrice(POSITION_TYPE_BUY);
      double targetTP = NormalizeDouble(avgPrice + tp_points, _Digits);
      ModifyAllTP(POSITION_TYPE_BUY, targetTP);
   }

   // SELL grid
   if(g_sellCount > 0)
   {
      double avgPrice = CalcAveragePrice(POSITION_TYPE_SELL);
      double targetTP = NormalizeDouble(avgPrice - tp_points, _Digits);
      ModifyAllTP(POSITION_TYPE_SELL, targetTP);
   }
}

//--- Modify TP cho tất cả positions cùng loại
void ModifyAllTP(ENUM_POSITION_TYPE type, double tp)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != type) continue;

      if(MathAbs(posInfo.TakeProfit() - tp) > _Point)
      {
         trade.PositionModify(posInfo.Ticket(), posInfo.StopLoss(), tp);
      }
   }
}

//--- Đóng toàn bộ grid theo loại
void CloseAllByType(ENUM_POSITION_TYPE type, string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != type) continue;

      trade.PositionClose(posInfo.Ticket());
   }
   Print("📌 Closed all ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"), " — ", reason);
}

//--- Đóng toàn bộ positions
void CloseAll(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;

      trade.PositionClose(posInfo.Ticket());
   }
   Print("🔒 CLOSE ALL — ", reason);
}

//--- NW Band Exit: đóng khi giá chạm band đối diện
void CheckNWBandExit()
{
   if(!InpCloseOnBandHit) return;

   double close = iClose(_Symbol, InpSignalTF, 0);

   // BUY grid: đóng khi giá chạm Upper Band (đã lời hết sóng)
   if(g_buyCount > 0 && close >= g_nwUpper[0])
   {
      double pnl = CalcFloatingPnL(POSITION_TYPE_BUY);
      if(pnl > 0) CloseAllByType(POSITION_TYPE_BUY, "NW Upper Band TP");
   }

   // SELL grid: đóng khi giá chạm Lower Band
   if(g_sellCount > 0 && close <= g_nwLower[0])
   {
      double pnl = CalcFloatingPnL(POSITION_TYPE_SELL);
      if(pnl > 0) CloseAllByType(POSITION_TYPE_SELL, "NW Lower Band TP");
   }
}

//--- Tính floating PnL theo loại
double CalcFloatingPnL(ENUM_POSITION_TYPE type)
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != type) continue;
      pnl += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
   }
   return pnl;
}

//--- Tính tổng floating PnL
double CalcTotalFloatingPnL()
{
   double pnl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      pnl += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
   }
   return pnl;
}

//--- Trailing Stop cho grid
void ProcessTrailingStop()
{
   if(!InpUseTrailing) return;

   double trailStart = InpTrailingStart * _Point;
   double trailStep  = InpTrailingStep * _Point;

   // Trailing BUY grid
   if(g_buyCount > 0)
   {
      double avgPrice = CalcAveragePrice(POSITION_TYPE_BUY);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(bid > avgPrice + trailStart)
      {
         double newSL = NormalizeDouble(bid - trailStep, _Digits);
         TrailAllSL(POSITION_TYPE_BUY, newSL, true);
      }
   }

   // Trailing SELL grid
   if(g_sellCount > 0)
   {
      double avgPrice = CalcAveragePrice(POSITION_TYPE_SELL);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(ask < avgPrice - trailStart)
      {
         double newSL = NormalizeDouble(ask + trailStep, _Digits);
         TrailAllSL(POSITION_TYPE_SELL, newSL, false);
      }
   }
}

//--- Dời SL cho tất cả positions cùng loại
void TrailAllSL(ENUM_POSITION_TYPE type, double newSL, bool isBuy)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() != InpMagicNumber) continue;
      if(posInfo.PositionType() != type) continue;

      double currentSL = posInfo.StopLoss();

      bool shouldModify = false;
      if(isBuy && (currentSL == 0 || newSL > currentSL))
         shouldModify = true;
      if(!isBuy && (currentSL == 0 || newSL < currentSL))
         shouldModify = true;

      if(shouldModify)
         trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
   }
}

//+------------------------------------------------------------------+
//| MODULE 4: RISK MANAGEMENT                                       |
//+------------------------------------------------------------------+

//--- Kiểm tra Drawdown
bool CheckDrawdown()
{
   if(InpMaxDD_Percent <= 0) return true; // disabled

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(equity > g_maxEquity) g_maxEquity = equity;

   g_currentDD = (g_maxEquity > 0) ? (g_maxEquity - equity) / g_maxEquity * 100 : 0;

   if(g_currentDD >= InpMaxDD_Percent)
   {
      CloseAll(StringFormat("MAX DD %.1f%% reached!", g_currentDD));
      return false;
   }
   return true;
}

//--- Kiểm tra bộ lọc thời gian
bool CheckTimeFilter()
{
   if(!InpUseTimeFilter) return true;

   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;

   if(InpStartHour <= InpEndHour)
      return (hour >= InpStartHour && hour <= InpEndHour);
   else // overnight (e.g. 22 → 6)
      return (hour >= InpStartHour || hour <= InpEndHour);
}

//+------------------------------------------------------------------+
//| MODULE 5: GUI DASHBOARD                                         |
//+------------------------------------------------------------------+

void CreateDashboard()
{
   int x = 10, y = 30, w = 280, h = 20;
   color bgColor   = C'20,20,30';
   color textColor = clrWhite;

   // Background panel
   CreateRectangle(g_panelPrefix + "BG", x - 5, y - 25, w + 10, 340, bgColor, 200);

   // Title
   CreateLabel(g_panelPrefix + "Title", x, y, "🔥 PHOENIX DCA PRO v1.00", clrGold, 11, true);
   y += 25;
   CreateLabel(g_panelPrefix + "Author", x, y, "by hungpixi | Tele: hungpixi", C'150,150,150', 8, false);
   y += 20;

   // Separator
   CreateLabel(g_panelPrefix + "Sep1", x, y, "────────────────────────", C'60,60,80', 8, false);
   y += 18;

   // NW Wave Direction
   CreateLabel(g_panelPrefix + "WaveLabel", x, y, "Wave Direction:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "WaveValue", x + 140, y, "---", clrYellow, 9, true);
   y += 20;

   // NW Slope
   CreateLabel(g_panelPrefix + "SlopeLabel", x, y, "NW Slope:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "SlopeValue", x + 140, y, "0.00", textColor, 9, false);
   y += 20;

   // Price Zone
   CreateLabel(g_panelPrefix + "ZoneLabel", x, y, "Price Zone:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "ZoneValue", x + 140, y, "---", textColor, 9, false);
   y += 20;

   // Separator
   CreateLabel(g_panelPrefix + "Sep2", x, y, "────────────────────────", C'60,60,80', 8, false);
   y += 18;

   // Buy Orders
   CreateLabel(g_panelPrefix + "BuyLabel", x, y, "BUY Orders:", C'100,200,100', 9, false);
   CreateLabel(g_panelPrefix + "BuyValue", x + 140, y, "0", clrLimeGreen, 9, true);
   y += 20;

   // Sell Orders
   CreateLabel(g_panelPrefix + "SellLabel", x, y, "SELL Orders:", C'200,100,100', 9, false);
   CreateLabel(g_panelPrefix + "SellValue", x + 140, y, "0", clrTomato, 9, true);
   y += 20;

   // Floating PnL
   CreateLabel(g_panelPrefix + "PnLLabel", x, y, "Floating PnL:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "PnLValue", x + 140, y, "$0.00", textColor, 9, true);
   y += 20;

   // Drawdown
   CreateLabel(g_panelPrefix + "DDLabel", x, y, "Drawdown:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "DDValue", x + 140, y, "0.0%", textColor, 9, false);
   y += 20;

   // Separator
   CreateLabel(g_panelPrefix + "Sep3", x, y, "────────────────────────", C'60,60,80', 8, false);
   y += 18;

   // Distance to next DCA
   CreateLabel(g_panelPrefix + "DCADistLabel", x, y, "Next DCA Dist:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "DCADistValue", x + 140, y, "---", textColor, 9, false);
   y += 20;

   // Signal Score
   CreateLabel(g_panelPrefix + "ScoreLabel", x, y, "Signal Score:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "ScoreValue", x + 140, y, "0", textColor, 9, true);
   y += 20;

   // Spread
   CreateLabel(g_panelPrefix + "SpreadLabel", x, y, "Spread:", C'180,180,200', 9, false);
   CreateLabel(g_panelPrefix + "SpreadValue", x + 140, y, "0", textColor, 9, false);
}

//--- Cập nhật Dashboard mỗi tick
void UpdateDashboard()
{
   if(!InpShowDashboard) return;

   // Wave Direction
   string waveText = "---";
   color  waveColor = clrYellow;
   switch(g_waveDirection)
   {
      case NW_BULLISH:  waveText = "▲ BULLISH"; waveColor = clrLimeGreen; break;
      case NW_BEARISH:  waveText = "▼ BEARISH"; waveColor = clrTomato;    break;
      case NW_NEUTRAL:  waveText = "◆ SIDEWAY"; waveColor = clrYellow;    break;
   }
   UpdateLabelText(g_panelPrefix + "WaveValue", waveText);
   UpdateLabelColor(g_panelPrefix + "WaveValue", waveColor);

   // Slope
   UpdateLabelText(g_panelPrefix + "SlopeValue", StringFormat("%.2f", g_nwSlope / _Point));

   // Price Zone
   string zoneText = "MIDDLE";
   color  zoneColor = clrYellow;
   switch(g_priceZone)
   {
      case ZONE_UPPER: zoneText = "🔴 OVERBOUGHT"; zoneColor = clrTomato;    break;
      case ZONE_LOWER: zoneText = "🟢 OVERSOLD";   zoneColor = clrLimeGreen; break;
      case ZONE_MIDDLE: zoneText = "⚪ NEUTRAL";    zoneColor = clrYellow;    break;
   }
   UpdateLabelText(g_panelPrefix + "ZoneValue", zoneText);
   UpdateLabelColor(g_panelPrefix + "ZoneValue", zoneColor);

   // Orders
   UpdateLabelText(g_panelPrefix + "BuyValue", IntegerToString(g_buyCount));
   UpdateLabelText(g_panelPrefix + "SellValue", IntegerToString(g_sellCount));

   // PnL
   g_floatingPnL = CalcTotalFloatingPnL();
   color pnlColor = (g_floatingPnL >= 0) ? clrLimeGreen : clrTomato;
   UpdateLabelText(g_panelPrefix + "PnLValue", StringFormat("$%.2f", g_floatingPnL));
   UpdateLabelColor(g_panelPrefix + "PnLValue", pnlColor);

   // Drawdown
   color ddColor = (g_currentDD > 30) ? clrTomato : (g_currentDD > 15 ? clrOrange : clrLimeGreen);
   UpdateLabelText(g_panelPrefix + "DDValue", StringFormat("%.1f%%", g_currentDD));
   UpdateLabelColor(g_panelPrefix + "DDValue", ddColor);

   // Distance to next DCA
   string dcaDistText = "---";
   if(g_buyCount > 0)
   {
      double lastBuyPrice = GetLastOrderPrice(POSITION_TYPE_BUY);
      double dist = (lastBuyPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / _Point;
      dcaDistText = StringFormat("B: %.0f pts", InpDCAStep - dist);
   }
   if(g_sellCount > 0)
   {
      double lastSellPrice = GetLastOrderPrice(POSITION_TYPE_SELL);
      double dist = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - lastSellPrice) / _Point;
      if(dcaDistText != "---") dcaDistText += " | ";
      else dcaDistText = "";
      dcaDistText += StringFormat("S: %.0f pts", InpDCAStep - dist);
   }
   UpdateLabelText(g_panelPrefix + "DCADistValue", dcaDistText);

   // Signal Score
   color scoreColor = (MathAbs(g_lastSignalScore) >= InpMinSignalScore) ? clrLimeGreen : C'120,120,140';
   UpdateLabelText(g_panelPrefix + "ScoreValue", StringFormat("%d / %d", g_lastSignalScore, InpMinSignalScore));
   UpdateLabelColor(g_panelPrefix + "ScoreValue", scoreColor);

   // Spread
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   color spreadColor = (currentSpread <= InpMaxSpread) ? clrLimeGreen : clrTomato;
   UpdateLabelText(g_panelPrefix + "SpreadValue", StringFormat("%d / %d pts", (int)currentSpread, InpMaxSpread));
   UpdateLabelColor(g_panelPrefix + "SpreadValue", spreadColor);

   ChartRedraw();
}

//--- Vẽ NW Envelope lên chart
void DrawNWEnvelope()
{
   if(!InpDrawNWEnvelope) return;

   int drawBars = MathMin(200, ArraySize(g_nwLine));
   datetime timeArr[];
   ArraySetAsSeries(timeArr, true);
   CopyTime(_Symbol, InpSignalTF, 0, drawBars, timeArr);

   for(int i = 0; i < drawBars - 1; i++)
   {
      string nameNW  = g_panelPrefix + "NW_" + IntegerToString(i);
      string nameUp  = g_panelPrefix + "UP_" + IntegerToString(i);
      string nameLow = g_panelPrefix + "LO_" + IntegerToString(i);

      // NW Center Line
      DrawTrendLine(nameNW, timeArr[i+1], g_nwLine[i+1], timeArr[i], g_nwLine[i],
                    InpNW_LineColor, InpNW_LineWidth);

      // Upper Band
      DrawTrendLine(nameUp, timeArr[i+1], g_nwUpper[i+1], timeArr[i], g_nwUpper[i],
                    InpUpperBandColor, 1);

      // Lower Band
      DrawTrendLine(nameLow, timeArr[i+1], g_nwLower[i+1], timeArr[i], g_nwLower[i],
                    InpLowerBandColor, 1);
   }
}

//+------------------------------------------------------------------+
//| GUI Helper Functions                                             |
//+------------------------------------------------------------------+

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateRectangle(string name, int x, int y, int width, int height, color clr, int opacity)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, C'40,40,60');
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void DrawTrendLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int width)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void UpdateLabelText(string name, string text)
{
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void UpdateLabelColor(string name, color clr)
{
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void DeleteDashboard()
{
   ObjectsDeleteAll(0, g_panelPrefix, 0, -1);
}

void DeleteNWEnvelopeObjects()
{
   ObjectsDeleteAll(0, g_panelPrefix + "NW_", 0, -1);
   ObjectsDeleteAll(0, g_panelPrefix + "UP_", 0, -1);
   ObjectsDeleteAll(0, g_panelPrefix + "LO_", 0, -1);
}

//+------------------------------------------------------------------+
//| MAIN TICK HANDLER                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Kiểm tra new bar (chỉ xử lý logic khi có nến mới để tối ưu CPU)
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, InpSignalTF, 0);
   bool isNewBar = (currentBarTime != lastBarTime);
   if(isNewBar) lastBarTime = currentBarTime;

   //--- Đếm lệnh đang mở
   CountOrders(g_buyCount, g_sellCount);

   //--- Cập nhật NW mỗi nến mới
   if(isNewBar)
   {
      // Tính Nadaraya-Watson
      if(!CalcNadarayaWatson()) 
      {
         if(isNewBar && MQLInfoInteger(MQL_TESTER)) Print("❌ CalcNadarayaWatson Failed! Check History/Buffer!");
         return;
      }

      // Cập nhật wave direction & price zone
      g_waveDirection = GetWaveDirection();
      g_priceZone     = GetPriceZone();

      // Cooldown counter
      if(g_buyCount == 0 && g_sellCount == 0)
         g_barsSinceClose++;
      else
         g_barsSinceClose = 0;

      // Vẽ NW Envelope
      if(InpDrawNWEnvelope && !MQLInfoInteger(MQL_OPTIMIZATION)) DrawNWEnvelope();
   }

   //--- Risk Management
   if(!CheckDrawdown()) return;

   //--- Time Filter
   if(!CheckTimeFilter()) return;

   //--- NW Band Exit
   CheckNWBandExit();

   //--- Xử lý DCA cho grid đang mở
   ProcessDCA();

   //--- Quản lý TP
   ManageTP();

   //--- Trailing Stop
   ProcessTrailingStop();

   //--- Chỉ mở lệnh mới khi new bar + chưa có grid
   if(isNewBar)
   {
      int signal = CheckEntrySignal();

      if(signal == 1 && g_buyCount == 0)
      {
         string comment = StringFormat("PhxDCA_B1_%.2f", InpStartLot);
         if(OpenOrder(1, InpStartLot, comment))
         {
            g_barsSinceClose = 0;
            Print("🟢 FIRST BUY | Score=", g_lastSignalScore,
                  " | NW=", EnumToString(g_waveDirection),
                  " | Zone=", EnumToString(g_priceZone));
         }
      }
      else if(signal == -1 && g_sellCount == 0)
      {
         string comment = StringFormat("PhxDCA_S1_%.2f", InpStartLot);
         if(OpenOrder(-1, InpStartLot, comment))
         {
            g_barsSinceClose = 0;
            Print("🔴 FIRST SELL | Score=", g_lastSignalScore,
                  " | NW=", EnumToString(g_waveDirection),
                  " | Zone=", EnumToString(g_priceZone));
         }
      }
      // Debug no signal
      else if(signal == 0 && MQLInfoInteger(MQL_TESTER))
      {
         // Bật Print log trong lúc Test để truy xuất root cause
         long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         PrintFormat("⚪ Bar[%s] - Signal=0 | Score=%d | NW=%s | Zone=%s | Spread=%d", 
               TimeToString(iTime(_Symbol, InpSignalTF, 0), TIME_MINUTES),
               g_lastSignalScore, 
               EnumToString(g_waveDirection), 
               EnumToString(g_priceZone),
               currentSpread);
      }
   }

   //--- Cập nhật GUI Dashboard
   if(InpShowDashboard && !MQLInfoInteger(MQL_OPTIMIZATION)) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Chart event handler (cho nút bấm tương lai)                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Xử lý click nút Close All (sẽ bổ sung sau)
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
