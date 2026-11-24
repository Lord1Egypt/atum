//+------------------------------------------------------------------+
//|                                                   Smart Scalp PA |
//+------------------------------------------------------------------+
//|                                Copyright (c) 2025 LogicCrafterDZ |
//|                                  Email: logiccrafterdz@gmail.com |
//|                                              Twitter: @Arana_lib |
//|                          Telegram: `https://t.me/LogicCrafterDZ` |
//+------------------------------------------------------------------+
#property copyright "(c) 2025 LogicCrafterDZ"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

// --- Inputs (kept simple, aligned with strategy) ---
input double Lots                = 0.10;          // Trade lot size
input int    BoringThreshold     = 25;            // Boring candle body % of range (previous candle)
input int    EngulfingThreshold  = 50;            // Engulfing candle body % of range (current candle)
input int    StopLevelPips       = 200;           // Base stop level in pips (internally capped to 10)
input int    SRLookbackBars      = 200;           // Lookback for S/R clustering
input int    PivotLeft           = 5;             // Left bars for pivot
input int    PivotRight          = 5;             // Right bars for pivot
input int    Magic               = 272727;        // Magic number for this EA

// --- Globals ---
int htfEmaHandle = -1; // H1 EMA(50) handle
static datetime lastProcessedBarTime = 0; // process once per closed bar

// --- Utility: safe access ---
bool BarsReady(int min_bars)
{
   return (Bars(_Symbol, _Period) >= min_bars);
}

// --- HTF EMA50 (H1), non-repainting: read from the last closed H1 bar ---
bool GetHTFEMA50(double &ema)
{
   if(htfEmaHandle == -1) return false;
   double buf[];
   // shift=1 to use closed H1 bar
   if(CopyBuffer(htfEmaHandle, 0, 1, 1, buf) != 1) return false;
   if(ArraySize(buf) < 1) return false;
   ema = buf[0];
   return true;
}

// --- Pivot detection (closed history only) ---
bool IsPivotHigh(int i, int left, int right)
{
   int total = Bars(_Symbol, _Period);
   if(i <= right || i >= total - left) return false; // ensure window exists
   double hi = iHigh(_Symbol, _Period, i);
   for(int k=1; k<=left; ++k) if(hi <= iHigh(_Symbol,_Period, i-k)) return false;
   for(int k=1; k<=right; ++k) if(hi <  iHigh(_Symbol,_Period, i+k)) return false;
   return true;
}

bool IsPivotLow(int i, int left, int right)
{
   int total = Bars(_Symbol, _Period);
   if(i <= right || i >= total - left) return false;
   double lo = iLow(_Symbol, _Period, i);
   for(int k=1; k<=left; ++k) if(lo >= iLow(_Symbol,_Period, i-k)) return false;
   for(int k=1; k<=right; ++k) if(lo >  iLow(_Symbol,_Period, i+k)) return false;
   return true;
}

// --- SR clustering within lookback using tolerance ---
struct SRCluster { double level; int count; };

bool HasStrongSRNear(double price, int lookback, double tol)
{
   int total = Bars(_Symbol, _Period);
   if(total < lookback + 50) lookback = total - 50; // guard
   if(lookback < 10) return false;

   SRCluster clusters[];
   ArrayResize(clusters, 0);

   int start = 1 + PivotRight; // skip current forming bar and ensure right window
   int end   = MathMin(1 + lookback, total - 1 - PivotLeft);

   for(int j=start; j<=end; ++j)
   {
      double lvl = 0.0;
      bool isPH = IsPivotHigh(j, PivotLeft, PivotRight);
      bool isPL = IsPivotLow(j, PivotLeft, PivotRight);
      if(!isPH && !isPL) continue;
      lvl = isPH ? iHigh(_Symbol, _Period, j) : iLow(_Symbol, _Period, j);

      // find cluster within tolerance
      bool matched = false;
      for(int c=0; c<ArraySize(clusters); ++c)
      {
         if(MathAbs(lvl - clusters[c].level) <= tol)
         {
            clusters[c].count++;
            matched = true;
            break;
         }
      }
      if(!matched)
      {
         SRCluster nc; nc.level = lvl; nc.count = 1;
         int newSize = ArraySize(clusters) + 1;
         ArrayResize(clusters, newSize);
         clusters[newSize-1] = nc;
      }
   }

   // check proximity to any strong cluster (>=2 touches)
   for(int c=0; c<ArraySize(clusters); ++c)
   {
      if(clusters[c].count >= 2 && MathAbs(price - clusters[c].level) <= tol)
         return true;
   }
   return false;
}

// --- Position helper: avoid stacking multiple positions ---
bool HasOpenPositionOfType(int type)
{
   for(int i=0; i<PositionsTotal(); ++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      int    t   = (int)PositionGetInteger(POSITION_TYPE);
      long   mg  = PositionGetInteger(POSITION_MAGIC);
      if(sym == _Symbol && t == type && mg == Magic)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   htfEmaHandle = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(htfEmaHandle == -1)
   {
      Print("Failed to create H1 EMA(50) handle");
      return(INIT_FAILED);
   }
   Print("Engulfing with Trend EA initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(htfEmaHandle != -1) IndicatorRelease(htfEmaHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!BarsReady(300)) return;

   // Process once per newly closed bar
   datetime closedBarTime = iTime(_Symbol, _Period, 1);
   if(lastProcessedBarTime == closedBarTime) return;
   lastProcessedBarTime = closedBarTime;

   int shift = 1; // use closed bar for all logic to avoid repaint
   double htfEma=0.0;
   if(!GetHTFEMA50(htfEma)) return;

   double open0  = iOpen(_Symbol, _Period, shift);
   double close0 = iClose(_Symbol, _Period, shift);
   double high0  = iHigh(_Symbol, _Period, shift);
   double low0   = iLow(_Symbol, _Period, shift);

   double open1  = iOpen(_Symbol, _Period, shift+1);
   double close1 = iClose(_Symbol, _Period, shift+1);
   double high1  = iHigh(_Symbol, _Period, shift+1);
   double low1   = iLow(_Symbol, _Period, shift+1);

   // Trend filter (HTF EMA only)
   bool longTrendOK  = (close0 > htfEma);
   bool shortTrendOK = (close0 < htfEma);

   // Boring/Engulfing thresholds
   bool isBoringPrev = (MathAbs(open1 - close1) * 100.0 / MathMax(1e-8, MathAbs(high1 - low1)) <= (double)BoringThreshold);
   bool isEngulfingCurBodySmall = (MathAbs(open0 - close0) * 100.0 / MathMax(1e-8, MathAbs(high0 - low0)) <= (double)EngulfingThreshold);
   // Precise Engulfing (full body engulfment)
   bool bullEngulfingCandle = (close0 > open0) && (close1 < open1) && (open0 <= close1) && (close0 >= open1);
   bool bearEngulfingCandle = (close0 < open0) && (close1 > open1) && (open0 >= close1) && (close0 <= open1);

   // Pin Bar detection (HTF EMA trend only)
   double body        = MathAbs(close0 - open0);
   double candleRange = MathAbs(high0 - low0);
   double upperWick   = high0 - MathMax(open0, close0);
   double lowerWick   = MathMin(open0, close0) - low0;
   bool bullPinBar    = longTrendOK  && (lowerWick > body*2.0) && (candleRange > 0.0) && ((lowerWick / candleRange) >= 0.5) && (close0 >= open0);
   bool bearPinBar    = shortTrendOK && (upperWick > body*2.0) && (candleRange > 0.0) && ((upperWick / candleRange) >= 0.5) && (close0 <= open0);

   // S/R proximity: require >=2 touches within lookback, near current price by tolerance
   double srTol = 5.0 * _Point;
   bool nearSR  = HasStrongSRNear(close0, SRLookbackBars, srTol);

   // Setup signals (immediate recommendations)
   bool bullishSetup = ( (bullPinBar || bullEngulfingCandle) && nearSR && longTrendOK );
   bool bearishSetup = ( (bearPinBar || bearEngulfingCandle) && nearSR && shortTrendOK );

   // Risk/Reward: Entry, SL behind previous candle wick, TP at 2R
   int slBufferPipsEff = (int)MathMin((double)StopLevelPips, 10.0);
   double pip = _Point;

   double bullStop = close0;
   double bearStop = close0;
   double bullSL   = low1  - slBufferPipsEff * pip;
   double bearSL   = high1 + slBufferPipsEff * pip;

   double riskLong  = bullStop - bullSL;
   double riskShort = bearSL   - bearStop;
   double bullTP    = bullStop + (riskLong * 2.0);
   double bearTP    = bearStop - (riskShort * 2.0);

   // Normalize prices
   bullSL   = NormalizeDouble(bullSL,   (int)_Digits);
   bullTP   = NormalizeDouble(bullTP,   (int)_Digits);
   bearSL   = NormalizeDouble(bearSL,   (int)_Digits);
   bearTP   = NormalizeDouble(bearTP,   (int)_Digits);
   bullStop = NormalizeDouble(bullStop, (int)_Digits);
   bearStop = NormalizeDouble(bearStop, (int)_Digits);

   // Place trades (avoid stacking same-direction positions for this symbol)
   if(bullishSetup && riskLong > 0.0 && !HasOpenPositionOfType(POSITION_TYPE_BUY))
   {
      trade.SetExpertMagicNumber(Magic);
      bool ok = trade.Buy(Lots, _Symbol, bullStop, bullSL, bullTP);
      if(ok) Print("BUY: ", _Symbol, " @", bullStop, " SL:", bullSL, " TP:", bullTP);
      else   Print("BUY failed. Error: ", GetLastError());
   }

   if(bearishSetup && riskShort > 0.0 && !HasOpenPositionOfType(POSITION_TYPE_SELL))
   {
      trade.SetExpertMagicNumber(Magic);
      bool ok = trade.Sell(Lots, _Symbol, bearStop, bearSL, bearTP);
      if(ok) Print("SELL: ", _Symbol, " @", bearStop, " SL:", bearSL, " TP:", bearTP);
      else   Print("SELL failed. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+