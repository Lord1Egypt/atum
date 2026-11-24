//+------------------------------------------------------------------+
//|                                   BollingerWPRReversalEA.mq5     |
//|                    Bollinger Bands and Williams %R reversal EA   |
//|                                                    Version 1.31  |
//+------------------------------------------------------------------+
#property copyright "Damian Acri <damianacridev@gmail.com>"
#property link      ""
#property version   "1.31"

//--- Description
#property description "Bollinger Bands and Williams %R reversal EA"
#property description "Supported currencies: GBP/CAD, EUR/SGD"
#property description "Timeframe: M1"

//+------------------------------------------------------------------+
//| Include files                                                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Class instances                                                   |
//+------------------------------------------------------------------+
CTrade         trade;           // For buy, sell, modify operations
CPositionInfo  positionInfo;    // For getting position information
COrderInfo     orderInfo;       // For getting order information

//+------------------------------------------------------------------+
//| Input parameters                                                   |
//+------------------------------------------------------------------+
input double   Lots = 0.1;                          // Lots
input bool     CompoundInterestSwitch = false;      // Risk in basis points instead of fixed lots
input int      Risk = 100;                          // Risk (basis points)
input bool     ParameterSwitching = true;           // Use different settings for different pairs
input int      Volatility = 5;                      // Volatility (WPR threshold)
input int      StopLoss = 500;                      // Stop Loss (points)
input int      TakeProfit = 500;                    // Take Profit (points)
input int      PointDifferentialLimit = 50;         // Max Spread Allowed (points)
input bool     DisplaySwitch = true;                // Display Switch
input long     MagicNumber = 123456;                // Magic Number
input string   CommentName = "BollingerWPRReversalEA"; // Comment Name

//--- Time inputs for tester (to match broker time to GMT)
input int      HourTimeOne = 20;                    // Start Hour 1
input int      EndHourTimeOne = 24;                 // End Hour 1
input int      HourTimeTwo = 0;                     // Start Hour 2
input int      EndHourTimeTwo = 3;                  // End Hour 2

//+------------------------------------------------------------------+
//| Global variables (not input - internal use)                       |
//+------------------------------------------------------------------+
// Variables to store values that may change based on currency pair
int      VolatilityThreshold;
int      StopLossPoints;
int      TakeProfitPoints;
int      MaxBandwidth;
int      MinBandwidth;

// Lot size calculation variables
double   CalculatedLotSize;
double   AccountBalanceDivisor = 1000000;
int      MaxSlippage = 30;
bool     TradingAllowed = false;

// Indicator handles
int      HandleBollingerBand;
int      HandleWPR;

// Time variables
datetime LastBarTime;
datetime LastSignalTime;

// Position counting variables
int      BuyPositionCount = 0;
int      SellPositionCount = 0;

// Position information variables
double   BuyLots = 0;
double   SellLots = 0;
double   BuyPrice = 0;
double   SellPrice = 0;
double   BuyStopLoss = 0;
double   SellStopLoss = 0;

// Profit variables for panel
double   TotalBuyProfit = 0;
double   TotalSellProfit = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set the expert magic number
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Remove grid from chart
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   
   // Parameter switching - use different settings for different pairs
   if(ParameterSwitching)
   {
      // Check if symbol is NOT CHF/SGD and NOT GBP/SGD
      if(StringFind(_Symbol, "CHFSGD") < 0 && StringFind(_Symbol, "GBPSGD") < 0)
      {
         // Use user-defined values as default
         VolatilityThreshold = Volatility;
         StopLossPoints = StopLoss;
         TakeProfitPoints = TakeProfit;
         MaxBandwidth = 1000;
         MinBandwidth = 150;
      }
      else
      {
         // Special case for CHF/SGD and GBP/SGD - will be overwritten below if needed
         VolatilityThreshold = Volatility;
         StopLossPoints = StopLoss;
         TakeProfitPoints = TakeProfit;
         MaxBandwidth = 1000;
         MinBandwidth = 150;
      }
      
      // GBP/CAD specific settings
      if(StringFind(_Symbol, "GBPCAD") >= 0)
      {
         VolatilityThreshold = 110;
         StopLossPoints = 500;
         TakeProfitPoints = 500;
         MaxBandwidth = 1000;
         MinBandwidth = 150;
      }
      // EUR/SGD specific settings
      else if(StringFind(_Symbol, "EURSGD") >= 0)
      {
         VolatilityThreshold = 5;
         StopLossPoints = 300;
         TakeProfitPoints = 300;
         MaxBandwidth = 600;
         MinBandwidth = 100;
      }
      // GBP/CHF specific settings
      else if(StringFind(_Symbol, "GBPCHF") >= 0)
      {
         VolatilityThreshold = 5;
         StopLossPoints = 400;
         TakeProfitPoints = 400;
         MaxBandwidth = 800;
         MinBandwidth = 120;
      }
      // CHF/SGD specific settings
      else if(StringFind(_Symbol, "CHFSGD") >= 0)
      {
         VolatilityThreshold = 5;
         StopLossPoints = 250;
         TakeProfitPoints = 250;
         MaxBandwidth = 500;
         MinBandwidth = 80;
      }
      // GBP/SGD specific settings
      else if(StringFind(_Symbol, "GBPSGD") >= 0)
      {
         VolatilityThreshold = 5;
         StopLossPoints = 350;
         TakeProfitPoints = 350;
         MaxBandwidth = 700;
         MinBandwidth = 100;
      }
   }
   else
   {
      // Use user-defined values
      VolatilityThreshold = Volatility;
      StopLossPoints = StopLoss;
      TakeProfitPoints = TakeProfit;
      MaxBandwidth = 1000;
      MinBandwidth = 150;
   }
   
   // Initialize Bollinger Bands indicator handle
   // Parameters: symbol, period, bb_period, bb_shift, bb_deviation, applied_price
   HandleBollingerBand = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   
   // Initialize Williams Percent Range indicator handle
   // Parameters: symbol, period, wpr_period
   HandleWPR = iWPR(_Symbol, PERIOD_CURRENT, 14);
   
   // Create display panel if switch is true
   if(DisplaySwitch)
   {
      CreateDisplayPanel();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Delete all objects starting with "TB"
   ObjectsDeleteAll(0, "TB");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Local variables for indicators
   double UpperBollingerBand;
   double LowerBollingerBand;
   double CurrentWPR;
   double IndicatorBuffer[];
   
   // Set array as series (most recent first)
   ArraySetAsSeries(IndicatorBuffer, true);
   
   // Copy Upper Bollinger Band value
   // Buffer 1 = Upper Band, Buffer 2 = Lower Band, Buffer 0 = Middle
   CopyBuffer(HandleBollingerBand, 1, 0, 1, IndicatorBuffer);
   UpperBollingerBand = IndicatorBuffer[0];
   
   // Copy Lower Bollinger Band value
   CopyBuffer(HandleBollingerBand, 2, 0, 1, IndicatorBuffer);
   LowerBollingerBand = IndicatorBuffer[0];
   
   // Copy Williams %R value
   CopyBuffer(HandleWPR, 0, 0, 1, IndicatorBuffer);
   CurrentWPR = IndicatorBuffer[0];
   
   // Check if spread is acceptable
   long currentSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpread <= PointDifferentialLimit)
   {
      TradingAllowed = true;
   }
   else
   {
      TradingAllowed = false;
   }
   
   // Update last bar time
   LastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   // Calculate lot size based on compound interest switch
   if(CompoundInterestSwitch)
   {
      // Risk-based lot calculation
      double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      CalculatedLotSize = NormalizeDouble((accountEquity * Risk) / AccountBalanceDivisor, 2);
   }
   else
   {
      // Fixed lot size
      CalculatedLotSize = Lots;
   }
   
   // Update positions (get current position info)
   UpdatePositions();
   
   // Get broker time and GMT time
   MqlDateTime brokerTime;
   TimeCurrent(brokerTime);
   
   MqlDateTime gmtTime;
   TimeGMT(gmtTime);
   
   // Get ask and bid prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Get point value
   double point = _Point;
   
   //+------------------------------------------------------------------+
   //| Trading Logic - Tester Mode                                      |
   //+------------------------------------------------------------------+
   if(MQLInfoInteger(MQL_TESTER) == true)
   {
      // In tester, use broker time with user-defined hours
      if((brokerTime.hour >= HourTimeOne && brokerTime.hour < EndHourTimeOne) ||
         (brokerTime.hour >= HourTimeTwo && brokerTime.hour < EndHourTimeTwo))
      {
         // Check Bollinger Band width
         double bandWidth = (UpperBollingerBand - LowerBollingerBand) / point;
         
         if(bandWidth < MaxBandwidth)
         {
            if(bandWidth > MinBandwidth)
            {
               // Check if no positions are open
               if((SellPositionCount + BuyPositionCount) < 1)
               {
                  if(TradingAllowed)
                  {
                     //--- BUY Logic
                     if(CurrentWPR < (-100 + VolatilityThreshold))
                     {
                        if(LastSignalTime != LastBarTime)
                        {
                           double margin;
                           if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, CalculatedLotSize, ask, margin))
                           {
                              if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin)
                              {
                                 double sl = ask - StopLossPoints * point;
                                 
                                 trade.Buy(CalculatedLotSize, _Symbol, ask, sl, 0, CommentName);
                                 LastSignalTime = LastBarTime;
                              }
                           }
                        }
                     }
                     
                     //--- SELL Logic
                     if(CurrentWPR > -VolatilityThreshold)
                     {
                        if(LastSignalTime != LastBarTime)
                        {
                           double margin;
                           if(OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, CalculatedLotSize, bid, margin))
                           {
                              if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin)
                              {
                                 double sl = bid + StopLossPoints * point;
                                 
                                 trade.Sell(CalculatedLotSize, _Symbol, bid, sl, 0, CommentName);
                                 LastSignalTime = LastBarTime;
                              }
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }
   //+------------------------------------------------------------------+
   //| Trading Logic - Live Mode                                        |
   //+------------------------------------------------------------------+
   else
   {
      // In live mode, use GMT time (18:00 to 01:00 GMT)
      if((gmtTime.hour >= 18 && gmtTime.hour < 24) ||
         (gmtTime.hour >= 0 && gmtTime.hour < 1))
      {
         // Check Bollinger Band width
         double bandWidth = (UpperBollingerBand - LowerBollingerBand) / point;
         
         if(bandWidth < MaxBandwidth)
         {
            if(bandWidth > MinBandwidth)
            {
               // Check if no positions are open
               if((SellPositionCount + BuyPositionCount) < 1)
               {
                  if(TradingAllowed)
                  {
                     //--- BUY Logic
                     if(CurrentWPR < (-100 + VolatilityThreshold))
                     {
                        if(LastSignalTime != LastBarTime)
                        {
                           double margin;
                           if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, CalculatedLotSize, ask, margin))
                           {
                              if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin)
                              {
                                 double sl = ask - StopLossPoints * point;
                                 
                                 trade.Buy(CalculatedLotSize, _Symbol, ask, sl, 0, CommentName);
                                 LastSignalTime = LastBarTime;
                              }
                           }
                        }
                     }
                     
                     //--- SELL Logic
                     if(CurrentWPR > -VolatilityThreshold)
                     {
                        if(LastSignalTime != LastBarTime)
                        {
                           double margin;
                           if(OrderCalcMargin(ORDER_TYPE_SELL, _Symbol, CalculatedLotSize, bid, margin))
                           {
                              if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin)
                              {
                                 double sl = bid + StopLossPoints * point;
                                 
                                 trade.Sell(CalculatedLotSize, _Symbol, bid, sl, 0, CommentName);
                                 LastSignalTime = LastBarTime;
                              }
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close BUY positions based on WPR                                 |
   //+------------------------------------------------------------------+
   if(BuyPositionCount > 0 && TradingAllowed && CurrentWPR > -VolatilityThreshold)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i))
         {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            {
               if(positionInfo.PositionType() == POSITION_TYPE_BUY)
               {
                  trade.PositionClose(positionInfo.Ticket(), MaxSlippage);
               }
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close SELL positions based on WPR                                |
   //+------------------------------------------------------------------+
   if(SellPositionCount > 0 && TradingAllowed && CurrentWPR < (-100 + VolatilityThreshold))
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i))
         {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            {
               if(positionInfo.PositionType() == POSITION_TYPE_SELL)
               {
                  trade.PositionClose(positionInfo.Ticket(), MaxSlippage);
               }
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close BUY positions based on Take Profit                         |
   //+------------------------------------------------------------------+
   if(BuyPositionCount > 0 && TradingAllowed && (bid - BuyPrice) > (TakeProfitPoints * point))
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i))
         {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            {
               if(positionInfo.PositionType() == POSITION_TYPE_BUY)
               {
                  trade.PositionClose(positionInfo.Ticket(), MaxSlippage);
               }
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close SELL positions based on Take Profit                        |
   //+------------------------------------------------------------------+
   if(SellPositionCount > 0 && TradingAllowed && (SellPrice - ask) > (TakeProfitPoints * point))
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(positionInfo.SelectByIndex(i))
         {
            if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
            {
               if(positionInfo.PositionType() == POSITION_TYPE_SELL)
               {
                  trade.PositionClose(positionInfo.Ticket(), MaxSlippage);
               }
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Update panel at the end of OnTick                                |
   //+------------------------------------------------------------------+
   if(DisplaySwitch)
   {
      UpdatePositions();
      UpdatePanelData();
   }
}

//+------------------------------------------------------------------+
//| Update positions function                                         |
//+------------------------------------------------------------------+
int UpdatePositions()
{
   // Reset all values to zero at start
   BuyPositionCount = 0;
   SellPositionCount = 0;
   BuyLots = 0;
   SellLots = 0;
   BuyPrice = 0;
   SellPrice = 0;
   BuyStopLoss = 0;
   SellStopLoss = 0;
   TotalBuyProfit = 0;
   TotalSellProfit = 0;
   
   // Loop through all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         ulong ticket = positionInfo.Ticket();
         
         // Check if it's our position
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            if(positionInfo.PositionType() == POSITION_TYPE_SELL)
            {
               SellPositionCount++;
               SellLots += positionInfo.Volume();
               TotalSellProfit += positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();
               SellPrice = positionInfo.PriceOpen();
               SellStopLoss = positionInfo.StopLoss();
            }
            else if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               BuyPositionCount++;
               BuyLots += positionInfo.Volume();
               TotalBuyProfit += positionInfo.Profit() + positionInfo.Commission() + positionInfo.Swap();
               BuyPrice = positionInfo.PriceOpen();
               BuyStopLoss = positionInfo.StopLoss();
            }
         }
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Create display panel function                                     |
//+------------------------------------------------------------------+
void CreateDisplayPanel()
{
   // Panel variables
   int panelX = 10;
   int panelY = 20;
   int panelWidth = 120;
   int panelHeight = 50;
   int spacing = 5;
   int fontSize = 10;
   string fontName = "Arial";
   
   //--- First box (Sell/Buy Lots)
   ObjectCreate(0, "TB_Box1", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_XDISTANCE, panelX);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_YDISTANCE, panelY);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_BGCOLOR, clrDimGray);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "TB_Box1", OBJPROP_COLOR, clrWhite);
   
   // Sell lots label
   ObjectCreate(0, "TB_SellLotsLabel", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_SellLotsLabel", OBJPROP_XDISTANCE, panelX + 10);
   ObjectSetInteger(0, "TB_SellLotsLabel", OBJPROP_YDISTANCE, panelY + 10);
   ObjectSetString(0, "TB_SellLotsLabel", OBJPROP_TEXT, "Sell Lot: 0");
   ObjectSetInteger(0, "TB_SellLotsLabel", OBJPROP_COLOR, clrGoldenrod);
   ObjectSetInteger(0, "TB_SellLotsLabel", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_SellLotsLabel", OBJPROP_FONT, fontName);
   
   // Buy lots label
   ObjectCreate(0, "TB_BuyLotsLabel", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_BuyLotsLabel", OBJPROP_XDISTANCE, panelX + 10);
   ObjectSetInteger(0, "TB_BuyLotsLabel", OBJPROP_YDISTANCE, panelY + 30);
   ObjectSetString(0, "TB_BuyLotsLabel", OBJPROP_TEXT, "Buy Lot: 0");
   ObjectSetInteger(0, "TB_BuyLotsLabel", OBJPROP_COLOR, clrGoldenrod);
   ObjectSetInteger(0, "TB_BuyLotsLabel", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_BuyLotsLabel", OBJPROP_FONT, fontName);
   
   //--- Second box (Sell/Buy Profit)
   panelX = panelX + panelWidth + spacing;
   
   ObjectCreate(0, "TB_Box2", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_XDISTANCE, panelX);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_YDISTANCE, panelY);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_BGCOLOR, clrDimGray);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "TB_Box2", OBJPROP_COLOR, clrWhite);
   
   // Sell profit label (left part)
   ObjectCreate(0, "TB_SellProfitLabel", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_SellProfitLabel", OBJPROP_XDISTANCE, panelX + 10);
   ObjectSetInteger(0, "TB_SellProfitLabel", OBJPROP_YDISTANCE, panelY + 10);
   ObjectSetString(0, "TB_SellProfitLabel", OBJPROP_TEXT, "Sell Profit:");
   ObjectSetInteger(0, "TB_SellProfitLabel", OBJPROP_COLOR, clrDeepSkyBlue);
   ObjectSetInteger(0, "TB_SellProfitLabel", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_SellProfitLabel", OBJPROP_FONT, fontName);
   
   // Sell profit value (right part)
   ObjectCreate(0, "TB_SellProfitValue", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_SellProfitValue", OBJPROP_XDISTANCE, panelX + panelWidth - 10);
   ObjectSetInteger(0, "TB_SellProfitValue", OBJPROP_YDISTANCE, panelY + 10);
   ObjectSetString(0, "TB_SellProfitValue", OBJPROP_TEXT, "0.00");
   ObjectSetInteger(0, "TB_SellProfitValue", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, "TB_SellProfitValue", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_SellProfitValue", OBJPROP_FONT, fontName);
   ObjectSetInteger(0, "TB_SellProfitValue", OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   
   // Buy profit label (left part)
   ObjectCreate(0, "TB_BuyProfitLabel", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_BuyProfitLabel", OBJPROP_XDISTANCE, panelX + 10);
   ObjectSetInteger(0, "TB_BuyProfitLabel", OBJPROP_YDISTANCE, panelY + 30);
   ObjectSetString(0, "TB_BuyProfitLabel", OBJPROP_TEXT, "Buy Profit:");
   ObjectSetInteger(0, "TB_BuyProfitLabel", OBJPROP_COLOR, clrDeepSkyBlue);
   ObjectSetInteger(0, "TB_BuyProfitLabel", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_BuyProfitLabel", OBJPROP_FONT, fontName);
   
   // Buy profit value (right part)
   ObjectCreate(0, "TB_BuyProfitValue", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_BuyProfitValue", OBJPROP_XDISTANCE, panelX + panelWidth - 10);
   ObjectSetInteger(0, "TB_BuyProfitValue", OBJPROP_YDISTANCE, panelY + 30);
   ObjectSetString(0, "TB_BuyProfitValue", OBJPROP_TEXT, "0.00");
   ObjectSetInteger(0, "TB_BuyProfitValue", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, "TB_BuyProfitValue", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_BuyProfitValue", OBJPROP_FONT, fontName);
   ObjectSetInteger(0, "TB_BuyProfitValue", OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   
   //--- Third box (Spread)
   panelX = panelX + panelWidth + spacing;
   
   ObjectCreate(0, "TB_Box3", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_XDISTANCE, panelX);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_YDISTANCE, panelY);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_XSIZE, panelWidth);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_YSIZE, panelHeight);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_BGCOLOR, clrDimGray);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "TB_Box3", OBJPROP_COLOR, clrWhite);
   
   // Spread label
   ObjectCreate(0, "TB_SpreadLabel", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_SpreadLabel", OBJPROP_XDISTANCE, panelX + 10);
   ObjectSetInteger(0, "TB_SpreadLabel", OBJPROP_YDISTANCE, panelY + 10);
   ObjectSetString(0, "TB_SpreadLabel", OBJPROP_TEXT, "Spread:");
   ObjectSetInteger(0, "TB_SpreadLabel", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "TB_SpreadLabel", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_SpreadLabel", OBJPROP_FONT, fontName);
   
   // Spread value
   ObjectCreate(0, "TB_SpreadValue", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "TB_SpreadValue", OBJPROP_XDISTANCE, panelX + 10);
   ObjectSetInteger(0, "TB_SpreadValue", OBJPROP_YDISTANCE, panelY + 30);
   ObjectSetString(0, "TB_SpreadValue", OBJPROP_TEXT, IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   ObjectSetInteger(0, "TB_SpreadValue", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "TB_SpreadValue", OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, "TB_SpreadValue", OBJPROP_FONT, fontName);
}

//+------------------------------------------------------------------+
//| Update panel data function                                        |
//+------------------------------------------------------------------+
void UpdatePanelData()
{
   double totalBuyLots = 0;
   double totalSellLots = 0;
   
   // Loop through positions to get lot totals
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i))
      {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber)
         {
            if(positionInfo.PositionType() == POSITION_TYPE_BUY)
            {
               totalBuyLots += positionInfo.Volume();
            }
            else if(positionInfo.PositionType() == POSITION_TYPE_SELL)
            {
               totalSellLots += positionInfo.Volume();
            }
         }
      }
   }
   
   // Update lot labels
   ObjectSetString(0, "TB_SellLotsLabel", OBJPROP_TEXT, "Sell Lot: " + DoubleToString(totalSellLots, 2));
   ObjectSetString(0, "TB_BuyLotsLabel", OBJPROP_TEXT, "Buy Lot: " + DoubleToString(totalBuyLots, 2));
   
   // Update profit displays
   UpdateProfitDisplay("TB_SellProfitValue", TotalSellProfit);
   UpdateProfitDisplay("TB_BuyProfitValue", TotalBuyProfit);
   
   // Update spread value
   ObjectSetString(0, "TB_SpreadValue", OBJPROP_TEXT, IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
}

//+------------------------------------------------------------------+
//| Update profit display function                                    |
//+------------------------------------------------------------------+
void UpdateProfitDisplay(string objectName, double profitValue)
{
   color textColor;
   
   // Set color based on profit
   if(profitValue >= 0)
   {
      textColor = clrLime;
   }
   else
   {
      textColor = clrRed;
   }
   
   // Convert profit to string
   string textValue = DoubleToString(profitValue, 2);
   
   // Update object
   ObjectSetString(0, objectName, OBJPROP_TEXT, textValue);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR, textColor);
}
//+------------------------------------------------------------------+
