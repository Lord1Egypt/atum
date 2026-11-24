//+------------------------------------------------------------------+
//|                          XAUUSDPreviousDayBreakoutEA.mq5        |
//|                  Previous-day high/low breakout for XAUUSD      |
//|                       Research implementation                   |
//+------------------------------------------------------------------+
#property copyright "Damian Acri <damianacridev@gmail.com>"
#property link      ""
#property version   "1.21"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_RISK_TYPE
{
   RISK_FIXED_LOT   = 0,
   RISK_PERCENTAGE  = 1
};

enum ENUM_ATR_TF
{
   ATR_TF_M15 = PERIOD_M15,
   ATR_TF_M30 = PERIOD_M30,
   ATR_TF_H1  = PERIOD_H1,
   ATR_TF_H4  = PERIOD_H4,
   ATR_TF_D1  = PERIOD_D1
};

// News separator helper
enum ENUM_NEWS_SEPARATOR
{
   NEWS_COMMA = 0,   // ","
   NEWS_SEMICOLON = 1 // ";"
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - EXPERT SETTINGS                                |
//+------------------------------------------------------------------+
input group "=== Expert Settings ==="
input long                 InpMagicNumber = 1517;                 // Magic Number
input int                  InpDeviationPoints = 30;               // Slippage/Deviation (points)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - RISK MANAGEMENT                                |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input ENUM_RISK_TYPE       InpRiskType = RISK_FIXED_LOT;          // Type of Risk
input double               InpLotSize = 0.10;                     // Lot Size (if Fixed)
input double               InpRiskPercent = 2.0;                  // Risk % for Auto Lot
input int                  InpMaxTradesPerDay = 1;                // Max FILLED trades/day (0 = unlimited)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - BREAKOUT SETTINGS                              |
//+------------------------------------------------------------------+
input group "=== Breakout Settings ==="
input int                  InpTP = 1000;                          // Take Profit (points) if ATR disabled
input int                  InpSL = 1000;                          // Stop Loss (points) if ATR disabled
input int                  InpBuffer = 10;                        // Entry Buffer from High/Low (points)
input bool                 InpCancelOpposite = true;              // Cancel Opposite Order on Fill
input int                  InpMinEntryGapFromPrice = 50;          // Extra min gap from current price (points)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - TRAILING                                       |
//+------------------------------------------------------------------+
input group "=== Trailing Stop ==="
input bool                 InpUseTrailing = true;                 // Use trailing stop
input int                  InpTrailingStart = 200;                // Trailing Start (points)
input int                  InpTrailingDistance = 100;             // Trailing Distance (points)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - FILTERS                                        |
//+------------------------------------------------------------------+
input group "=== Filters ==="
input int                  InpMaxSpreadPoints = 500;              // Max allowed spread (points)
input bool                 InpUseRangeFilter = true;              // Filter by previous day range
input int                  InpMinPrevDayRangePoints = 300;        // Min prev day range (points)
input int                  InpMaxPrevDayRangePoints = 8000;       // Max prev day range (points)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - ATR (optional)                                 |
//+------------------------------------------------------------------+
input group "=== ATR SL/TP (Optional) ==="
input bool                 InpUseATR_SLTP = false;                // Use ATR-based SL/TP
input ENUM_ATR_TF          InpATR_Timeframe = ATR_TF_H1;           // ATR timeframe
input int                  InpATR_Period = 14;                    // ATR period
input double               InpATR_SL_Mult = 2.0;                  // SL = ATR * Mult
input double               InpATR_TP_Mult = 2.0;                  // TP = ATR * Mult
input double               InpATR_MinPoints = 200;                // Min ATR (points) to allow trading (0=off)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - TIME FILTERS                                   |
//+------------------------------------------------------------------+
input group "=== Time Filters ==="
input bool                 InpUseTimeFilter = false;              // Use Time Filter
input int                  InpStartHour = 2;                      // Start Hour (Server Time)
input int                  InpEndHour = 22;                       // End Hour (Server Time)
input bool                 InpTradeMonday = true;                 // Trade Monday
input bool                 InpTradeTuesday = true;                // Trade Tuesday
input bool                 InpTradeWednesday = true;              // Trade Wednesday
input bool                 InpTradeThursday = true;               // Trade Thursday
input bool                 InpTradeFriday = true;                 // Trade Friday

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - NEWS FILTER (NEW)                              |
//+------------------------------------------------------------------+
input group "=== News Filter ==="
input bool                 InpUseNewsFilter = true;               // Enable News Filter
input ENUM_NEWS_SEPARATOR  InpNewsSeparator = NEWS_COMMA;         // Separator for lists
input string               InpNewsKeywords = "CPI,FOMC,NFP,PCE,Interest Rate"; // Keywords
input string               InpNewsCurrencies = "USD";             // Currencies (e.g. USD,EUR)
input int                  InpNewsMinutesBefore = 30;             // Block minutes BEFORE event
input int                  InpNewsMinutesAfter  = 30;             // Block minutes AFTER event
input int                  InpNewsLookForwardDays = 2;            // Calendar scan forward days
input bool                 InpNewsUseFallbackWindow = true;       // If calendar unavailable, use fixed window
input int                  InpFallbackStartHour = 13;             // Fallback start hour (server)
input int                  InpFallbackEndHour   = 16;             // Fallback end hour (server)
input bool                 InpNewsDebug = false;                  // Print debug info

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade trade;

double   g_previousDayHigh   = 0.0;
double   g_previousDayLow    = 0.0;
datetime g_lastDayProcessed  = 0;

bool     g_ordersPlacedToday = false;

// count FILLED trades per day
int      g_tradesFilledToday  = 0;
datetime g_lastTradeCountDate = 0;

// ATR
int      g_atrHandle = INVALID_HANDLE;

// news debug throttle
datetime g_lastNewsDebugDay = 0;

//+------------------------------------------------------------------+
//| Forward declarations                                              |
//+------------------------------------------------------------------+
void     ResetDailyCounterIfNeeded();
bool     IsTradingDay();
bool     IsWithinTradingHours();
bool     IsMarketOpen();
bool     GetPreviousDayHighLow();
bool     HasOpenPosition();
void     ExecuteBreakoutStrategy();
void     PlaceBreakoutOrders();
void     CancelPendingOrders();
void     CheckAndCancelOppositeOrder();
void     ManageOpenPositions();
void     ApplyTrailingStop();
double   CalculateLotSize(double slDistancePrice);
double   NormalizeLot(double lot);
bool     HasSufficientMargin(double lotSize);
int      StopsLevelPoints();
int      FreezeLevelPoints();
bool     GetATRPoints(double &atrPoints);
bool     PassPrevDayRangeFilter();

// news
bool     IsNewsRestrictedNow();
int      SplitList(const string src, const ENUM_NEWS_SEPARATOR sep, string &outArr[]);

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   // Optional: only set filling if symbol supports it (avoid forcing IOC on brokers that reject)
   long filling = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE, filling))
   {
      // Use symbol default; don't force unless you want to
      // trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);
   }

   if(InpUseATR_SLTP)
   {
      g_atrHandle = iATR(_Symbol, (ENUM_TIMEFRAMES)InpATR_Timeframe, InpATR_Period);
      if(g_atrHandle == INVALID_HANDLE)
      {
         Print("ATR handle creation failed. Error: ", GetLastError());
         return INIT_FAILED;
      }
   }

   Print("=== XAUUSD Previous-Day Breakout EA v", (string)__FILE__, " Initialized ===");
   Print("Magic Number: ", InpMagicNumber);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   Print("=== XAUUSD Previous-Day Breakout EA Stopped ===");
}

//+------------------------------------------------------------------+
//| Trade transaction: count FILLED trades (deals)                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   // trans.deal contains the ticket of the newly added deal
   ulong deal_ticket = (ulong)trans.deal;
   if(deal_ticket == 0)
      return;

   if(!HistoryDealSelect(deal_ticket))
      return;

   string sym = (string)HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   if(sym != _Symbol)
      return;

   long magic = (long)HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(magic != InpMagicNumber)
      return;

   long entry = (long)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)  // cuenta solo entradas (apertura)
   {
      ResetDailyCounterIfNeeded();
      g_tradesFilledToday++;
      Print("Deal entry counted. Trades filled today: ", g_tradesFilledToday);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyCounterIfNeeded();

   // Always manage trailing even if restricted
   if(InpUseTrailing)
      ManageOpenPositions();

   // Max FILLED trades/day
   if(InpMaxTradesPerDay > 0 && g_tradesFilledToday >= InpMaxTradesPerDay)
      return;

   // Time/day filters
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

   if(!IsTradingDay())
      return;

   // News filter: do NOT place new orders during restriction
   if(IsNewsRestrictedNow())
      return;

   // Strategy
   ExecuteBreakoutStrategy();
}

//+------------------------------------------------------------------+
//| Breakout Strategy - Previous Day High/Low                         |
//+------------------------------------------------------------------+
void ExecuteBreakoutStrategy()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime currentDay = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));

   // New day
   if(currentDay != g_lastDayProcessed)
   {
      g_lastDayProcessed  = currentDay;
      g_ordersPlacedToday = false;

      // Refresh levels
      GetPreviousDayHighLow();

      // Cancel any leftover pendings from this EA
      CancelPendingOrders();
   }

   // If already in a position, don't place new pendings (prevents stacking exposure across days)
   if(HasOpenPosition())
   {
      if(InpCancelOpposite)
         CheckAndCancelOppositeOrder();
      return;
   }

   // Must pass market & filters
   if(!IsMarketOpen())
      return;

   if(!PassPrevDayRangeFilter())
      return;

   // News filter again (so even if called elsewhere it's safe)
   if(IsNewsRestrictedNow())
      return;

   // Place orders once per day
   if(!g_ordersPlacedToday && g_previousDayHigh > 0 && g_previousDayLow > 0)
      PlaceBreakoutOrders();

   // OCO cancel
   if(InpCancelOpposite)
      CheckAndCancelOppositeOrder();
}

//+------------------------------------------------------------------+
//| Get Previous Day High and Low                                     |
//+------------------------------------------------------------------+
bool GetPreviousDayHighLow()
{
   MqlRates dailyRates[];
   ArraySetAsSeries(dailyRates, true);

   if(CopyRates(_Symbol, PERIOD_D1, 0, 2, dailyRates) < 2)
   {
      Print("Error getting daily rates: ", GetLastError());
      return false;
   }

   g_previousDayHigh = dailyRates[1].high;
   g_previousDayLow  = dailyRates[1].low;

   Print("Previous Day High: ", g_previousDayHigh, " | Low: ", g_previousDayLow);
   return true;
}

//+------------------------------------------------------------------+
//| Range filter                                                      |
//+------------------------------------------------------------------+
bool PassPrevDayRangeFilter()
{
   if(!InpUseRangeFilter)
      return true;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(g_previousDayHigh <= 0 || g_previousDayLow <= 0 || point <= 0)
      return false;

   double rangePrice = g_previousDayHigh - g_previousDayLow;
   int rangePoints   = (int)MathRound(rangePrice / point);

   if(rangePoints < InpMinPrevDayRangePoints || rangePoints > InpMaxPrevDayRangePoints)
   {
      Print("Range filter blocked. Prev day range points: ", rangePoints);
      return false;
   }

   // ATR minimum filter (optional)
   if(InpUseATR_SLTP && InpATR_MinPoints > 0)
   {
      double atrPts = 0;
      if(GetATRPoints(atrPts))
      {
         if(atrPts < InpATR_MinPoints)
         {
            Print("ATR min filter blocked. ATR points: ", atrPts);
            return false;
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Place Breakout Orders (Buy Stop + Sell Stop)                      |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
{
   if(g_ordersPlacedToday) return;

   // News filter safety
   if(IsNewsRestrictedNow())
      return;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(point <= 0 || ask <= 0 || bid <= 0) return;

   // Spread filter
   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPoints > InpMaxSpreadPoints)
   {
      Print("Spread blocked: ", spreadPoints, " points");
      return;
   }

   // Broker constraints
   int stopsLevel  = StopsLevelPoints();
   int freezeLevel = FreezeLevelPoints();
   int minGapPts   = MathMax(InpMinEntryGapFromPrice, stopsLevel + 1);

   // Entry levels with buffer
   double buyStopPrice  = NormalizeDouble(g_previousDayHigh + InpBuffer * point, digits);
   double sellStopPrice = NormalizeDouble(g_previousDayLow  - InpBuffer * point, digits);

   // Ensure pendings are not too close to current price (and respect stops level)
   double minGapPrice = minGapPts * point;

   if(buyStopPrice <= ask + minGapPrice)
      buyStopPrice = NormalizeDouble(ask + minGapPrice, digits);

   if(sellStopPrice >= bid - minGapPrice)
      sellStopPrice = NormalizeDouble(bid - minGapPrice, digits);

   // Decide SL/TP distances
   double slDistPrice = InpSL * point;
   double tpDistPrice = InpTP * point;

   if(InpUseATR_SLTP)
   {
      double atrPts = 0;
      if(GetATRPoints(atrPts) && atrPts > 0)
      {
         slDistPrice = (atrPts * point) * InpATR_SL_Mult;
         tpDistPrice = (atrPts * point) * InpATR_TP_Mult;
      }
      else
      {
         Print("ATR read failed; fallback to fixed SL/TP points.");
      }
   }

   // SL/TP levels
   double buySL  = NormalizeDouble(buyStopPrice  - slDistPrice, digits);
   double buyTP  = NormalizeDouble(buyStopPrice  + tpDistPrice, digits);
   double sellSL = NormalizeDouble(sellStopPrice + slDistPrice, digits);
   double sellTP = NormalizeDouble(sellStopPrice - tpDistPrice, digits);

   // Ensure SL/TP respect stops level too (distance from entry)
   double minSLTPDist = (stopsLevel + 1) * point;

   if((buyStopPrice - buySL) < minSLTPDist)  buySL  = NormalizeDouble(buyStopPrice  - minSLTPDist, digits);
   if((buyTP - buyStopPrice) < minSLTPDist)  buyTP  = NormalizeDouble(buyStopPrice  + minSLTPDist, digits);

   if((sellSL - sellStopPrice) < minSLTPDist) sellSL = NormalizeDouble(sellStopPrice + minSLTPDist, digits);
   if((sellStopPrice - sellTP) < minSLTPDist) sellTP = NormalizeDouble(sellStopPrice - minSLTPDist, digits);

   // Lot size based on SL distance in price
   double lotSize = CalculateLotSize(slDistPrice);
   if(lotSize <= 0)
   {
      Print("Lot size <= 0. Abort.");
      return;
   }

   // Margin check
   if(!HasSufficientMargin(lotSize))
   {
      Print("Skipping orders - insufficient margin for lot size: ", lotSize);
      return;
   }

   bool buyPlaced  = false;
   bool sellPlaced = false;

   // Place Buy Stop
   if(trade.BuyStop(lotSize, buyStopPrice, _Symbol, buySL, buyTP, ORDER_TIME_GTC, 0, "Breakout BUY"))
   {
      Print("Buy Stop @ ", buyStopPrice, " | SL: ", buySL, " | TP: ", buyTP);
      buyPlaced = true;
   }
   else
   {
      Print("Buy Stop Error: ", GetLastError(), " / retcode: ", trade.ResultRetcode());
   }

   // Place Sell Stop
   if(trade.SellStop(lotSize, sellStopPrice, _Symbol, sellSL, sellTP, ORDER_TIME_GTC, 0, "Breakout SELL"))
   {
      Print("Sell Stop @ ", sellStopPrice, " | SL: ", sellSL, " | TP: ", sellTP);
      sellPlaced = true;
   }
   else
   {
      Print("Sell Stop Error: ", GetLastError(), " / retcode: ", trade.ResultRetcode());
   }

   if(buyPlaced || sellPlaced)
      g_ordersPlacedToday = true;
}

//+------------------------------------------------------------------+
//| Market open check                                                 |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return false;

   if(tick.ask <= 0 || tick.bid <= 0)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Sufficient margin check                                           |
//+------------------------------------------------------------------+
bool HasSufficientMargin(double lotSize)
{
   double marginRequired = 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, price, marginRequired))
      return false;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // Require at least 2:1 safety ratio
   if(freeMargin < marginRequired * 2.0)
   {
      Print("Insufficient margin. Free: ", freeMargin, " | Required: ", marginRequired);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Has open position for this EA?                                    |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cancel opposite pending when one is filled                        |
//+------------------------------------------------------------------+
void CheckAndCancelOppositeOrder()
{
   // If no position, nothing to cancel
   if(!HasOpenPosition())
      return;

   long posType = -1;
   // determine position type
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong pt = PositionGetTicket(i);
      if(!PositionSelectByTicket(pt)) continue;

      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         posType = PositionGetInteger(POSITION_TYPE);
         break;
      }
   }
   if(posType == -1) return;

   // delete opposite pending
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ot = OrderGetTicket(i);
      if(!OrderSelect(ot)) continue;

      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      int orderType = (int)OrderGetInteger(ORDER_TYPE);

      if(posType == POSITION_TYPE_BUY && orderType == ORDER_TYPE_SELL_STOP)
      {
         if(trade.OrderDelete(ot))
            Print("Cancelled opposite Sell Stop");
      }
      else if(posType == POSITION_TYPE_SELL && orderType == ORDER_TYPE_BUY_STOP)
      {
         if(trade.OrderDelete(ot))
            Print("Cancelled opposite Buy Stop");
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel all pending orders from this EA                            |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;

      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
         type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
      {
         trade.OrderDelete(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (Trailing)                                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   // One-symbol EA; just apply trailing to this symbol position
   if(!HasOpenPosition())
      return;

   ApplyTrailingStop();
}

//+------------------------------------------------------------------+
//| Apply trailing stop (correct PositionModify usage)                |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(!PositionSelect(_Symbol))
      return;

   if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   long   posType   = PositionGetInteger(POSITION_TYPE);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int stopsLevel  = StopsLevelPoints();
   int freezeLevel = FreezeLevelPoints();

   double trailingStart    = InpTrailingStart * point;
   double trailingDistance = InpTrailingDistance * point;

   // Freeze constraint: avoid modifying SL if within freeze distance
   double freezeDist = freezeLevel * point;

   if(posType == POSITION_TYPE_BUY)
   {
      double profit = bid - openPrice;
      if(profit < trailingStart) return;

      double newSL = NormalizeDouble(bid - trailingDistance, digits);

      // Respect stops level
      double maxSL = NormalizeDouble(bid - (stopsLevel + 1) * point, digits);
      if(newSL > maxSL) newSL = maxSL;

      // Freeze
      if(freezeLevel > 0 && (bid - newSL) < freezeDist) return;

      if(currentSL == 0.0 || newSL > currentSL)
         trade.PositionModify(_Symbol, newSL, currentTP);
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double profit = openPrice - ask;
      if(profit < trailingStart) return;

      double newSL = NormalizeDouble(ask + trailingDistance, digits);

      // Respect stops level
      double minSL = NormalizeDouble(ask + (stopsLevel + 1) * point, digits);
      if(newSL < minSL) newSL = minSL;

      // Freeze
      if(freezeLevel > 0 && (newSL - ask) < freezeDist) return;

      if(currentSL == 0.0 || newSL < currentSL)
         trade.PositionModify(_Symbol, newSL, currentTP);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   if(InpRiskType == RISK_FIXED_LOT)
      return NormalizeLot(InpLotSize);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0 || tickValue <= 0 || slDistancePrice <= 0)
      return NormalizeLot(InpLotSize);

   double slTicks    = slDistancePrice / tickSize;
   double riskPerLot = slTicks * tickValue;

   if(riskPerLot <= 0)
      return NormalizeLot(InpLotSize);

   double lotSize = riskAmount / riskPerLot;
   return NormalizeLot(lotSize);
}

//+------------------------------------------------------------------+
//| Normalize lot                                                     |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep <= 0) lotStep = 0.01;

   lot = MathMax(minLot, lot);
   lot = MathMin(maxLot, lot);

   lot = MathFloor(lot / lotStep) * lotStep; // conservative
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Reset daily filled-trade counter                                  |
//+------------------------------------------------------------------+
void ResetDailyCounterIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));

   if(today != g_lastTradeCountDate)
   {
      g_lastTradeCountDate = today;
      g_tradesFilledToday  = 0;
   }
}

//+------------------------------------------------------------------+
//| Trading hours filter                                              |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpStartHour < InpEndHour)
      return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   else
      return (dt.hour >= InpStartHour || dt.hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Trading day filter                                                |
//+------------------------------------------------------------------+
bool IsTradingDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   switch(dt.day_of_week)
   {
      case 1: return InpTradeMonday;
      case 2: return InpTradeTuesday;
      case 3: return InpTradeWednesday;
      case 4: return InpTradeThursday;
      case 5: return InpTradeFriday;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| Broker stops level (points)                                       |
//+------------------------------------------------------------------+
int StopsLevelPoints()
{
   long v = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, v))
      return (int)v;
   return 0;
}

//+------------------------------------------------------------------+
//| Broker freeze level (points)                                      |
//+------------------------------------------------------------------+
int FreezeLevelPoints()
{
   long v = 0;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL, v))
      return (int)v;
   return 0;
}

//+------------------------------------------------------------------+
//| Get ATR in points (rounded)                                       |
//+------------------------------------------------------------------+
bool GetATRPoints(double &atrPoints)
{
   atrPoints = 0;

   if(!InpUseATR_SLTP) return false;
   if(g_atrHandle == INVALID_HANDLE) return false;

   double buff[];
   ArraySetAsSeries(buff, true);

   if(CopyBuffer(g_atrHandle, 0, 0, 2, buff) < 1)
   {
      Print("CopyBuffer ATR failed: ", GetLastError());
      return false;
   }

   double atrPrice = buff[0];
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return false;

   atrPoints = MathRound(atrPrice / point);
   return (atrPoints > 0);
}

//+------------------------------------------------------------------+
//| NEWS: split helper                                                |
//+------------------------------------------------------------------+
int SplitList(const string src, const ENUM_NEWS_SEPARATOR sep, string &outArr[])
{
   ArrayResize(outArr, 0);
   string s = src;
   // trim outer
   StringTrimLeft(s); StringTrimRight(s);

   if(s == "")
      return 0;

   ushort delimiter = (sep == NEWS_COMMA ? (ushort)',' : (ushort)';');
   int n = StringSplit(s, delimiter, outArr);

   for(int i=0;i<n;i++)
   {
      StringTrimLeft(outArr[i]);
      StringTrimRight(outArr[i]);
   }
   return n;
}

//+------------------------------------------------------------------+
//| NEWS: restriction check                                           |
//+------------------------------------------------------------------+
bool IsNewsRestrictedNow()
{
   if(!InpUseNewsFilter)
      return false;

   datetime now = TimeCurrent();

   // daily debug throttle
   if(InpNewsDebug)
   {
      MqlDateTime dt;
      TimeToStruct(now, dt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
      if(today != g_lastNewsDebugDay)
      {
         g_lastNewsDebugDay = today;
         Print("NewsFilter debug: checking calendar...");
      }
   }

   // Query calendar
   datetime from = now - (InpNewsMinutesBefore * 60);
   datetime to   = now + (InpNewsLookForwardDays * 86400);

   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to);

   // If calendar unavailable -> fallback
   if(total <= 0)
   {
      if(InpNewsDebug)
         Print("NewsFilter: CalendarValueHistory total=0 (unavailable).");

      if(!InpNewsUseFallbackWindow)
         return false;

      MqlDateTime dt;
      TimeToStruct(now, dt);

      // simple fallback window
      if(InpFallbackStartHour < InpFallbackEndHour)
         return (dt.hour >= InpFallbackStartHour && dt.hour < InpFallbackEndHour);
      else
         return (dt.hour >= InpFallbackStartHour || dt.hour < InpFallbackEndHour);
   }

   string keywords[];
   string currencies[];
   int kCount = SplitList(InpNewsKeywords, InpNewsSeparator, keywords);
   int cCount = SplitList(InpNewsCurrencies, InpNewsSeparator, currencies);

   if(kCount <= 0 || cCount <= 0)
   {
      // if misconfigured, don't block
      if(InpNewsDebug)
         Print("NewsFilter: empty keywords/currencies list -> no block.");
      return false;
   }

   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue;

      MqlCalendarCountry co;
      if(!CalendarCountryById(ev.country_id, co))
         continue;

      // currency match
      bool currencyMatch = false;
      for(int c = 0; c < cCount; c++)
      {
         if(currencies[c] == "") continue;
         if(StringFind(co.currency, currencies[c]) >= 0)
         {
            currencyMatch = true;
            break;
         }
      }
      if(!currencyMatch)
         continue;

      // keyword match
      bool keywordMatch = false;
      for(int k = 0; k < kCount; k++)
      {
         if(keywords[k] == "") continue;
         if(StringFind(ev.name, keywords[k]) >= 0)
         {
            keywordMatch = true;
            break;
         }
      }
      if(!keywordMatch)
         continue;

      datetime eventTime = (datetime)values[i].time;

      if(now >= eventTime - InpNewsMinutesBefore * 60 &&
         now <= eventTime + InpNewsMinutesAfter  * 60)
      {
         if(InpNewsDebug)
            Print("NewsFilter BLOCK: ", co.currency, " | ", ev.name, " | eventTime=", TimeToString(eventTime, TIME_DATE|TIME_MINUTES));
         return true;
      }
   }

   return false;
}
//+------------------------------------------------------------------+
