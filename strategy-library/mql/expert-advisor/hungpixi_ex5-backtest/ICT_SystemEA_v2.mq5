//+------------------------------------------------------------------+
//|                                          ICT_SystemEA_v2.mq5     |
//|                        ICT System EA v2.0 for The5%ers           |
//|                        CISD + PDA + SMT + PSP + Liquidity        |
//|                        + OHLC/OLHC Daily Bias                    |
//|                                                                  |
//|  Author: Phạm Phú Nguyễn Hưng                                   |
//|  Website: https://comarai.com                                    |
//|  GitHub: https://github.com/hungpixi                             |
//+------------------------------------------------------------------+
#property copyright "Comarai - https://comarai.com"
#property link      "https://github.com/hungpixi"
#property version   "2.00"
#property description "ICT System EA v2.0 - The5%ers Edition"
#property description "Modules: CISD, PDA, SMT, PSP, Liquidity, OHLC/OLHC"
#property description "Semi-Auto: Signal + Alert + Auto Risk Management"

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_MARKET_BIAS { BIAS_NONE, BIAS_BULLISH, BIAS_BEARISH };
enum ENUM_STRUCTURE  { STRUCT_NONE, STRUCT_BOS, STRUCT_CHOCH, STRUCT_CISD };
enum ENUM_PDA_ZONE   { PDA_NONE, PDA_PREMIUM, PDA_DISCOUNT, PDA_EQ };
enum ENUM_SESSION    { SESSION_ASIAN, SESSION_LONDON, SESSION_NY, SESSION_OFF };

enum ENUM_EA_STATE
{
   STATE_SCANNING,
   STATE_SIGNAL_READY,
   STATE_IN_TRADE,
   STATE_DAILY_DONE,
   STATE_KILLED
};

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct SwingPoint
{
   double   price;
   datetime time;
   int      barIndex;
   bool     isHigh;
};

struct MarketStructure
{
   ENUM_MARKET_BIAS  trend;
   ENUM_STRUCTURE    lastSignal;
   SwingPoint        lastSwingHigh;
   SwingPoint        lastSwingLow;
   SwingPoint        prevSwingHigh;
   SwingPoint        prevSwingLow;
   bool              cisdConfirmed;
};

struct PDAData
{
   double         equilibrium;
   ENUM_PDA_ZONE  currentZone;
   double         premiumStart;
   double         discountEnd;
   double         fvgTop;
   double         fvgBottom;
   bool           fvgBullish;
   bool           fvgValid;
   double         obTop;
   double         obBottom;
   bool           obBullish;
   bool           obValid;
};

struct SMTData
{
   bool           divergenceDetected;
   ENUM_MARKET_BIAS smtBias;
   string         description;
};

struct SessionData
{
   double         prevAsianHigh, prevAsianLow;
   double         prevLondonHigh, prevLondonLow;
   double         prevNYHigh, prevNYLow;
   ENUM_SESSION   currentSession;
};

struct LiquidityData
{
   double         bslLevel;
   double         sslLevel;
   bool           bslSwept;
   bool           sslSwept;
   bool           equalHighs;
   bool           equalLows;
   double         equalHighPrice;
   double         equalLowPrice;
};

struct DailyBias
{
   ENUM_MARKET_BIAS bias;
   double         dailyOpen;
   double         dailyHigh;
   double         dailyLow;
   bool           highFirst;
   int            confidence;
};

struct SignalData
{
   ENUM_MARKET_BIAS direction;
   int            confluenceCount;
   string         confluences;
   double         entryPrice;
   double         slPrice;
   double         tpPrice;
   bool           isValid;
};

struct DailyStats
{
   int            tradesOpened;
   int            consecutiveLosses;
   double         dailyPnL;
   double         startBalance;
   datetime       lastTradeDate;
};

//+------------------------------------------------------------------+
//| MODULE 1: MARKET STRUCTURE (CISD/BOS/CHoCH)                      |
//+------------------------------------------------------------------+
class CMarketStructure
{
private:
   string         m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int            m_swingLen;
   SwingPoint     m_swings[];
   int            m_maxSwings;
   
public:
   MarketStructure data;
   
   void Init(string symbol, ENUM_TIMEFRAMES tf, int swingLen=5)
   {
      m_symbol = symbol; m_tf = tf; m_swingLen = swingLen;
      m_maxSwings = 20; ArrayResize(m_swings, 0);
      data.trend = BIAS_NONE; data.lastSignal = STRUCT_NONE; data.cisdConfirmed = false;
   }
   
   void Update()
   {
      DetectSwingPoints();
      if(ArraySize(m_swings) < 4) return;
      AnalyzeStructure();
   }
   
   void DetectSwingPoints()
   {
      ArrayResize(m_swings, 0);
      int bars = iBars(m_symbol, m_tf);
      int limit = MathMin(bars - m_swingLen - 1, 200);
      
      for(int i = m_swingLen; i < limit; i++)
      {
         bool isSwingHigh = true, isSwingLow = true;
         double high_i = iHigh(m_symbol, m_tf, i);
         double low_i  = iLow(m_symbol, m_tf, i);
         
         for(int j = 1; j <= m_swingLen; j++)
         {
            if(iHigh(m_symbol, m_tf, i-j) >= high_i || iHigh(m_symbol, m_tf, i+j) >= high_i) isSwingHigh = false;
            if(iLow(m_symbol, m_tf, i-j) <= low_i || iLow(m_symbol, m_tf, i+j) <= low_i) isSwingLow = false;
         }
         
         if(isSwingHigh)
         {
            SwingPoint sp; sp.price = high_i; sp.time = iTime(m_symbol, m_tf, i);
            sp.barIndex = i; sp.isHigh = true;
            int sz = ArraySize(m_swings); ArrayResize(m_swings, sz+1); m_swings[sz] = sp;
         }
         if(isSwingLow)
         {
            SwingPoint sp; sp.price = low_i; sp.time = iTime(m_symbol, m_tf, i);
            sp.barIndex = i; sp.isHigh = false;
            int sz = ArraySize(m_swings); ArrayResize(m_swings, sz+1); m_swings[sz] = sp;
         }
         if(ArraySize(m_swings) >= m_maxSwings) break;
      }
   }
   
   void AnalyzeStructure()
   {
      SwingPoint sh1={0}, sh2={0}, sl1={0}, sl2={0};
      int shCount=0, slCount=0;
      for(int i=0; i<ArraySize(m_swings) && (shCount<2 || slCount<2); i++)
      {
         if(m_swings[i].isHigh && shCount<2) { if(shCount==0) sh1=m_swings[i]; else sh2=m_swings[i]; shCount++; }
         if(!m_swings[i].isHigh && slCount<2) { if(slCount==0) sl1=m_swings[i]; else sl2=m_swings[i]; slCount++; }
      }
      if(shCount<2 || slCount<2) return;
      
      data.lastSwingHigh = sh1; data.prevSwingHigh = sh2;
      data.lastSwingLow = sl1; data.prevSwingLow = sl2;
      
      double close = iClose(m_symbol, m_tf, 1);
      
      if(sh1.price > sh2.price && sl1.price > sl2.price) data.trend = BIAS_BULLISH;
      else if(sh1.price < sh2.price && sl1.price < sl2.price) data.trend = BIAS_BEARISH;
      
      if(data.trend == BIAS_BULLISH && close > sh1.price) data.lastSignal = STRUCT_BOS;
      else if(data.trend == BIAS_BEARISH && close < sl1.price) data.lastSignal = STRUCT_BOS;
      
      if(data.trend == BIAS_BULLISH && close < sl1.price) { data.lastSignal = STRUCT_CHOCH; data.trend = BIAS_BEARISH; }
      else if(data.trend == BIAS_BEARISH && close > sh1.price) { data.lastSignal = STRUCT_CHOCH; data.trend = BIAS_BULLISH; }
      
      if(data.lastSignal == STRUCT_CHOCH)
      {
         double body = MathAbs(iClose(m_symbol, m_tf, 1) - iOpen(m_symbol, m_tf, 1));
         double range = iHigh(m_symbol, m_tf, 1) - iLow(m_symbol, m_tf, 1);
         if(range > 0 && body/range > 0.6) { data.lastSignal = STRUCT_CISD; data.cisdConfirmed = true; }
      }
   }
};

//+------------------------------------------------------------------+
//| MODULE 2: PDA (Premium/Discount Array + FVG + OB)                |
//+------------------------------------------------------------------+
class CPDA
{
private:
   string m_symbol; ENUM_TIMEFRAMES m_tf;
public:
   PDAData data;
   void Init(string symbol, ENUM_TIMEFRAMES tf) { m_symbol=symbol; m_tf=tf; data.fvgValid=false; data.obValid=false; }
   
   void Update(double swingHigh, double swingLow)
   {
      // Fallback: nếu swing prices = 0, tự tính từ 50 bars gần nhất
      if(swingHigh <= 0 || swingLow <= 0 || swingHigh <= swingLow)
      {
         swingHigh = 0; swingLow = DBL_MAX;
         for(int i=1; i<=50; i++)
         {
            double h=iHigh(m_symbol,m_tf,i), l=iLow(m_symbol,m_tf,i);
            if(h>swingHigh) swingHigh=h;
            if(l<swingLow) swingLow=l;
         }
      }
      data.premiumStart = swingHigh; data.discountEnd = swingLow;
      data.equilibrium = (swingHigh + swingLow) / 2.0;
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(bid > data.equilibrium) data.currentZone = PDA_PREMIUM;
      else if(bid < data.equilibrium) data.currentZone = PDA_DISCOUNT;
      else data.currentZone = PDA_EQ;
      DetectFVG(); DetectOrderBlock();
   }
   
   void DetectFVG()
   {
      data.fvgValid = false;
      for(int i = 1; i < 20; i++)
      {
         double h1 = iHigh(m_symbol, m_tf, i+2), l1 = iLow(m_symbol, m_tf, i+2);
         double h3 = iHigh(m_symbol, m_tf, i), l3 = iLow(m_symbol, m_tf, i);
         if(h1 < l3) { data.fvgTop=l3; data.fvgBottom=h1; data.fvgBullish=true; data.fvgValid=true; break; }
         if(h3 < l1) { data.fvgTop=l1; data.fvgBottom=h3; data.fvgBullish=false; data.fvgValid=true; break; }
      }
   }
   
   void DetectOrderBlock()
   {
      data.obValid = false;
      for(int i = 1; i < 30; i++)
      {
         double o=iOpen(m_symbol,m_tf,i), c=iClose(m_symbol,m_tf,i);
         double nO=iOpen(m_symbol,m_tf,i-1), nC=iClose(m_symbol,m_tf,i-1);
         double nH=iHigh(m_symbol,m_tf,i-1), nL=iLow(m_symbol,m_tf,i-1);
         double nBody=MathAbs(nC-nO), nRange=nH-nL;
         if(nRange<=0) continue;
         bool big = (nBody/nRange>0.6) && (nRange > iHigh(m_symbol,m_tf,i)-iLow(m_symbol,m_tf,i));
         if(!big) continue;
         if(c<o && nC>nO) { data.obTop=iHigh(m_symbol,m_tf,i); data.obBottom=iLow(m_symbol,m_tf,i); data.obBullish=true; data.obValid=true; break; }
         if(c>o && nC<nO) { data.obTop=iHigh(m_symbol,m_tf,i); data.obBottom=iLow(m_symbol,m_tf,i); data.obBullish=false; data.obValid=true; break; }
      }
   }
};

//+------------------------------------------------------------------+
//| MODULE 3: SMT DIVERGENCE                                         |
//+------------------------------------------------------------------+
class CSMT
{
private:
   string m_symbol1, m_symbol2; ENUM_TIMEFRAMES m_tf; bool m_inverseCorr;
   bool m_available;
   
   string FindSymbol(string preferred)
   {
      // Try preferred name first
      if(SymbolSelect(preferred, true) && iBars(preferred, PERIOD_H1) > 0) return preferred;
      // Try common DXY/Dollar Index names across brokers
      string names[] = {"DXY","USDX","USDollar","DollarIndex","DX","DXYUSD","USDIndex","DXY.sml","USDX.sml"};
      for(int i=0; i<ArraySize(names); i++)
      {
         if(SymbolSelect(names[i], true) && iBars(names[i], PERIOD_H1) > 0)
         {
            Print("✅ SMT: Tìm thấy symbol \"", names[i], "\" thay cho \"", preferred, "\"");
            return names[i];
         }
      }
      return "";
   }
   
public:
   SMTData data;
   void Init(string s1, string s2, ENUM_TIMEFRAMES tf, bool inv=true)
   {
      m_symbol1=s1; m_tf=tf; m_inverseCorr=inv;
      data.divergenceDetected=false; data.smtBias=BIAS_NONE;
      m_symbol2 = FindSymbol(s2);
      m_available = (m_symbol2 != "");
      if(!m_available) Print("⚠️ SMT: Không tìm thấy symbol DXY trên broker này. SMT module sẽ bị skip.");
      else Print("✅ SMT: Sử dụng symbol \"", m_symbol2, "\" cho SMT divergence");
   }
   
   void Update()
   {
      data.divergenceDetected=false; data.smtBias=BIAS_NONE; data.description="";
      if(!m_available) return;
      if(iBars(m_symbol2, m_tf) < 20) return;
      
      double s1h1=iHigh(m_symbol1,m_tf,1), s1h2=iHigh(m_symbol1,m_tf,5);
      double s1l1=iLow(m_symbol1,m_tf,1), s1l2=iLow(m_symbol1,m_tf,5);
      double s2h1=iHigh(m_symbol2,m_tf,1), s2h2=iHigh(m_symbol2,m_tf,5);
      double s2l1=iLow(m_symbol2,m_tf,1), s2l2=iLow(m_symbol2,m_tf,5);
      
      if(m_inverseCorr)
      {
         if(s1h1>s1h2 && s2l1>=s2l2) { data.divergenceDetected=true; data.smtBias=BIAS_BEARISH; data.description="Bearish SMT"; }
         if(s1l1<s1l2 && s2h1<=s2h2) { data.divergenceDetected=true; data.smtBias=BIAS_BULLISH; data.description="Bullish SMT"; }
      }
      else
      {
         if(s1h1>s1h2 && s2h1<=s2h2) { data.divergenceDetected=true; data.smtBias=BIAS_BEARISH; data.description="Bearish SMT"; }
         if(s1l1<s1l2 && s2l1>=s2l2) { data.divergenceDetected=true; data.smtBias=BIAS_BULLISH; data.description="Bullish SMT"; }
      }
   }
};

//+------------------------------------------------------------------+
//| MODULE 4: PSP (Previous Session Price)                           |
//+------------------------------------------------------------------+
class CPSP
{
private:
   string m_symbol;
   int m_asianStart, m_asianEnd, m_londonStart, m_londonEnd, m_nyStart, m_nyEnd;
public:
   SessionData data;
   
   void Init(string symbol)
   {
      m_symbol = symbol;
      m_asianStart=0; m_asianEnd=8; m_londonStart=7; m_londonEnd=16; m_nyStart=12; m_nyEnd=21;
      data.prevAsianHigh=0; data.prevAsianLow=DBL_MAX;
      data.prevLondonHigh=0; data.prevLondonLow=DBL_MAX;
      data.prevNYHigh=0; data.prevNYLow=DBL_MAX;
   }
   
   void Update() { UpdateCurrentSession(); CalculateSessionLevels(); }
   
   void UpdateCurrentSession()
   {
      MqlDateTime now; TimeToStruct(TimeCurrent(), now); int h = now.hour;
      // Check London/NY FIRST (priority over Asian overlap)
      if(h>=m_londonStart && h<m_londonEnd) data.currentSession = SESSION_LONDON;
      else if(h>=m_nyStart && h<m_nyEnd) data.currentSession = SESSION_NY;
      else if(h>=m_asianStart && h<m_asianEnd) data.currentSession = SESSION_ASIAN;
      else data.currentSession = SESSION_OFF;
   }
   
   void CalculateSessionLevels()
   {
      int bars = MathMin(iBars(m_symbol, PERIOD_M15), 200);
      double aH=0,aL=DBL_MAX,lH=0,lL=DBL_MAX,nH=0,nL=DBL_MAX;
      bool aF=false,lF=false,nF=false;
      for(int i=1; i<bars; i++)
      {
         MqlDateTime bt; TimeToStruct(iTime(m_symbol,PERIOD_M15,i), bt);
         int bh=bt.hour; double h=iHigh(m_symbol,PERIOD_M15,i), l=iLow(m_symbol,PERIOD_M15,i);
         if(!aF && bh>=m_asianStart && bh<m_asianEnd) { if(h>aH) aH=h; if(l<aL) aL=l; aF=true; }
         if(!lF && bh>=m_londonStart && bh<m_londonEnd) { if(h>lH) lH=h; if(l<lL) lL=l; lF=true; }
         if(!nF && bh>=m_nyStart && bh<m_nyEnd) { if(h>nH) nH=h; if(l<nL) nL=l; nF=true; }
         if(aF&&lF&&nF) break;
      }
      if(aH>0){data.prevAsianHigh=aH; data.prevAsianLow=aL;}
      if(lH>0){data.prevLondonHigh=lH; data.prevLondonLow=lL;}
      if(nH>0){data.prevNYHigh=nH; data.prevNYLow=nL;}
   }
};

//+------------------------------------------------------------------+
//| MODULE 5: LIQUIDITY (BSL/SSL/Equal HL/Sweep)                     |
//+------------------------------------------------------------------+
class CLiquidity
{
private:
   string m_symbol; ENUM_TIMEFRAMES m_tf; double m_eqTol;
public:
   LiquidityData data;
   
   void Init(string symbol, ENUM_TIMEFRAMES tf, double eqPts=30)
   { m_symbol=symbol; m_tf=tf; m_eqTol=eqPts*SymbolInfoDouble(symbol,SYMBOL_POINT); data.bslSwept=false; data.sslSwept=false; data.equalHighs=false; data.equalLows=false; }
   
   void Update() { DetectPools(); DetectEqualHL(); DetectSweep(); }
   
   void DetectPools()
   {
      double maxH=0, minL=DBL_MAX;
      for(int i=1;i<50;i++) { double h=iHigh(m_symbol,m_tf,i),l=iLow(m_symbol,m_tf,i); if(h>maxH)maxH=h; if(l<minL)minL=l; }
      data.bslLevel=maxH; data.sslLevel=minL;
   }
   
   void DetectEqualHL()
   {
      data.equalHighs=false; data.equalLows=false;
      for(int i=1;i<25;i++)
      {
         double hi=iHigh(m_symbol,m_tf,i), li=iLow(m_symbol,m_tf,i);
         for(int j=i+3;j<30;j++)
         {
            double hj=iHigh(m_symbol,m_tf,j), lj=iLow(m_symbol,m_tf,j);
            if(!data.equalHighs && MathAbs(hi-hj)<=m_eqTol) { data.equalHighs=true; data.equalHighPrice=(hi+hj)/2.0; }
            if(!data.equalLows && MathAbs(li-lj)<=m_eqTol) { data.equalLows=true; data.equalLowPrice=(li+lj)/2.0; }
         }
      }
   }
   
   void DetectSweep()
   {
      data.bslSwept=false; data.sslSwept=false;
      double h1=iHigh(m_symbol,m_tf,1), l1=iLow(m_symbol,m_tf,1), c1=iClose(m_symbol,m_tf,1);
      if(h1>data.bslLevel && c1<data.bslLevel) data.bslSwept=true;
      if(l1<data.sslLevel && c1>data.sslLevel) data.sslSwept=true;
   }
};

//+------------------------------------------------------------------+
//| MODULE 6: OHLC/OLHC DAILY BIAS                                  |
//+------------------------------------------------------------------+
class CDailyBiasEngine
{
private:
   string m_symbol;
public:
   DailyBias data;
   void Init(string symbol) { m_symbol=symbol; data.bias=BIAS_NONE; data.confidence=0; }
   
   void Update()
   {
      data.dailyOpen = iOpen(m_symbol, PERIOD_D1, 0);
      data.dailyHigh = iHigh(m_symbol, PERIOD_D1, 0);
      data.dailyLow  = iLow(m_symbol, PERIOD_D1, 0);
      if(data.dailyOpen == 0) return;
      
      DetermineFirstExtreme();
      
      if(data.highFirst)
      {
         data.bias = BIAS_BEARISH; // OHLC
         double mD=(data.dailyOpen-data.dailyLow), mU=(data.dailyHigh-data.dailyOpen);
         if(mD>0 && mU>0) data.confidence = (int)(mD/(mD+mU)*100);
      }
      else
      {
         data.bias = BIAS_BULLISH; // OLHC
         double mU=(data.dailyHigh-data.dailyOpen), mD=(data.dailyOpen-data.dailyLow);
         if(mU>0 && mD>0) data.confidence = (int)(mU/(mU+mD)*100);
      }
   }
   
   void DetermineFirstExtreme()
   {
      int bars = iBars(m_symbol, PERIOD_M5);
      datetime todayStart = iTime(m_symbol, PERIOD_D1, 0);
      datetime highTime=0, lowTime=0;
      double firstHigh=data.dailyOpen, firstLow=data.dailyOpen;
      double pt = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      
      for(int i = bars-1; i >= 0; i--)
      {
         datetime bt = iTime(m_symbol, PERIOD_M5, i);
         if(bt < todayStart) continue;
         double h=iHigh(m_symbol,PERIOD_M5,i), l=iLow(m_symbol,PERIOD_M5,i);
         if(h>firstHigh && highTime==0) { firstHigh=h; highTime=bt; }
         if(l<firstLow && lowTime==0) { firstLow=l; lowTime=bt; }
         if(MathAbs(h-data.dailyHigh)<pt*10) { highTime=bt; break; }
         if(MathAbs(l-data.dailyLow)<pt*10) { lowTime=bt; break; }
      }
      data.highFirst = (highTime>0 && lowTime>0) ? (highTime<lowTime) : false;
   }
};

//+------------------------------------------------------------------+
//| MODULE 7: CONFLUENCE ENGINE                                      |
//+------------------------------------------------------------------+
class CConfluenceEngine
{
public:
   SignalData signal;
   int        minConfluence;
   
   void Init(int minConf=3) { minConfluence=minConf; signal.isValid=false; signal.confluenceCount=0; }
   
   void Evaluate(MarketStructure &ms, PDAData &pda, SMTData &smt, SessionData &psp, LiquidityData &liq, DailyBias &bias, double bid, double point)
   {
      signal.isValid=false; signal.confluenceCount=0; signal.confluences=""; signal.direction=BIAS_NONE;
      int bullC=0, bearC=0; string bullS="", bearS="";
      
      // 1. Market Structure TREND (bull/bear alignment)
      if(ms.trend==BIAS_BULLISH) { bullC++; bullS+="Trend↑ "; }
      if(ms.trend==BIAS_BEARISH) { bearC++; bearS+="Trend↓ "; }
      
      // 1b. Bonus: CISD/BOS signal (+1 extra)
      if(ms.lastSignal==STRUCT_CISD || ms.lastSignal==STRUCT_BOS)
      {
         if(ms.trend==BIAS_BULLISH) { bullC++; bullS+="CISD "; }
         if(ms.trend==BIAS_BEARISH) { bearC++; bearS+="CISD "; }
      }
      
      // 2. PDA Zone (buy in discount, sell in premium)
      if(pda.currentZone==PDA_DISCOUNT) { bullC++; bullS+="Disc "; }
      if(pda.currentZone==PDA_PREMIUM) { bearC++; bearS+="Prem "; }
      
      // 3. FVG (có FVG gần = confluence, không cần giá đúng trong FVG)
      if(pda.fvgValid)
      {
         if(pda.fvgBullish) { bullC++; bullS+="FVG↑ "; }
         else { bearC++; bearS+="FVG↓ "; }
      }
      
      // 4. OB (có OB gần = confluence)
      if(pda.obValid)
      {
         if(pda.obBullish) { bullC++; bullS+="OB↑ "; }
         else { bearC++; bearS+="OB↓ "; }
      }
      
      // 5. SMT
      if(smt.divergenceDetected)
      {
         if(smt.smtBias==BIAS_BULLISH) { bullC++; bullS+="SMT↑ "; }
         if(smt.smtBias==BIAS_BEARISH) { bearC++; bearS+="SMT↓ "; }
      }
      
      // 6. Liquidity sweep
      if(liq.sslSwept) { bullC++; bullS+="SSL_Swept "; }
      if(liq.bslSwept) { bearC++; bearS+="BSL_Swept "; }
      
      // 7. OHLC/OLHC Daily Bias (x2 weight — quan trọng nhất)
      if(bias.bias==BIAS_BULLISH) { bullC+=2; bullS+="OLHC "; }
      if(bias.bias==BIAS_BEARISH) { bearC+=2; bearS+="OHLC "; }
      
      if(bullC>=minConfluence && bullC>bearC) { signal.direction=BIAS_BULLISH; signal.confluenceCount=bullC; signal.confluences=bullS; signal.isValid=true; }
      else if(bearC>=minConfluence && bearC>bullC) { signal.direction=BIAS_BEARISH; signal.confluenceCount=bearC; signal.confluences=bearS; signal.isValid=true; }
   }
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "═══ CHẾ ĐỘ EA ═══"
input bool     AutoTrade           = true;    // true=Tự vào lệnh, false=Chỉ Alert
input int      MinConfluence       = 3;       // Số confluence tối thiểu để signal

input group "═══ SMT DIVERGENCE ═══"
input string   SMTPairSymbol       = "DXY";   // Symbol tương quan (DXY/USDX)
input bool     SMTInverseCorr      = true;    // Tương quan nghịch (Gold vs DXY)

input group "═══ CẤU TRÚC THỊ TRƯỜNG ═══"
input ENUM_TIMEFRAMES StructureTF  = PERIOD_H1;
input ENUM_TIMEFRAMES EntryTF      = PERIOD_M5;
input int      SwingLength         = 3;          // Giảm để detect nhiều swing hơn

input group "═══ QUẢN LÝ RỦI RO (The5%ers) ═══"
input double   RiskPercent         = 0.5;
input double   MaxSLPercent        = 2.0;     // Max SL % account (The5%ers rule)
input double   DailyLossLimitPct   = 2.0;     // Daily loss limit (firm 5%, ta 2%)
input double   DailyProfitTargetPct= 1.5;
input double   MaxDrawdownPct      = 5.0;     // Kill switch DD (firm 10%, ta 5%)
input int      MaxTradesPerDay     = 3;
input int      MaxConsecutiveLosses= 2;       // Thua 2 = dừng (MINDSET)
input double   FixedLot            = 0.0;

input group "═══ CÀI ĐẶT GIAO DỊCH ═══"
input double   TakeProfitMultiplier= 2.0;
input int      MaxSLPoints         = 400;     // Max SL distance (points) - skip nếu xa hơn
input bool     UseTrailingStop     = true;
input int      TrailingStartPoints = 100;     // Trailing sớm hơn
input int      TrailingStepPoints  = 30;      // Step nhỏ hơn
input bool     UseBreakeven        = true;
input double   BreakevenTriggerR   = 0.5;     // Dời SL về entry khi profit = 0.5R
input int      MaxSpreadPoints     = 500;

input group "═══ SESSION FILTER ═══"
input bool     TradeAsian          = false;
input bool     TradeLondon         = true;
input bool     TradeNY             = true;

input group "═══ DASHBOARD ═══"
input bool     ShowDashboard       = true;
input bool     ShowPDAZones        = true;
input bool     ShowLiquidityLevels = true;
input color    BullColor           = clrDodgerBlue;
input color    BearColor           = clrTomato;
input color    NeutralColor        = clrGray;

input group "═══ AN TOÀN ═══"
input int      MagicNumber         = 260316;
input string   TradeComment        = "ICTv2";

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS                                                   |
//+------------------------------------------------------------------+
CTrade trade; CPositionInfo posInfo; CAccountInfo accInfo; CSymbolInfo symInfo;
CMarketStructure g_structure; CPDA g_pda; CSMT g_smt; CPSP g_psp;
CLiquidity g_liquidity; CDailyBiasEngine g_dailyBias; CConfluenceEngine g_confluence;
ENUM_EA_STATE g_state; DailyStats g_daily;
double g_initialBalance, g_highestBalance; datetime g_lastBarTime, g_lastAlertTime;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symInfo.Name(_Symbol)) { Print("❌ Không thể load symbol: ", _Symbol); return INIT_FAILED; }
   trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(20); trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   g_structure.Init(_Symbol, StructureTF, SwingLength);
   g_pda.Init(_Symbol, EntryTF);
   g_smt.Init(_Symbol, SMTPairSymbol, StructureTF, SMTInverseCorr);
   g_psp.Init(_Symbol);
   g_liquidity.Init(_Symbol, EntryTF, 30);
   g_dailyBias.Init(_Symbol);
   g_confluence.Init(MinConfluence);
   
   g_state = STATE_SCANNING; g_initialBalance = accInfo.Balance();
   g_highestBalance = g_initialBalance; g_lastBarTime = 0; g_lastAlertTime = 0;
   ResetDailyStats();
   
   Print("✅ ICT System EA v2.0 khởi động | Mode: ", AutoTrade ? "AUTO" : "SIGNAL",
         " | Risk: ", DoubleToString(RiskPercent,1), "% | MinConf: ", MinConfluence);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0,"ICT_"); Comment(""); }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   symInfo.RefreshRates();
   if(!CheckKillSwitch()) return;
   CheckDailyReset();
   if(!CheckDailyLimits()) return;
   ManagePositions();
   if(!IsNewBar(EntryTF)) return;
   
   // ===== UPDATE ALL MODULES =====
   g_structure.Update();
   g_pda.Update(g_structure.data.lastSwingHigh.price, g_structure.data.lastSwingLow.price);
   g_smt.Update(); g_psp.Update(); g_liquidity.Update(); g_dailyBias.Update();
   
   double bid=symInfo.Bid(), point=symInfo.Point();
   g_confluence.Evaluate(g_structure.data, g_pda.data, g_smt.data, g_psp.data, g_liquidity.data, g_dailyBias.data, bid, point);
   
   // Debug log mỗi 6 bars (~30 phút M5)
   static int barCount = 0;
   barCount++;
   if(barCount % 6 == 0)
   {
      string trendS = (g_structure.data.trend==BIAS_BULLISH)?"Bull":(g_structure.data.trend==BIAS_BEARISH)?"Bear":"None";
      string pdaS = (g_pda.data.currentZone==PDA_PREMIUM)?"Prem":(g_pda.data.currentZone==PDA_DISCOUNT)?"Disc":"EQ";
      string biasS = (g_dailyBias.data.bias==BIAS_BULLISH)?"OLHC":(g_dailyBias.data.bias==BIAS_BEARISH)?"OHLC":"None";
      Print("[DBG] Bar#",barCount," Bid:",DoubleToString(bid,2),
            " T:",trendS," Z:",pdaS," B:",biasS,
            " FVG:",g_pda.data.fvgValid," OB:",g_pda.data.obValid,
            " SwH:",DoubleToString(g_structure.data.lastSwingHigh.price,2),
            " SwL:",DoubleToString(g_structure.data.lastSwingLow.price,2),
            " Sig:",g_confluence.signal.isValid?g_confluence.signal.confluenceCount:0);
   }
   
   if(ShowDashboard) DrawDashboard();
   if(g_confluence.signal.isValid && g_state == STATE_SCANNING) ProcessSignal();
}

//+------------------------------------------------------------------+
//| PROCESS SIGNAL                                                   |
//+------------------------------------------------------------------+
void ProcessSignal()
{
   SignalData sig = g_confluence.signal;
   double ask=symInfo.Ask(), bid=symInfo.Bid(), point=symInfo.Point();
   int digits=symInfo.Digits();
   double entry, sl, tp, slDist;
   
   if(sig.direction == BIAS_BULLISH)
   {
      entry = ask;
      // SL: dưới OB hoặc swing low, nhưng cap tối đa
      sl = (g_pda.data.obValid && g_pda.data.obBullish) ? g_pda.data.obBottom - 20*point : g_structure.data.lastSwingLow.price - 20*point;
      slDist = entry - sl;
      // Cap SL distance
      if(slDist > MaxSLPoints * point) { sl = entry - MaxSLPoints * point; slDist = MaxSLPoints * point; }
      tp = entry + slDist * TakeProfitMultiplier;
   }
   else
   {
      entry = bid;
      sl = (g_pda.data.obValid && !g_pda.data.obBullish) ? g_pda.data.obTop + 20*point : g_structure.data.lastSwingHigh.price + 20*point;
      slDist = sl - entry;
      if(slDist > MaxSLPoints * point) { sl = entry + MaxSLPoints * point; slDist = MaxSLPoints * point; }
      tp = entry - slDist * TakeProfitMultiplier;
   }
   
   if(slDist <= 0 || slDist/point < 30) return;
   
   double lot = CalculateLotSize(slDist);
   double potLoss = lot * (slDist/symInfo.TickSize()) * symInfo.TickValue();
   double maxLoss = accInfo.Balance() * MaxSLPercent / 100.0;
   if(potLoss > maxLoss) { lot = (maxLoss * symInfo.TickSize()) / (slDist * symInfo.TickValue()); lot = NormalizeLot(lot); }
   
   sl = NormalizeDouble(sl, digits); tp = NormalizeDouble(tp, digits);
   string dir = (sig.direction==BIAS_BULLISH) ? "BUY" : "SELL";
   double rr = (slDist>0) ? MathAbs(tp-entry)/slDist : 0;
   
   Print("\xF0\x9F\x8E\xAF ",dir," Conf:",sig.confluenceCount," E:",DoubleToString(entry,digits),
         " SL:",DoubleToString(sl,digits)," TP:",DoubleToString(tp,digits),
         " RR:1:",DoubleToString(rr,1)," Lot:",DoubleToString(lot,2),
         " SLdist:",DoubleToString(slDist/point,0),"pts");
   
   if(AutoTrade)
   {
      string comment = TradeComment + "_" + dir;
      bool res = (sig.direction==BIAS_BULLISH) ? trade.Buy(lot,_Symbol,ask,sl,tp,comment) : trade.Sell(lot,_Symbol,bid,sl,tp,comment);
      if(res) { g_daily.tradesOpened++; g_state = STATE_IN_TRADE; }
      else Print("Trade failed! Error: ", GetLastError());
   }
   else
   {
      if(TimeCurrent() - g_lastAlertTime < 300) return;
      g_lastAlertTime = TimeCurrent();
      Alert(dir," ",_Symbol," Conf:",sig.confluenceCount); SendNotification(dir+" "+_Symbol);
   }
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT                                                  |
//+------------------------------------------------------------------+
bool CheckKillSwitch()
{
   if(g_state==STATE_KILLED) return false;
   double eq=accInfo.Equity(), bal=accInfo.Balance();
   if(bal>g_highestBalance) g_highestBalance=bal;
   double dd1=(g_initialBalance-eq)/g_initialBalance*100, dd2=(g_highestBalance-eq)/g_highestBalance*100;
   if(dd1>=MaxDrawdownPct) { Print("🚨 KILL DD initial=",DoubleToString(dd1,2),"%"); g_state=STATE_KILLED; CloseAllPositions(); return false; }
   if(dd2>=MaxDrawdownPct) { Print("🚨 KILL DD highest=",DoubleToString(dd2,2),"%"); g_state=STATE_KILLED; CloseAllPositions(); return false; }
   return true;
}

bool CheckDailyLimits()
{
   if(g_state==STATE_DAILY_DONE || g_state==STATE_KILLED) return false;
   double eq=accInfo.Equity(); g_daily.dailyPnL=eq-g_daily.startBalance;
   double pct=g_daily.dailyPnL/g_daily.startBalance*100;
   if(pct<=-DailyLossLimitPct) { Print("⛔ Daily Loss: ",DoubleToString(pct,2),"%"); g_state=STATE_DAILY_DONE; CloseAllPositions(); return false; }
   if(DailyProfitTargetPct>0 && pct>=DailyProfitTargetPct) { Print("🎯 Daily Target: +",DoubleToString(pct,2),"%"); g_state=STATE_DAILY_DONE; return false; }
   if(g_daily.tradesOpened>=MaxTradesPerDay) { g_state=STATE_DAILY_DONE; return false; }
   if(g_daily.consecutiveLosses>=MaxConsecutiveLosses) { Print("🚦 ",g_daily.consecutiveLosses," loss → DỪNG ĐÈN ĐỎ"); g_state=STATE_DAILY_DONE; return false; }
   return true;
}

void CheckDailyReset()
{
   MqlDateTime now,last; TimeToStruct(TimeCurrent(),now); TimeToStruct(g_daily.lastTradeDate,last);
   if(now.day!=last.day || now.mon!=last.mon) { Print("📅 Ngày mới — Reset."); ResetDailyStats(); g_state=STATE_SCANNING; }
}

void ResetDailyStats() { g_daily.tradesOpened=0; g_daily.consecutiveLosses=0; g_daily.dailyPnL=0; g_daily.startBalance=accInfo.Balance(); g_daily.lastTradeDate=TimeCurrent(); }

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+
void ManagePositions()
{
   bool hasPos = false;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      hasPos = true;
      
      double oP=posInfo.PriceOpen(), cSL=posInfo.StopLoss(), cTP=posInfo.TakeProfit();
      double vol=posInfo.Volume();
      double cP=(posInfo.PositionType()==POSITION_TYPE_BUY)?symInfo.Bid():symInfo.Ask();
      double pt=symInfo.Point(); int dg=symInfo.Digits();
      ulong ticket = posInfo.Ticket();
      
      double profPts = (posInfo.PositionType()==POSITION_TYPE_BUY) ? (cP-oP)/pt : (oP-cP)/pt;
      double slD = (posInfo.PositionType()==POSITION_TYPE_BUY) ? (oP-cSL)/pt : (cSL-oP)/pt;
      if(slD <= 0) slD = MaxSLPoints; // fallback
      
      // === 1. TIME-BASED EXIT: 2h không profit → close ===
      datetime openTime = (datetime)posInfo.Time();
      if(TimeCurrent() - openTime > 7200 && profPts < 0) // 2h = 7200s
      {
         Print("⏰ 2h timeout, lỗ ",DoubleToString(profPts,0),"pts → close");
         trade.PositionClose(ticket);
         continue;
      }
      
      // === 2. PARTIAL CLOSE 50% tại 1R ===
      if(profPts >= slD && vol > symInfo.LotsMin())
      {
         double halfLot = NormalizeLot(vol * 0.5);
         if(halfLot >= symInfo.LotsMin())
         {
            trade.PositionClosePartial(ticket, halfLot);
            Print("💰 Partial close 50% tại 1R (+",DoubleToString(profPts,0),"pts)");
         }
      }
      
      // === 3. BREAKEVEN tại 0.5R ===
      if(UseBreakeven && profPts >= slD * BreakevenTriggerR)
      {
         double nSL;
         if(posInfo.PositionType()==POSITION_TYPE_BUY)
         {
            nSL = NormalizeDouble(oP + 5*pt, dg); // +5pts buffer
            if(cSL < nSL) trade.PositionModify(ticket, nSL, cTP);
         }
         else
         {
            nSL = NormalizeDouble(oP - 5*pt, dg);
            if(cSL > nSL || cSL == 0) trade.PositionModify(ticket, nSL, cTP);
         }
      }
      
      // === 4. TRAILING STOP agressive ===
      if(UseTrailingStop && profPts >= TrailingStartPoints)
      {
         double nSL;
         if(posInfo.PositionType()==POSITION_TYPE_BUY)
         {
            nSL = NormalizeDouble(cP - TrailingStepPoints*pt, dg);
            if(nSL > cSL) trade.PositionModify(ticket, nSL, cTP);
         }
         else
         {
            nSL = NormalizeDouble(cP + TrailingStepPoints*pt, dg);
            if(nSL < cSL || cSL == 0) trade.PositionModify(ticket, nSL, cTP);
         }
      }
   }
   if(g_state==STATE_IN_TRADE && !hasPos) g_state=STATE_SCANNING;
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   { if(!posInfo.SelectByIndex(i))continue; if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol)continue; trade.PositionClose(posInfo.Ticket()); }
}

//+------------------------------------------------------------------+
//| LOT CALCULATION                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
{
   if(FixedLot>0) return NormalizeLot(FixedLot);
   double bal=accInfo.Balance(), risk=bal*(RiskPercent/100.0);
   double tv=symInfo.TickValue(), ts=symInfo.TickSize();
   if(tv<=0||ts<=0||slDist<=0) return 0;
   return NormalizeLot((risk*ts)/(slDist*tv));
}

double NormalizeLot(double lot)
{
   double mn=symInfo.LotsMin(), mx=symInfo.LotsMax(), st=symInfo.LotsStep();
   lot=MathFloor(lot/st)*st; lot=MathMax(lot,mn); lot=MathMin(lot,mx);
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
//| UTILITIES                                                        |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES tf) { datetime c=iTime(_Symbol,tf,0); if(c==g_lastBarTime)return false; g_lastBarTime=c; return true; }
bool CheckSpread() { return (int)symInfo.Spread()<=MaxSpreadPoints; }

bool IsAllowedSession()
{
   g_psp.UpdateCurrentSession(); ENUM_SESSION s=g_psp.data.currentSession;
   if(s==SESSION_ASIAN && TradeAsian) return true;
   if(s==SESSION_LONDON && TradeLondon) return true;
   if(s==SESSION_NY && TradeNY) return true;
   return false;
}

//+------------------------------------------------------------------+
//| ON TRADE TRANSACTION                                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal_type==DEAL_TYPE_BUY||trans.deal_type==DEAL_TYPE_SELL)
      {
         if(HistoryDealSelect(trans.deal))
         {
            double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
            long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
            if(entry==DEAL_ENTRY_OUT)
            {
               if(profit<0) { g_daily.consecutiveLosses++; Print("📉 Loss #",g_daily.consecutiveLosses,": $",DoubleToString(profit,2)); }
               else { g_daily.consecutiveLosses=0; Print("📈 Win: +$",DoubleToString(profit,2)); }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   string nl="\n";
   double eq=accInfo.Equity();
   double ddP=(g_highestBalance>0)?(g_highestBalance-eq)/g_highestBalance*100:0;
   double dyP=(g_daily.startBalance>0)?g_daily.dailyPnL/g_daily.startBalance*100:0;
   
   string st;
   switch(g_state) { case STATE_SCANNING:st="🔍 SCAN";break; case STATE_SIGNAL_READY:st="🎯 SIG";break; case STATE_IN_TRADE:st="📊 TRADE";break; case STATE_DAILY_DONE:st="🛑 DONE";break; case STATE_KILLED:st="☠️ KILL";break; default:st="?";break; }
   string bias=(g_dailyBias.data.bias==BIAS_BULLISH)?"OLHC↑":(g_dailyBias.data.bias==BIAS_BEARISH)?"OHLC↓":"---";
   string struc=(g_structure.data.trend==BIAS_BULLISH)?"Bull↑":(g_structure.data.trend==BIAS_BEARISH)?"Bear↓":"---";
   string pda=(g_pda.data.currentZone==PDA_PREMIUM)?"Premium🔴":(g_pda.data.currentZone==PDA_DISCOUNT)?"Discount🟢":"EQ⚪";
   string smt=g_smt.data.divergenceDetected?((g_smt.data.smtBias==BIAS_BULLISH)?"Bull↑":"Bear↓"):"None";
   string conf=g_confluence.signal.isValid?StringFormat("%d(%s)",g_confluence.signal.confluenceCount,g_confluence.signal.confluences):"No sig";
   
   Comment(
      "╔═══ ICT EA v2.0 The5%ers ═══╗"+nl+
      "║ "+st+" | "+(AutoTrade?"AUTO":"SIGNAL")+nl+
      "╠════════════════════════════╣"+nl+
      "║ Bias: "+bias+"("+IntegerToString(g_dailyBias.data.confidence)+"%)" +nl+
      "║ Struct: "+struc+" | PDA: "+pda+nl+
      "║ SMT: "+smt+nl+
      "║ FVG:"+(g_pda.data.fvgValid?"✓":"✗")+" OB:"+(g_pda.data.obValid?"✓":"✗")+" Sweep:"+(g_liquidity.data.bslSwept||g_liquidity.data.sslSwept?"✓":"✗")+nl+
      "║ Conf: "+conf+nl+
      "╠════════════════════════════╣"+nl+
      "║ Eq:$"+DoubleToString(eq,2)+" DD:"+DoubleToString(ddP,2)+"%"+nl+
      "║ Day:"+DoubleToString(dyP,2)+"% T:"+IntegerToString(g_daily.tradesOpened)+"/"+IntegerToString(MaxTradesPerDay)+" L:"+IntegerToString(g_daily.consecutiveLosses)+"/"+IntegerToString(MaxConsecutiveLosses)+nl+
      "╚════════════════════════════╝"
   );
   
   if(ShowPDAZones)
   {
      DrawHL("ICT_EQ",g_pda.data.equilibrium,NeutralColor,STYLE_DOT);
      DrawHL("ICT_Prem",g_pda.data.premiumStart,BearColor,STYLE_DASH);
      DrawHL("ICT_Disc",g_pda.data.discountEnd,BullColor,STYLE_DASH);
      if(g_pda.data.fvgValid) DrawRect("ICT_FVG",g_pda.data.fvgTop,g_pda.data.fvgBottom,g_pda.data.fvgBullish?BullColor:BearColor);
      if(g_pda.data.obValid) DrawRect("ICT_OB",g_pda.data.obTop,g_pda.data.obBottom,g_pda.data.obBullish?BullColor:BearColor);
   }
   if(ShowLiquidityLevels)
   {
      DrawHL("ICT_BSL",g_liquidity.data.bslLevel,BearColor,STYLE_DASHDOT);
      DrawHL("ICT_SSL",g_liquidity.data.sslLevel,BullColor,STYLE_DASHDOT);
      if(g_liquidity.data.equalHighs) DrawHL("ICT_EQH",g_liquidity.data.equalHighPrice,clrOrange,STYLE_DOT);
      if(g_liquidity.data.equalLows) DrawHL("ICT_EQL",g_liquidity.data.equalLowPrice,clrOrange,STYLE_DOT);
   }
}

void DrawHL(string name, double price, color clr, ENUM_LINE_STYLE style)
{
   if(price<=0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
}

void DrawRect(string name, double p1, double p2, color clr)
{
   if(p1<=0||p2<=0) return;
   datetime t1=iTime(_Symbol,PERIOD_M5,20), t2=TimeCurrent()+PeriodSeconds(PERIOD_H1);
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,p1); ObjectSetDouble(0,name,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1); ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr); ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
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
