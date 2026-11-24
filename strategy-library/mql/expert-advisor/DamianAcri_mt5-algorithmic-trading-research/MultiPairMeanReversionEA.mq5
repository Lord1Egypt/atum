
//+------------------------------------------------------------------+
//|                                    MultiPairMeanReversionEA.mq5  |
//|                                      Mean-reversion grid system  |
//|                                  Multi-pair research implementation|
//+------------------------------------------------------------------+
#property copyright "Damian Acri <damianacridev@gmail.com>"
#property link      ""
#property version   "2.11"
#property strict
#property description "Mean Reversion Grid EA for AUDNZD, AUDCAD, NZDCAD"
#property description "Uses Bollinger Bands and RSI entries with basket management"
#property description "v2.11: RSI cap mode, failsafe SL, daily drawdown controls, max open lots, TP updates"

// DESIGN NOTES:
// - Safeguards are exposed as optional inputs and integrated into the main flow.
// - The implementation has no external runtime dependencies.

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                             |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
{
   LOT_MODE_FIXED,              // Fixed Lot
   LOT_MODE_DYNAMIC,            // Dynamic (Balance/Equity based)
   LOT_MODE_DEPOSIT_LOAD,       // Deposit Load %
   LOT_MODE_DEPOSIT_LOAD_FIXED, // Deposit Load % (Fixed Initial Balance)
   LOT_MODE_LOW_RISK,           // Low exposure profile
   LOT_MODE_MEDIUM_RISK,        // Medium exposure profile
   LOT_MODE_HIGH_RISK,          // High exposure profile
   LOT_MODE_SIGNIFICANT_RISK    // Significant exposure profile
};

enum ENUM_TRADE_DIRECTION
{
   TRADE_BOTH,                  // Buy and Sell
   TRADE_BUY_ONLY,              // Buy Only
   TRADE_SELL_ONLY              // Sell Only
};

enum ENUM_DD_ACTION
{
   DD_ACTION_CLOSE_STOP,        // Close trades & stop trading
   DD_ACTION_CLOSE_CONTINUE,    // Close trades & continue
   DD_ACTION_STOP_ONLY          // Stop new trades only
};

enum ENUM_DD_CALCULATION
{
   DD_CALC_THIS_EA,             // This EA only
   DD_CALC_ACCOUNT              // The entire account
};

enum ENUM_TREND_FILTER_MODE
{
   TREND_BLOCK_AGAINST = 0,     // Block trades against the MA trend
   TREND_ONLY_WITH     = 1      // Only trade with MA trend (same as block-against, kept for clarity)
};

// RSI entry logic modes
enum ENUM_RSI_ENTRY_MODE
{
   RSI_MODE_CAP = 0,            // If RSI > MaxRSI => SKIP any entry (cap/safety filter)
   RSI_MODE_CLASSIC_MINMAX = 1, // Classic: SELL if RSI >= MaxRSI, BUY if RSI <= MinRSI
   RSI_MODE_DISABLED = 2        // Ignore RSI filter entirely
};

// NEW: Daily drawdown action
enum ENUM_DAILY_DD_ACTION
{
   DAILY_DD_CLOSE_AND_BLOCK = 0, // Close all EA positions and block new trades until reset
   DAILY_DD_BLOCK_ONLY      = 1  // Block new trades until reset (do not force-close)
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - MM & Risk Settings                             |
//+------------------------------------------------------------------+
input group "===== MM & Risk Settings ====="
input bool              InpAllowNewGrid = true;                    // Allow Opening a new Grid?
input ENUM_LOT_MODE     InpLotMode = LOT_MODE_DEPOSIT_LOAD_FIXED;  // Lot-sizing Method
input double            InpFixedLot = 0.01;                        // Fixed Lot
input double            InpDynamicLot = 10000.0;                   // Dynamic Lot (Balance per 0.01 lot)
input double            InpDepositLoad = 0.15;                     // Deposit Load % (0.15 = 15%)
input double            InpFixedDepositBase = 0.0;                 // Fixed Deposit Base (0=use initial balance)
input double            InpMaxLot = 100.0;                         // Maximum Lot
input double            InpMaxSpread = 10.0;                       // Maximum Spread, in pips
input double            InpMaxSlippage = 10.0;                     // Maximum Slippage for non-ECN, in pips
input int               InpMaxSymbols = 2;                         // Maximum Symbols at a time
input double            InpMaxOpenLots = 0.0;                      // Max Open Lots (Filter) [0=disabled]
input bool              InpAllowHolidays = false;                  // Allow Trading on Holidays? (basic calendar keyword check)
input ENUM_TRADE_DIRECTION InpTradeDirection = TRADE_BOTH;         // Allow to Buy/Sell
input double            InpMinFreeMargin = 0.0;                    // Minimum Free Margin % [0=disabled]
input double            InpMaxDrawdownPercent = 100.0;             // Max Floating Drawdown % [100=disabled]
input double            InpMaxDrawdownMoney = 0.0;                 // Max Floating Drawdown in Money [0=disabled]
input ENUM_DD_ACTION    InpDDAction = DD_ACTION_CLOSE_STOP;        // Max Drawdown Action
input ENUM_DD_CALCULATION InpDDCalculation = DD_CALC_THIS_EA;      // Max Drawdown Calculation

// NEW: Daily drawdown controls
input double            InpDailyDDPercent = 0.0;                   // Max Daily Drawdown % [0=disabled]
input double            InpDailyDDMoney   = 0.0;                   // Max Daily Drawdown $ [0=disabled]
input int               InpDailyDDResetHour = 0;                   // Daily DD reset hour (broker time, 0..23)
input ENUM_DAILY_DD_ACTION InpDailyDDAction = DAILY_DD_CLOSE_AND_BLOCK; // Daily DD action
input bool              InpDailyDDCalcAccount = true;              // If true use account equity; else EA-only equity

// --- Circuit Breaker A/B/C --- (disabled by default)
// (kept as OPTIONAL safety feature; set >0 to enable)
input double            InpCB_FreezeDDPercent = 0.0;               // CircuitBreaker A: Freeze grids at DD% (0=off)
input double            InpCB_ReduceDDPercent = 0.0;               // CircuitBreaker B: Reduce exposure at DD% (0=off)
input double            InpCB_KillDDPercent   = 0.0;               // CircuitBreaker C: Kill-switch at DD% (0=off)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Strategy Settings                              |
//+------------------------------------------------------------------+
input group "===== Strategy Settings ====="
input string            InpSymbols = "";                           // Symbols (comma separated, empty=default)
input int               InpHourStart = 0;                          // Hour to Start Trading (broker's time)
input int               InpHourStop = 0;                           // Hour to Stop Trading (0=24h)

input bool              InpUseClosedBarSignal = true;              // Use last CLOSED bar price for signal checks
input ENUM_RSI_ENTRY_MODE InpRSIEntryMode = RSI_MODE_CAP;          // RSI entry logic mode

input int               InpBBPeriod = 20;                          // Bollinger Bands Period
input double            InpBBDeviation = 2.0;                      // Bollinger Bands Deviation
input int               InpRSIPeriod = 14;                         // RSI Period
input int               InpMinRSI = 0;                             // Min RSI (used by CLASSIC mode; 0=unused)
input int               InpMaxRSI = 70;                            // Max RSI (cap or classic sell threshold)
input ENUM_TIMEFRAMES   InpWorkingTF = PERIOD_M15;                 // Working Timeframe

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Grid Settings                                  |
//+------------------------------------------------------------------+
input group "===== Grid Settings ====="
input int               InpTradeDistance = 35;                     // Trade Distance (base pips)
input bool              InpSmartDistance = true;                   // Smart Distance (volatility adjusted)
input int               InpATRPeriod = 14;                         // ATR Period (for Smart Distance)
input double            InpATRMultiplier = 1.0;                    // ATR Multiplier
input double            InpMult2nd = 1.5;                          // 2nd Trade Multiplier (1.0=same lot)
input double            InpMult3to5 = 2.0;                         // 3rd-5th Trade Multiplier
input double            InpMult6Plus = 2.5;                        // 6th+ Trade Multiplier
input int               InpMaxTrades = 9;                          // Maximum Trades per grid

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Take Profit Settings                           |
//+------------------------------------------------------------------+
input group "===== TakeProfit Settings ====="
input double            InpTPInitial = 10.0;                       // TakeProfit for Initial Trade (pips)
input double            InpTPGrid = 0.0;                           // TakeProfit for Grid (0=weighted mode)
input bool              InpCoverSwaps = true;                      // Cover Swaps in TP calculation
input bool              InpAdjustTPOnNewLevel = true;              // Do NOT adjust TP unless new grid level opened
input double            InpIncreaseTPDuringNewsPips = 0.0;         // Increase TP target during news (pips on initial lot; 0=off)
input bool              InpRemoveTPDuringRollover = false;         // Temporarily remove TP during rollover window

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Staged Exit Settings                           |
//+------------------------------------------------------------------+
input group "===== Staged Exit Management ====="
input bool              InpUseExitStages = true;                   // Enable staged TP reduction / early exit logic
input int               InpStage1_MinLevel = 4;                    // Stage #1 triggers after this grid level (0=off)
input int               InpStage1_AfterBars = 0;                   // Stage #1 triggers after this many bars (0=off)
input int               InpStage1_AfterMinutes = 0;                // Stage #1 triggers after this many minutes (0=off)
input double            InpStage1_TargetPips = 2.0;                // Stage #1 target (pips-equivalent on initial lot; can be 0 or negative)

input int               InpStage2_MinLevel = 6;                    // Stage #2 triggers after this grid level (0=off)
input int               InpStage2_AfterBars = 0;                   // Stage #2 triggers after this many bars (0=off)
input int               InpStage2_AfterMinutes = 0;                // Stage #2 triggers after this many minutes (0=off)
input double            InpStage2_TargetPips = 0.0;                // Stage #2 target (0=breakeven-equivalent on initial lot)

input int               InpStage3_MinLevel = 8;                    // Stage #3 triggers after this grid level (0=off)
input int               InpStage3_AfterBars = 0;                   // Stage #3 triggers after this many bars (0=off)
input int               InpStage3_AfterMinutes = 1440;             // Stage #3 triggers after this many minutes (0=off)
input double            InpStage3_TargetPips = -2.0;               // Stage #3 target (can be negative: accept small loss)

input int               InpBreakEvenAfterLevel = 0;                // Force BE-style target after this level (0=off)
input double            InpBreakEvenOffsetPips = 0.0;              // BE offset in pips-equivalent (0 = strict BE)

input bool              InpApplyBasketTPToPositions = true;        // If true, sets TP on each position to basketTP price

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Trend / Prudence Filter (Optional)             |
//+------------------------------------------------------------------+
input group "===== Trend / Prudence Filter (Optional) ====="
input bool              InpUseTrendFilter = false;                 // Use higher-TF MA filter for new grids
input ENUM_TIMEFRAMES   InpTrendTF = PERIOD_H4;                    // Trend timeframe
input int               InpTrendMAPeriod = 200;                    // MA period
input ENUM_MA_METHOD    InpTrendMAMethod = MODE_EMA;               // MA method
input ENUM_APPLIED_PRICE InpTrendMAPrice = PRICE_CLOSE;            // Applied price
input ENUM_TREND_FILTER_MODE InpTrendFilterMode = TREND_BLOCK_AGAINST; // Mode

input bool              InpADXFilter = false;                      // Use ADX to avoid strong trends (optional)
input ENUM_TIMEFRAMES   InpADXTF = PERIOD_D1;                      // ADX timeframe
input int               InpADXPeriod = 14;                         // ADX period
input double            InpADXMax = 25.0;                          // If ADX > this, block new grids (and optionally add-levels)
input bool              InpADXBlockAddLevels = false;              // If true, also block adding levels when ADX is high

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Grid Runaway Protection / Skip-Pause Logic     |
//+------------------------------------------------------------------+
input group "===== Grid Runaway Protection ====="
input bool              InpRunawayProtection = false;              // Enable runaway guard
input double            InpRunawayMoveATRMult = 2.0;               // If move since last entry > ATR*mult, pause adding levels
input int               InpRunawayFreezeMinutes = 60;              // Pause duration (minutes)
input double            InpRunawayBasketDDPercent = 0.0;           // If basket DD% >= this, pause adding levels (0=off)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Stop Loss Settings                             |
//+------------------------------------------------------------------+
input group "===== StopLoss Settings ====="
input double            InpSLGrid = 0.0;                           // StopLoss for Grid in pips (0=use failsafe if enabled)
input bool              InpUseFailsafeSL = true;                   // If SLGrid=0, use a failsafe stop loss
input double            InpFailsafeSLPips = 1000.0;                // Failsafe SL distance (pips)
input bool              InpHideSL = true;                          // Hide StopLoss from broker (true=hidden SL checks)
input double            InpTrailingSLSize = 0.0;                   // Trailing SL Size (pips, 0=disabled)
input double            InpTrailingSLStart = 0.0;                  // Trailing SL Start (pips profit)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - News Filter Settings                           |
//+------------------------------------------------------------------+
input group "===== News Filter Settings ====="
input bool              InpUseNewsFilter = true;                   // News Filter Enabled
input int               InpNewsMinutesBefore = 30;                 // Minutes Before News Event
input int               InpNewsMinutesAfter = 30;                  // Minutes After News Event
input int               InpNewsLookForwardDays = 7;                // Days to Look Forward
input string            InpNewsKeywords = "NFP,FOMC,CPI,GDP,Interest Rate,Employment,Retail Sales,PMI"; // News Keywords
input string            InpNewsCurrencies = "USD,EUR,GBP,AUD,NZD,CAD,JPY,CHF"; // Currencies to Monitor
input string            InpNewsSeparator = ",";                    // Separator for lists
input bool              InpNewsUseFallbackWindow = true;           // Use Fallback if Calendar Unavailable
input int               InpFallbackStartHour = 12;                 // Fallback Block Start Hour (UTC)
input int               InpFallbackEndHour = 16;                   // Fallback Block End Hour (UTC)
input bool              InpNewsDebug = false;                      // Debug News Filter

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Stock Market Crash Filter                      |
//+------------------------------------------------------------------+
input group "===== Stock Market Crash Filter ====="
input bool              InpCrashFilterEnabled = false;             // Crash Filter Enabled
input string            InpCrashSymbol = "US500";                  // Index Symbol (SP500)
input int               InpCrashATRPeriod = 14;                    // ATR Period for Volatility
input ENUM_TIMEFRAMES   InpCrashTimeframe = PERIOD_D1;             // Timeframe for Crash Check
input double            InpCrashVolatilityThreshold = 2.0;         // Volatility Threshold (ATR multiplier)
input int               InpCrashLookback = 100;                    // Lookback Period for Normal Volatility

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Rollover Filter Settings                       |
//+------------------------------------------------------------------+
input group "===== Rollover Filter Settings ====="
input bool              InpRolloverFilter = true;                  // Rollover Filter Enabled
input int               InpRolloverStartHour = 23;                 // Rollover Start Hour
input int               InpRolloverStartMin = 45;                  // Rollover Start Minute
input int               InpRolloverEndHour = 0;                    // Rollover End Hour
input int               InpRolloverEndMin = 15;                    // Rollover End Minute

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Friday Filter                                  |
//+------------------------------------------------------------------+
input group "===== Friday Settings ====="
input int               InpFridayCloseHour = 0;                    // Hour to Close on Friday (0=disabled)
input bool              InpFridayStopNewTrades = false;            // Stop New Trades on Friday
input int               InpFridayFreezeAddLevelsHour = 0;          // Freeze adding grid levels after this hour on Friday (0=disabled)
input bool              InpFridayCloseOnlyIfProfit    = true;      // If Friday close triggers, close baskets only if >=0 profit
input double            InpFridayMaxLossToCloseMoney  = 0.0;       // Allow closing even if loss is up to this (0=profit-only)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - Miscellaneous                                  |
//+------------------------------------------------------------------+
input group "===== Miscellaneous ====="
input int               InpMagicNumber = 84570;                    // Magic Number (base)
input int               InpUID = 0;                                // Unique ID (0-9 for multiple instances)
input string            InpTradeComment = "MultiPairMeanReversionEA";               // Trade Comment
input bool              InpShowPanel = true;                       // Show Info Panel
input bool              InpRandomizeTPSL = false;                  // Randomize TP/SL (small offset)
input int               InpRandomDelay = 0;                        // Random Delay before orders (seconds)
input bool              InpCheckMarginAll = true;                  // Check Margin for all Grid Levels

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CAccountInfo   accInfo;
CSymbolInfo    symInfo;

// Default symbols
string         g_Symbols[];
int            g_SymbolCount = 0;

// Indicator handles per symbol
struct SymbolData
{
   string      symbol;
   int         bbHandle;
   int         rsiHandle;
   int         atrHandle;

   // Optional filters
   int         maHandle;        // trend MA (optional)
   int         adxHandle;       // ADX (optional)

   // Buffers
   double      bbUpper[];
   double      bbMiddle[];
   double      bbLower[];
   double      rsi[];
   double      atr[];
   double      ma[];
   double      adx[];

   // Grid state
   int         gridCount;
   int         gridDirection;  // 1=buy, -1=sell, 0=none
   double      lastEntryPrice;
   double      initialLot;
   double      basketTP;
   datetime    lastTradeTime;

   // NEW: staged exit / timing
   datetime    firstTradeTime;

   // NEW: runaway freeze for adding levels
   datetime    addFreezeUntil;

   // NEW: UI/debug
   int         currentExitStage;
   double      currentTargetProfitMoney;

   // NEW: TP application tracking (for "adjust only on new level")
   int         lastTPApplyGridCount;
   int         lastTPApplyStage;
   bool        tpRemovedDuringRollover;
};

SymbolData     g_Data[];
int            g_ActiveGrids = 0;
double         g_InitialBalance = 0;
double         g_FixedLotBase = 0;           // Fixed base for lot calculation
bool           g_TradingAllowed = true;
datetime       g_LastNewsCheck = 0;
bool           g_NewsBlocked = false;
datetime       g_lastNewsDebugDay = 0;
int            g_CrashATRHandle = INVALID_HANDLE;
bool           g_CrashFilterActive = false;

// Freeze flags / circuit-breaker state
bool g_FreezeNewGrids      = false;
bool g_FreezeAddLevels     = false;
bool g_CB_ReduceDoneToday  = false;
datetime g_CB_DayMarker    = 0;

// NEW: per-tick "new orders allowed" flag (we still manage open grids even if false)
bool g_NewOrdersAllowed = true;

// NEW: Daily DD tracking
datetime g_DailyResetAnchor = 0;
double   g_DailyStartEquity = 0.0;
bool     g_DailyBlocked = false;
datetime g_DailyBlockedUntil = 0;

//+------------------------------------------------------------------+
//| Helpers: robust pip/spread/slippage                               |
//+------------------------------------------------------------------+
double PipSize(const string sym)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

double SpreadPips(const string sym)
{
   long spreadPoints = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double pip = PipSize(sym);
   if(pip <= 0.0) return 0.0;
   return (spreadPoints * point) / pip;
}

ulong SlippagePoints(const string sym)
{
   double pip = PipSize(sym);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0) return 0;
   double pts = InpMaxSlippage * (pip / point);
   if(pts < 0) pts = 0;
   return (ulong)MathRound(pts);
}

double ProfitPerPipPerLot(const string sym)
{
   symInfo.Name(sym);
   double pipValue = PipSize(sym);
   double tickValue = symInfo.TickValue();
   double tickSize = symInfo.TickSize();
   if(tickSize <= 0.0) return 0.0;
   return (tickValue / tickSize) * pipValue;
}

//+------------------------------------------------------------------+
//| Helpers: Magic V2 + backward-compatible parsing                   |
//+------------------------------------------------------------------+
#define MAGIC_DIR_FACTOR   1000000000LL
#define MAGIC_BASE_FACTOR  1000LL

long GetMagicNumberV2(const int direction, const int tradeIndex)
{
   return (long)direction * (long)MAGIC_DIR_FACTOR
        + (long)InpMagicNumber * (long)MAGIC_BASE_FACTOR
        + (long)InpUID * 100L
        + (long)tradeIndex;
}

bool ParseMagic(const long magic, int &direction, int &uid, int &tradeIndex, bool &isV2)
{
   direction = (int)(magic / (long)MAGIC_DIR_FACTOR);
   long tail = magic % (long)MAGIC_DIR_FACTOR;

   long basePartV2 = tail / (long)MAGIC_BASE_FACTOR;
   long remV2      = tail % (long)MAGIC_BASE_FACTOR;

   int uidV2       = (int)(remV2 / 100L);
   int idxV2       = (int)(remV2 % 100L);

   if(direction >= 0 && direction <= 2 && uidV2 >= 0 && uidV2 <= 9 && idxV2 >= 0 && idxV2 <= 99)
   {
      if(basePartV2 == (long)InpMagicNumber)
      {
         uid = uidV2;
         tradeIndex = idxV2;
         isV2 = true;
         return true;
      }
   }

   // Version 1 compatibility
   direction = (int)(magic / 100000000L);
   long tailV1 = magic % 100000000L;
   int idxV1 = (int)(tailV1 % 100L);
   long combined = (tailV1 / 100L);

   if(direction >= 0 && direction <= 2 && idxV1 >= 0 && idxV1 <= 99)
   {
      if(combined == (long)(InpMagicNumber + InpUID))
      {
         uid = InpUID;
         tradeIndex = idxV1;
         isV2 = false;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Circuit breaker helpers                                           |
//+------------------------------------------------------------------+
void CircuitBreaker_ResetDaily()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
   if(today != g_CB_DayMarker)
   {
      g_CB_DayMarker = today;
      g_CB_ReduceDoneToday = false;
      // Reset freeze flags daily (if DD recovered)
      g_FreezeNewGrids = false;
      g_FreezeAddLevels = false;
   }
}

// Forward declarations
int FindWorstBasketIndex();
double GetBasketProfit(int idx);
void CloseBasket(int idx);
void CloseAllPositions();
bool InitializeSymbols();
bool InitializeIndicators();
void ScanExistingPositions();
int GetSymbolIndex(string symbol);
long GetMagicNumber(int direction, int tradeIndex);
bool IsMagicNumberOurs(long magic);
bool CheckTradingConditions();           // NEW ORDERS only (open/add) - open grids are still managed regardless
bool CheckTimeFilter();
bool IsRolloverPeriod();
bool CheckFridayFilter();
bool CheckDrawdownLimits();
double GetEAFloatingPL();
void HandleDrawdownEvent();
void ProcessSymbol(int idx);
bool UpdateIndicators(int idx);
void CheckEntrySignal(int idx);
void OpenInitialTrade(int idx, int direction);
double CalculateLotSize(int idx);
double CalculateDepositLoadLot(int idx, double loadPercent, double depositBase);
double NormalizeLot(string sym, double lot);
double CalculateFullGridMargin(int idx, double initialLot);
void ManageGrid(int idx);
void CheckHiddenSL(int idx);
void UpdateGridState(int idx);
void CheckAddGridLevel(int idx);
void AddGridLevel(int idx);
void ManageBasketTP(int idx);
double CalculateTargetProfit(int idx);
void UpdateWeightedTP(int idx, double targetProfitMoney, int stage); // UPDATED
void ManageTrailingStop(int idx);
void CreatePanel();
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold);
void UpdatePanel();
int SplitList(string text, string sep, string &result[]);
bool IsNewsRestrictedNow();
bool InitializeCrashFilter();
bool IsMarketCrashActive();

// NEW helpers
int BarsSinceTime(const string sym, ENUM_TIMEFRAMES tf, datetime t);
int GetExitStage(int idx, int barsOpen, int minutesOpen);
double GetTargetProfitMoneyForStage(int idx, int stage);
bool IsDirectionAllowedByTrend(int idx, int direction);
bool IsADXAllowed(int idx);
void ApplyBasketTPToPositions(int idx, double tpPrice);
bool ShouldRunawayFreezeAddLevels(int idx, double currentPrice, double lastEntryPrice);

double GetTotalOpenLotsEA();
bool CanOpenMoreLots(double addLots);
double EffectiveSLPips(); // returns either InpSLGrid or failsafe if enabled

void DailyDD_UpdateAnchor();
bool DailyDD_IsBlocked();
void DailyDD_CheckAndHandle();

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpUID < 0 || InpUID > 9)
   {
      Print("UID must be between 0 and 9");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(GetMagicNumber(0, 0));
   // Slippage is set per-order (multi-symbol, multi-digits), see OpenInitialTrade/AddGridLevel
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   if(!InitializeSymbols())
      return INIT_FAILED;

   if(!InitializeIndicators())
      return INIT_FAILED;

   // Store initial balance for fixed lot calculation
   g_InitialBalance = accInfo.Balance();

   // Set fixed lot base
   if(InpFixedDepositBase > 0)
      g_FixedLotBase = InpFixedDepositBase;
   else
      g_FixedLotBase = g_InitialBalance;

   Print("Fixed lot base set to: ", g_FixedLotBase);

   // Init daily DD anchor
   DailyDD_UpdateAnchor();

   ScanExistingPositions();

   if(InpCrashFilterEnabled)
   {
      if(!InitializeCrashFilter())
         Print("Warning: Crash filter symbol not available: ", InpCrashSymbol);
   }

   if(InpShowPanel)
      CreatePanel();

   Print("MultiPairMeanReversionEA v2.11 initialized. Symbols: ", g_SymbolCount,
         " | MaxTrades: ", InpMaxTrades,
         " | Mults: ", InpMult2nd, "/", InpMult3to5, "/", InpMult6Plus,
         " | RSI mode: ", (int)InpRSIEntryMode);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Data[i].bbHandle != INVALID_HANDLE)
         IndicatorRelease(g_Data[i].bbHandle);
      if(g_Data[i].rsiHandle != INVALID_HANDLE)
         IndicatorRelease(g_Data[i].rsiHandle);
      if(g_Data[i].atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_Data[i].atrHandle);

      if(g_Data[i].maHandle != INVALID_HANDLE)
         IndicatorRelease(g_Data[i].maHandle);
      if(g_Data[i].adxHandle != INVALID_HANDLE)
         IndicatorRelease(g_Data[i].adxHandle);
   }

   if(g_CrashATRHandle != INVALID_HANDLE)
      IndicatorRelease(g_CrashATRHandle);

   if(InpShowPanel)
      ObjectsDeleteAll(0, "MultiPairMeanReversionEA_");

   Print("MultiPairMeanReversionEA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Reset freeze flags at start of each tick (will be re-set if needed)
   static datetime lastResetCheck = 0;
   if(TimeCurrent() - lastResetCheck > 60) // Check every minute
   {
      lastResetCheck = TimeCurrent();
      // Only reset if not in Friday freeze
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week != 5)
      {
         g_FreezeNewGrids = false;
         g_FreezeAddLevels = false;
      }
   }

   // Daily DD anchor update + check
   DailyDD_UpdateAnchor();
   DailyDD_CheckAndHandle();

   if(!CheckDrawdownLimits())
      return;

   if(InpShowPanel)
      UpdatePanel();

   // IMPORTANT: We compute NEW ORDER conditions (open/add). We still manage existing grids regardless.
   g_NewOrdersAllowed = CheckTradingConditions();

   for(int i = 0; i < g_SymbolCount; i++)
   {
      ProcessSymbol(i);
   }
}

//+------------------------------------------------------------------+
//| Initialize symbols array                                          |
//+------------------------------------------------------------------+
bool InitializeSymbols()
{
   string symbolList = InpSymbols;

   if(StringLen(symbolList) == 0)
      symbolList = "AUDNZD,AUDCAD,NZDCAD";

   string tempSymbols[];
   int count = StringSplit(symbolList, ',', tempSymbols);

   if(count == 0)
   {
      Print("No symbols specified");
      return false;
   }

   ArrayResize(g_Symbols, count);
   ArrayResize(g_Data, count);
   g_SymbolCount = 0;

   for(int i = 0; i < count; i++)
   {
      string sym = tempSymbols[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);

      if(!SymbolSelect(sym, true))
      {
         Print("Symbol not found: ", sym);
         continue;
      }

      g_Symbols[g_SymbolCount] = sym;

      g_Data[g_SymbolCount].symbol = sym;
      g_Data[g_SymbolCount].bbHandle = INVALID_HANDLE;
      g_Data[g_SymbolCount].rsiHandle = INVALID_HANDLE;
      g_Data[g_SymbolCount].atrHandle = INVALID_HANDLE;
      g_Data[g_SymbolCount].maHandle  = INVALID_HANDLE;
      g_Data[g_SymbolCount].adxHandle = INVALID_HANDLE;

      g_Data[g_SymbolCount].gridCount = 0;
      g_Data[g_SymbolCount].gridDirection = 0;
      g_Data[g_SymbolCount].lastEntryPrice = 0;
      g_Data[g_SymbolCount].initialLot = 0;
      g_Data[g_SymbolCount].basketTP = 0;
      g_Data[g_SymbolCount].lastTradeTime = 0;

      g_Data[g_SymbolCount].firstTradeTime = 0;
      g_Data[g_SymbolCount].addFreezeUntil = 0;
      g_Data[g_SymbolCount].currentExitStage = 0;
      g_Data[g_SymbolCount].currentTargetProfitMoney = 0;

      g_Data[g_SymbolCount].lastTPApplyGridCount = -1;
      g_Data[g_SymbolCount].lastTPApplyStage = -1;
      g_Data[g_SymbolCount].tpRemovedDuringRollover = false;

      ArraySetAsSeries(g_Data[g_SymbolCount].bbUpper, true);
      ArraySetAsSeries(g_Data[g_SymbolCount].bbMiddle, true);
      ArraySetAsSeries(g_Data[g_SymbolCount].bbLower, true);
      ArraySetAsSeries(g_Data[g_SymbolCount].rsi, true);
      ArraySetAsSeries(g_Data[g_SymbolCount].atr, true);
      ArraySetAsSeries(g_Data[g_SymbolCount].ma, true);
      ArraySetAsSeries(g_Data[g_SymbolCount].adx, true);

      g_SymbolCount++;
   }

   if(g_SymbolCount == 0)
   {
      Print("No valid symbols found");
      return false;
   }

   ArrayResize(g_Symbols, g_SymbolCount);
   ArrayResize(g_Data, g_SymbolCount);

   return true;
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                      |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      string sym = g_Data[i].symbol;

      g_Data[i].bbHandle = iBands(sym, InpWorkingTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      if(g_Data[i].bbHandle == INVALID_HANDLE)
      {
         Print("Failed to create BB handle for ", sym);
         return false;
      }

      g_Data[i].rsiHandle = iRSI(sym, InpWorkingTF, InpRSIPeriod, PRICE_CLOSE);
      if(g_Data[i].rsiHandle == INVALID_HANDLE)
      {
         Print("Failed to create RSI handle for ", sym);
         return false;
      }

      g_Data[i].atrHandle = iATR(sym, InpWorkingTF, InpATRPeriod);
      if(g_Data[i].atrHandle == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle for ", sym);
         return false;
      }

      if(InpUseTrendFilter)
      {
         g_Data[i].maHandle = iMA(sym, InpTrendTF, InpTrendMAPeriod, 0, InpTrendMAMethod, InpTrendMAPrice);
         if(g_Data[i].maHandle == INVALID_HANDLE)
            Print("Warning: failed to create MA handle for trend filter on ", sym);
      }

      if(InpADXFilter)
      {
         g_Data[i].adxHandle = iADX(sym, InpADXTF, InpADXPeriod);
         if(g_Data[i].adxHandle == INVALID_HANDLE)
            Print("Warning: failed to create ADX handle for trend strength filter on ", sym);
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Scan existing positions to restore grid state                     |
//+------------------------------------------------------------------+
void ScanExistingPositions()
{
   g_ActiveGrids = 0;

   for(int i = 0; i < g_SymbolCount; i++)
   {
      g_Data[i].gridCount = 0;
      g_Data[i].gridDirection = 0;
      g_Data[i].lastEntryPrice = 0;
      g_Data[i].initialLot = 0;
      g_Data[i].basketTP = 0;
      g_Data[i].lastTradeTime = 0;
      g_Data[i].firstTradeTime = 0;
      g_Data[i].addFreezeUntil = 0;
      g_Data[i].currentExitStage = 0;
      g_Data[i].currentTargetProfitMoney = 0;
      g_Data[i].lastTPApplyGridCount = -1;
      g_Data[i].lastTPApplyStage = -1;
      g_Data[i].tpRemovedDuringRollover = false;
   }

   int total = PositionsTotal();
   for(int j = 0; j < total; j++)
   {
      if(!posInfo.SelectByIndex(j))
         continue;

      long magic = posInfo.Magic();
      if(!IsMagicNumberOurs(magic))
         continue;

      string sym = posInfo.Symbol();
      int idx = GetSymbolIndex(sym);
      if(idx < 0)
         continue;

      g_Data[idx].gridCount++;

      // direction and initial lot (first seen)
      if(g_Data[idx].gridCount == 1)
      {
         g_Data[idx].gridDirection = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
         g_Data[idx].initialLot = posInfo.Volume();
         g_ActiveGrids++;
      }

      // track worst/lastEntry for grid
      if(g_Data[idx].lastEntryPrice == 0 ||
         (g_Data[idx].gridDirection == 1 && posInfo.PriceOpen() < g_Data[idx].lastEntryPrice) ||
         (g_Data[idx].gridDirection == -1 && posInfo.PriceOpen() > g_Data[idx].lastEntryPrice))
      {
         g_Data[idx].lastEntryPrice = posInfo.PriceOpen();
      }

      // earliest open time
      datetime ot = (datetime)posInfo.Time();
      if(g_Data[idx].firstTradeTime == 0 || ot < g_Data[idx].firstTradeTime)
         g_Data[idx].firstTradeTime = ot;

      // latest open time
      if(g_Data[idx].lastTradeTime == 0 || ot > g_Data[idx].lastTradeTime)
         g_Data[idx].lastTradeTime = ot;
   }

   Print("Scanned existing positions. Active grids: ", g_ActiveGrids);
}

//+------------------------------------------------------------------+
//| Get symbol index in array                                         |
//+------------------------------------------------------------------+
int GetSymbolIndex(string symbol)
{
   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Data[i].symbol == symbol)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Generate magic number                                             |
//+------------------------------------------------------------------+
long GetMagicNumber(int direction, int tradeIndex)
{
   return GetMagicNumberV2(direction, tradeIndex);
}

//+------------------------------------------------------------------+
//| Check if magic number belongs to this EA                          |
//+------------------------------------------------------------------+
bool IsMagicNumberOurs(long magic)
{
   int dir, uid, idx;
   bool isV2;
   if(!ParseMagic(magic, dir, uid, idx, isV2))
      return false;

   if(dir < 0 || dir > 2) return false;
   if(uid != InpUID) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check global NEW-ORDER conditions (open/add)                      |
//+------------------------------------------------------------------+
bool CheckTradingConditions()
{
   // Hard off
   if(!g_TradingAllowed)
      return false;

   // Daily DD block
   if(DailyDD_IsBlocked())
      return false;

   // Time window
   if(!CheckTimeFilter())
      return false;

   // Rollover new-order block
   if(InpRolloverFilter && IsRolloverPeriod())
      return false;

   // Friday logic may close positions / freeze; if it returns false, we block new orders.
   if(!CheckFridayFilter())
      return false;

   // News blocks new orders (we still manage open baskets)
   if(InpUseNewsFilter && IsNewsRestrictedNow())
      return false;

   // Crash blocks new orders
   if(InpCrashFilterEnabled && IsMarketCrashActive())
      return false;

   // Max open lots filter blocks new orders
   if(InpMaxOpenLots > 0.0 && GetTotalOpenLotsEA() >= InpMaxOpenLots)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Check time filter                                                 |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
   if(InpHourStart == 0 && InpHourStop == 0)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;

   if(InpHourStart < InpHourStop)
      return (currentHour >= InpHourStart && currentHour < InpHourStop);
   else
      return (currentHour >= InpHourStart || currentHour < InpHourStop);
}

//+------------------------------------------------------------------+
//| Check if currently in rollover period                             |
//+------------------------------------------------------------------+
bool IsRolloverPeriod()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentMinutes = dt.hour * 60 + dt.min;
   int startMinutes = InpRolloverStartHour * 60 + InpRolloverStartMin;
   int endMinutes = InpRolloverEndHour * 60 + InpRolloverEndMin;

   if(startMinutes < endMinutes)
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   else
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
}

//+------------------------------------------------------------------+
//| Check Friday filter                                               |
//+------------------------------------------------------------------+
bool CheckFridayFilter()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.day_of_week != 5)
      return true;

   if(InpFridayStopNewTrades)
      g_FreezeNewGrids = true;

   if(InpFridayFreezeAddLevelsHour > 0 && dt.hour >= InpFridayFreezeAddLevelsHour)
      g_FreezeAddLevels = true;

   if(InpFridayCloseHour > 0 && dt.hour >= InpFridayCloseHour)
   {
      g_FreezeNewGrids = true;
      g_FreezeAddLevels = true;

      if(InpFridayCloseOnlyIfProfit || InpFridayMaxLossToCloseMoney > 0.0)
      {
         for(int i = 0; i < g_SymbolCount; i++)
         {
            if(g_Data[i].gridCount <= 0) continue;

            double p = GetBasketProfit(i);
            bool canClose = (p >= 0.0);

            if(!canClose && InpFridayMaxLossToCloseMoney > 0.0)
               canClose = (p >= -InpFridayMaxLossToCloseMoney);

            if(canClose)
               CloseBasket(i);
         }
         return false;
      }

      CloseAllPositions();
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check drawdown limits                                             |
//+------------------------------------------------------------------+
bool CheckDrawdownLimits()
{
   CircuitBreaker_ResetDaily();

   double balance = accInfo.Balance();
   double floatingPL = (InpDDCalculation == DD_CALC_THIS_EA) ? GetEAFloatingPL() : (accInfo.Equity() - balance);

   // Min free margin % -> freeze (new orders + add levels)
   if(InpMinFreeMargin > 0.0)
   {
      double fm = accInfo.FreeMargin();
      double eq = accInfo.Equity();
      if(eq > 0.0)
      {
         double freeMarginPct = (fm / eq) * 100.0;
         if(freeMarginPct < InpMinFreeMargin)
         {
            g_FreezeNewGrids = true;
            g_FreezeAddLevels = true;
         }
      }
   }

   double ddPercent = 0.0;
   if(balance > 0.0 && floatingPL < 0.0)
      ddPercent = (MathAbs(floatingPL) / balance) * 100.0;

   // === Circuit breaker A/B/C === (optional; defaults are off)
   if(floatingPL < 0.0)
   {
      // Phase C: kill switch
      if(InpCB_KillDDPercent > 0.0 && ddPercent >= InpCB_KillDDPercent)
      {
         Print("CB Phase C KILL: DD=", DoubleToString(ddPercent, 2), "% -> CloseAll & Stop");
         CloseAllPositions();
         g_TradingAllowed = false;
         return false;
      }

      // Phase B: reduce exposure once per day
      if(InpCB_ReduceDDPercent > 0.0 && ddPercent >= InpCB_ReduceDDPercent)
      {
         g_FreezeNewGrids = true;
         g_FreezeAddLevels = true;

         if(!g_CB_ReduceDoneToday)
         {
            int worst = FindWorstBasketIndex();
            if(worst >= 0)
            {
               Print("CB Phase B REDUCE: closing worst basket ", g_Data[worst].symbol,
                     " basketPL=", DoubleToString(GetBasketProfit(worst), 2),
                     " DD=", DoubleToString(ddPercent, 2), "%");
               CloseBasket(worst);
            }
            g_CB_ReduceDoneToday = true;
         }
      }
      // Phase A: freeze only
      else if(InpCB_FreezeDDPercent > 0.0 && ddPercent >= InpCB_FreezeDDPercent)
      {
         g_FreezeNewGrids = true;
         g_FreezeAddLevels = true;
      }
   }

   // === Baseline hard limits ===
   if(InpMaxDrawdownPercent < 100.0 && floatingPL < 0.0)
   {
      if(ddPercent >= InpMaxDrawdownPercent)
      {
         Print("Max drawdown reached: ", ddPercent, "% - Taking action");
         HandleDrawdownEvent();
         return false;
      }
   }

   if(InpMaxDrawdownMoney > 0 && floatingPL < 0)
   {
      if(MathAbs(floatingPL) >= InpMaxDrawdownMoney)
      {
         Print("Max drawdown money reached: ", MathAbs(floatingPL), " - Taking action");
         HandleDrawdownEvent();
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Get floating PL for this EA only                                  |
//+------------------------------------------------------------------+
double GetEAFloatingPL()
{
   double pl = 0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(IsMagicNumberOurs(posInfo.Magic()))
         pl += posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
   }

   return pl;
}

//+------------------------------------------------------------------+
//| Handle drawdown event                                             |
//+------------------------------------------------------------------+
void HandleDrawdownEvent()
{
   switch(InpDDAction)
   {
      case DD_ACTION_CLOSE_STOP:
         CloseAllPositions();
         g_TradingAllowed = false;
         Print("Trading stopped due to drawdown limit");
         break;

      case DD_ACTION_CLOSE_CONTINUE:
         CloseAllPositions();
         Print("Positions closed due to drawdown, continuing trading");
         break;

      case DD_ACTION_STOP_ONLY:
         g_TradingAllowed = false;
         Print("New trading stopped due to drawdown limit");
         break;
   }
}

//+------------------------------------------------------------------+
//| Close all positions for this EA                                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(IsMagicNumberOurs(posInfo.Magic()))
         trade.PositionClose(posInfo.Ticket());
   }

   for(int i = 0; i < g_SymbolCount; i++)
   {
      g_Data[i].gridCount = 0;
      g_Data[i].gridDirection = 0;
      g_Data[i].lastEntryPrice = 0;
      g_Data[i].initialLot = 0;
      g_Data[i].basketTP = 0;
      g_Data[i].lastTradeTime = 0;
      g_Data[i].firstTradeTime = 0;
      g_Data[i].addFreezeUntil = 0;
      g_Data[i].currentExitStage = 0;
      g_Data[i].currentTargetProfitMoney = 0;
      g_Data[i].lastTPApplyGridCount = -1;
      g_Data[i].lastTPApplyStage = -1;
      g_Data[i].tpRemovedDuringRollover = false;
   }
   g_ActiveGrids = 0;
}

//+------------------------------------------------------------------+
//| Process individual symbol                                         |
//+------------------------------------------------------------------+
void ProcessSymbol(int idx)
{
   string sym = g_Data[idx].symbol;

   if(!UpdateIndicators(idx))
      return;

   double spread = SpreadPips(sym);
   if(spread > InpMaxSpread)
      return;

   // Manage existing grid ALWAYS (even when news/rollover/time blocks new orders)
   if(g_Data[idx].gridCount > 0)
   {
      ManageGrid(idx);
      return;
   }

   // From here: NEW GRID logic only
   if(!g_NewOrdersAllowed)
      return;

   if(!InpAllowNewGrid)
      return;

   if(g_FreezeNewGrids)
      return;

   if(g_ActiveGrids >= InpMaxSymbols)
      return;

   if(InpMaxOpenLots > 0.0 && GetTotalOpenLotsEA() >= InpMaxOpenLots)
      return;

   // ADX filter (optional) for new grids
   if(!IsADXAllowed(idx))
      return;

   CheckEntrySignal(idx);
}

//+------------------------------------------------------------------+
//| Update indicator values                                           |
//+------------------------------------------------------------------+
bool UpdateIndicators(int idx)
{
   // Required indicators (must succeed)
   if(CopyBuffer(g_Data[idx].bbHandle, 1, 0, 3, g_Data[idx].bbUpper) < 3)
      return false;
   if(CopyBuffer(g_Data[idx].bbHandle, 0, 0, 3, g_Data[idx].bbMiddle) < 3)
      return false;
   if(CopyBuffer(g_Data[idx].bbHandle, 2, 0, 3, g_Data[idx].bbLower) < 3)
      return false;

   if(CopyBuffer(g_Data[idx].rsiHandle, 0, 0, 3, g_Data[idx].rsi) < 3)
      return false;

   if(CopyBuffer(g_Data[idx].atrHandle, 0, 0, 3, g_Data[idx].atr) < 3)
      return false;

   // Optional indicators (do not hard-fail the EA if they can't be copied)
   if(g_Data[idx].maHandle != INVALID_HANDLE)
      CopyBuffer(g_Data[idx].maHandle, 0, 0, 3, g_Data[idx].ma);

   if(g_Data[idx].adxHandle != INVALID_HANDLE)
      CopyBuffer(g_Data[idx].adxHandle, 0, 0, 3, g_Data[idx].adx);

   return true;
}

//+------------------------------------------------------------------+
//| Check entry signal                                                |
//+------------------------------------------------------------------+
void CheckEntrySignal(int idx)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   double ask = symInfo.Ask();
   double bid = symInfo.Bid();

   double bbUpper = g_Data[idx].bbUpper[1];
   double bbLower = g_Data[idx].bbLower[1];
   double rsi = g_Data[idx].rsi[1];

   // Use closed-bar price or current bid/ask
   double sigPrice = 0.0;
   if(InpUseClosedBarSignal)
   {
      double closes[];
      ArraySetAsSeries(closes, true);
      if(CopyClose(sym, InpWorkingTF, 1, 1, closes) >= 1)
         sigPrice = closes[0];
      else
         sigPrice = (ask + bid) * 0.5;
   }
   else
   {
      sigPrice = (ask + bid) * 0.5;
   }

   // RSI filters
   bool rsiCapOK = true;
   if(InpRSIEntryMode == RSI_MODE_CAP)
   {
      // Cap mode: skip entries when RSI is too high (strong trend/momentum)
      rsiCapOK = (rsi <= InpMaxRSI);
   }

   // SELL signal: price > upper BB
   if(InpTradeDirection != TRADE_BUY_ONLY)
   {
      if(sigPrice > bbUpper)
      {
         bool rsiOK = true;
         if(InpRSIEntryMode == RSI_MODE_CAP)
            rsiOK = rsiCapOK;
         else if(InpRSIEntryMode == RSI_MODE_CLASSIC_MINMAX)
            rsiOK = (rsi >= InpMaxRSI);
         else
            rsiOK = true;

         if(rsiOK && IsDirectionAllowedByTrend(idx, -1))
            OpenInitialTrade(idx, -1);
         return;
      }
   }

   // BUY signal: price < lower BB
   if(InpTradeDirection != TRADE_SELL_ONLY)
   {
      if(sigPrice < bbLower)
      {
         bool rsiOK = true;
         if(InpRSIEntryMode == RSI_MODE_CAP)
            rsiOK = rsiCapOK;
         else if(InpRSIEntryMode == RSI_MODE_CLASSIC_MINMAX)
         {
            if(InpMinRSI > 0)
               rsiOK = (rsi <= InpMinRSI);
            else
               rsiOK = true;
         }
         else
            rsiOK = true;

         if(rsiOK && IsDirectionAllowedByTrend(idx, 1))
            OpenInitialTrade(idx, 1);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Get effective SL distance in pips                                 |
//+------------------------------------------------------------------+
double EffectiveSLPips()
{
   if(InpSLGrid > 0.0) return InpSLGrid;
   if(InpUseFailsafeSL) return InpFailsafeSLPips;
   return 0.0;
}

//+------------------------------------------------------------------+
//| Open initial trade                                                |
//+------------------------------------------------------------------+
void OpenInitialTrade(int idx, int direction)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   double lot = CalculateLotSize(idx);
   if(lot <= 0)
      return;

   // Check margin for full grid
   if(InpCheckMarginAll)
   {
      double requiredMargin = CalculateFullGridMargin(idx, lot);
      if(requiredMargin > accInfo.FreeMargin())
      {
         lot = lot * (accInfo.FreeMargin() / requiredMargin) * 0.8;
         lot = NormalizeLot(sym, lot);
      }
   }

   if(lot < symInfo.LotsMin())
   {
      Print("Lot size too small after margin check: ", lot);
      return;
   }

   if(!CanOpenMoreLots(lot))
   {
      Print("MaxOpenLots filter: blocking initial trade. CurrentLots=", DoubleToString(GetTotalOpenLotsEA(),2),
            " Add=", DoubleToString(lot,2), " Max=", DoubleToString(InpMaxOpenLots,2));
      return;
   }

   if(InpRandomDelay > 0)
      Sleep(MathRand() % (InpRandomDelay * 1000));

   trade.SetDeviationInPoints(SlippagePoints(sym));

   double tp = 0, sl = 0;
   double pipValue = PipSize(sym);
   double effSLPips = EffectiveSLPips();

   if(direction == 1)  // Buy
   {
      double price = symInfo.Ask();
      tp = price + InpTPInitial * pipValue;

      if(effSLPips > 0.0 && !InpHideSL)
         sl = price - effSLPips * pipValue;

      if(InpRandomizeTPSL)
         tp += (MathRand() % 10 - 5) * symInfo.Point();

      long magic = GetMagicNumber(1, 1);
      trade.SetExpertMagicNumber(magic);

      if(trade.Buy(lot, sym, price, sl, tp, InpTradeComment))
      {
         g_Data[idx].gridCount = 1;
         g_Data[idx].gridDirection = 1;
         g_Data[idx].lastEntryPrice = price;
         g_Data[idx].initialLot = lot;
         g_Data[idx].lastTradeTime = TimeCurrent();
         g_Data[idx].firstTradeTime = g_Data[idx].lastTradeTime;
         g_Data[idx].addFreezeUntil = 0;
         g_Data[idx].lastTPApplyGridCount = -1;
         g_Data[idx].lastTPApplyStage = -1;
         g_Data[idx].tpRemovedDuringRollover = false;
         g_ActiveGrids++;
         Print("Opened BUY initial trade on ", sym, " lot=", lot, " price=", price, " SL=", sl);
      }
   }
   else  // Sell
   {
      double price = symInfo.Bid();
      tp = price - InpTPInitial * pipValue;

      if(effSLPips > 0.0 && !InpHideSL)
         sl = price + effSLPips * pipValue;

      if(InpRandomizeTPSL)
         tp += (MathRand() % 10 - 5) * symInfo.Point();

      long magic = GetMagicNumber(2, 1);
      trade.SetExpertMagicNumber(magic);

      if(trade.Sell(lot, sym, price, sl, tp, InpTradeComment))
      {
         g_Data[idx].gridCount = 1;
         g_Data[idx].gridDirection = -1;
         g_Data[idx].lastEntryPrice = price;
         g_Data[idx].initialLot = lot;
         g_Data[idx].lastTradeTime = TimeCurrent();
         g_Data[idx].firstTradeTime = g_Data[idx].lastTradeTime;
         g_Data[idx].addFreezeUntil = 0;
         g_Data[idx].lastTPApplyGridCount = -1;
         g_Data[idx].lastTPApplyStage = -1;
         g_Data[idx].tpRemovedDuringRollover = false;
         g_ActiveGrids++;
         Print("Opened SELL initial trade on ", sym, " lot=", lot, " price=", price, " SL=", sl);
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on selected method                       |
//+------------------------------------------------------------------+
double CalculateLotSize(int idx)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);

   double lot = 0;

   switch(InpLotMode)
   {
      case LOT_MODE_FIXED:
         lot = InpFixedLot;
         break;

      case LOT_MODE_DYNAMIC:
         lot = (accInfo.Balance() / InpDynamicLot) * 0.01;
         break;

      case LOT_MODE_DEPOSIT_LOAD:
         // Uses current balance (can grow dangerously)
         lot = CalculateDepositLoadLot(idx, InpDepositLoad, accInfo.Balance());
         break;

      case LOT_MODE_DEPOSIT_LOAD_FIXED:
         // Uses FIXED base, not current balance
         lot = CalculateDepositLoadLot(idx, InpDepositLoad, g_FixedLotBase);
         break;

      case LOT_MODE_LOW_RISK:
         lot = CalculateDepositLoadLot(idx, 0.15, g_FixedLotBase);
         break;

      case LOT_MODE_MEDIUM_RISK:
         lot = CalculateDepositLoadLot(idx, 0.25, g_FixedLotBase);
         break;

      case LOT_MODE_HIGH_RISK:
         lot = CalculateDepositLoadLot(idx, 0.40, g_FixedLotBase);
         break;

      case LOT_MODE_SIGNIFICANT_RISK:
         lot = CalculateDepositLoadLot(idx, 0.60, g_FixedLotBase);
         break;
   }

   lot = MathMin(lot, InpMaxLot);
   lot = NormalizeLot(sym, lot);

   return lot;
}

//+------------------------------------------------------------------+
//| Calculate lot based on deposit load percentage                    |
//+------------------------------------------------------------------+
double CalculateDepositLoadLot(int idx, double loadPercent, double depositBase)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);

   double targetLoad = depositBase * loadPercent;

   // Calculate total multiplier for full grid
   double totalMultiplier = 1.0;  // Level 1
   if(InpMaxTrades >= 2) totalMultiplier += InpMult2nd;
   if(InpMaxTrades >= 3) totalMultiplier += InpMult3to5;
   if(InpMaxTrades >= 4) totalMultiplier += InpMult3to5;
   if(InpMaxTrades >= 5) totalMultiplier += InpMult3to5;
   for(int i = 6; i <= InpMaxTrades; i++)
      totalMultiplier += InpMult6Plus;

   double marginPerLot = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, symInfo.Ask(), marginPerLot))
      marginPerLot = symInfo.Ask() * symInfo.ContractSize() / accInfo.Leverage();

   if(marginPerLot <= 0)
      return InpFixedLot;

   double initialLot = targetLoad / (marginPerLot * totalMultiplier);

   // Safety cap: never more than 1% of fixed base per initial lot (kept)
   double maxSafeLot = depositBase * 0.01 / marginPerLot;
   initialLot = MathMin(initialLot, maxSafeLot);

   return initialLot;
}

//+------------------------------------------------------------------+
//| Normalize lot to broker requirements                              |
//+------------------------------------------------------------------+
double NormalizeLot(string sym, double lot)
{
   symInfo.Name(sym);

   double minLot = symInfo.LotsMin();
   double maxLot = symInfo.LotsMax();
   double lotStep = symInfo.LotsStep();

   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);
   lot = MathFloor(lot / lotStep) * lotStep;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Calculate margin required for full grid                           |
//+------------------------------------------------------------------+
double CalculateFullGridMargin(int idx, double initialLot)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);

   double marginPerLot = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, symInfo.Ask(), marginPerLot))
      marginPerLot = symInfo.Ask() * symInfo.ContractSize() / accInfo.Leverage();

   double totalLots = initialLot;  // Level 1
   if(InpMaxTrades >= 2) totalLots += initialLot * InpMult2nd;
   if(InpMaxTrades >= 3) totalLots += initialLot * InpMult3to5;
   if(InpMaxTrades >= 4) totalLots += initialLot * InpMult3to5;
   if(InpMaxTrades >= 5) totalLots += initialLot * InpMult3to5;
   for(int i = 6; i <= InpMaxTrades; i++)
      totalLots += initialLot * InpMult6Plus;

   return totalLots * marginPerLot;
}

//+------------------------------------------------------------------+
//| Manage existing grid                                              |
//+------------------------------------------------------------------+
void ManageGrid(int idx)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   UpdateGridState(idx);

   if(g_Data[idx].gridCount == 0)
   {
      if(g_ActiveGrids > 0) g_ActiveGrids--;
      return;
   }

   // Check SL hit (if hidden SL mode)
   if(InpHideSL && EffectiveSLPips() > 0.0)
   {
      CheckHiddenSL(idx);
   }

   // ADX filter (optional) for adding levels
   if(InpADXFilter && InpADXBlockAddLevels)
   {
      if(!IsADXAllowed(idx))
      {
         // Still manage TP/exit even if ADX blocks adding levels
         ManageBasketTP(idx);
         if(InpTrailingSLSize > 0)
            ManageTrailingStop(idx);
         return;
      }
   }

   // Add-levels are blocked when global new-order conditions fail
   CheckAddGridLevel(idx);
   ManageBasketTP(idx);

   if(InpTrailingSLSize > 0)
      ManageTrailingStop(idx);
}

//+------------------------------------------------------------------+
//| Check hidden SL                                                   |
//+------------------------------------------------------------------+
void CheckHiddenSL(int idx)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   double pipValue = PipSize(sym);
   double effSLPips = EffectiveSLPips();
   if(effSLPips <= 0.0) return;

   double slDistance = effSLPips * pipValue;

   // Find the first (worst) entry price
   double worstEntry = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(!IsMagicNumberOurs(posInfo.Magic()))
         continue;
      if(posInfo.Symbol() != sym)
         continue;

      double entryPrice = posInfo.PriceOpen();
      if(g_Data[idx].gridDirection == 1) // Buy
      {
         if(worstEntry == 0 || entryPrice < worstEntry)
            worstEntry = entryPrice;
      }
      else // Sell
      {
         if(worstEntry == 0 || entryPrice > worstEntry)
            worstEntry = entryPrice;
      }
   }

   if(worstEntry == 0)
      return;

   double currentPrice = (g_Data[idx].gridDirection == 1) ? symInfo.Bid() : symInfo.Ask();

   bool slHit = false;
   if(g_Data[idx].gridDirection == 1) // Buy
   {
      if(currentPrice <= worstEntry - slDistance)
         slHit = true;
   }
   else // Sell
   {
      if(currentPrice >= worstEntry + slDistance)
         slHit = true;
   }

   if(slHit)
   {
      Print("Hidden SL triggered on ", sym, " - closing basket");
      CloseBasket(idx);
   }
}

//+------------------------------------------------------------------+
//| Update grid state from actual positions                           |
//+------------------------------------------------------------------+
void UpdateGridState(int idx)
{
   string sym = g_Data[idx].symbol;
   int count = 0;
   double lastPrice = 0;
   int direction = 0;

   datetime earliestOpen = 0;
   datetime latestOpen   = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(!IsMagicNumberOurs(posInfo.Magic()))
         continue;

      if(posInfo.Symbol() != sym)
         continue;

      count++;

      if(count == 1)
         direction = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;

      if(direction == 1)
      {
         if(lastPrice == 0 || posInfo.PriceOpen() < lastPrice)
            lastPrice = posInfo.PriceOpen();
      }
      else
      {
         if(lastPrice == 0 || posInfo.PriceOpen() > lastPrice)
            lastPrice = posInfo.PriceOpen();
      }

      datetime ot = (datetime)posInfo.Time();
      if(earliestOpen == 0 || ot < earliestOpen) earliestOpen = ot;
      if(latestOpen == 0 || ot > latestOpen)    latestOpen   = ot;
   }

   g_Data[idx].gridCount = count;
   g_Data[idx].gridDirection = direction;
   g_Data[idx].lastEntryPrice = lastPrice;

   if(count == 0)
   {
      g_Data[idx].initialLot = 0;
      g_Data[idx].basketTP = 0;
      g_Data[idx].firstTradeTime = 0;
      g_Data[idx].lastTradeTime = 0;
      g_Data[idx].addFreezeUntil = 0;
      g_Data[idx].currentExitStage = 0;
      g_Data[idx].currentTargetProfitMoney = 0;
      g_Data[idx].lastTPApplyGridCount = -1;
      g_Data[idx].lastTPApplyStage = -1;
      g_Data[idx].tpRemovedDuringRollover = false;
   }
   else
   {
      if(earliestOpen != 0) g_Data[idx].firstTradeTime = earliestOpen;
      if(latestOpen != 0)   g_Data[idx].lastTradeTime  = latestOpen;
   }
}

//+------------------------------------------------------------------+
//| Check if we should add a grid level                               |
//+------------------------------------------------------------------+
void CheckAddGridLevel(int idx)
{
   // Do not add levels if new orders are blocked globally (news/time/rollover/crash/daily)
   if(!g_NewOrdersAllowed)
      return;

   if(g_FreezeAddLevels)
      return;

   if(g_Data[idx].gridCount >= InpMaxTrades)
      return;

   // per-basket runaway freeze
   if(InpRunawayProtection && g_Data[idx].addFreezeUntil > TimeCurrent())
      return;

   // Max open lots filter
   // (we check later with the calculated lot too)
   if(InpMaxOpenLots > 0.0 && GetTotalOpenLotsEA() >= InpMaxOpenLots)
      return;

   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   double currentPrice = (g_Data[idx].gridDirection == 1) ? symInfo.Ask() : symInfo.Bid();
   double lastEntry = g_Data[idx].lastEntryPrice;

   if(lastEntry == 0)
      return;

   double distance = InpTradeDistance;

   if(InpSmartDistance)
   {
      double atr = g_Data[idx].atr[0];
      double pip = PipSize(sym);
      double atrPips = (pip > 0.0) ? (atr / pip) : 0.0;

      double volatilityFactor = atrPips / 20.0;
      volatilityFactor = MathMax(0.5, MathMin(2.0, volatilityFactor));

      distance = distance * volatilityFactor * InpATRMultiplier;
   }

   double pip = PipSize(sym);
   double requiredMove = distance * pip;

   bool shouldAdd = false;

   if(g_Data[idx].gridDirection == 1)
   {
      if(currentPrice <= lastEntry - requiredMove)
         shouldAdd = true;
   }
   else
   {
      if(currentPrice >= lastEntry + requiredMove)
         shouldAdd = true;
   }

   if(!shouldAdd)
      return;

   // Runaway protection: pause adding levels in "fast move" / deep DD scenarios
   if(InpRunawayProtection)
   {
      if(ShouldRunawayFreezeAddLevels(idx, currentPrice, lastEntry))
      {
         g_Data[idx].addFreezeUntil = TimeCurrent() + InpRunawayFreezeMinutes * 60;
         Print("Runaway protection: pausing add-levels on ", sym, " until ", TimeToString(g_Data[idx].addFreezeUntil, TIME_DATE|TIME_MINUTES));
         return;
      }
   }

   AddGridLevel(idx);
}

//+------------------------------------------------------------------+
//| Add a new grid level                                              |
//+------------------------------------------------------------------+
void AddGridLevel(int idx)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   int newLevel = g_Data[idx].gridCount + 1;

   double lot = g_Data[idx].initialLot;

   if(newLevel == 2)
      lot *= InpMult2nd;
   else if(newLevel >= 3 && newLevel <= 5)
      lot *= InpMult3to5;
   else
      lot *= InpMult6Plus;

   lot = NormalizeLot(sym, lot);
   lot = MathMin(lot, InpMaxLot);

   if(!CanOpenMoreLots(lot))
   {
      Print("MaxOpenLots filter: blocking add-level. CurrentLots=", DoubleToString(GetTotalOpenLotsEA(),2),
            " Add=", DoubleToString(lot,2), " Max=", DoubleToString(InpMaxOpenLots,2));
      return;
   }

   double marginRequired = 0;
   ENUM_ORDER_TYPE orderType = (g_Data[idx].gridDirection == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (g_Data[idx].gridDirection == 1) ? symInfo.Ask() : symInfo.Bid();

   if(!OrderCalcMargin(orderType, sym, lot, price, marginRequired))
      return;

   if(marginRequired > accInfo.FreeMargin())
   {
      Print("Insufficient margin for grid level ", newLevel, " on ", sym);
      return;
   }

   if(InpRandomDelay > 0)
      Sleep(MathRand() % (InpRandomDelay * 1000));

   trade.SetDeviationInPoints(SlippagePoints(sym));

   // Calculate SL for this level
   double sl = 0;
   double pipValue = PipSize(sym);
   double effSLPips = EffectiveSLPips();
   if(effSLPips > 0.0 && !InpHideSL)
   {
      if(g_Data[idx].gridDirection == 1)
         sl = price - effSLPips * pipValue;
      else
         sl = price + effSLPips * pipValue;
   }

   long magic = GetMagicNumber(g_Data[idx].gridDirection == 1 ? 1 : 2, newLevel);
   trade.SetExpertMagicNumber(magic);

   bool result = false;

   if(g_Data[idx].gridDirection == 1)
      result = trade.Buy(lot, sym, symInfo.Ask(), sl, 0, InpTradeComment + "_L" + IntegerToString(newLevel));
   else
      result = trade.Sell(lot, sym, symInfo.Bid(), sl, 0, InpTradeComment + "_L" + IntegerToString(newLevel));

   if(result)
   {
      g_Data[idx].gridCount = newLevel;
      g_Data[idx].lastEntryPrice = price;
      g_Data[idx].lastTradeTime = TimeCurrent();
      Print("Added grid level ", newLevel, " on ", sym, " lot=", lot, " price=", price, " SL=", sl);

      // Force TP refresh on new level
      g_Data[idx].lastTPApplyGridCount = -1;

      if(InpTPGrid == 0)
      {
         // Stage will be computed in ManageBasketTP; we just want to ensure TP gets applied after add
         ManageBasketTP(idx);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage basket take profit (weighted + staged TP logic)            |
//+------------------------------------------------------------------+
void ManageBasketTP(int idx)
{
   if(InpTPGrid != 0.0)
      return; // Only weighted mode is handled here.

   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);

   double basketProfit = GetBasketProfit(idx);

   // Determine exit stage
   int minutesOpen = 0;
   if(g_Data[idx].firstTradeTime > 0)
      minutesOpen = (int)((TimeCurrent() - g_Data[idx].firstTradeTime) / 60);

   int barsOpen = 0;
   if(g_Data[idx].firstTradeTime > 0)
      barsOpen = BarsSinceTime(sym, InpWorkingTF, g_Data[idx].firstTradeTime);

   int stage = 0;
   if(InpUseExitStages)
      stage = GetExitStage(idx, barsOpen, minutesOpen);

   // Optional BE-after-level override
   if(InpBreakEvenAfterLevel > 0 && g_Data[idx].gridCount >= InpBreakEvenAfterLevel)
      stage = 99; // special stage: break-even mode

   g_Data[idx].currentExitStage = stage;

   // Compute target profit in MONEY (can be 0 or negative)
   double targetProfitMoney = 0.0;

   if(stage == 99)
   {
      double ppp = ProfitPerPipPerLot(sym);
      targetProfitMoney = g_Data[idx].initialLot * InpBreakEvenOffsetPips * ppp;
   }
   else if(stage > 0)
   {
      targetProfitMoney = GetTargetProfitMoneyForStage(idx, stage);
   }
   else
   {
      targetProfitMoney = CalculateTargetProfit(idx); // Weighted target in account currency
   }

   // Optional: increase TP during news (to avoid closing right before / into news)
   if(InpIncreaseTPDuringNewsPips > 0.0 && InpUseNewsFilter && IsNewsRestrictedNow())
   {
      double ppp = ProfitPerPipPerLot(sym);
      targetProfitMoney += g_Data[idx].initialLot * InpIncreaseTPDuringNewsPips * ppp;
   }

   g_Data[idx].currentTargetProfitMoney = targetProfitMoney;

   // Update internal basketTP + optionally apply to positions (with "adjust only on new level" semantics)
   UpdateWeightedTP(idx, targetProfitMoney, stage);

   // Close condition: money-based (covers swap/commission automatically via GetBasketProfit)
   if(basketProfit >= targetProfitMoney)
   {
      CloseBasket(idx);
      Print("Basket TP reached on ", sym, " Profit: ", basketProfit,
            " | Target: ", targetProfitMoney,
            " | Stage: ", stage, " | BarsOpen: ", barsOpen, " | MinutesOpen: ", minutesOpen);
   }
}

//+------------------------------------------------------------------+
//| Get current basket profit                                         |
//+------------------------------------------------------------------+
double GetBasketProfit(int idx)
{
   string sym = g_Data[idx].symbol;
   double profit = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(!IsMagicNumberOurs(posInfo.Magic()))
         continue;

      if(posInfo.Symbol() != sym)
         continue;

      profit += posInfo.Profit();

      if(InpCoverSwaps)
         profit += posInfo.Swap();

      profit += posInfo.Commission();
   }

   return profit;
}

//+------------------------------------------------------------------+
//| Calculate target profit for weighted TP (BASE, money)             |
//+------------------------------------------------------------------+
double CalculateTargetProfit(int idx)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);

   double ppp = ProfitPerPipPerLot(sym);
   double targetProfit = g_Data[idx].initialLot * InpTPInitial * ppp;

   return targetProfit;
}

//+------------------------------------------------------------------+
//| Update weighted TP (stores basketTP price + optional TP apply)    |
//| - If InpAdjustTPOnNewLevel=true: apply TP only when gridCount or  |
//|   stage changes.                                                  |
//| - If false: apply every tick.                                     |
//+------------------------------------------------------------------+
void UpdateWeightedTP(int idx, double targetProfitMoney, int stage)
{
   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);

   double totalLots = 0;
   double weightedSum = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(!IsMagicNumberOurs(posInfo.Magic()))
         continue;

      if(posInfo.Symbol() != sym)
         continue;

      totalLots += posInfo.Volume();
      weightedSum += posInfo.PriceOpen() * posInfo.Volume();
   }

   if(totalLots <= 0)
      return;

   double avgEntry = weightedSum / totalLots;

   double ppp = ProfitPerPipPerLot(sym);
   double pipValue = PipSize(sym);

   if(ppp <= 0.0 || pipValue <= 0.0)
      return;

   double requiredPips = targetProfitMoney / (totalLots * ppp);
   double tpPrice = 0;

   if(g_Data[idx].gridDirection == 1)
      tpPrice = avgEntry + requiredPips * pipValue;
   else
      tpPrice = avgEntry - requiredPips * pipValue;

   g_Data[idx].basketTP = tpPrice;

   if(!InpApplyBasketTPToPositions)
      return;

   // Rollover TP removal (optional)
   bool inRollover = (InpRolloverFilter && IsRolloverPeriod());
   if(InpRemoveTPDuringRollover && inRollover)
   {
      if(!g_Data[idx].tpRemovedDuringRollover)
      {
         ApplyBasketTPToPositions(idx, 0.0); // remove broker TP
         g_Data[idx].tpRemovedDuringRollover = true;
      }
      return;
   }
   else
   {
      g_Data[idx].tpRemovedDuringRollover = false;
   }

   bool shouldApply = true;
   if(InpAdjustTPOnNewLevel)
   {
      // Apply only when grid count changes OR stage changes OR first apply
      if(g_Data[idx].lastTPApplyGridCount == g_Data[idx].gridCount &&
         g_Data[idx].lastTPApplyStage == stage)
      {
         shouldApply = false;
      }
   }

   if(shouldApply)
   {
      ApplyBasketTPToPositions(idx, tpPrice);
      g_Data[idx].lastTPApplyGridCount = g_Data[idx].gridCount;
      g_Data[idx].lastTPApplyStage = stage;
   }
}

//+------------------------------------------------------------------+
//| Close entire basket                                               |
//+------------------------------------------------------------------+
void CloseBasket(int idx)
{
   string sym = g_Data[idx].symbol;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(!IsMagicNumberOurs(posInfo.Magic()))
         continue;

      if(posInfo.Symbol() != sym)
         continue;

      trade.PositionClose(posInfo.Ticket());
   }

   g_Data[idx].gridCount = 0;
   g_Data[idx].gridDirection = 0;
   g_Data[idx].lastEntryPrice = 0;
   g_Data[idx].initialLot = 0;
   g_Data[idx].basketTP = 0;
   g_Data[idx].lastTradeTime = 0;
   g_Data[idx].firstTradeTime = 0;
   g_Data[idx].addFreezeUntil = 0;
   g_Data[idx].currentExitStage = 0;
   g_Data[idx].currentTargetProfitMoney = 0;
   g_Data[idx].lastTPApplyGridCount = -1;
   g_Data[idx].lastTPApplyStage = -1;
   g_Data[idx].tpRemovedDuringRollover = false;

   if(g_ActiveGrids > 0) g_ActiveGrids--;
}

//+------------------------------------------------------------------+
//| Manage trailing stop for basket                                   |
//+------------------------------------------------------------------+
void ManageTrailingStop(int idx)
{
   double basketProfit = GetBasketProfit(idx);
   double pipValue = PipSize(g_Data[idx].symbol);

   double startThreshold = InpTrailingSLStart * pipValue * g_Data[idx].initialLot;
   if(basketProfit < startThreshold)
      return;

   double trailProfit = basketProfit - (InpTrailingSLSize * pipValue * g_Data[idx].initialLot);

   if(trailProfit > 0)
   {
      static double lastTrailLevel[];
      if(ArraySize(lastTrailLevel) <= idx)
         ArrayResize(lastTrailLevel, idx + 1);

      if(lastTrailLevel[idx] == 0 || trailProfit > lastTrailLevel[idx])
         lastTrailLevel[idx] = trailProfit;

      if(basketProfit < lastTrailLevel[idx])
      {
         CloseBasket(idx);
         Print("Trailing stop triggered on ", g_Data[idx].symbol);
         lastTrailLevel[idx] = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Create info panel                                                 |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x = 10, y = 30;
   int width = 300, height = 20;
   color bgColor = clrDarkSlateGray;
   color textColor = clrWhite;

   ObjectCreate(0, "MultiPairMeanReversionEA_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_BG", OBJPROP_XDISTANCE, x - 5);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_BG", OBJPROP_YDISTANCE, y - 5);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_BG", OBJPROP_XSIZE, width + 10);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_BG", OBJPROP_YSIZE, 340);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_BG", OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);

   CreateLabel("MultiPairMeanReversionEA_Title", x, y, "Multi-Pair Mean Reversion EA v2.11", textColor, 10, true);
   y += 25;

   CreateLabel("MultiPairMeanReversionEA_Balance", x, y, "Balance: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_Equity", x, y, "Equity: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_Profit", x, y, "Floating P/L: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_DD", x, y, "Drawdown: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_Grids", x, y, "Active Grids: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_LotBase", x, y, "Lot Base: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_Status", x, y, "Status: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_NewOrders", x, y, "New Orders: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_NewsFilter", x, y, "News Filter: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_CrashFilter", x, y, "Crash Filter: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_ExitStage", x, y, "Exit Stage: ", textColor, 9, false);
   y += height;
   CreateLabel("MultiPairMeanReversionEA_Target", x, y, "Target $: ", textColor, 9, false);
}

//+------------------------------------------------------------------+
//| Create label helper                                               |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

//+------------------------------------------------------------------+
//| Update info panel                                                 |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   double balance = accInfo.Balance();
   double equity = accInfo.Equity();
   double floatingPL = GetEAFloatingPL();
   double ddPercent = (balance > 0 && floatingPL < 0) ? MathAbs(floatingPL) / balance * 100.0 : 0;

   ObjectSetString(0, "MultiPairMeanReversionEA_Balance", OBJPROP_TEXT, "Balance: " + DoubleToString(balance, 2));
   ObjectSetString(0, "MultiPairMeanReversionEA_Equity", OBJPROP_TEXT, "Equity: " + DoubleToString(equity, 2));
   ObjectSetString(0, "MultiPairMeanReversionEA_Profit", OBJPROP_TEXT, "Floating P/L: " + DoubleToString(floatingPL, 2));
   ObjectSetString(0, "MultiPairMeanReversionEA_DD", OBJPROP_TEXT, "Drawdown: " + DoubleToString(ddPercent, 2) + "%");
   ObjectSetString(0, "MultiPairMeanReversionEA_Grids", OBJPROP_TEXT, "Active Grids: " + IntegerToString(g_ActiveGrids) + "/" + IntegerToString(InpMaxSymbols));
   ObjectSetString(0, "MultiPairMeanReversionEA_LotBase", OBJPROP_TEXT, "Lot Base: $" + DoubleToString(g_FixedLotBase, 0));

   string status = g_TradingAllowed ? "Trading Active" : "Trading Stopped";
   if(!InpAllowNewGrid || g_FreezeNewGrids)
      status = "New Grids Frozen";
   if(g_FreezeAddLevels)
      status += " | Levels Frozen";
   if(DailyDD_IsBlocked())
      status += " | DailyDD BLOCK";

   ObjectSetString(0, "MultiPairMeanReversionEA_Status", OBJPROP_TEXT, "Status: " + status);

   string newOrders = g_NewOrdersAllowed ? "ALLOWED" : "BLOCKED";
   ObjectSetString(0, "MultiPairMeanReversionEA_NewOrders", OBJPROP_TEXT, "New Orders: " + newOrders);

   color plColor = (floatingPL >= 0) ? clrLime : clrRed;
   ObjectSetInteger(0, "MultiPairMeanReversionEA_Profit", OBJPROP_COLOR, plColor);

   string newsStatus = "OFF";
   color newsColor = clrGray;
   if(InpUseNewsFilter)
   {
      if(IsNewsRestrictedNow())
      {
         newsStatus = "BLOCKING";
         newsColor = clrOrange;
      }
      else
      {
         newsStatus = "OK";
         newsColor = clrLime;
      }
   }
   ObjectSetString(0, "MultiPairMeanReversionEA_NewsFilter", OBJPROP_TEXT, "News Filter: " + newsStatus);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_NewsFilter", OBJPROP_COLOR, newsColor);

   string crashStatus = "OFF";
   color crashColor = clrGray;
   if(InpCrashFilterEnabled)
   {
      if(g_CrashFilterActive)
      {
         crashStatus = "BLOCKING";
         crashColor = clrRed;
      }
      else
      {
         crashStatus = "OK";
         crashColor = clrLime;
      }
   }
   ObjectSetString(0, "MultiPairMeanReversionEA_CrashFilter", OBJPROP_TEXT, "Crash Filter: " + crashStatus);
   ObjectSetInteger(0, "MultiPairMeanReversionEA_CrashFilter", OBJPROP_COLOR, crashColor);

   // Show staged exit info from the WORST (largest grid) currently active (simple)
   int worstIdx = -1;
   int worstCount = 0;
   for(int i=0;i<g_SymbolCount;i++)
   {
      if(g_Data[i].gridCount > worstCount)
      {
         worstCount = g_Data[i].gridCount;
         worstIdx = i;
      }
   }
   if(worstIdx >= 0 && worstCount > 0)
   {
      ObjectSetString(0, "MultiPairMeanReversionEA_ExitStage", OBJPROP_TEXT, "Exit Stage: " + IntegerToString(g_Data[worstIdx].currentExitStage) + " (" + g_Data[worstIdx].symbol + ")");
      ObjectSetString(0, "MultiPairMeanReversionEA_Target", OBJPROP_TEXT, "Target $: " + DoubleToString(g_Data[worstIdx].currentTargetProfitMoney, 2));
   }
   else
   {
      ObjectSetString(0, "MultiPairMeanReversionEA_ExitStage", OBJPROP_TEXT, "Exit Stage: -");
      ObjectSetString(0, "MultiPairMeanReversionEA_Target", OBJPROP_TEXT, "Target $: -");
   }
}

//+------------------------------------------------------------------+
//| OnTrade - handle trade events                                     |
//+------------------------------------------------------------------+
void OnTrade()
{
   ScanExistingPositions();
}

//+------------------------------------------------------------------+
//| Split string into array by separator                              |
//+------------------------------------------------------------------+
int SplitList(string text, string sep, string &result[])
{
   if(StringLen(text) == 0)
      return 0;

   int count = StringSplit(text, StringGetCharacter(sep, 0), result);

   for(int i = 0; i < count; i++)
   {
      StringTrimLeft(result[i]);
      StringTrimRight(result[i]);
   }

   return count;
}

//+------------------------------------------------------------------+
//| News Filter - Check if trading restricted due to news             |
//+------------------------------------------------------------------+
bool IsNewsRestrictedNow()
{
   if(!InpUseNewsFilter)
      return false;

   datetime now = TimeCurrent();

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

   datetime from = now - (InpNewsMinutesBefore * 60);
   datetime to   = now + (InpNewsLookForwardDays * 86400);
   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, from, to);

   if(total <= 0)
   {
      if(InpNewsDebug)
         Print("NewsFilter: CalendarValueHistory total=0 (unavailable).");

      if(!InpNewsUseFallbackWindow)
         return false;

      MqlDateTime dt;
      TimeToStruct(now, dt);

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
//| Initialize Crash Filter                                           |
//+------------------------------------------------------------------+
bool InitializeCrashFilter()
{
   if(!InpCrashFilterEnabled)
      return true;

   if(!SymbolSelect(InpCrashSymbol, true))
   {
      Print("Crash filter symbol not found: ", InpCrashSymbol);
      return false;
   }

   g_CrashATRHandle = iATR(InpCrashSymbol, InpCrashTimeframe, InpCrashATRPeriod);

   if(g_CrashATRHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR handle for crash filter");
      return false;
   }

   Print("Crash filter initialized on ", InpCrashSymbol);
   return true;
}

//+------------------------------------------------------------------+
//| Check if market crash conditions are active                       |
//+------------------------------------------------------------------+
bool IsMarketCrashActive()
{
   if(!InpCrashFilterEnabled)
      return false;

   if(g_CrashATRHandle == INVALID_HANDLE)
      return false;

   double atrCurrent[];
   double atrHistory[];

   ArraySetAsSeries(atrCurrent, true);
   ArraySetAsSeries(atrHistory, true);

   if(CopyBuffer(g_CrashATRHandle, 0, 0, 1, atrCurrent) < 1)
      return false;

   if(CopyBuffer(g_CrashATRHandle, 0, 1, InpCrashLookback, atrHistory) < InpCrashLookback)
      return false;

   double avgATR = 0;
   for(int i = 0; i < InpCrashLookback; i++)
      avgATR += atrHistory[i];
   avgATR /= InpCrashLookback;

   if(avgATR <= 0)
      return false;

   double volatilityRatio = atrCurrent[0] / avgATR;

   if(volatilityRatio >= InpCrashVolatilityThreshold)
   {
      if(!g_CrashFilterActive)
      {
         g_CrashFilterActive = true;
         Print("CRASH FILTER ACTIVATED: ", InpCrashSymbol, " volatility ratio = ",
               DoubleToString(volatilityRatio, 2), " (threshold: ",
               DoubleToString(InpCrashVolatilityThreshold, 2), ")");
      }
      return true;
   }
   else
   {
      if(g_CrashFilterActive)
      {
         g_CrashFilterActive = false;
         Print("Crash filter deactivated: volatility normalized");
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Circuit breaker: choose worst basket                              |
//+------------------------------------------------------------------+
int FindWorstBasketIndex()
{
   int worstIdx = -1;
   double worstProfit = 0;

   for(int i = 0; i < g_SymbolCount; i++)
   {
      if(g_Data[i].gridCount <= 0) continue;

      double p = GetBasketProfit(i);
      if(worstIdx < 0 || p < worstProfit)
      {
         worstIdx = i;
         worstProfit = p;
      }
   }
   return worstIdx;
}

//+------------------------------------------------------------------+
//| NEW: helper - bars since time (working TF)                        |
//+------------------------------------------------------------------+
int BarsSinceTime(const string sym, ENUM_TIMEFRAMES tf, datetime t)
{
   if(t <= 0) return 0;
   int shift = iBarShift(sym, tf, t, true);
   if(shift < 0) shift = iBarShift(sym, tf, t, false);
   if(shift < 0) return 0;
   return shift;
}

//+------------------------------------------------------------------+
//| NEW: Determine exit stage (1..3)                                  |
//+------------------------------------------------------------------+
int GetExitStage(int idx, int barsOpen, int minutesOpen)
{
   // Check stage 3 first (highest priority)
   if(InpStage3_MinLevel > 0 && g_Data[idx].gridCount >= InpStage3_MinLevel) return 3;
   if(InpStage3_AfterBars > 0 && barsOpen >= InpStage3_AfterBars) return 3;
   if(InpStage3_AfterMinutes > 0 && minutesOpen >= InpStage3_AfterMinutes) return 3;

   // Stage 2
   if(InpStage2_MinLevel > 0 && g_Data[idx].gridCount >= InpStage2_MinLevel) return 2;
   if(InpStage2_AfterBars > 0 && barsOpen >= InpStage2_AfterBars) return 2;
   if(InpStage2_AfterMinutes > 0 && minutesOpen >= InpStage2_AfterMinutes) return 2;

   // Stage 1
   if(InpStage1_MinLevel > 0 && g_Data[idx].gridCount >= InpStage1_MinLevel) return 1;
   if(InpStage1_AfterBars > 0 && barsOpen >= InpStage1_AfterBars) return 1;
   if(InpStage1_AfterMinutes > 0 && minutesOpen >= InpStage1_AfterMinutes) return 1;

   return 0;
}

//+------------------------------------------------------------------+
//| NEW: target money for stage based on pips-equivalent              |
//+------------------------------------------------------------------+
double GetTargetProfitMoneyForStage(int idx, int stage)
{
   string sym = g_Data[idx].symbol;
   double ppp = ProfitPerPipPerLot(sym);
   if(ppp <= 0.0) return 0.0;

   double pips = InpTPInitial;
   if(stage == 1) pips = InpStage1_TargetPips;
   if(stage == 2) pips = InpStage2_TargetPips;
   if(stage == 3) pips = InpStage3_TargetPips;

   return g_Data[idx].initialLot * pips * ppp;
}

//+------------------------------------------------------------------+
//| NEW: Trend filter - allow direction?                              |
//+------------------------------------------------------------------+
bool IsDirectionAllowedByTrend(int idx, int direction)
{
   if(!InpUseTrendFilter)
      return true;

   if(g_Data[idx].maHandle == INVALID_HANDLE)
      return true; // fail-open

   double ma = 0.0;
   if(ArraySize(g_Data[idx].ma) >= 2)
      ma = g_Data[idx].ma[1];

   if(ma <= 0.0)
      return true; // fail-open

   string sym = g_Data[idx].symbol;
   symInfo.Name(sym);
   symInfo.RefreshRates();

   double price = (direction == 1) ? symInfo.Ask() : symInfo.Bid();

   // If price is above MA -> only BUY allowed; below MA -> only SELL allowed.
   if(direction == 1)
      return (price >= ma);
   else
      return (price <= ma);
}

//+------------------------------------------------------------------+
//| NEW: ADX filter - allowed?                                        |
//+------------------------------------------------------------------+
bool IsADXAllowed(int idx)
{
   if(!InpADXFilter)
      return true;

   if(g_Data[idx].adxHandle == INVALID_HANDLE)
      return true; // fail-open

   double adx = 0.0;
   if(ArraySize(g_Data[idx].adx) >= 2)
      adx = g_Data[idx].adx[1];

   if(adx <= 0.0)
      return true; // fail-open

   return (adx <= InpADXMax);
}

//+------------------------------------------------------------------+
//| NEW: apply basket TP price to all positions (optional)            |
//+------------------------------------------------------------------+
void ApplyBasketTPToPositions(int idx, double tpPrice)
{
   string sym = g_Data[idx].symbol;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(!IsMagicNumberOurs(posInfo.Magic()))
         continue;

      if(posInfo.Symbol() != sym)
         continue;

      // Keep current SL as-is
      double sl = posInfo.StopLoss();
      trade.PositionModify(posInfo.Ticket(), sl, tpPrice);
   }
}

//+------------------------------------------------------------------+
//| NEW: runaway freeze logic                                         |
//+------------------------------------------------------------------+
bool ShouldRunawayFreezeAddLevels(int idx, double currentPrice, double lastEntryPrice)
{
   string sym = g_Data[idx].symbol;

   // ATR-based fast-move guard
   if(InpRunawayMoveATRMult > 0.0)
   {
      double atr = g_Data[idx].atr[0];
      if(atr > 0.0)
      {
         double move = MathAbs(currentPrice - lastEntryPrice);
         if(move >= atr * InpRunawayMoveATRMult)
            return true;
      }
   }

   // Basket DD-based pause (optional)
   if(InpRunawayBasketDDPercent > 0.0)
   {
      double balance = accInfo.Balance();
      if(balance > 0.0)
      {
         double p = GetBasketProfit(idx);
         if(p < 0.0)
         {
            double ddPct = (MathAbs(p) / balance) * 100.0;
            if(ddPct >= InpRunawayBasketDDPercent)
               return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| NEW: Max Open Lots helper                                         |
//+------------------------------------------------------------------+
double GetTotalOpenLotsEA()
{
   double lots = 0.0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      if(!posInfo.SelectByIndex(i))
         continue;

      if(IsMagicNumberOurs(posInfo.Magic()))
         lots += posInfo.Volume();
   }
   return lots;
}

bool CanOpenMoreLots(double addLots)
{
   if(InpMaxOpenLots <= 0.0) return true;
   return (GetTotalOpenLotsEA() + addLots) <= (InpMaxOpenLots + 1e-8);
}

//+------------------------------------------------------------------+
//| NEW: Daily DD tracking                                            |
//+------------------------------------------------------------------+
void DailyDD_UpdateAnchor()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // Compute today's reset time at InpDailyDDResetHour
   datetime todayReset = StringToTime(StringFormat("%04d.%02d.%02d %02d:00:00", dt.year, dt.mon, dt.day, InpDailyDDResetHour));

   // If current time is BEFORE today's reset hour, anchor is yesterday's reset
   if(now < todayReset)
      todayReset -= 86400;

   if(g_DailyResetAnchor != todayReset)
   {
      g_DailyResetAnchor = todayReset;
      g_DailyStartEquity = accInfo.Equity();
      g_DailyBlocked = false;
      g_DailyBlockedUntil = 0;
      // New day: allow trading again (only for daily block)
      Print("DailyDD anchor reset at ", TimeToString(g_DailyResetAnchor, TIME_DATE|TIME_MINUTES), " startEquity=", DoubleToString(g_DailyStartEquity,2));
   }
}

bool DailyDD_IsBlocked()
{
   if(!g_DailyBlocked) return false;
   return (TimeCurrent() < g_DailyBlockedUntil);
}

void DailyDD_CheckAndHandle()
{
   // disabled?
   if(InpDailyDDPercent <= 0.0 && InpDailyDDMoney <= 0.0)
      return;

   if(DailyDD_IsBlocked())
      return;

   // Evaluate current daily DD
   double curEquity = accInfo.Equity();
   double baseEquity = g_DailyStartEquity;
   if(baseEquity <= 0.0) baseEquity = curEquity;

   double ddMoney = baseEquity - curEquity;
   if(ddMoney <= 0.0) return;

   double ddPercent = (ddMoney / baseEquity) * 100.0;

   bool hit = false;
   if(InpDailyDDPercent > 0.0 && ddPercent >= InpDailyDDPercent) hit = true;
   if(InpDailyDDMoney > 0.0 && ddMoney >= InpDailyDDMoney) hit = true;

   if(!hit) return;

   Print("DAILY DD HIT: ddMoney=", DoubleToString(ddMoney,2), " dd%=", DoubleToString(ddPercent,2),
         " (limits: ", DoubleToString(InpDailyDDMoney,2), " / ", DoubleToString(InpDailyDDPercent,2), "%)");

   if(InpDailyDDAction == DAILY_DD_CLOSE_AND_BLOCK)
   {
      CloseAllPositions();
   }

   g_DailyBlocked = true;
   g_DailyBlockedUntil = g_DailyResetAnchor + 86400; // next reset
}

//+------------------------------------------------------------------+

