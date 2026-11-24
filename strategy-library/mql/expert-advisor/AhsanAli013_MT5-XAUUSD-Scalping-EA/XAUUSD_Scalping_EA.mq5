//+------------------------------------------------------------------+
//|          XAUUSDm M5 Safe Scalper EA for MetaTrader 5             |
//|                                                                  |
//| Strategy:                                                        |
//| - M5 entries                                                     |
//| - M15 trend confirmation                                         |
//| - H1 major trend confirmation                                    |
//| - EMA + RSI + ADX + ATR                                          |
//| - Spread-aware take profit                                       |
//| - Risk-based lot sizing                                          |
//| - Reject trade if 0.01 lot risks too much                        |
//| - Break-even + trailing stop                                     |
//| - Daily trade/loss/drawdown limits                               |
//+------------------------------------------------------------------+

#property strict
#property version   "3.00"

#include <Trade/Trade.mqh>

CTrade trade;

//==================================================================
// INPUT SETTINGS
//==================================================================

//-----------------------------
// Risk
//-----------------------------
input double RiskPercent               = 0.35;
input bool   RejectIfMinLotTooRisky     = true;

//-----------------------------
// Timeframes
//-----------------------------
input ENUM_TIMEFRAMES EntryTF           = PERIOD_M5;
input ENUM_TIMEFRAMES TrendTF           = PERIOD_M15;
input ENUM_TIMEFRAMES HigherTF          = PERIOD_H1;

//-----------------------------
// M5 EMAs
//-----------------------------
input int FastEMA                       = 9;
input int SlowEMA                       = 21;

//-----------------------------
// M15 trend EMAs
//-----------------------------
input int TrendFastEMA                  = 50;
input int TrendSlowEMA                  = 200;

//-----------------------------
// H1 trend EMA
//-----------------------------
input int HigherEMA                     = 200;

//-----------------------------
// RSI
//-----------------------------
input int    RSIPeriod                  = 14;
input double BuyRSI                     = 52.0;
input double SellRSI                    = 48.0;

//-----------------------------
// ADX
//-----------------------------
input int    ADXPeriod                  = 14;
input double MinimumADX                 = 18.0;

//-----------------------------
// ATR
//-----------------------------
input int    ATRPeriod                  = 14;
input double ATRStopMultiplier          = 1.20;

//-----------------------------
// Gold pip size
// Exness XAUUSDm:
// 1 "pip" in this EA = 0.01 price
//-----------------------------
input double PipSize                    = 0.01;

//-----------------------------
// Stop / Target
//-----------------------------
input double MinimumStopPips            = 30.0;
input double MinimumTargetPips          = 30.0;
input double RiskRewardRatio            = 1.50;

// TP must also be at least:
// current spread × this multiplier
input double SpreadTargetMultiplier     = 3.0;

//-----------------------------
// Entry filters
//-----------------------------
input double PullbackTolerancePips      = 15.0;
input double MinEMASeparationPips       = 5.0;

//-----------------------------
// Spread
//-----------------------------
input double MaxSpreadPips              = 40.0;

//-----------------------------
// Break-even
//-----------------------------
input bool   UseBreakEven               = true;
input double BreakEvenTriggerPips       = 30.0;
input double BreakEvenLockPips          = 3.0;

//-----------------------------
// Trailing stop
//-----------------------------
input bool   UseTrailingStop            = true;
input double TrailingStartPips          = 45.0;
input double TrailingDistancePips       = 20.0;

//-----------------------------
// Trading frequency
//-----------------------------
input int MaxTradesPerDay               = 8;
input int MaxLossesPerDay               = 3;
input int MinMinutesBetweenTrades       = 15;

//-----------------------------
// Daily protection
//-----------------------------
input double MaxDailyDrawdownPercent    = 2.0;

//-----------------------------
// General
//-----------------------------
input ulong MagicNumber                 = 260903;
input int   SlippagePoints              = 30;


//==================================================================
// INDICATOR HANDLES
//==================================================================

int hFastEMA       = INVALID_HANDLE;
int hSlowEMA       = INVALID_HANDLE;

int hRSI           = INVALID_HANDLE;
int hADX           = INVALID_HANDLE;
int hATR           = INVALID_HANDLE;

int hTrendFastEMA  = INVALID_HANDLE;
int hTrendSlowEMA  = INVALID_HANDLE;

int hHigherEMA     = INVALID_HANDLE;


//==================================================================
// GLOBAL VARIABLES
//==================================================================

datetime lastBar       = 0;
datetime lastTradeTime = 0;

double dayStartBalance = 0.0;

int dailyTrades = 0;
int dailyLosses = 0;

int storedDay   = -1;
int storedMonth = -1;
int storedYear  = -1;


//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);

   // M5 indicators
   hFastEMA = iMA(
      _Symbol,
      EntryTF,
      FastEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hSlowEMA = iMA(
      _Symbol,
      EntryTF,
      SlowEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hRSI = iRSI(
      _Symbol,
      EntryTF,
      RSIPeriod,
      PRICE_CLOSE
   );

   hADX = iADX(
      _Symbol,
      EntryTF,
      ADXPeriod
   );

   hATR = iATR(
      _Symbol,
      EntryTF,
      ATRPeriod
   );

   // M15 trend
   hTrendFastEMA = iMA(
      _Symbol,
      TrendTF,
      TrendFastEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   hTrendSlowEMA = iMA(
      _Symbol,
      TrendTF,
      TrendSlowEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   // H1 major trend
   hHigherEMA = iMA(
      _Symbol,
      HigherTF,
      HigherEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE
   );

   // Validate
   if(
      hFastEMA      == INVALID_HANDLE ||
      hSlowEMA      == INVALID_HANDLE ||
      hRSI          == INVALID_HANDLE ||
      hADX          == INVALID_HANDLE ||
      hATR          == INVALID_HANDLE ||
      hTrendFastEMA == INVALID_HANDLE ||
      hTrendSlowEMA == INVALID_HANDLE ||
      hHigherEMA    == INVALID_HANDLE
   )
   {
      Print("ERROR: Failed to initialize one or more indicators.");

      return INIT_FAILED;
   }

   ResetDailyStats();

   Print("----------------------------------------");
   Print("XAU Safe Scalper initialized.");
   Print("Symbol: ", _Symbol);
   Print("Digits: ", _Digits);
   Print("PipSize: ", PipSize);
   Print("Risk: ", RiskPercent, "%");
   Print("----------------------------------------");

   return INIT_SUCCEEDED;
}


//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hFastEMA != INVALID_HANDLE)
      IndicatorRelease(hFastEMA);

   if(hSlowEMA != INVALID_HANDLE)
      IndicatorRelease(hSlowEMA);

   if(hRSI != INVALID_HANDLE)
      IndicatorRelease(hRSI);

   if(hADX != INVALID_HANDLE)
      IndicatorRelease(hADX);

   if(hATR != INVALID_HANDLE)
      IndicatorRelease(hATR);

   if(hTrendFastEMA != INVALID_HANDLE)
      IndicatorRelease(hTrendFastEMA);

   if(hTrendSlowEMA != INVALID_HANDLE)
      IndicatorRelease(hTrendSlowEMA);

   if(hHigherEMA != INVALID_HANDLE)
      IndicatorRelease(hHigherEMA);
}


//+------------------------------------------------------------------+
//| MAIN TICK                                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckNewDay();

   // Manage existing trade on every tick
   ManageOpenPosition();

   // New entries only once per M5 candle
   if(!IsNewBar())
      return;

   UpdateDailyLosses();

   if(!DailyTradingAllowed())
      return;

   if(HasOpenPosition())
      return;

   if(!EnoughTimeSinceLastTrade())
      return;

   if(!SpreadOK())
      return;

   EvaluateEntry();
}


//+------------------------------------------------------------------+
//| ENTRY EVALUATION                                                 |
//+------------------------------------------------------------------+
void EvaluateEntry()
{
   // Dynamic arrays avoid ArraySetAsSeries warnings

   double fastEMA[];
   double slowEMA[];

   double rsi[];
   double adx[];
   double atr[];

   double trendFast[];
   double trendSlow[];

   double higherEMA[];

   ArrayResize(fastEMA,3);
   ArrayResize(slowEMA,3);

   ArrayResize(rsi,3);
   ArrayResize(adx,3);
   ArrayResize(atr,3);

   ArrayResize(trendFast,3);
   ArrayResize(trendSlow,3);

   ArrayResize(higherEMA,3);

   ArraySetAsSeries(fastEMA,true);
   ArraySetAsSeries(slowEMA,true);

   ArraySetAsSeries(rsi,true);
   ArraySetAsSeries(adx,true);
   ArraySetAsSeries(atr,true);

   ArraySetAsSeries(trendFast,true);
   ArraySetAsSeries(trendSlow,true);

   ArraySetAsSeries(higherEMA,true);


   // Read indicator buffers

   if(CopyBuffer(
      hFastEMA,
      0,
      0,
      3,
      fastEMA
   ) < 3)
      return;

   if(CopyBuffer(
      hSlowEMA,
      0,
      0,
      3,
      slowEMA
   ) < 3)
      return;

   if(CopyBuffer(
      hRSI,
      0,
      0,
      3,
      rsi
   ) < 3)
      return;

   // ADX buffer 0 = main ADX line
   if(CopyBuffer(
      hADX,
      0,
      0,
      3,
      adx
   ) < 3)
      return;

   if(CopyBuffer(
      hATR,
      0,
      0,
      3,
      atr
   ) < 3)
      return;

   if(CopyBuffer(
      hTrendFastEMA,
      0,
      0,
      3,
      trendFast
   ) < 3)
      return;

   if(CopyBuffer(
      hTrendSlowEMA,
      0,
      0,
      3,
      trendSlow
   ) < 3)
      return;

   if(CopyBuffer(
      hHigherEMA,
      0,
      0,
      3,
      higherEMA
   ) < 3)
      return;


   // Previous CLOSED M5 candle

   double open1 =
      iOpen(
         _Symbol,
         EntryTF,
         1
      );

   double close1 =
      iClose(
         _Symbol,
         EntryTF,
         1
      );

   double high1 =
      iHigh(
         _Symbol,
         EntryTF,
         1
      );

   double low1 =
      iLow(
         _Symbol,
         EntryTF,
         1
      );


   // Trend timeframe closes

   double trendClose =
      iClose(
         _Symbol,
         TrendTF,
         1
      );

   double higherClose =
      iClose(
         _Symbol,
         HigherTF,
         1
      );


   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );


   //===============================================================
   // GENERAL FILTERS
   //===============================================================

   if(adx[1] < MinimumADX)
   {
      Print(
         "No trade: ADX too low = ",
         DoubleToString(adx[1],1)
      );

      return;
   }


   double emaDistancePips =
      MathAbs(
         fastEMA[1] -
         slowEMA[1]
      )
      /
      PipSize;


   if(
      emaDistancePips <
      MinEMASeparationPips
   )
   {
      return;
   }


   double tolerance =
      PullbackTolerancePips *
      PipSize;


   //===============================================================
   // BUY CONDITIONS
   //===============================================================

   bool higherBull =
      higherClose >
      higherEMA[1];


   bool trendBull =
      trendFast[1] >
      trendSlow[1];


   bool entryBull =
      fastEMA[1] >
      slowEMA[1];


   bool rsiBull =
      rsi[1] >=
      BuyRSI;


   bool bullishCandle =
      close1 >
      open1;


   bool pullbackBuy =
      (
         low1 <=
         fastEMA[1] +
         tolerance
      )
      &&
      (
         close1 >=
         fastEMA[1]
      );


   //===============================================================
   // SELL CONDITIONS
   //===============================================================

   bool higherBear =
      higherClose <
      higherEMA[1];


   bool trendBear =
      trendFast[1] <
      trendSlow[1];


   bool entryBear =
      fastEMA[1] <
      slowEMA[1];


   bool rsiBear =
      rsi[1] <=
      SellRSI;


   bool bearishCandle =
      close1 <
      open1;


   bool pullbackSell =
      (
         high1 >=
         fastEMA[1] -
         tolerance
      )
      &&
      (
         close1 <=
         fastEMA[1]
      );


   //===============================================================
   // BUY
   //===============================================================

   if(
      higherBull &&
      trendBull &&
      entryBull &&
      rsiBull &&
      bullishCandle &&
      pullbackBuy
   )
   {
      OpenBuy(
         ask,
         atr[1]
      );

      return;
   }


   //===============================================================
   // SELL
   //===============================================================

   if(
      higherBear &&
      trendBear &&
      entryBear &&
      rsiBear &&
      bearishCandle &&
      pullbackSell
   )
   {
      OpenSell(
         bid,
         atr[1]
      );

      return;
   }
}


//+------------------------------------------------------------------+
//| CURRENT SPREAD IN PIPS                                           |
//+------------------------------------------------------------------+
double CurrentSpreadPips()
{
   double ask =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_ASK
      );

   double bid =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_BID
      );

   if(PipSize <= 0)
      return 999999;

   return (
      ask -
      bid
   )
   /
   PipSize;
}


//+------------------------------------------------------------------+
//| BUY                                                              |
//+------------------------------------------------------------------+
void OpenBuy(
   double entry,
   double atrValue
)
{
   // ATR or minimum SL
   double stopDistance =
      MathMax(
         MinimumStopPips *
         PipSize,
         atrValue *
         ATRStopMultiplier
      );


   double spreadPips =
      CurrentSpreadPips();


   // Spread-aware target
   double spreadTargetPips =
      spreadPips *
      SpreadTargetMultiplier;


   // Risk/reward target
   double rrTargetPips =
      (
         stopDistance /
         PipSize
      )
      *
      RiskRewardRatio;


   double targetPips =
      MathMax(
         MinimumTargetPips,
         spreadTargetPips
      );


   targetPips =
      MathMax(
         targetPips,
         rrTargetPips
      );


   double targetDistance =
      targetPips *
      PipSize;


   double sl =
      NormalizeDouble(
         entry -
         stopDistance,
         _Digits
      );


   double tp =
      NormalizeDouble(
         entry +
         targetDistance,
         _Digits
      );


   double lot =
      CalculateSafeLot(
         stopDistance
      );


   if(lot <= 0)
   {
      Print(
         "BUY skipped: minimum lot exceeds allowed risk."
      );

      return;
   }


   if(
      !ValidateStops(
         ORDER_TYPE_BUY,
         entry,
         sl,
         tp
      )
   )
   {
      Print(
         "BUY skipped: invalid SL/TP."
      );

      return;
   }


   bool result =
      trade.Buy(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "XAU Safe BUY"
      );


   if(result)
   {
      dailyTrades++;

      lastTradeTime =
         TimeCurrent();


      Print(
         "BUY OPENED | Lot=",
         DoubleToString(lot,2),
         " | Entry=",
         DoubleToString(entry,_Digits),
         " | SL=",
         DoubleToString(sl,_Digits),
         " | TP=",
         DoubleToString(tp,_Digits),
         " | Spread=",
         DoubleToString(spreadPips,1),
         " pips",
         " | Target=",
         DoubleToString(targetPips,1),
         " pips"
      );
   }
   else
   {
      Print(
         "BUY FAILED | ",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );
   }
}


//+------------------------------------------------------------------+
//| SELL                                                             |
//+------------------------------------------------------------------+
void OpenSell(
   double entry,
   double atrValue
)
{
   double stopDistance =
      MathMax(
         MinimumStopPips *
         PipSize,
         atrValue *
         ATRStopMultiplier
      );


   double spreadPips =
      CurrentSpreadPips();


   double spreadTargetPips =
      spreadPips *
      SpreadTargetMultiplier;


   double rrTargetPips =
      (
         stopDistance /
         PipSize
      )
      *
      RiskRewardRatio;


   double targetPips =
      MathMax(
         MinimumTargetPips,
         spreadTargetPips
      );


   targetPips =
      MathMax(
         targetPips,
         rrTargetPips
      );


   double targetDistance =
      targetPips *
      PipSize;


   double sl =
      NormalizeDouble(
         entry +
         stopDistance,
         _Digits
      );


   double tp =
      NormalizeDouble(
         entry -
         targetDistance,
         _Digits
      );


   double lot =
      CalculateSafeLot(
         stopDistance
      );


   if(lot <= 0)
   {
      Print(
         "SELL skipped: minimum lot exceeds allowed risk."
      );

      return;
   }


   if(
      !ValidateStops(
         ORDER_TYPE_SELL,
         entry,
         sl,
         tp
      )
   )
   {
      Print(
         "SELL skipped: invalid SL/TP."
      );

      return;
   }


   bool result =
      trade.Sell(
         lot,
         _Symbol,
         0,
         sl,
         tp,
         "XAU Safe SELL"
      );


   if(result)
   {
      dailyTrades++;

      lastTradeTime =
         TimeCurrent();


      Print(
         "SELL OPENED | Lot=",
         DoubleToString(lot,2),
         " | Entry=",
         DoubleToString(entry,_Digits),
         " | SL=",
         DoubleToString(sl,_Digits),
         " | TP=",
         DoubleToString(tp,_Digits),
         " | Spread=",
         DoubleToString(spreadPips,1),
         " pips",
         " | Target=",
         DoubleToString(targetPips,1),
         " pips"
      );
   }
   else
   {
      Print(
         "SELL FAILED | ",
         trade.ResultRetcode(),
         " | ",
         trade.ResultRetcodeDescription()
      );
   }
}


//+------------------------------------------------------------------+
//| SAFE LOT SIZE                                                    |
//+------------------------------------------------------------------+
double CalculateSafeLot(
   double stopDistance
)
{
   double balance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );


   double allowedRiskMoney =
      balance *
      RiskPercent /
      100.0;


   double tickSize =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_SIZE
      );


   double tickValue =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_VALUE
      );


   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );


   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );


   double lotStep =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );


   if(
      tickSize <= 0 ||
      tickValue <= 0 ||
      stopDistance <= 0 ||
      minLot <= 0 ||
      lotStep <= 0
   )
   {
      Print(
         "ERROR: Invalid symbol risk parameters."
      );

      return 0;
   }


   double numberOfTicks =
      stopDistance /
      tickSize;


   double lossPerOneLot =
      numberOfTicks *
      tickValue;


   if(lossPerOneLot <= 0)
      return 0;


   // Risk at minimum broker lot
   double minimumLotRisk =
      lossPerOneLot *
      minLot;


   if(
      RejectIfMinLotTooRisky &&
      minimumLotRisk >
      allowedRiskMoney
   )
   {
      Print(
         "TRADE REJECTED | Allowed risk=$",
         DoubleToString(
            allowedRiskMoney,
            2
         ),
         " | 0.01-lot risk=$",
         DoubleToString(
            minimumLotRisk,
            2
         )
      );


      return 0;
   }


   double desiredLots =
      allowedRiskMoney /
      lossPerOneLot;


   double lots =
      MathFloor(
         desiredLots /
         lotStep
      )
      *
      lotStep;


   if(lots < minLot)
      lots = minLot;


   if(lots > maxLot)
      lots = maxLot;


   return NormalizeVolume(
      lots
   );
}


//+------------------------------------------------------------------+
//| NORMALIZE VOLUME                                                 |
//+------------------------------------------------------------------+
double NormalizeVolume(
   double lots
)
{
   double step =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );


   int digits = 2;


   if(step >= 1.0)
      digits = 0;

   else if(step >= 0.1)
      digits = 1;

   else if(step >= 0.01)
      digits = 2;

   else if(step >= 0.001)
      digits = 3;

   else
      digits = 4;


   return NormalizeDouble(
      lots,
      digits
   );
}


//+------------------------------------------------------------------+
//| VALIDATE STOPS                                                   |
//+------------------------------------------------------------------+
bool ValidateStops(
   ENUM_ORDER_TYPE orderType,
   double entry,
   double sl,
   double tp
)
{
   if(orderType == ORDER_TYPE_BUY)
   {
      if(sl >= entry)
         return false;

      if(tp <= entry)
         return false;
   }


   if(orderType == ORDER_TYPE_SELL)
   {
      if(sl <= entry)
         return false;

      if(tp >= entry)
         return false;
   }


   return true;
}


//+------------------------------------------------------------------+
//| MANAGE POSITION                                                  |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   for(
      int i =
         PositionsTotal() - 1;
      i >= 0;
      i--
   )
   {
      ulong ticket =
         PositionGetTicket(i);


      if(ticket == 0)
         continue;


      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );


      ulong magic =
         (ulong)PositionGetInteger(
            POSITION_MAGIC
         );


      if(
         symbol != _Symbol ||
         magic != MagicNumber
      )
         continue;


      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(
            POSITION_TYPE
         );


      double openPrice =
         PositionGetDouble(
            POSITION_PRICE_OPEN
         );


      double currentSL =
         PositionGetDouble(
            POSITION_SL
         );


      double currentTP =
         PositionGetDouble(
            POSITION_TP
         );


      double bid =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_BID
         );


      double ask =
         SymbolInfoDouble(
            _Symbol,
            SYMBOL_ASK
         );


      //============================================================
      // BUY MANAGEMENT
      //============================================================

      if(
         type ==
         POSITION_TYPE_BUY
      )
      {
         double profitPips =
            (
               bid -
               openPrice
            )
            /
            PipSize;


         //-------------------------
         // Break-even
         //-------------------------

         if(
            UseBreakEven &&
            profitPips >=
            BreakEvenTriggerPips
         )
         {
            double newSL =
               NormalizeDouble(
                  openPrice +
                  BreakEvenLockPips *
                  PipSize,
                  _Digits
               );


            if(
               currentSL == 0 ||
               currentSL <
               newSL
            )
            {
               if(
                  trade.PositionModify(
                     ticket,
                     newSL,
                     currentTP
                  )
               )
               {
                  currentSL =
                     newSL;
               }
            }
         }


         //-------------------------
         // Trailing
         //-------------------------

         if(
            UseTrailingStop &&
            profitPips >=
            TrailingStartPips
         )
         {
            double trailSL =
               NormalizeDouble(
                  bid -
                  TrailingDistancePips *
                  PipSize,
                  _Digits
               );


            if(
               trailSL >
               openPrice
               &&
               (
                  currentSL == 0 ||
                  trailSL >
                  currentSL
               )
            )
            {
               trade.PositionModify(
                  ticket,
                  trailSL,
                  currentTP
               );
            }
         }
      }


      //============================================================
      // SELL MANAGEMENT
      //============================================================

      else if(
         type ==
         POSITION_TYPE_SELL
      )
      {
         double profitPips =
            (
               openPrice -
               ask
            )
            /
            PipSize;


         //-------------------------
         // Break-even
         //-------------------------

         if(
            UseBreakEven &&
            profitPips >=
            BreakEvenTriggerPips
         )
         {
            double newSL =
               NormalizeDouble(
                  openPrice -
                  BreakEvenLockPips *
                  PipSize,
                  _Digits
               );


            if(
               currentSL == 0 ||
               currentSL >
               newSL
            )
            {
               if(
                  trade.PositionModify(
                     ticket,
                     newSL,
                     currentTP
                  )
               )
               {
                  currentSL =
                     newSL;
               }
            }
         }


         //-------------------------
         // Trailing
         //-------------------------

         if(
            UseTrailingStop &&
            profitPips >=
            TrailingStartPips
         )
         {
            double trailSL =
               NormalizeDouble(
                  ask +
                  TrailingDistancePips *
                  PipSize,
                  _Digits
               );


            if(
               trailSL <
               openPrice
               &&
               (
                  currentSL == 0 ||
                  trailSL <
                  currentSL
               )
            )
            {
               trade.PositionModify(
                  ticket,
                  trailSL,
                  currentTP
               );
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//| OPEN POSITION CHECK                                              |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(
      int i =
         PositionsTotal()-1;
      i >= 0;
      i--
   )
   {
      ulong ticket =
         PositionGetTicket(i);


      if(ticket == 0)
         continue;


      string symbol =
         PositionGetString(
            POSITION_SYMBOL
         );


      ulong magic =
         (ulong)PositionGetInteger(
            POSITION_MAGIC
         );


      if(
         symbol == _Symbol &&
         magic == MagicNumber
      )
      {
         return true;
      }
   }


   return false;
}


//+------------------------------------------------------------------+
//| SPREAD FILTER                                                    |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   double spread =
      CurrentSpreadPips();


   if(
      spread >
      MaxSpreadPips
   )
   {
      Print(
         "Entry blocked | Spread=",
         DoubleToString(
            spread,
            1
         ),
         " pips"
      );


      return false;
   }


   return true;
}


//+------------------------------------------------------------------+
//| MINIMUM TIME BETWEEN TRADES                                      |
//+------------------------------------------------------------------+
bool EnoughTimeSinceLastTrade()
{
   if(lastTradeTime == 0)
      return true;


   long elapsedSeconds =
      TimeCurrent() -
      lastTradeTime;


   if(
      elapsedSeconds <
      MinMinutesBetweenTrades *
      60
   )
   {
      return false;
   }


   return true;
}


//+------------------------------------------------------------------+
//| NEW BAR                                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBar =
      iTime(
         _Symbol,
         EntryTF,
         0
      );


   if(currentBar <= 0)
      return false;


   if(
      currentBar !=
      lastBar
   )
   {
      lastBar =
         currentBar;


      return true;
   }


   return false;
}


//+------------------------------------------------------------------+
//| DAILY PROTECTION                                                 |
//+------------------------------------------------------------------+
bool DailyTradingAllowed()
{
   //-------------------------
   // Trades/day
   //-------------------------

   if(
      dailyTrades >=
      MaxTradesPerDay
   )
   {
      Print(
         "Trading stopped: max trades reached."
      );


      return false;
   }


   //-------------------------
   // Losses/day
   //-------------------------

   if(
      dailyLosses >=
      MaxLossesPerDay
   )
   {
      Print(
         "Trading stopped: max daily losses reached."
      );


      return false;
   }


   //-------------------------
   // Daily drawdown
   //-------------------------

   if(
      dayStartBalance >
      0
   )
   {
      double equity =
         AccountInfoDouble(
            ACCOUNT_EQUITY
         );


      double drawdown =
         (
            dayStartBalance -
            equity
         )
         /
         dayStartBalance
         *
         100.0;


      if(
         drawdown >=
         MaxDailyDrawdownPercent
      )
      {
         Print(
            "Trading stopped: daily DD = ",
            DoubleToString(
               drawdown,
               2
            ),
            "%"
         );


         return false;
      }
   }


   return true;
}


//+------------------------------------------------------------------+
//| COUNT DAILY LOSSES                                               |
//+------------------------------------------------------------------+
void UpdateDailyLosses()
{
   dailyLosses = 0;


   datetime dayStart =
      StringToTime(
         TimeToString(
            TimeCurrent(),
            TIME_DATE
         )
      );


   if(
      !HistorySelect(
         dayStart,
         TimeCurrent()
      )
   )
      return;


   int totalDeals =
      HistoryDealsTotal();


   for(
      int i = 0;
      i < totalDeals;
      i++
   )
   {
      ulong dealTicket =
         HistoryDealGetTicket(i);


      if(dealTicket == 0)
         continue;


      string symbol =
         HistoryDealGetString(
            dealTicket,
            DEAL_SYMBOL
         );


      ulong magic =
         (ulong)HistoryDealGetInteger(
            dealTicket,
            DEAL_MAGIC
         );


      if(
         symbol != _Symbol ||
         magic != MagicNumber
      )
         continue;


      ENUM_DEAL_ENTRY entry =
         (ENUM_DEAL_ENTRY)
         HistoryDealGetInteger(
            dealTicket,
            DEAL_ENTRY
         );


      if(
         entry !=
         DEAL_ENTRY_OUT
      )
         continue;


      double profit =
         HistoryDealGetDouble(
            dealTicket,
            DEAL_PROFIT
         );


      double commission =
         HistoryDealGetDouble(
            dealTicket,
            DEAL_COMMISSION
         );


      double swap =
         HistoryDealGetDouble(
            dealTicket,
            DEAL_SWAP
         );


      double netResult =
         profit +
         commission +
         swap;


      if(netResult < 0)
         dailyLosses++;
   }
}


//+------------------------------------------------------------------+
//| NEW DAY CHECK                                                    |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime now;

   TimeToStruct(
      TimeCurrent(),
      now
   );


   if(
      now.day   != storedDay   ||
      now.mon   != storedMonth ||
      now.year  != storedYear
   )
   {
      ResetDailyStats();
   }
}


//+------------------------------------------------------------------+
//| RESET DAILY STATS                                                |
//+------------------------------------------------------------------+
void ResetDailyStats()
{
   MqlDateTime now;

   TimeToStruct(
      TimeCurrent(),
      now
   );


   storedDay =
      now.day;


   storedMonth =
      now.mon;


   storedYear =
      now.year;


   dayStartBalance =
      AccountInfoDouble(
         ACCOUNT_BALANCE
      );


   dailyTrades =
      0;


   dailyLosses =
      0;


   Print(
      "New trading day | Balance=$",
      DoubleToString(
         dayStartBalance,
         2
      )
   );
}
//+------------------------------------------------------------------+