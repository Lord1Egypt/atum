//+------------------------------------------------------------------+
//|                                            IchiDCAHedgeXAU.mq5   |
//|               XAUUSD-focused Ichimoku breakout basket manager    |
//+------------------------------------------------------------------+
#property copyright "Antigravity Quant"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input group "=== Core ==="
input double InpBaseLot                = 0.19;
input long   InpMagicNumber            = 26042301;
input double InpMaxSpreadPips          = 35.0;
input int    InpCooldownSeconds        = 30;
input int    InpMaxMainPositions       = 8;
input double InpMaxTotalLots           = 3.5;
input double InpMaxFloatingDDPct       = 18.0;

input group "=== Ichimoku Entry ==="
input int    InpTenkan                 = 9;
input int    InpKijun                  = 26;
input int    InpSenkou                 = 52;
input double InpBreakoutBufferPips     = 0.3;
input bool   InpUseChikouFilter        = false;

input group "=== Basket Management ==="
input double InpBasketTPPips           = 10.0;
input bool   InpUseHardSL              = false;
input double InpHardSLPips             = 180.0;
input bool   InpUseDCA                 = true;
input double InpDCAFirstDistancePips   = 10.0;
input double InpDCAStepPips            = 15.0;
input double InpLotMultiplier          = 1.35;
input bool   InpPauseDCAWhileHedged    = true;

input group "=== Hedge ==="
input bool   InpUseHedge               = true;
input int    InpHedgeTriggerLayers     = 3;
input double InpHedgeTriggerLossPct    = 8.0;
input double InpHedgeTriggerPips       = 45.0;
input double InpHedgeLotRatio          = 0.35;
input double InpMaxHedgeLots           = 1.2;
input double InpHedgeTPPips            = 25.0;
input double InpHedgeReleaseProfitPct  = 2.0;

CTrade trade;
int ichimokuHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;
datetime g_lastEntryTime = 0;

enum BasketDirection
  {
   BASKET_NONE = 0,
   BASKET_BUY  = 1,
   BASKET_SELL = -1
  };

string MainComment(const BasketDirection dir,const bool isDca)
  {
   if(dir==BASKET_BUY)
      return isDca ? "ICHI_MAIN_BUY_DCA" : "ICHI_MAIN_BUY";
   if(dir==BASKET_SELL)
      return isDca ? "ICHI_MAIN_SELL_DCA" : "ICHI_MAIN_SELL";
   return "ICHI_MAIN";
  }

string HedgeComment(const BasketDirection dir)
  {
   if(dir==BASKET_BUY)
      return "ICHI_HEDGE_BUY";
   if(dir==BASKET_SELL)
      return "ICHI_HEDGE_SELL";
   return "ICHI_HEDGE";
  }

double PipPoint()
  {
   if(_Digits==3 || _Digits==5)
      return _Point*10.0;
   return _Point;
  }

double CurrentSpreadPips()
  {
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ask<=0.0 || bid<=0.0)
      return 9999.0;
   return (ask-bid)/PipPoint();
  }

bool IsNewBar()
  {
   datetime current=iTime(_Symbol,_Period,0);
   if(current==0)
      return false;
   if(current!=g_lastBarTime)
     {
      g_lastBarTime=current;
      return true;
     }
   return false;
  }

bool CopyIchimokuValue(const int buffer,const int shift,double &value)
  {
   double data[];
   ArraySetAsSeries(data,true);
   if(CopyBuffer(ichimokuHandle,buffer,shift,1,data)<=0)
      return false;
   value=data[0];
  return true;
  }

double HighestHigh(const int period,const int shift)
  {
   double highest=-DBL_MAX;
   for(int i=shift;i<shift+period;i++)
     {
      double value=iHigh(_Symbol,_Period,i);
      if(value==0.0)
         return 0.0;
      if(value>highest)
         highest=value;
     }
   return highest;
  }

double LowestLow(const int period,const int shift)
  {
   double lowest=DBL_MAX;
   for(int i=shift;i<shift+period;i++)
     {
      double value=iLow(_Symbol,_Period,i);
      if(value==0.0)
         return 0.0;
      if(value<lowest)
         lowest=value;
     }
   return lowest;
  }

double NormalizeLots(const double requested)
  {
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double lots=MathMax(minLot,MathMin(maxLot,requested));
   if(step>0.0)
      lots=MathFloor(lots/step)*step;
   int digits=0;
   if(step==0.1)
      digits=1;
   else if(step==0.01)
      digits=2;
   return NormalizeDouble(lots,digits);
  }

bool PositionIsMine()
  {
   return PositionGetString(POSITION_SYMBOL)==_Symbol &&
          PositionGetInteger(POSITION_MAGIC)==InpMagicNumber;
  }

bool CommentContains(const string needle)
  {
   return StringFind(PositionGetString(POSITION_COMMENT),needle)>=0;
  }

BasketDirection GetMainDirection()
  {
   bool hasBuy=false;
   bool hasSell=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(!PositionIsMine())
         continue;
      if(!CommentContains("ICHI_MAIN"))
         continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type==POSITION_TYPE_BUY)
         hasBuy=true;
      if(type==POSITION_TYPE_SELL)
         hasSell=true;
     }

   if(hasBuy && !hasSell)
      return BASKET_BUY;
   if(hasSell && !hasBuy)
      return BASKET_SELL;
   return BASKET_NONE;
  }

int CountPositionsByPrefix(const string prefix)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(!PositionIsMine())
         continue;
      if(CommentContains(prefix))
         count++;
     }
   return count;
  }

double SumLotsByPrefix(const string prefix)
  {
   double lots=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(!PositionIsMine())
         continue;
      if(CommentContains(prefix))
         lots+=PositionGetDouble(POSITION_VOLUME);
     }
   return lots;
  }

double BasketLots(const BasketDirection dir)
  {
   if(dir==BASKET_NONE)
      return 0.0;
   return SumLotsByPrefix(dir==BASKET_BUY ? "ICHI_MAIN_BUY" : "ICHI_MAIN_SELL");
  }

double HedgeLots(const BasketDirection dir)
  {
   if(dir==BASKET_NONE)
      return 0.0;
   return SumLotsByPrefix(dir==BASKET_BUY ? "ICHI_HEDGE_SELL" : "ICHI_HEDGE_BUY");
  }

int BasketCount(const BasketDirection dir)
  {
   if(dir==BASKET_NONE)
      return 0;
   return CountPositionsByPrefix(dir==BASKET_BUY ? "ICHI_MAIN_BUY" : "ICHI_MAIN_SELL");
  }

double BasketAveragePrice(const BasketDirection dir)
  {
   double priceVolume=0.0;
   double totalLots=0.0;
   string prefix=(dir==BASKET_BUY ? "ICHI_MAIN_BUY" : "ICHI_MAIN_SELL");
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(!PositionIsMine())
         continue;
      if(!CommentContains(prefix))
         continue;
      double lots=PositionGetDouble(POSITION_VOLUME);
      priceVolume+=PositionGetDouble(POSITION_PRICE_OPEN)*lots;
      totalLots+=lots;
     }
   if(totalLots<=0.0)
      return 0.0;
   return priceVolume/totalLots;
  }

double LatestMainEntryPrice(const BasketDirection dir)
  {
   datetime latest=0;
   double price=0.0;
   string prefix=(dir==BASKET_BUY ? "ICHI_MAIN_BUY" : "ICHI_MAIN_SELL");
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(!PositionIsMine())
         continue;
      if(!CommentContains(prefix))
         continue;
      datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
      if(openTime>=latest)
        {
         latest=openTime;
         price=PositionGetDouble(POSITION_PRICE_OPEN);
        }
     }
   return price;
  }

double BasketFloatingProfit()
  {
   double profit=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if(!PositionIsMine())
         continue;
      profit+=PositionGetDouble(POSITION_PROFIT);
     }
   return profit;
  }

double FloatingDDPercent()
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance<=0.0)
      return 0.0;
   double dd=(balance-equity)/balance*100.0;
   return MathMax(0.0,dd);
  }

double BasketStressPips(const BasketDirection dir)
  {
   double avg=BasketAveragePrice(dir);
   if(avg<=0.0)
      return 0.0;
   double price=(dir==BASKET_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(price<=0.0)
      return 0.0;
   if(dir==BASKET_BUY)
      return MathMax(0.0,(avg-price)/PipPoint());
   return MathMax(0.0,(price-avg)/PipPoint());
  }

double NextDcaLots(const BasketDirection dir)
  {
   int count=BasketCount(dir);
   double lots=InpBaseLot*MathPow(InpLotMultiplier,count);
   return NormalizeLots(lots);
  }

bool CanTrade()
  {
   if(CurrentSpreadPips()>InpMaxSpreadPips)
      return false;
   if((TimeCurrent()-g_lastEntryTime)<InpCooldownSeconds)
      return false;
   return true;
  }

bool ClosePositionsByPrefix(const string prefix)
  {
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(!PositionIsMine())
         continue;
      if(!CommentContains(prefix))
         continue;
      if(!trade.PositionClose(ticket))
         ok=false;
     }
   return ok;
  }

void EmergencyFlatten()
  {
   ClosePositionsByPrefix("ICHI_MAIN");
   ClosePositionsByPrefix("ICHI_HEDGE");
  }

void UpdateBasketTargets(const BasketDirection dir)
  {
   string prefix=(dir==BASKET_BUY ? "ICHI_MAIN_BUY" : "ICHI_MAIN_SELL");
   double avg=BasketAveragePrice(dir);
   if(avg<=0.0)
      return;

   double tp=(dir==BASKET_BUY)
      ? avg+InpBasketTPPips*PipPoint()
      : avg-InpBasketTPPips*PipPoint();
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double minStopDistance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;

   if(dir==BASKET_BUY && tp<=ask+minStopDistance)
      return;
   if(dir==BASKET_SELL && tp>=bid-minStopDistance)
      return;

   double sl=0.0;
   if(InpUseHardSL)
      sl=(dir==BASKET_BUY)
         ? avg-InpHardSLPips*PipPoint()
         : avg+InpHardSLPips*PipPoint();

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(!PositionIsMine())
         continue;
      if(!CommentContains(prefix))
         continue;
      double currentSL=PositionGetDouble(POSITION_SL);
      double currentTP=PositionGetDouble(POSITION_TP);
      if(MathAbs(currentSL-sl)<=_Point && MathAbs(currentTP-tp)<=_Point)
         continue;
      trade.PositionModify(ticket,sl,tp);
     }
  }

bool OpenMainOrder(const BasketDirection dir,const double lots,const bool isDca)
  {
   if(dir==BASKET_BUY)
     {
      if(!trade.Buy(lots,_Symbol,0.0,0.0,0.0,MainComment(dir,isDca)))
         return false;
     }
   if(dir==BASKET_SELL)
     {
      if(!trade.Sell(lots,_Symbol,0.0,0.0,0.0,MainComment(dir,isDca)))
         return false;
     }
   g_lastEntryTime=TimeCurrent();
   return true;
  }

bool OpenHedgeOrder(const BasketDirection dir,const double lots)
  {
   BasketDirection hedgeDir=(dir==BASKET_BUY ? BASKET_SELL : BASKET_BUY);
   double tpDistance=InpHedgeTPPips*PipPoint();
   double price=(hedgeDir==BASKET_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double tp=(hedgeDir==BASKET_BUY) ? price+tpDistance : price-tpDistance;

   bool ok=false;
   if(hedgeDir==BASKET_BUY)
      ok=trade.Buy(lots,_Symbol,0.0,0.0,tp,HedgeComment(hedgeDir));
   else
      ok=trade.Sell(lots,_Symbol,0.0,0.0,tp,HedgeComment(hedgeDir));

   if(ok)
      g_lastEntryTime=TimeCurrent();
   return ok;
  }

int IchimokuSignal()
  {
   double tenkanHigh=HighestHigh(InpTenkan,1);
   double tenkanLow=LowestLow(InpTenkan,1);
   double kijunHigh=HighestHigh(InpKijun,1);
   double kijunLow=LowestLow(InpKijun,1);
   double senkouHigh=HighestHigh(InpSenkou,1);
   double senkouLow=LowestLow(InpSenkou,1);
   double close1=iClose(_Symbol,_Period,1);
   double close2=iClose(_Symbol,_Period,2);
   if(close1==0.0 || close2==0.0 || tenkanHigh==0.0 || tenkanLow==0.0 || kijunHigh==0.0 || kijunLow==0.0 || senkouHigh==0.0 || senkouLow==0.0)
      return 0;

   double tenkan1=(tenkanHigh+tenkanLow)*0.5;
   double kijun1=(kijunHigh+kijunLow)*0.5;
   double spanA1=(tenkan1+kijun1)*0.5;
   double spanB1=(senkouHigh+senkouLow)*0.5;

   double cloudTop=MathMax(spanA1,spanB1);
   double cloudBottom=MathMin(spanA1,spanB1);
   double buffer=InpBreakoutBufferPips*PipPoint();

   bool chikouBuy=true;
   bool chikouSell=true;
   if(InpUseChikouFilter)
     {
      double compare=iClose(_Symbol,_Period,1+InpKijun);
      if(compare==0.0)
         return 0;
      chikouBuy=(close1>compare);
      chikouSell=(close1<compare);
     }

   bool buy=(close1>cloudTop+buffer && tenkan1>=kijun1 && close1>close2 && chikouBuy);
   bool sell=(close1<cloudBottom-buffer && tenkan1<=kijun1 && close1<close2 && chikouSell);

   if(buy && !sell)
      return 1;
   if(sell && !buy)
      return -1;
   return 0;
  }

void ManageEntry()
  {
   if(GetMainDirection()!=BASKET_NONE)
      return;
   if(!CanTrade())
      return;

   int signal=IchimokuSignal();
   if(signal==1)
      OpenMainOrder(BASKET_BUY,NormalizeLots(InpBaseLot),false);
   if(signal==-1)
      OpenMainOrder(BASKET_SELL,NormalizeLots(InpBaseLot),false);
  }

void ManageDCA(const BasketDirection dir)
  {
   if(!InpUseDCA)
      return;
   if(dir==BASKET_NONE)
      return;
   if(InpPauseDCAWhileHedged && HedgeLots(dir)>0.0)
      return;
   if(!CanTrade())
      return;

   int count=BasketCount(dir);
   if(count<=0 || count>=InpMaxMainPositions)
      return;

   double totalLots=BasketLots(dir)+HedgeLots(dir);
   if(totalLots>=InpMaxTotalLots)
      return;

   double anchor=LatestMainEntryPrice(dir);
   if(anchor<=0.0)
      anchor=BasketAveragePrice(dir);
   if(anchor<=0.0)
      return;

   double needed=(count==1 ? InpDCAFirstDistancePips : InpDCAStepPips);
   double price=(dir==BASKET_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double distance=(dir==BASKET_BUY) ? (anchor-price)/PipPoint() : (price-anchor)/PipPoint();
   if(distance<needed)
      return;

   double lots=NextDcaLots(dir);
   if(totalLots+lots>InpMaxTotalLots)
      return;

   OpenMainOrder(dir,lots,true);
  }

void ManageHedge(const BasketDirection dir)
  {
   if(!InpUseHedge || dir==BASKET_NONE)
      return;

   double existingHedgeLots=HedgeLots(dir);
   double ddPct=FloatingDDPercent();
   double stress=BasketStressPips(dir);
   int layers=BasketCount(dir);

   if(existingHedgeLots<=0.0)
     {
      if(!CanTrade())
         return;
      if(layers<InpHedgeTriggerLayers)
         return;
      if(ddPct<InpHedgeTriggerLossPct && stress<InpHedgeTriggerPips)
         return;

      double hedgeLots=NormalizeLots(MathMin(InpMaxHedgeLots,BasketLots(dir)*InpHedgeLotRatio));
      if(hedgeLots<=0.0)
         return;
      if(BasketLots(dir)+existingHedgeLots+hedgeLots>InpMaxTotalLots)
         return;
      OpenHedgeOrder(dir,hedgeLots);
      return;
     }

   double releaseThreshold=AccountInfoDouble(ACCOUNT_BALANCE)*(InpHedgeReleaseProfitPct/100.0);
   if(BasketFloatingProfit()>=releaseThreshold || ddPct<(InpHedgeTriggerLossPct*0.5))
      ClosePositionsByPrefix(dir==BASKET_BUY ? "ICHI_HEDGE_SELL" : "ICHI_HEDGE_BUY");
  }

void ManageRisk()
  {
   if(FloatingDDPercent()>=InpMaxFloatingDDPct)
      EmergencyFlatten();
  }

void ManageBasket()
  {
   BasketDirection dir=GetMainDirection();
   if(dir==BASKET_NONE)
      return;
   UpdateBasketTargets(dir);
   ManageRisk();
   ManageHedge(dir);
   ManageDCA(dir);
  }

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);
   trade.LogLevel(LOG_LEVEL_ERRORS);

   ichimokuHandle=iIchimoku(_Symbol,_Period,InpTenkan,InpKijun,InpSenkou);
   if(ichimokuHandle==INVALID_HANDLE)
     {
      Print("Failed to initialize Ichimoku handle");
      return INIT_FAILED;
     }

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(ichimokuHandle!=INVALID_HANDLE)
      IndicatorRelease(ichimokuHandle);
  }

void OnTick()
  {
   ManageBasket();
   if(!IsNewBar())
      return;
   if(CurrentSpreadPips()>InpMaxSpreadPips)
      return;
   ManageEntry();
  }

double OnTester()
  {
   double profit=TesterStatistics(STAT_PROFIT);
   double pf=TesterStatistics(STAT_PROFIT_FACTOR);
   double dd=TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   double trades=TesterStatistics(STAT_TRADES);
   if(dd<=0.0)
      dd=0.1;
   return pf*MathSqrt(MathMax(trades,1.0))*(profit/dd);
  }
