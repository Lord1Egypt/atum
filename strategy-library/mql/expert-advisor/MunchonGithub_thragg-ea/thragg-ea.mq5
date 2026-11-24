//+------------------------------------------------------------------+
//|                                                  ConquestV3.mq5  |
//|                          Empire Trading Systems — Conquest v3.20 |
//|                                                                  |
//|  PERCEPTION -> BELIEF -> RISK -> EXECUTION                       |
//|  + ENGRAM MEMORY  + MODE LAYER  + TARGET PACING ENGINE           |
//|                                                                  |
//|  Design principles:                                              |
//|   1. Scale invariance — thresholds in ATR units, ratios,         |
//|      percentages. One EA, any symbol, any timeframe.             |
//|   2. Conditional triggers beat narrative — belief arms a setup   |
//|      with a trigger LEVEL; only the level firing executes.       |
//|      Every mode and strategy obeys this. No exceptions.          |
//|   3. HTF momentum rollover = directional veto (2 Jun 2026).      |
//|      Hard veto at AI>=30, soft penalty below.                    |
//|   4. Engram memory harvests every closed trade on the symbol     |
//|      (EA, manual, pre-existing history) with market context      |
//|      and outcome anatomy; context win-rates feed back into       |
//|      conviction and can veto toxic contexts.                     |
//|   5. Grounded pacing: behind-pace urgency relaxes thresholds     |
//|      and scales risk within HARD CAPS. Never martingale,         |
//|      never SL removal. Daily loss guardrail outranks target.     |
//|   6. Anti-stall valve: barren bars progressively relax the       |
//|      belief gate (bounded). First-run trade anxiety is           |
//|      structurally impossible.                                    |
//+------------------------------------------------------------------+
#property copyright "Empire Trading Systems"
#property version   "3.20"
#property description "Conquest v3.20 — mode layer + target pacing over conditional-trigger engine with Engram memory"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT ENUMS                                                      |
//+------------------------------------------------------------------+
enum ENUM_CQ3_TRADEMODE
{
   TM_AUTO       = 0,   // Auto (both directions, belief decides)
   TM_BUY        = 1,   // Buy only
   TM_SELL       = 2,   // Sell only
   TM_SEQUENTIAL = 3,   // Sequential (one at a time, ride winners, flip losers)
   TM_PHASE      = 4    // Phase (anti-martingale: escalate risk on win streaks)
};

enum ENUM_CQ3_STRATEGY
{
   ST_AUTO     = 0,   // Auto (regime decides trigger style)
   ST_ACE      = 1,   // ACE (adaptive: both trigger styles, all regimes)
   ST_PRINT    = 2,   // Print (momentum continuation, frequent partials)
   ST_SCALP    = 3,   // Scalp (FVG fills, tight targets, fast exits)
   ST_DAYBREAK = 4    // Daybreak (previous-day high/low breakout)
};

enum ENUM_CQ3_TGTMODE
{
   TGT_AMOUNT  = 0,   // Target is account currency amount
   TGT_PERCENT = 1    // Target is % of cycle-start balance
};

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Mode & Strategy ==="
input ENUM_CQ3_TRADEMODE InpTradeMode = TM_AUTO;     // Trade mode
input ENUM_CQ3_STRATEGY  InpStrategy  = ST_AUTO;     // Strategy

input group "=== Sizing ==="
input double InpLotSize     = 0.0;    // Fixed lot size (0 = risk-based sizing)
input double InpRiskPercent = 0.75;   // Risk per trade % of balance (when lot size = 0)

input group "=== Target System ==="
input double           InpTargetValue     = 0.0;         // Target value (0 = no target)
input ENUM_CQ3_TGTMODE InpTargetMode      = TGT_AMOUNT;  // Target mode: amount or percent
input bool             InpStopAfterTarget = true;        // Stop trading after target hit
input double           InpTimeLimitHours  = 0.0;         // Time limit to reach target, hours (0 = off)

input group "=== Interface & Intelligence ==="
input bool InpShowDashboard = true;   // Show target-tracking dashboard on chart
input int  InpAILevel       = 70;     // AI intelligence in trading, 0-100

//+------------------------------------------------------------------+
//| INTERNAL CONSTANTS                                               |
//+------------------------------------------------------------------+
#define CQ3_MAGIC             747320
#define CQ3_LOGGING           true
#define CQ3_MAX_POSITIONS     2
#define CQ3_DAILY_MAXLOSS_PCT 3.0
#define CQ3_RISK_HARDCAP_PCT  2.0    // absolute per-trade risk ceiling, any mode, any urgency

#define CQ3_TRACK_MAX         16
#define CQ3_SETUP_EXPIRY_BARS 12
#define CQ3_REGIMES            4

// Trigger geometry (ATR units)
#define CQ3_BREAK_OFFSET      0.10
#define CQ3_SL_MIN_ATR        0.80
#define CQ3_SL_MAX_ATR        2.50
#define CQ3_BE_BUFFER_ATR     0.05

// Spread gate (fraction of ATR)
#define CQ3_SPREAD_SOFT       0.12
#define CQ3_SPREAD_HARD       0.25

// Belief thresholds per regime (raw, before AI blending)
#define CQ3_THR_TREND         0.62
#define CQ3_THR_CHOP          0.72
#define CQ3_THR_PANIC         0.99
#define CQ3_THR_REVERSION     0.70
#define CQ3_THR_FLOOR         0.52   // AI=0 / max-relief floor: just above coin flip

// Calibration / memory
#define CQ3_REQUIRED_WR       0.42
#define CQ3_CALIB_MIN_N       8
#define CQ3_MEM_MIN_N         6
#define CQ3_MEM_VETO_N        10
#define CQ3_MEM_VETO_WR       0.25
#define CQ3_HICONV            0.60
#define CQ3_MEM_KEYS          864

// Pacing / anti-stall (all bounded)
#define CQ3_URGENCY_THR_RELIEF 0.06  // max threshold relief from being behind pace
#define CQ3_URGENCY_RISK_BOOST 0.30  // max +30% risk from urgency (hard cap still applies)
#define CQ3_STALL_BARS_STEP    15    // barren bars per relief step
#define CQ3_STALL_RELIEF_STEP  0.02
#define CQ3_STALL_RELIEF_MAX   0.06

//+------------------------------------------------------------------+
//| INTERNAL ENUMS                                                   |
//+------------------------------------------------------------------+
enum ENUM_CQ3_REGIME
{
   REGIME_TREND     = 0,
   REGIME_CHOP      = 1,
   REGIME_PANIC     = 2,
   REGIME_REVERSION = 3
};

enum ENUM_CQ3_TRIGGER
{
   TRIGGER_NONE  = 0,
   TRIGGER_BREAK = 1,
   TRIGGER_FILL  = 2
};

//+------------------------------------------------------------------+
//| STRUCTS — flat, global scope (strict dialect)                    |
//+------------------------------------------------------------------+
struct SymbolProfile
{
   double tick_value;
   double tick_size;
   double point;
   int    digits;
   double min_lot;
   double max_lot;
   double lot_step;
   double stops_level_px;
   ENUM_ORDER_TYPE_FILLING fill_mode;
   bool   valid;
};

struct MTFMap
{
   ENUM_TIMEFRAMES chart;
   ENUM_TIMEFRAMES htf1;
   ENUM_TIMEFRAMES htf2;
};

struct StructureState
{
   bool   bos_bull;
   bool   bos_bear;
   double bos_level;
   bool   fvg_bull;
   bool   fvg_bear;
   double fvg_high;
   double fvg_low;
   double fvg_mid;
   double fvg_target;
   double swing_high;
   double swing_low;
   double swing_mid;
   int    structural_dir;
   bool   valid;
};

struct MomentumState
{
   double chart_hist;
   double chart_hist_prev;
   int    htf1_dir;
   int    htf2_dir;
   bool   htf2_cross_down;
   bool   htf2_cross_up;
   bool   htf2_decel_bull;
   bool   htf2_decel_bear;
   bool   valid;
};

struct RegimeState
{
   ENUM_CQ3_REGIME regime;
   double atr_ratio;
   double extension;
   bool   valid;
};

struct LiquidityState
{
   double spread_atr;
   bool   tradeable;
   double penalty;
};

struct BeliefState
{
   double log_odds;
   double p_long;
   double threshold;
   int    candidate_dir;
   double conviction;
   bool   vetoed;
   string veto_reason;
};

struct ArmedSetup
{
   bool             active;
   int              direction;
   ENUM_CQ3_TRIGGER trigger_type;
   double           trigger_price;
   double           invalidation;
   double           sl_price;
   double           tp_price;
   datetime         expiry;
   double           conviction;
   ENUM_CQ3_REGIME  regime_at_arm;
   bool             is_daybreak;
};

struct PositionTrack
{
   bool     used;
   ulong    position_id;
   double   entry_price;
   double   risk_dist;
   int      direction;
   bool     scale1_done;
   bool     scale2_done;
   ENUM_CQ3_REGIME regime;
   double   conviction;
   int      trigger_type;
   datetime entry_time;
   double   atr_at_entry;
   double   mfe_atr;
   double   mae_atr;
};

struct DailyState
{
   datetime day_stamp;
   double   start_balance;
   bool     loss_locked;
   string   lock_reason;
};

// Target cycle: either the time-limit window or the server day
struct CycleState
{
   datetime anchor;          // cycle start time
   double   start_balance;   // balance at cycle start
   bool     target_hit;      // achieved within current cycle
   bool     target_locked;   // stop-after-target engaged
   bool     missed_logged;   // time expired without target (logged once)
   double   urgency;         // 0..1 behind-pace pressure
};

struct CalibState
{
   double wr_ema[CQ3_REGIMES];
   int    n[CQ3_REGIMES];
};

struct ContextSnapshot
{
   int    regime;
   int    struct_b;
   int    mom_b;
   int    ext_b;
   int    hour_b;
   double atr;
   bool   valid;
};

struct MemKeyStats
{
   double wr_ema;
   int    n;
};

// Strategy execution profile — zone schedule and trigger permissions
struct StrategyProfile
{
   bool   allow_break;
   bool   allow_fill;
   bool   regime_decides;    // ST_AUTO behavior
   double zone1_r;
   double zone2_r;
   double tp_r;
   double trail_atr;
   double trail_tight_atr;
};

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade          g_trade;
SymbolProfile   g_sym;
MTFMap          g_tf;
StructureState  g_struct;
MomentumState   g_mom;
RegimeState     g_regime;
LiquidityState  g_liq;
BeliefState     g_belief;
ArmedSetup      g_setup;
PositionTrack   g_tracks[CQ3_TRACK_MAX];
DailyState      g_daily;
CycleState      g_cycle;
CalibState      g_calib;
StrategyProfile g_prof;

MemKeyStats     g_mem[CQ3_MEM_KEYS];
ulong           g_known_ids[];
int             g_known_count = 0;

int g_h_atr14_chart = INVALID_HANDLE;
int g_h_atr55_chart = INVALID_HANDLE;
int g_h_atr14_htf1  = INVALID_HANDLE;
int g_h_macd_chart  = INVALID_HANDLE;
int g_h_macd_htf1   = INVALID_HANDLE;
int g_h_macd_htf2   = INVALID_HANDLE;

double   g_atr           = 0.0;
double   g_atr_htf1      = 0.0;
datetime g_last_bar      = 0;
bool     g_initialized   = false;
bool     g_backfill_done = false;
double   g_ai            = 0.7;    // InpAILevel / 100, clamped

// Mode-layer state
int      g_seq_dir       = 0;      // SEQUENTIAL: last closed direction
bool     g_seq_win       = false;  // SEQUENTIAL: last closed outcome
bool     g_seq_has_data  = false;
int      g_consec_wins   = 0;      // PHASE: consecutive wins today
datetime g_phase_day     = 0;

// DAYBREAK once-per-side-per-day
datetime g_db_day        = 0;
bool     g_db_long_done  = false;
bool     g_db_short_done = false;

// Anti-stall valve
int      g_barren_bars   = 0;

// Fire-time payload for track registration
ENUM_CQ3_REGIME g_pending_regime = REGIME_CHOP;
bool            g_pending_regime_set = false;
double          g_pending_conviction = -1.0;
int             g_pending_trigger = 0;

//+------------------------------------------------------------------+
//| UTILITIES                                                        |
//+------------------------------------------------------------------+
double Clamp(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

double SafeTanh(double x)
{
   if(x > 20.0)  return 1.0;
   if(x < -20.0) return -1.0;
   double e = MathExp(2.0 * x);
   return (e - 1.0) / (e + 1.0);
}

double Sigmoid(double x)
{
   if(x > 30.0)  return 1.0;
   if(x < -30.0) return 0.0;
   return 1.0 / (1.0 + MathExp(-x));
}

string RegimeToString(int r)
{
   if(r == REGIME_TREND)     return "TREND";
   if(r == REGIME_CHOP)      return "CHOP";
   if(r == REGIME_PANIC)     return "PANIC";
   if(r == REGIME_REVERSION) return "REVERSION";
   return "UNKNOWN";
}

string ModeToString(int m)
{
   if(m == TM_AUTO)       return "AUTO";
   if(m == TM_BUY)        return "BUY";
   if(m == TM_SELL)       return "SELL";
   if(m == TM_SEQUENTIAL) return "SEQUENTIAL";
   if(m == TM_PHASE)      return "PHASE";
   return "?";
}

string StrategyToString(int s)
{
   if(s == ST_AUTO)     return "AUTO";
   if(s == ST_ACE)      return "ACE";
   if(s == ST_PRINT)    return "PRINT";
   if(s == ST_SCALP)    return "SCALP";
   if(s == ST_DAYBREAK) return "DAYBREAK";
   return "?";
}

void Log(string msg)
{
   if(CQ3_LOGGING) Print("CQ3 | ", msg);
}

//+------------------------------------------------------------------+
//| SYMBOL PROFILE                                                   |
//+------------------------------------------------------------------+
bool BuildSymbolProfile()
{
   g_sym.tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_sym.tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_sym.point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_sym.digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_sym.min_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_sym.max_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_sym.lot_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_sym.stops_level_px = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_sym.point;

   long fill_flags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fill_flags & SYMBOL_FILLING_FOK) != 0)
      g_sym.fill_mode = ORDER_FILLING_FOK;
   else if((fill_flags & SYMBOL_FILLING_IOC) != 0)
      g_sym.fill_mode = ORDER_FILLING_IOC;
   else
      g_sym.fill_mode = ORDER_FILLING_RETURN;

   g_sym.valid = (g_sym.tick_value > 0.0 && g_sym.tick_size > 0.0 &&
                  g_sym.min_lot > 0.0 && g_sym.lot_step > 0.0);

   if(!g_sym.valid)
      Print("CQ3 ERROR: symbol profile invalid — tick_value=", g_sym.tick_value,
            " tick_size=", g_sym.tick_size);
   return g_sym.valid;
}

double NormalizeLot(double lot)
{
   double stepped = MathFloor(lot / g_sym.lot_step) * g_sym.lot_step;
   stepped = Clamp(stepped, g_sym.min_lot, g_sym.max_lot);
   return NormalizeDouble(stepped, 8);
}

double NormPrice(double p)
{
   return NormalizeDouble(p, g_sym.digits);
}

//+------------------------------------------------------------------+
//| MTF MAP                                                          |
//+------------------------------------------------------------------+
void BuildMTFMap()
{
   g_tf.chart = (ENUM_TIMEFRAMES)Period();

   switch(g_tf.chart)
   {
      case PERIOD_M1:  g_tf.htf1 = PERIOD_M15; g_tf.htf2 = PERIOD_H1;  break;
      case PERIOD_M2:  g_tf.htf1 = PERIOD_M30; g_tf.htf2 = PERIOD_H1;  break;
      case PERIOD_M3:  g_tf.htf1 = PERIOD_M30; g_tf.htf2 = PERIOD_H2;  break;
      case PERIOD_M4:  g_tf.htf1 = PERIOD_H1;  g_tf.htf2 = PERIOD_H4;  break;
      case PERIOD_M5:  g_tf.htf1 = PERIOD_H1;  g_tf.htf2 = PERIOD_H4;  break;
      case PERIOD_M6:  g_tf.htf1 = PERIOD_H1;  g_tf.htf2 = PERIOD_H4;  break;
      case PERIOD_M10: g_tf.htf1 = PERIOD_H1;  g_tf.htf2 = PERIOD_H4;  break;
      case PERIOD_M12: g_tf.htf1 = PERIOD_H1;  g_tf.htf2 = PERIOD_H4;  break;
      case PERIOD_M15: g_tf.htf1 = PERIOD_H1;  g_tf.htf2 = PERIOD_H4;  break;
      case PERIOD_M20: g_tf.htf1 = PERIOD_H2;  g_tf.htf2 = PERIOD_H8;  break;
      case PERIOD_M30: g_tf.htf1 = PERIOD_H4;  g_tf.htf2 = PERIOD_D1;  break;
      case PERIOD_H1:  g_tf.htf1 = PERIOD_H4;  g_tf.htf2 = PERIOD_D1;  break;
      case PERIOD_H2:  g_tf.htf1 = PERIOD_H8;  g_tf.htf2 = PERIOD_D1;  break;
      case PERIOD_H3:  g_tf.htf1 = PERIOD_H12; g_tf.htf2 = PERIOD_D1;  break;
      case PERIOD_H4:  g_tf.htf1 = PERIOD_D1;  g_tf.htf2 = PERIOD_W1;  break;
      case PERIOD_H6:  g_tf.htf1 = PERIOD_D1;  g_tf.htf2 = PERIOD_W1;  break;
      case PERIOD_H8:  g_tf.htf1 = PERIOD_D1;  g_tf.htf2 = PERIOD_W1;  break;
      case PERIOD_H12: g_tf.htf1 = PERIOD_W1;  g_tf.htf2 = PERIOD_MN1; break;
      case PERIOD_D1:  g_tf.htf1 = PERIOD_W1;  g_tf.htf2 = PERIOD_MN1; break;
      default:         g_tf.htf1 = PERIOD_MN1; g_tf.htf2 = PERIOD_MN1; break;
   }
}

//+------------------------------------------------------------------+
//| STRATEGY PROFILE — zone schedule + trigger permissions           |
//+------------------------------------------------------------------+
void ApplyStrategyProfile()
{
   // Defaults = ST_AUTO
   g_prof.allow_break     = true;
   g_prof.allow_fill      = true;
   g_prof.regime_decides  = true;
   g_prof.zone1_r         = 1.0;
   g_prof.zone2_r         = 2.0;
   g_prof.tp_r            = 3.0;
   g_prof.trail_atr       = 1.00;
   g_prof.trail_tight_atr = 0.70;

   if(InpStrategy == ST_ACE)
   {
      g_prof.regime_decides = false;   // both styles, all non-panic regimes
   }
   else if(InpStrategy == ST_PRINT)
   {
      g_prof.allow_fill      = false;  // momentum continuation only
      g_prof.regime_decides  = false;
      g_prof.zone1_r         = 0.8;
      g_prof.zone2_r         = 1.6;
      g_prof.tp_r            = 2.5;
      g_prof.trail_atr       = 0.80;
      g_prof.trail_tight_atr = 0.60;
   }
   else if(InpStrategy == ST_SCALP)
   {
      g_prof.allow_break     = false;  // fills only
      g_prof.regime_decides  = false;
      g_prof.zone1_r         = 0.5;
      g_prof.zone2_r         = 1.0;
      g_prof.tp_r            = 1.5;
      g_prof.trail_atr       = 0.60;
      g_prof.trail_tight_atr = 0.45;
   }
   else if(InpStrategy == ST_DAYBREAK)
   {
      g_prof.allow_break     = true;
      g_prof.allow_fill      = false;
      g_prof.regime_decides  = false;
      g_prof.zone1_r         = 1.0;
      g_prof.zone2_r         = 2.0;
      g_prof.tp_r            = 2.0;
   }
}

//+------------------------------------------------------------------+
//| SHARED REGIME CLASSIFIER                                         |
//+------------------------------------------------------------------+
int ClassifyRegime(double atr_ratio, double extension,
                   double hist, double hist_prev,
                   int struct_dir, int htf1_dir)
{
   bool decel = (MathAbs(hist) < MathAbs(hist_prev));
   if(atr_ratio >= 1.60)
      return REGIME_PANIC;
   if(MathAbs(extension) > 2.0 && decel)
      return REGIME_REVERSION;
   if(struct_dir != 0 &&
      ((struct_dir > 0 && htf1_dir > 0) || (struct_dir < 0 && htf1_dir < 0)))
      return REGIME_TREND;
   return REGIME_CHOP;
}

int HourBucket(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   if(dt.hour < 7)  return 0;
   if(dt.hour < 12) return 1;
   if(dt.hour < 17) return 2;
   return 3;
}

//+------------------------------------------------------------------+
//| ENGRAM MEMORY — context keys                                     |
//+------------------------------------------------------------------+
int MemKey(int dir_buy, const ContextSnapshot &ctx)
{
   int d = (dir_buy > 0) ? 1 : 0;
   int key = d
           + 2 * (ctx.regime
           + 4 * (ctx.struct_b
           + 3 * (ctx.mom_b
           + 3 * (ctx.ext_b
           + 3 *  ctx.hour_b))));
   if(key < 0) key = 0;
   if(key >= CQ3_MEM_KEYS) key = CQ3_MEM_KEYS - 1;
   return key;
}

void MemUpdate(int key, bool win, double weight)
{
   if(key < 0 || key >= CQ3_MEM_KEYS) return;
   double outcome = win ? 1.0 : 0.0;
   int reps = (weight >= 2.0) ? 2 : 1;
   for(int r = 0; r < reps; r++)
   {
      g_mem[key].wr_ema = 0.90 * g_mem[key].wr_ema + 0.10 * outcome;
      g_mem[key].n++;
   }
}

bool IsKnownPosition(ulong pos_id)
{
   for(int i = 0; i < g_known_count; i++)
      if(g_known_ids[i] == pos_id) return true;
   return false;
}

void AddKnownPosition(ulong pos_id)
{
   if(IsKnownPosition(pos_id)) return;
   ArrayResize(g_known_ids, g_known_count + 1, 256);
   g_known_ids[g_known_count] = pos_id;
   g_known_count++;
}

//+------------------------------------------------------------------+
//| CONTEXT RECONSTRUCTION                                           |
//+------------------------------------------------------------------+
bool ReconstructContext(datetime t, ContextSnapshot &out_ctx)
{
   out_ctx.valid = false;

   int chart_bars = Bars(_Symbol, g_tf.chart);
   int htf1_bars  = Bars(_Symbol, g_tf.htf1);
   if(chart_bars < 60 || htf1_bars < 15) return false;
   if(t < iTime(_Symbol, g_tf.chart, chart_bars - 1)) return false;
   if(t < iTime(_Symbol, g_tf.htf1, htf1_bars - 1))   return false;

   int cs  = iBarShift(_Symbol, g_tf.chart, t, false);
   int h1s = iBarShift(_Symbol, g_tf.htf1, t, false);
   if(cs < 0 || h1s < 0) return false;

   int c_closed  = cs + 1;
   int h1_closed = h1s + 1;
   if(c_closed + 2 >= chart_bars) return false;
   if(h1_closed + 11 >= htf1_bars) return false;

   double a14[], a55[], a14h[], m1[], s1[], mc[], sc[];
   ArraySetAsSeries(a14, true);  ArraySetAsSeries(a55, true);
   ArraySetAsSeries(a14h, true); ArraySetAsSeries(m1, true);
   ArraySetAsSeries(s1, true);   ArraySetAsSeries(mc, true);
   ArraySetAsSeries(sc, true);

   if(CopyBuffer(g_h_atr14_chart, 0, c_closed, 1, a14)  < 1) return false;
   if(CopyBuffer(g_h_atr55_chart, 0, c_closed, 1, a55)  < 1) return false;
   if(CopyBuffer(g_h_atr14_htf1,  0, h1_closed, 1, a14h) < 1) return false;
   if(CopyBuffer(g_h_macd_htf1,   0, h1_closed, 1, m1)  < 1) return false;
   if(CopyBuffer(g_h_macd_htf1,   1, h1_closed, 1, s1)  < 1) return false;
   if(CopyBuffer(g_h_macd_chart,  0, c_closed, 2, mc)   < 2) return false;
   if(CopyBuffer(g_h_macd_chart,  1, c_closed, 2, sc)   < 2) return false;

   double atr = a14[0];
   if(atr <= 0.0 || a55[0] <= 0.0 || a14h[0] <= 0.0) return false;

   double atr_ratio = atr / a55[0];
   double hist      = mc[0] - sc[0];
   double hist_prev = mc[1] - sc[1];
   int    htf1_dir  = (m1[0] > s1[0]) ? 1 : -1;

   double rec_hi = -DBL_MAX, rec_lo = DBL_MAX, old_hi = -DBL_MAX, old_lo = DBL_MAX;
   double swH = -DBL_MAX, swL = DBL_MAX;
   for(int b = h1_closed + 1; b <= h1_closed + 10; b++)
   {
      double hi = iHigh(_Symbol, g_tf.htf1, b);
      double lo = iLow(_Symbol, g_tf.htf1, b);
      swH = MathMax(swH, hi);
      swL = MathMin(swL, lo);
      if(b <= h1_closed + 5) { rec_hi = MathMax(rec_hi, hi); rec_lo = MathMin(rec_lo, lo); }
      else                   { old_hi = MathMax(old_hi, hi); old_lo = MathMin(old_lo, lo); }
   }
   if(swH <= -DBL_MAX || swL >= DBL_MAX) return false;

   int struct_dir = 0;
   if(rec_hi > old_hi && rec_lo > old_lo)      struct_dir = 1;
   else if(rec_hi < old_hi && rec_lo < old_lo) struct_dir = -1;

   double swing_mid = 0.5 * (swH + swL);
   double close_c   = iClose(_Symbol, g_tf.chart, c_closed);
   double extension = (close_c - swing_mid) / a14h[0];

   out_ctx.regime   = ClassifyRegime(atr_ratio, extension, hist, hist_prev,
                                     struct_dir, htf1_dir);
   out_ctx.struct_b = struct_dir + 1;
   int hist_sign    = (hist > 0) ? 1 : -1;
   out_ctx.mom_b    = (htf1_dir > 0 && hist_sign > 0) ? 2 :
                      (htf1_dir < 0 && hist_sign < 0) ? 0 : 1;
   out_ctx.ext_b    = (extension < -1.5) ? 0 : (extension > 1.5) ? 2 : 1;
   out_ctx.hour_b   = HourBucket(t);
   out_ctx.atr      = atr;
   out_ctx.valid    = true;
   return true;
}

void LiveContext(ContextSnapshot &out_ctx)
{
   out_ctx.regime   = (int)g_regime.regime;
   out_ctx.struct_b = g_struct.structural_dir + 1;
   int hist_sign    = (g_mom.chart_hist > 0) ? 1 : -1;
   out_ctx.mom_b    = (g_mom.htf1_dir > 0 && hist_sign > 0) ? 2 :
                      (g_mom.htf1_dir < 0 && hist_sign < 0) ? 0 : 1;
   out_ctx.ext_b    = (g_regime.extension < -1.5) ? 0 :
                      (g_regime.extension > 1.5) ? 2 : 1;
   out_ctx.hour_b   = HourBucket(TimeCurrent());
   out_ctx.atr      = g_atr;
   out_ctx.valid    = (g_struct.valid && g_mom.valid && g_regime.valid);
}

//+------------------------------------------------------------------+
//| ENGRAM FILE                                                      |
//+------------------------------------------------------------------+
string MemFileName()
{
   return StringFormat("CQ3_Engram_%s.csv", _Symbol);
}

void MemAppendRecord(ulong pos_id, string src, int dir,
                     datetime t_in, datetime t_out,
                     double entry, double exitp, double profit, bool win,
                     const ContextSnapshot &ctx, double conviction, int trig,
                     double mfe, double mae, int bars_held, bool hc_fail)
{
   int h = FileOpen(MemFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
   {
      Log(StringFormat("ENGRAM WRITE FAIL | err=%d", GetLastError()));
      return;
   }
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, (long)pos_id, src, dir,
             (long)t_in, (long)t_out,
             DoubleToString(entry, g_sym.digits),
             DoubleToString(exitp, g_sym.digits),
             DoubleToString(profit, 2), win ? 1 : 0,
             ctx.regime, ctx.struct_b, ctx.mom_b, ctx.ext_b, ctx.hour_b,
             DoubleToString(conviction, 3), trig,
             DoubleToString(mfe, 2), DoubleToString(mae, 2),
             bars_held, hc_fail ? 1 : 0);
   FileClose(h);
}

void LoadEngramFile()
{
   int loaded = 0;
   int h = FileOpen(MemFileName(), FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
   {
      Log("ENGRAM | no existing journal — starting fresh");
      return;
   }

   while(!FileIsEnding(h))
   {
      long   pos_id = (long)FileReadNumber(h);
      string src    = FileReadString(h);
      int    dir    = (int)FileReadNumber(h);
      long   t_in   = (long)FileReadNumber(h);
      long   t_out  = (long)FileReadNumber(h);
      double entry  = FileReadNumber(h);
      double exitp  = FileReadNumber(h);
      double profit = FileReadNumber(h);
      int    win    = (int)FileReadNumber(h);
      int    regime = (int)FileReadNumber(h);
      int    st_b   = (int)FileReadNumber(h);
      int    mom_b  = (int)FileReadNumber(h);
      int    ext_b  = (int)FileReadNumber(h);
      int    hour_b = (int)FileReadNumber(h);
      double conv   = FileReadNumber(h);
      int    trig   = (int)FileReadNumber(h);
      double mfe    = FileReadNumber(h);
      double mae    = FileReadNumber(h);
      int    bars   = (int)FileReadNumber(h);
      int    hcf    = (int)FileReadNumber(h);

      if(pos_id <= 0) continue;

      ContextSnapshot ctx;
      ctx.regime = regime; ctx.struct_b = st_b; ctx.mom_b = mom_b;
      ctx.ext_b = ext_b; ctx.hour_b = hour_b; ctx.atr = 0.0; ctx.valid = true;

      double weight = (hcf == 1) ? 2.0 : 1.0;
      MemUpdate(MemKey(dir, ctx), win == 1, weight);
      AddKnownPosition((ulong)pos_id);
      loaded++;

      if(t_in == 0 && t_out == 0 && entry == 0 && exitp == 0 &&
         profit == 0 && conv == 0 && trig == 0 && mfe == 0 &&
         mae == 0 && bars == 0 && src == "") {}
   }
   FileClose(h);
   Log(StringFormat("ENGRAM | loaded %d records from journal", loaded));
}

//+------------------------------------------------------------------+
//| HARVEST                                                          |
//+------------------------------------------------------------------+
bool HarvestClosedPosition(ulong pos_id)
{
   if(IsKnownPosition(pos_id)) return false;
   if(!HistorySelectByPosition((long)pos_id)) return false;

   int deals = HistoryDealsTotal();
   if(deals < 2) return false;

   datetime t_in = 0, t_out = 0;
   double entry = 0.0, exitp = 0.0;
   double vol_in = 0.0, vol_out = 0.0;
   double net = 0.0;
   int dir = 0;
   long magic = 0;
   bool symbol_ok = false;

   for(int d = 0; d < deals; d++)
   {
      ulong dt = HistoryDealGetTicket(d);
      if(dt == 0) continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
      symbol_ok = true;

      long entry_kind = HistoryDealGetInteger(dt, DEAL_ENTRY);
      double v = HistoryDealGetDouble(dt, DEAL_VOLUME);
      net += HistoryDealGetDouble(dt, DEAL_PROFIT) +
             HistoryDealGetDouble(dt, DEAL_SWAP) +
             HistoryDealGetDouble(dt, DEAL_COMMISSION);

      if(entry_kind == DEAL_ENTRY_IN)
      {
         if(t_in == 0)
         {
            t_in  = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
            entry = HistoryDealGetDouble(dt, DEAL_PRICE);
            dir   = (HistoryDealGetInteger(dt, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
            magic = HistoryDealGetInteger(dt, DEAL_MAGIC);
         }
         vol_in += v;
      }
      else if(entry_kind == DEAL_ENTRY_OUT || entry_kind == DEAL_ENTRY_INOUT ||
              entry_kind == DEAL_ENTRY_OUT_BY)
      {
         t_out = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
         exitp = HistoryDealGetDouble(dt, DEAL_PRICE);
         vol_out += v;
      }
   }

   if(!symbol_ok || t_in == 0 || t_out == 0 || dir == 0) return false;
   if(vol_out < vol_in - g_sym.lot_step * 0.5) return false;

   ContextSnapshot ctx;
   if(!ReconstructContext(t_in, ctx)) return false;

   double mfe = 0.0, mae = 0.0;
   int bars_held = 0;
   int se = iBarShift(_Symbol, g_tf.chart, t_in, false);
   int sx = iBarShift(_Symbol, g_tf.chart, t_out, false);
   if(se >= 0 && sx >= 0 && se >= sx && ctx.atr > 0.0)
   {
      int count = se - sx + 1;
      bars_held = count;
      int hi_idx = iHighest(_Symbol, g_tf.chart, MODE_HIGH, count, sx);
      int lo_idx = iLowest(_Symbol, g_tf.chart, MODE_LOW, count, sx);
      if(hi_idx >= 0 && lo_idx >= 0)
      {
         double hh = iHigh(_Symbol, g_tf.chart, hi_idx);
         double ll = iLow(_Symbol, g_tf.chart, lo_idx);
         if(dir > 0)
         {
            mfe = MathMax(0.0, (hh - entry) / ctx.atr);
            mae = MathMax(0.0, (entry - ll) / ctx.atr);
         }
         else
         {
            mfe = MathMax(0.0, (entry - ll) / ctx.atr);
            mae = MathMax(0.0, (hh - entry) / ctx.atr);
         }
      }
   }

   bool   win     = (net > 0.0);
   bool   is_ours = (magic == CQ3_MAGIC);
   string src     = is_ours ? "EA" : "MANUAL";

   double conviction = -1.0;
   int    trig = 0;
   int slot = FindTrack(pos_id);
   if(slot >= 0)
   {
      conviction = g_tracks[slot].conviction;
      trig       = g_tracks[slot].trigger_type;
      if(g_tracks[slot].mfe_atr > mfe) mfe = g_tracks[slot].mfe_atr;
      if(g_tracks[slot].mae_atr > mae) mae = g_tracks[slot].mae_atr;
   }

   bool hc_fail = (is_ours && !win && conviction >= CQ3_HICONV);
   double weight = hc_fail ? 2.0 : 1.0;

   MemUpdate(MemKey(dir, ctx), win, weight);
   MemAppendRecord(pos_id, src, dir, t_in, t_out, entry, exitp, net, win,
                   ctx, conviction, trig, mfe, mae, bars_held, hc_fail);
   AddKnownPosition(pos_id);

   if(hc_fail)
      Log(StringFormat("ENGRAM HC-FAIL | posID=%I64u conv=%.2f %s regime=%s mae=%.1fATR — double-weighted",
          pos_id, conviction, dir > 0 ? "LONG" : "SHORT",
          RegimeToString(ctx.regime), mae));
   else if(win)
      Log(StringFormat("ENGRAM WIN | posID=%I64u %s %s regime=%s mfe=%.1f mae=%.1fATR bars=%d",
          pos_id, src, dir > 0 ? "LONG" : "SHORT",
          RegimeToString(ctx.regime), mfe, mae, bars_held));

   return true;
}

void HarvestAccountHistory()
{
   if(!HistorySelect(0, TimeCurrent()))
   {
      Log("ENGRAM | history select failed — no backfill harvest");
      return;
   }

   ulong ids[];
   int   id_count = 0;
   int total = HistoryDealsTotal();
   for(int d = 0; d < total; d++)
   {
      ulong dt = HistoryDealGetTicket(d);
      if(dt == 0) continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
      ulong pid = (ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID);
      if(pid == 0) continue;

      bool dup = false;
      for(int i = 0; i < id_count; i++)
         if(ids[i] == pid) { dup = true; break; }
      if(dup) continue;

      ArrayResize(ids, id_count + 1, 256);
      ids[id_count] = pid;
      id_count++;
   }

   int harvested = 0, skipped = 0;
   for(int i = 0; i < id_count; i++)
   {
      if(IsKnownPosition(ids[i])) continue;
      if(HarvestClosedPosition(ids[i])) harvested++;
      else skipped++;
   }

   Log(StringFormat("ENGRAM BACKFILL | %d positions | %d harvested | %d skipped (open/beyond depth/known)",
       id_count, harvested, skipped));
}

//+------------------------------------------------------------------+
//| MEMORY FEEDBACK — AI-scaled                                      |
//+------------------------------------------------------------------+
double MemAdjust(int dir, const ContextSnapshot &ctx, bool &veto, string &note)
{
   veto = false;
   note = "";
   if(!ctx.valid) return 1.0;

   int key = MemKey(dir, ctx);
   if(g_mem[key].n < CQ3_MEM_MIN_N) return 1.0;

   double wr = g_mem[key].wr_ema;

   // Memory veto requires meaningful AI engagement
   if(g_ai >= 0.5 && g_mem[key].n >= CQ3_MEM_VETO_N && wr < CQ3_MEM_VETO_WR)
   {
      veto = true;
      note = StringFormat("memory veto: context key %d wr=%.2f n=%d",
                          key, wr, g_mem[key].n);
      return 0.0;
   }

   double edge = wr - CQ3_REQUIRED_WR;
   double raw_mult = 1.0 + Clamp(edge * 2.0, -0.50, 0.40);
   // Blend toward neutral as AI decreases
   double mult = 1.0 + (raw_mult - 1.0) * g_ai;
   note = StringFormat("memory: key=%d wr=%.2f n=%d mult=%.2f",
                       key, wr, g_mem[key].n, mult);
   return mult;
}

//+------------------------------------------------------------------+
//| COARSE CALIBRATION                                               |
//+------------------------------------------------------------------+
string CalibKey(int regime, string field)
{
   return StringFormat("CQ3_%s_%d_R%d_%s", _Symbol, CQ3_MAGIC, regime, field);
}

void LoadCalibration()
{
   for(int r = 0; r < CQ3_REGIMES; r++)
   {
      string k_wr = CalibKey(r, "WR");
      string k_n  = CalibKey(r, "N");
      g_calib.wr_ema[r] = GlobalVariableCheck(k_wr) ? GlobalVariableGet(k_wr) : 0.50;
      g_calib.n[r]      = GlobalVariableCheck(k_n)  ? (int)GlobalVariableGet(k_n) : 0;
   }
}

void SaveCalibration()
{
   for(int r = 0; r < CQ3_REGIMES; r++)
   {
      GlobalVariableSet(CalibKey(r, "WR"), g_calib.wr_ema[r]);
      GlobalVariableSet(CalibKey(r, "N"), (double)g_calib.n[r]);
   }
}

void UpdateCalibration(int regime, bool win)
{
   if(regime < 0 || regime >= CQ3_REGIMES) return;
   double outcome = win ? 1.0 : 0.0;
   g_calib.wr_ema[regime] = 0.90 * g_calib.wr_ema[regime] + 0.10 * outcome;
   g_calib.n[regime]++;
   SaveCalibration();
}

double ThresholdAdjustment(int regime)
{
   if(regime < 0 || regime >= CQ3_REGIMES) return 0.0;
   if(g_calib.n[regime] < CQ3_CALIB_MIN_N) return 0.0;
   return Clamp((CQ3_REQUIRED_WR - g_calib.wr_ema[regime]) * 0.5, -0.04, 0.08);
}

double RegimeBaseThreshold(int regime)
{
   if(regime == REGIME_TREND)     return CQ3_THR_TREND;
   if(regime == REGIME_CHOP)      return CQ3_THR_CHOP;
   if(regime == REGIME_PANIC)     return CQ3_THR_PANIC;
   if(regime == REGIME_REVERSION) return CQ3_THR_REVERSION;
   return 0.75;
}

// AI blending + urgency relief + anti-stall relief. Floor is absolute.
double EffectiveThreshold(int regime)
{
   double raw = RegimeBaseThreshold(regime) + ThresholdAdjustment(regime);

   // PANIC stand-down only holds at meaningful AI; below, it degrades
   // to a steep-but-passable gate (risk is also halved in panic).
   if(regime == REGIME_PANIC && g_ai < 0.5)
      raw = 0.80;

   double thr = CQ3_THR_FLOOR + (raw - CQ3_THR_FLOOR) * g_ai;

   thr -= CQ3_URGENCY_THR_RELIEF * g_cycle.urgency;

   double stall_relief = MathMin(CQ3_STALL_RELIEF_MAX,
                         (g_barren_bars / CQ3_STALL_BARS_STEP) * CQ3_STALL_RELIEF_STEP);
   thr -= stall_relief;

   return MathMax(thr, CQ3_THR_FLOOR);
}

//+------------------------------------------------------------------+
//| PERCEPTION 1/4 — STRUCTURE on HTF1                               |
//+------------------------------------------------------------------+
bool UpdateStructure()
{
   ZeroMemory(g_struct);

   if(Bars(_Symbol, g_tf.htf1) < 15) return false;

   double swH = -DBL_MAX, swL = DBL_MAX;
   for(int b = 2; b <= 11; b++)
   {
      swH = MathMax(swH, iHigh(_Symbol, g_tf.htf1, b));
      swL = MathMin(swL, iLow(_Symbol, g_tf.htf1, b));
   }
   if(swH <= -DBL_MAX || swL >= DBL_MAX) return false;
   g_struct.swing_high = swH;
   g_struct.swing_low  = swL;
   g_struct.swing_mid  = 0.5 * (swH + swL);

   double c1 = iClose(_Symbol, g_tf.htf1, 1);
   if(c1 > swH) { g_struct.bos_bull = true; g_struct.bos_level = swH; }
   else if(c1 < swL) { g_struct.bos_bear = true; g_struct.bos_level = swL; }

   double hi1 = iHigh(_Symbol, g_tf.htf1, 1);
   double lo1 = iLow(_Symbol, g_tf.htf1, 1);
   double hi3 = iHigh(_Symbol, g_tf.htf1, 3);
   double lo3 = iLow(_Symbol, g_tf.htf1, 3);

   if(lo1 > hi3 + g_sym.point)
   {
      g_struct.fvg_bull   = true;
      g_struct.fvg_low    = hi3;
      g_struct.fvg_high   = lo1;
      g_struct.fvg_mid    = 0.5 * (hi3 + lo1);
      g_struct.fvg_target = lo1 + (lo1 - hi3);
   }
   else if(hi1 < lo3 - g_sym.point)
   {
      g_struct.fvg_bear   = true;
      g_struct.fvg_high   = lo3;
      g_struct.fvg_low    = hi1;
      g_struct.fvg_mid    = 0.5 * (lo3 + hi1);
      g_struct.fvg_target = hi1 - (lo3 - hi1);
   }

   double rec_hi = -DBL_MAX, rec_lo = DBL_MAX, old_hi = -DBL_MAX, old_lo = DBL_MAX;
   for(int b = 2; b <= 6; b++)
   {
      rec_hi = MathMax(rec_hi, iHigh(_Symbol, g_tf.htf1, b));
      rec_lo = MathMin(rec_lo, iLow(_Symbol, g_tf.htf1, b));
   }
   for(int b = 7; b <= 11; b++)
   {
      old_hi = MathMax(old_hi, iHigh(_Symbol, g_tf.htf1, b));
      old_lo = MathMin(old_lo, iLow(_Symbol, g_tf.htf1, b));
   }
   bool hh = (rec_hi > old_hi), hl = (rec_lo > old_lo);
   bool lh = (rec_hi < old_hi), ll = (rec_lo < old_lo);
   if(hh && hl)      g_struct.structural_dir = 1;
   else if(lh && ll) g_struct.structural_dir = -1;
   else              g_struct.structural_dir = 0;

   g_struct.valid = true;
   return true;
}

//+------------------------------------------------------------------+
//| PERCEPTION 2/4 — MOMENTUM                                        |
//+------------------------------------------------------------------+
bool UpdateMomentum()
{
   ZeroMemory(g_mom);

   double main_c[], sig_c[], main_1[], sig_1[], main_2[], sig_2[];
   ArraySetAsSeries(main_c, true); ArraySetAsSeries(sig_c, true);
   ArraySetAsSeries(main_1, true); ArraySetAsSeries(sig_1, true);
   ArraySetAsSeries(main_2, true); ArraySetAsSeries(sig_2, true);

   if(CopyBuffer(g_h_macd_chart, 0, 0, 4, main_c) < 4) return false;
   if(CopyBuffer(g_h_macd_chart, 1, 0, 4, sig_c)  < 4) return false;
   if(CopyBuffer(g_h_macd_htf1,  0, 0, 3, main_1) < 3) return false;
   if(CopyBuffer(g_h_macd_htf1,  1, 0, 3, sig_1)  < 3) return false;
   if(CopyBuffer(g_h_macd_htf2,  0, 0, 5, main_2) < 5) return false;
   if(CopyBuffer(g_h_macd_htf2,  1, 0, 5, sig_2)  < 5) return false;

   g_mom.chart_hist      = main_c[1] - sig_c[1];
   g_mom.chart_hist_prev = main_c[2] - sig_c[2];

   g_mom.htf1_dir = (main_1[1] > sig_1[1]) ? 1 : -1;
   g_mom.htf2_dir = (main_2[1] > sig_2[1]) ? 1 : -1;

   for(int b = 1; b <= 3; b++)
   {
      bool above_now  = (main_2[b]     > sig_2[b]);
      bool above_prev = (main_2[b + 1] > sig_2[b + 1]);
      if(!above_now && above_prev) g_mom.htf2_cross_down = true;
      if(above_now && !above_prev) g_mom.htf2_cross_up   = true;
   }

   double gap1 = main_2[1] - sig_2[1];
   double gap2 = main_2[2] - sig_2[2];
   double gap3 = main_2[3] - sig_2[3];
   if(gap1 > 0 && gap1 < gap2 && gap2 < gap3) g_mom.htf2_decel_bull = true;
   if(gap1 < 0 && gap1 > gap2 && gap2 > gap3) g_mom.htf2_decel_bear = true;

   g_mom.valid = true;
   return true;
}

//+------------------------------------------------------------------+
//| PERCEPTION 3/4 — VOLATILITY REGIME                               |
//+------------------------------------------------------------------+
bool UpdateRegime()
{
   ZeroMemory(g_regime);

   double a14[], a55[], a14h[];
   ArraySetAsSeries(a14, true); ArraySetAsSeries(a55, true); ArraySetAsSeries(a14h, true);

   if(CopyBuffer(g_h_atr14_chart, 0, 0, 2, a14) < 2) return false;
   if(CopyBuffer(g_h_atr55_chart, 0, 0, 2, a55) < 2) return false;
   if(CopyBuffer(g_h_atr14_htf1,  0, 0, 2, a14h) < 2) return false;

   g_atr      = a14[1];
   g_atr_htf1 = a14h[1];
   if(g_atr <= 0.0 || a55[1] <= 0.0 || g_atr_htf1 <= 0.0) return false;

   g_regime.atr_ratio = g_atr / a55[1];

   double close_chart = iClose(_Symbol, g_tf.chart, 1);
   g_regime.extension = (g_struct.valid)
                        ? (close_chart - g_struct.swing_mid) / g_atr_htf1
                        : 0.0;

   g_regime.regime = (ENUM_CQ3_REGIME)ClassifyRegime(
                        g_regime.atr_ratio, g_regime.extension,
                        g_mom.chart_hist, g_mom.chart_hist_prev,
                        g_struct.structural_dir, g_mom.htf1_dir);

   g_regime.valid = true;
   return true;
}

//+------------------------------------------------------------------+
//| PERCEPTION 4/4 — LIQUIDITY                                       |
//+------------------------------------------------------------------+
void UpdateLiquidity()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = MathMax(0.0, ask - bid);

   g_liq.spread_atr = (g_atr > 0.0) ? spread / g_atr : 1.0;
   g_liq.tradeable  = (g_liq.spread_atr < CQ3_SPREAD_HARD);

   if(g_liq.spread_atr <= CQ3_SPREAD_SOFT)
      g_liq.penalty = 1.0;
   else
      g_liq.penalty = Clamp(1.0 - (g_liq.spread_atr - CQ3_SPREAD_SOFT) /
                                  (CQ3_SPREAD_HARD - CQ3_SPREAD_SOFT), 0.0, 1.0);
}

//+------------------------------------------------------------------+
//| BELIEF — AI-scaled gating, mode-aware direction filter           |
//+------------------------------------------------------------------+
void ResetBelief()
{
   g_belief.log_odds      = 0.0;
   g_belief.p_long        = 0.5;
   g_belief.threshold     = 1.0;
   g_belief.candidate_dir = 0;
   g_belief.conviction    = 0.0;
   g_belief.vetoed        = false;
   g_belief.veto_reason   = "";
}

void UpdateBelief()
{
   ResetBelief();

   if(!g_struct.valid || !g_mom.valid || !g_regime.valid)
      return;

   // Evidence 1: STRUCTURE
   double s_struct = 0.0;
   s_struct += 0.4 * g_struct.structural_dir;
   if(g_struct.bos_bull) s_struct += 0.4;
   if(g_struct.bos_bear) s_struct -= 0.4;
   if(g_struct.fvg_bull) s_struct += 0.2;
   if(g_struct.fvg_bear) s_struct -= 0.2;
   s_struct = Clamp(s_struct, -1.0, 1.0);

   // Evidence 2: MOMENTUM
   double hist_norm = SafeTanh(g_mom.chart_hist / (0.10 * g_atr));
   double s_mom = Clamp(0.5 * hist_norm + 0.5 * g_mom.htf1_dir, -1.0, 1.0);

   // Evidence 3: REGIME FIT
   double s_fit = 0.0;
   if(g_regime.regime == REGIME_TREND)
      s_fit = 0.3 * g_mom.htf1_dir;
   else if(g_regime.regime == REGIME_REVERSION)
      s_fit = (g_regime.extension > 0) ? -0.4 : 0.4;

   double w = 1.0 * s_struct + 0.8 * s_mom + 0.4 * s_fit;
   g_belief.log_odds = 1.6 * w;
   g_belief.p_long   = Sigmoid(g_belief.log_odds);

   double thr = EffectiveThreshold((int)g_regime.regime);

   // Direction acceptance — mode-filtered
   bool long_allowed  = (InpTradeMode != TM_SELL);
   bool short_allowed = (InpTradeMode != TM_BUY);

   // SEQUENTIAL: prefer last winner's direction, flip after a loss;
   // small threshold relief for the preferred direction keeps the
   // sequence flowing while belief still gates.
   int seq_pref = 0;
   if(InpTradeMode == TM_SEQUENTIAL && g_seq_has_data)
      seq_pref = g_seq_win ? g_seq_dir : -g_seq_dir;

   int    dir = 0;
   double p_dir = 0.0;
   double thr_long  = thr - ((seq_pref > 0) ? 0.04 : 0.0);
   double thr_short = thr - ((seq_pref < 0) ? 0.04 : 0.0);
   thr_long  = MathMax(thr_long, CQ3_THR_FLOOR);
   thr_short = MathMax(thr_short, CQ3_THR_FLOOR);

   if(long_allowed && g_belief.p_long >= thr_long)
   { dir = 1; p_dir = g_belief.p_long; thr = thr_long; }
   else if(short_allowed && (1.0 - g_belief.p_long) >= thr_short)
   { dir = -1; p_dir = 1.0 - g_belief.p_long; thr = thr_short; }

   // SEQUENTIAL strictness: only the preferred direction trades
   if(InpTradeMode == TM_SEQUENTIAL && seq_pref != 0 && dir != 0 && dir != seq_pref)
      dir = 0;

   // HTF2 momentum rollover (validated 2 Jun 2026):
   // hard veto at AI>=0.3, soft penalty below
   double rollover_mult = 1.0;
   if(dir > 0 && g_mom.htf2_cross_down)
   {
      if(g_ai >= 0.3)
      {
         g_belief.vetoed = true;
         g_belief.veto_reason = "HTF2 MACD signal-line cross DOWN — long vetoed";
         dir = 0;
      }
      else rollover_mult = 0.5;
   }
   if(dir < 0 && g_mom.htf2_cross_up)
   {
      if(g_ai >= 0.3)
      {
         g_belief.vetoed = true;
         g_belief.veto_reason = "HTF2 MACD signal-line cross UP — short vetoed";
         dir = 0;
      }
      else rollover_mult = 0.5;
   }

   double decel_mult = 1.0;
   if(dir > 0 && g_mom.htf2_decel_bull) decel_mult = 0.6;
   if(dir < 0 && g_mom.htf2_decel_bear) decel_mult = 0.6;

   double conviction = 0.0;
   if(dir != 0 && thr < 1.0)
      conviction = Clamp((p_dir - thr) / (1.0 - thr), 0.0, 1.0)
                   * decel_mult * rollover_mult * g_liq.penalty;

   // PANIC at low AI: trades pass the gate but at half risk
   if(dir != 0 && g_regime.regime == REGIME_PANIC && g_ai < 0.5)
      conviction *= 0.5;

   // ENGRAM feedback (AI-scaled inside MemAdjust)
   if(dir != 0)
   {
      ContextSnapshot ctx;
      LiveContext(ctx);
      bool mem_veto = false;
      string mem_note = "";
      double mem_mult = MemAdjust(dir, ctx, mem_veto, mem_note);
      if(mem_veto)
      {
         g_belief.vetoed = true;
         g_belief.veto_reason = mem_note;
         dir = 0;
         conviction = 0.0;
      }
      else
      {
         conviction = Clamp(conviction * mem_mult, 0.0, 1.0);
         if(mem_note != "" && CQ3_LOGGING && mem_mult != 1.0)
            Log("ENGRAM ADJ | " + mem_note);
      }
   }

   g_belief.threshold     = thr;
   g_belief.candidate_dir = dir;
   g_belief.conviction    = conviction;
}

//+------------------------------------------------------------------+
//| TARGET / CYCLE / PACING ENGINE                                   |
//+------------------------------------------------------------------+
string CycleKey(string field)
{
   return StringFormat("CQ3_%s_%d_CYC_%s", _Symbol, CQ3_MAGIC, field);
}

double TargetCurrency()
{
   if(InpTargetValue <= 0.0) return 0.0;
   if(InpTargetMode == TGT_PERCENT)
      return g_cycle.start_balance * InpTargetValue / 100.0;
   return InpTargetValue;
}

void StartNewCycle(string reason)
{
   g_cycle.anchor        = TimeCurrent();
   g_cycle.start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_cycle.target_hit    = false;
   g_cycle.target_locked = false;
   g_cycle.missed_logged = false;
   g_cycle.urgency       = 0.0;
   GlobalVariableSet(CycleKey("T"), (double)(long)g_cycle.anchor);
   GlobalVariableSet(CycleKey("B"), g_cycle.start_balance);
   Log(StringFormat("CYCLE START | %s | balance=%.2f target=%.2f%s timeLimit=%.1fh",
       reason, g_cycle.start_balance, TargetCurrency(),
       InpTargetMode == TGT_PERCENT ? StringFormat(" (%.2f%%)", InpTargetValue) : "",
       InpTimeLimitHours));
}

void LoadOrStartCycle()
{
   bool time_mode = (InpTimeLimitHours > 0.0);
   if(time_mode && GlobalVariableCheck(CycleKey("T")) && GlobalVariableCheck(CycleKey("B")))
   {
      // Resume a persisted time-limit cycle across restarts —
      // the clock does not reset because the terminal did.
      g_cycle.anchor        = (datetime)(long)GlobalVariableGet(CycleKey("T"));
      g_cycle.start_balance = GlobalVariableGet(CycleKey("B"));
      g_cycle.target_hit    = false;
      g_cycle.target_locked = false;
      g_cycle.missed_logged = false;
      g_cycle.urgency       = 0.0;
      long limit_sec = (long)(InpTimeLimitHours * 3600.0);
      if(TimeCurrent() - g_cycle.anchor >= limit_sec || g_cycle.start_balance <= 0.0)
         StartNewCycle("stale persisted cycle");
      else
         Log(StringFormat("CYCLE RESUME | anchor=%s balance=%.2f",
             TimeToString(g_cycle.anchor), g_cycle.start_balance));
   }
   else
      StartNewCycle(time_mode ? "init (timed)" : "init (daily)");
}

void UpdateTargetState()
{
   double target = TargetCurrency();
   bool time_mode = (InpTimeLimitHours > 0.0);

   // Daily-anchored cycle rolls with the server day when no time limit
   if(!time_mode && g_cycle.anchor < ServerDayStart())
      StartNewCycle("new server day");

   if(target <= 0.0) { g_cycle.urgency = 0.0; return; }

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double progress = equity - g_cycle.start_balance;

   // Target hit
   if(!g_cycle.target_hit && progress >= target)
   {
      g_cycle.target_hit = true;
      Log(StringFormat("TARGET HIT | %+.2f / %.2f", progress, target));
      if(InpStopAfterTarget)
      {
         g_cycle.target_locked = true;
         DisarmSetup("target reached — locked");
         Log("TARGET LOCK | no new entries; zones manage open positions");
      }
      else if(time_mode)
      {
         StartNewCycle("target hit — continue mode, new timed cycle");
      }
      // continue mode without time limit: keep stacking within the day
   }

   // Time expiry
   if(time_mode)
   {
      long limit_sec = (long)(InpTimeLimitHours * 3600.0);
      long elapsed   = (long)(TimeCurrent() - g_cycle.anchor);
      if(elapsed >= limit_sec)
      {
         if(!g_cycle.target_hit && !g_cycle.missed_logged)
         {
            g_cycle.missed_logged = true;
            Log(StringFormat("TARGET MISSED | %+.2f / %.2f in %.1fh — new cycle",
                progress, target, InpTimeLimitHours));
         }
         StartNewCycle("time window elapsed");
         return;
      }

      // Pacing: urgency = how far behind the straight-line path to target
      if(!g_cycle.target_hit && !g_cycle.target_locked)
      {
         double elapsed_frac = Clamp((double)elapsed / (double)limit_sec, 0.0, 1.0);
         double profit_frac  = Clamp(progress / target, -1.0, 1.0);
         g_cycle.urgency = Clamp((elapsed_frac - profit_frac) * 1.5, 0.0, 1.0);
      }
      else
         g_cycle.urgency = 0.0;
   }
   else
      g_cycle.urgency = 0.0;
}

//+------------------------------------------------------------------+
//| TRIGGER ENGINE                                                   |
//+------------------------------------------------------------------+
void ChartSwing(double &swing_hi, double &swing_lo)
{
   swing_hi = -DBL_MAX; swing_lo = DBL_MAX;
   for(int b = 1; b <= 8; b++)
   {
      swing_hi = MathMax(swing_hi, iHigh(_Symbol, g_tf.chart, b));
      swing_lo = MathMin(swing_lo, iLow(_Symbol, g_tf.chart, b));
   }
}

// Trigger-style permission for the current bar, honoring strategy +
// regime + urgency (urgency>0.5 unlocks both styles to find a path)
void TriggerPermissions(bool &can_break, bool &can_fill)
{
   can_break = g_prof.allow_break;
   can_fill  = g_prof.allow_fill;

   if(g_prof.regime_decides)
   {
      if(g_regime.regime == REGIME_TREND) { can_break = true;  can_fill = true; }
      else                                { can_break = false; can_fill = true; }
   }
   if(g_cycle.urgency > 0.5)
   {
      can_break = true;
      can_fill  = true;
   }
}

void ArmSetup()
{
   if(g_setup.active) return;
   if(g_belief.candidate_dir == 0) return;
   if(g_regime.regime == REGIME_PANIC && g_ai >= 0.5) return;

   int dir = g_belief.candidate_dir;

   double ch_hi, ch_lo;
   ChartSwing(ch_hi, ch_lo);
   if(ch_hi <= -DBL_MAX || ch_lo >= DBL_MAX) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool can_break = false, can_fill = false;
   TriggerPermissions(can_break, can_fill);

   ENUM_CQ3_TRIGGER ttype = TRIGGER_NONE;
   double trigger = 0.0, invalidation = 0.0, sl = 0.0;

   bool fill_possible_long  = (g_struct.fvg_bull && bid > g_struct.fvg_mid);
   bool fill_possible_short = (g_struct.fvg_bear && bid < g_struct.fvg_mid);

   if(dir > 0)
   {
      if(can_break && g_struct.bos_bull)
      {
         ttype        = TRIGGER_BREAK;
         trigger      = ch_hi + CQ3_BREAK_OFFSET * g_atr;
         invalidation = ch_lo;
         sl           = ch_lo - 0.20 * g_atr;
      }
      else if(can_fill && fill_possible_long)
      {
         ttype        = TRIGGER_FILL;
         trigger      = g_struct.fvg_mid;
         invalidation = g_struct.fvg_low - 0.30 * g_atr;
         sl           = g_struct.fvg_low - 0.40 * g_atr;
      }
      else if(can_break && g_cycle.urgency > 0.5 && g_struct.structural_dir > 0)
      {
         // Pacing path: structural alignment without fresh BOS still
         // earns a conditional breakout level — never a market order.
         ttype        = TRIGGER_BREAK;
         trigger      = ch_hi + CQ3_BREAK_OFFSET * g_atr;
         invalidation = ch_lo;
         sl           = ch_lo - 0.20 * g_atr;
      }
   }
   else
   {
      if(can_break && g_struct.bos_bear)
      {
         ttype        = TRIGGER_BREAK;
         trigger      = ch_lo - CQ3_BREAK_OFFSET * g_atr;
         invalidation = ch_hi;
         sl           = ch_hi + 0.20 * g_atr;
      }
      else if(can_fill && fill_possible_short)
      {
         ttype        = TRIGGER_FILL;
         trigger      = g_struct.fvg_mid;
         invalidation = g_struct.fvg_high + 0.30 * g_atr;
         sl           = g_struct.fvg_high + 0.40 * g_atr;
      }
      else if(can_break && g_cycle.urgency > 0.5 && g_struct.structural_dir < 0)
      {
         ttype        = TRIGGER_BREAK;
         trigger      = ch_lo - CQ3_BREAK_OFFSET * g_atr;
         invalidation = ch_hi;
         sl           = ch_hi + 0.20 * g_atr;
      }
   }

   if(ttype == TRIGGER_NONE) return;

   double sl_dist = MathAbs(trigger - sl);
   if(sl_dist < CQ3_SL_MIN_ATR * g_atr)
   {
      sl_dist = CQ3_SL_MIN_ATR * g_atr;
      sl = (dir > 0) ? trigger - sl_dist : trigger + sl_dist;
   }
   if(sl_dist > CQ3_SL_MAX_ATR * g_atr)
   {
      sl_dist = CQ3_SL_MAX_ATR * g_atr;
      sl = (dir > 0) ? trigger - sl_dist : trigger + sl_dist;
   }

   double tp = (dir > 0) ? trigger + g_prof.tp_r * sl_dist
                         : trigger - g_prof.tp_r * sl_dist;
   if(g_struct.fvg_target > 0.0)
   {
      if(dir > 0 && g_struct.fvg_bull && g_struct.fvg_target > tp)
         tp = g_struct.fvg_target;
      if(dir < 0 && g_struct.fvg_bear && g_struct.fvg_target < tp)
         tp = g_struct.fvg_target;
   }

   g_setup.active        = true;
   g_setup.direction     = dir;
   g_setup.trigger_type  = ttype;
   g_setup.trigger_price = NormPrice(trigger);
   g_setup.invalidation  = NormPrice(invalidation);
   g_setup.sl_price      = NormPrice(sl);
   g_setup.tp_price      = NormPrice(tp);
   g_setup.expiry        = TimeCurrent() + CQ3_SETUP_EXPIRY_BARS * PeriodSeconds(g_tf.chart);
   g_setup.conviction    = g_belief.conviction;
   g_setup.regime_at_arm = g_regime.regime;
   g_setup.is_daybreak   = false;

   Log(StringFormat("ARMED | %s %s trigger=%.5f inval=%.5f SL=%.5f TP=%.5f conv=%.2f regime=%s urg=%.2f",
       (dir > 0 ? "LONG" : "SHORT"),
       (ttype == TRIGGER_BREAK ? "BREAK" : "FILL"),
       g_setup.trigger_price, g_setup.invalidation, g_setup.sl_price,
       g_setup.tp_price, g_setup.conviction,
       RegimeToString((int)g_setup.regime_at_arm), g_cycle.urgency));
}

//+------------------------------------------------------------------+
//| DAYBREAK STRATEGY — previous-day high/low breakout               |
//| The simplest durable system in trading: yesterday's extremes are |
//| real liquidity. One trade per side per day. Pure conditional.    |
//+------------------------------------------------------------------+
void ArmDaybreak()
{
   if(g_setup.active) return;
   if(Bars(_Symbol, PERIOD_D1) < 3) return;

   datetime today = iTime(_Symbol, PERIOD_D1, 0);
   if(g_db_day != today)
   {
      g_db_day        = today;
      g_db_long_done  = false;
      g_db_short_done = false;
   }

   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow(_Symbol, PERIOD_D1, 1);
   double pdm = 0.5 * (pdh + pdl);
   if(pdh <= pdl) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool long_allowed  = (InpTradeMode != TM_SELL) && !g_db_long_done;
   bool short_allowed = (InpTradeMode != TM_BUY) && !g_db_short_done;

   // AI-scaled belief check: at high AI, belief must not strongly
   // oppose the breakout direction; at AI=0 the level alone decides.
   double oppose_gate = 0.40 * g_ai;   // p of breakout direction must exceed this
   bool long_ok  = long_allowed  && (g_belief.p_long >= oppose_gate) && (bid < pdh);
   bool short_ok = short_allowed && ((1.0 - g_belief.p_long) >= oppose_gate) && (bid > pdl);

   // Arm the nearer side first
   int dir = 0;
   if(long_ok && short_ok)
      dir = (pdh - bid <= bid - pdl) ? 1 : -1;
   else if(long_ok)  dir = 1;
   else if(short_ok) dir = -1;
   if(dir == 0) return;

   double trigger, sl, invalidation;
   if(dir > 0)
   {
      trigger      = pdh + CQ3_BREAK_OFFSET * g_atr;
      sl           = MathMax(pdm, trigger - CQ3_SL_MAX_ATR * g_atr);
      invalidation = pdl;
   }
   else
   {
      trigger      = pdl - CQ3_BREAK_OFFSET * g_atr;
      sl           = MathMin(pdm, trigger + CQ3_SL_MAX_ATR * g_atr);
      invalidation = pdh;
   }

   double sl_dist = MathAbs(trigger - sl);
   if(sl_dist < CQ3_SL_MIN_ATR * g_atr)
   {
      sl_dist = CQ3_SL_MIN_ATR * g_atr;
      sl = (dir > 0) ? trigger - sl_dist : trigger + sl_dist;
   }

   double tp = (dir > 0) ? trigger + g_prof.tp_r * sl_dist
                         : trigger - g_prof.tp_r * sl_dist;

   double conv = (g_belief.candidate_dir == dir) ? MathMax(g_belief.conviction, 0.30)
                                                 : 0.30;

   g_setup.active        = true;
   g_setup.direction     = dir;
   g_setup.trigger_type  = TRIGGER_BREAK;
   g_setup.trigger_price = NormPrice(trigger);
   g_setup.invalidation  = NormPrice(invalidation);
   g_setup.sl_price      = NormPrice(sl);
   g_setup.tp_price      = NormPrice(tp);
   g_setup.expiry        = TimeCurrent() + 24 * 3600;   // setup lives the day
   g_setup.conviction    = conv;
   g_setup.regime_at_arm = g_regime.regime;
   g_setup.is_daybreak   = true;

   Log(StringFormat("ARMED DAYBREAK | %s trigger=%.5f (PD%s) SL=%.5f TP=%.5f",
       dir > 0 ? "LONG" : "SHORT", g_setup.trigger_price,
       dir > 0 ? "H" : "L", g_setup.sl_price, g_setup.tp_price));
}

void DisarmSetup(string reason)
{
   if(!g_setup.active) return;
   Log("DISARMED | " + reason);
   ZeroMemory(g_setup);
}

//+------------------------------------------------------------------+
//| RISK — phase multiplier + urgency boost, hard-capped             |
//+------------------------------------------------------------------+
int MaxPositionsNow()
{
   return (InpTradeMode == TM_SEQUENTIAL) ? 1 : CQ3_MAX_POSITIONS;
}

double PhaseMultiplier()
{
   if(InpTradeMode != TM_PHASE) return 1.0;
   if(g_consec_wins >= 2) return 1.3;   // PRESS
   if(g_consec_wins == 1) return 1.0;   // BUILD
   return 0.6;                          // PROBE
}

string PhaseToString()
{
   if(InpTradeMode != TM_PHASE) return "";
   if(g_consec_wins >= 2) return "PRESS";
   if(g_consec_wins == 1) return "BUILD";
   return "PROBE";
}

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == CQ3_MAGIC)
         count++;
   }
   return count;
}

double ComputeLots(double sl_dist_price, double conviction)
{
   if(!g_sym.valid) return 0.0;

   if(InpLotSize > 0.0)
      return NormalizeLot(InpLotSize);

   if(sl_dist_price <= 0.0) return 0.0;

   double balance = MathMin(AccountInfoDouble(ACCOUNT_BALANCE),
                            AccountInfoDouble(ACCOUNT_EQUITY));
   if(balance <= 0.0) return 0.0;

   // Conviction band 60%-100% of input risk, then phase + urgency,
   // then the absolute hard cap. The cap is the last word, always.
   double risk_pct = InpRiskPercent * (0.60 + 0.40 * Clamp(conviction, 0.0, 1.0));
   risk_pct *= PhaseMultiplier();
   risk_pct *= (1.0 + CQ3_URGENCY_RISK_BOOST * g_cycle.urgency);
   risk_pct  = MathMin(risk_pct, CQ3_RISK_HARDCAP_PCT);

   double risk_money = balance * risk_pct / 100.0;

   double ticks        = sl_dist_price / g_sym.tick_size;
   double loss_per_lot = ticks * g_sym.tick_value;
   if(loss_per_lot <= 0.0) return 0.0;

   return NormalizeLot(risk_money / loss_per_lot);
}

bool MarginOK(ENUM_ORDER_TYPE type, double lots, double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin)) return false;
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (margin > 0.0 && margin < free_margin * 0.80);
}

//+------------------------------------------------------------------+
//| DAILY LOSS GUARDRAIL — outranks everything, including target     |
//+------------------------------------------------------------------+
datetime ServerDayStart()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

void FlattenAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == CQ3_MAGIC)
         g_trade.PositionClose(ticket);
   }
}

void UpdateDailyState()
{
   datetime today = ServerDayStart();
   if(g_daily.day_stamp != today)
   {
      g_daily.day_stamp     = today;
      g_daily.start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_daily.loss_locked   = false;
      g_daily.lock_reason   = "";
      g_consec_wins         = 0;       // phase resets daily
      Log(StringFormat("NEW DAY | start_balance=%.2f", g_daily.start_balance));
   }

   if(g_daily.loss_locked || g_daily.start_balance <= 0.0) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double pl_pct = (equity - g_daily.start_balance) / g_daily.start_balance * 100.0;

   if(pl_pct <= -CQ3_DAILY_MAXLOSS_PCT)
   {
      g_daily.loss_locked = true;
      g_daily.lock_reason = StringFormat("Daily max loss hit: %+.2f%%", pl_pct);
      DisarmSetup("daily loss lock");
      FlattenAll();
      Log("LOCKED + FLATTENED | " + g_daily.lock_reason);
   }
}

bool TradingBlocked()
{
   return (g_daily.loss_locked || g_cycle.target_locked);
}

//+------------------------------------------------------------------+
//| EXECUTION                                                        |
//+------------------------------------------------------------------+
bool FireSetup()
{
   if(!g_setup.active) return false;

   UpdateLiquidity();
   if(!g_liq.tradeable)
   {
      static datetime last_spread_log = 0;
      if(TimeCurrent() - last_spread_log >= 60)
      {
         Log(StringFormat("FIRE BLOCKED | spread %.1f%% of ATR exceeds hard gate",
             g_liq.spread_atr * 100.0));
         last_spread_log = TimeCurrent();
      }
      return false;
   }
   if(TradingBlocked()) { DisarmSetup("trading locked at fire"); return false; }
   if(CountOurPositions() >= MaxPositionsNow())
   {
      DisarmSetup("max positions at fire");
      return false;
   }

   ENUM_ORDER_TYPE type = (g_setup.direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl_dist = MathAbs(price - g_setup.sl_price);
   if(sl_dist < CQ3_SL_MIN_ATR * g_atr * 0.5)
   {
      DisarmSetup("SL distance collapsed at fire (gap through level)");
      return false;
   }

   double min_stop = g_sym.stops_level_px +
                     MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                             SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double sl = g_setup.sl_price;
   double tp = g_setup.tp_price;
   if(MathAbs(price - sl) < min_stop)
      sl = (type == ORDER_TYPE_BUY) ? price - min_stop : price + min_stop;
   if(MathAbs(tp - price) < min_stop)
      tp = (type == ORDER_TYPE_BUY) ? price + min_stop : price - min_stop;

   double lots = ComputeLots(MathAbs(price - sl), g_setup.conviction);
   if(lots < g_sym.min_lot)
   {
      DisarmSetup("computed lots below minimum");
      return false;
   }
   if(!MarginOK(type, lots, price))
   {
      DisarmSetup("insufficient margin");
      return false;
   }

   int deviation_pts = (int)Clamp(0.05 * g_atr / g_sym.point, 10.0, 300.0);
   g_trade.SetDeviationInPoints(deviation_pts);

   g_pending_regime     = g_setup.regime_at_arm;
   g_pending_regime_set = true;
   g_pending_conviction = g_setup.conviction;
   g_pending_trigger    = (int)g_setup.trigger_type;

   string comment = StringFormat("CQ3|R%d|%s", (int)g_setup.regime_at_arm,
                    g_setup.is_daybreak ? "DBK" :
                    g_setup.trigger_type == TRIGGER_BREAK ? "BRK" : "FIL");

   bool ok = (type == ORDER_TYPE_BUY)
             ? g_trade.Buy(lots, _Symbol, 0.0, NormPrice(sl), NormPrice(tp), comment)
             : g_trade.Sell(lots, _Symbol, 0.0, NormPrice(sl), NormPrice(tp), comment);

   if(ok)
   {
      g_barren_bars = 0;   // anti-stall valve resets on fire
      if(g_setup.is_daybreak)
      {
         if(g_setup.direction > 0) g_db_long_done = true;
         else                      g_db_short_done = true;
      }
      Log(StringFormat("FIRED | %s %.2f lots @ ~%.5f SL=%.5f TP=%.5f conv=%.2f [%s]%s",
          (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lots, price,
          NormPrice(sl), NormPrice(tp), g_setup.conviction,
          RegimeToString((int)g_setup.regime_at_arm),
          g_setup.is_daybreak ? " DAYBREAK" : ""));
   }
   else
   {
      Log(StringFormat("FIRE FAILED | retcode=%d (%s)",
          (int)g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
      g_pending_regime_set = false;
      g_pending_conviction = -1.0;
      g_pending_trigger    = 0;
   }

   DisarmSetup(ok ? "fired" : "fire failed");
   return ok;
}

//+------------------------------------------------------------------+
//| TICK-LEVEL TRIGGER MONITORING                                    |
//+------------------------------------------------------------------+
void CheckTriggersTick()
{
   if(!g_setup.active || g_atr <= 0.0) return;

   if(TimeCurrent() >= g_setup.expiry)
   {
      DisarmSetup("expired");
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(g_setup.direction > 0 && bid <= g_setup.invalidation)
   { DisarmSetup("invalidation hit (long)"); return; }
   if(g_setup.direction < 0 && ask >= g_setup.invalidation)
   { DisarmSetup("invalidation hit (short)"); return; }

   bool triggered = false;
   if(g_setup.trigger_type == TRIGGER_BREAK)
   {
      if(g_setup.direction > 0 && ask >= g_setup.trigger_price) triggered = true;
      if(g_setup.direction < 0 && bid <= g_setup.trigger_price) triggered = true;
   }
   else if(g_setup.trigger_type == TRIGGER_FILL)
   {
      if(g_setup.direction > 0 && bid <= g_setup.trigger_price) triggered = true;
      if(g_setup.direction < 0 && ask >= g_setup.trigger_price) triggered = true;
   }

   if(triggered) FireSetup();
}

//+------------------------------------------------------------------+
//| POSITION TRACKING                                                |
//+------------------------------------------------------------------+
int FindTrack(ulong position_id)
{
   for(int i = 0; i < CQ3_TRACK_MAX; i++)
      if(g_tracks[i].used && g_tracks[i].position_id == position_id)
         return i;
   return -1;
}

int FreeTrackSlot()
{
   for(int i = 0; i < CQ3_TRACK_MAX; i++)
      if(!g_tracks[i].used) return i;
   return -1;
}

void RegisterTrack(ulong position_id, double entry, double sl, int dir,
                   ENUM_CQ3_REGIME regime, double conviction, int trig,
                   datetime entry_time)
{
   if(FindTrack(position_id) >= 0) return;
   int slot = FreeTrackSlot();
   if(slot < 0) { Log("WARN | tracking table full"); return; }

   double risk = MathAbs(entry - sl);
   if(risk < g_sym.point * 2.0) risk = MathMax(g_atr * 1.2, g_sym.point * 10.0);

   g_tracks[slot].used         = true;
   g_tracks[slot].position_id  = position_id;
   g_tracks[slot].entry_price  = entry;
   g_tracks[slot].risk_dist    = risk;
   g_tracks[slot].direction    = dir;
   g_tracks[slot].scale1_done  = false;
   g_tracks[slot].scale2_done  = false;
   g_tracks[slot].regime       = regime;
   g_tracks[slot].conviction   = conviction;
   g_tracks[slot].trigger_type = trig;
   g_tracks[slot].entry_time   = entry_time;
   g_tracks[slot].atr_at_entry = (g_atr > 0.0) ? g_atr : risk;
   g_tracks[slot].mfe_atr      = 0.0;
   g_tracks[slot].mae_atr      = 0.0;

   Log(StringFormat("TRACK | posID=%I64u entry=%.5f 1R=%.5f dir=%d regime=%s conv=%.2f",
       position_id, entry, risk, dir, RegimeToString((int)regime), conviction));
}

void RecoverTracksOnInit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != CQ3_MAGIC) continue;

      ulong  pos_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      int    dir    = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      datetime t_in = (datetime)PositionGetInteger(POSITION_TIME);

      ENUM_CQ3_REGIME regime = g_regime.valid ? g_regime.regime : REGIME_CHOP;
      string c = PositionGetString(POSITION_COMMENT);
      int rpos = StringFind(c, "|R");
      if(rpos >= 0 && StringLen(c) > rpos + 2)
      {
         int rv = (int)StringToInteger(StringSubstr(c, rpos + 2, 1));
         if(rv >= 0 && rv < CQ3_REGIMES) regime = (ENUM_CQ3_REGIME)rv;
      }
      int trig = (StringFind(c, "BRK") >= 0 || StringFind(c, "DBK") >= 0) ? TRIGGER_BREAK :
                 (StringFind(c, "FIL") >= 0) ? TRIGGER_FILL : 0;

      RegisterTrack(pos_id, entry, sl, dir, regime, -1.0, trig, t_in);
   }
}

//+------------------------------------------------------------------+
//| TICK-LEVEL ZONE MANAGEMENT + MFE/MAE HARVESTING                  |
//| Zone schedule comes from the strategy profile.                   |
//+------------------------------------------------------------------+
void ManagePositionsTick()
{
   if(g_atr <= 0.0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int t = 0; t < CQ3_TRACK_MAX; t++)
   {
      if(!g_tracks[t].used) continue;

      bool found = false;
      ulong ticket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == g_tracks[t].position_id &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            found = true; ticket = tk; break;
         }
      }
      if(!found)
      {
         // Harvest FIRST (dedupe-safe), then free — conviction/MFE/MAE
         // survive even if the tick beats OnTradeTransaction to it.
         HarvestClosedPosition(g_tracks[t].position_id);
         g_tracks[t].used = false;
         continue;
      }

      double entry   = g_tracks[t].entry_price;
      double risk    = g_tracks[t].risk_dist;
      bool   is_buy  = (g_tracks[t].direction > 0);
      double cur     = is_buy ? bid : ask;
      double cur_sl  = PositionGetDouble(POSITION_SL);
      double cur_tp  = PositionGetDouble(POSITION_TP);
      double cur_vol = PositionGetDouble(POSITION_VOLUME);
      double r_mult  = is_buy ? (cur - entry) / risk : (entry - cur) / risk;

      double atr_e = MathMax(g_tracks[t].atr_at_entry, g_sym.point);
      double exc   = (is_buy ? (cur - entry) : (entry - cur)) / atr_e;
      if(exc > g_tracks[t].mfe_atr)  g_tracks[t].mfe_atr = exc;
      if(-exc > g_tracks[t].mae_atr) g_tracks[t].mae_atr = -exc;

      double min_stop = g_sym.stops_level_px + MathAbs(ask - bid);

      if(!g_tracks[t].scale1_done && r_mult >= g_prof.zone1_r)
      {
         double close_vol = NormalizeLot(cur_vol * 0.30);
         if(close_vol >= g_sym.min_lot && (cur_vol - close_vol) >= g_sym.min_lot)
            g_trade.PositionClosePartial(ticket, close_vol);

         double be = is_buy ? entry + CQ3_BE_BUFFER_ATR * g_atr
                            : entry - CQ3_BE_BUFFER_ATR * g_atr;
         if(MathAbs(cur - be) > min_stop)
            g_trade.PositionModify(ticket, NormPrice(be), cur_tp);

         g_tracks[t].scale1_done = true;
         Log(StringFormat("ZONE1 | posID=%I64u +%.1fR: 30%% out, SL->BE",
             g_tracks[t].position_id, g_prof.zone1_r));
      }
      else if(g_tracks[t].scale1_done && !g_tracks[t].scale2_done && r_mult >= g_prof.zone2_r)
      {
         cur_vol = PositionGetDouble(POSITION_VOLUME);
         double close_vol = NormalizeLot(cur_vol * 0.30);
         if(close_vol >= g_sym.min_lot && (cur_vol - close_vol) >= g_sym.min_lot)
            g_trade.PositionClosePartial(ticket, close_vol);

         double lock = is_buy ? entry + risk * g_prof.zone1_r
                              : entry - risk * g_prof.zone1_r;
         if(MathAbs(cur - lock) > min_stop)
            g_trade.PositionModify(ticket, NormPrice(lock), cur_tp);

         g_tracks[t].scale2_done = true;
         Log(StringFormat("ZONE2 | posID=%I64u +%.1fR: 30%% out, SL->+%.1fR",
             g_tracks[t].position_id, g_prof.zone2_r, g_prof.zone1_r));
      }
      else if(g_tracks[t].scale2_done && r_mult > g_prof.zone2_r)
      {
         double trail_atr = (r_mult >= 3.5) ? g_prof.trail_tight_atr : g_prof.trail_atr;
         double new_sl = is_buy ? cur - trail_atr * g_atr
                                : cur + trail_atr * g_atr;

         double floor_sl = is_buy ? entry + risk * g_prof.zone1_r
                                  : entry - risk * g_prof.zone1_r;
         if(is_buy)  new_sl = MathMax(new_sl, floor_sl);
         else        new_sl = MathMin(new_sl, floor_sl);

         bool improves = is_buy ? (new_sl > cur_sl + g_sym.point)
                                : (new_sl < cur_sl - g_sym.point);
         if(improves && MathAbs(cur - new_sl) > min_stop)
            g_trade.PositionModify(ticket, NormPrice(new_sl), cur_tp);
      }
   }
}

//+------------------------------------------------------------------+
//| DASHBOARD — target-tracking notification panel (Comment-based)   |
//+------------------------------------------------------------------+
string ProgressBar(double frac)
{
   frac = Clamp(frac, 0.0, 1.0);
   int filled = (int)MathRound(frac * 20.0);
   string bar = "[";
   for(int i = 0; i < 20; i++)
      bar += (i < filled) ? "#" : "-";
   bar += "]";
   return bar;
}

void RenderDashboard()
{
   if(!InpShowDashboard)
   {
      Comment("");
      return;
   }

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double target   = TargetCurrency();
   double progress = equity - g_cycle.start_balance;

   string s = "";
   s += "============ CONQUEST v3.20 ============\n";
   s += StringFormat("MODE: %s%s   STRATEGY: %s   AI: %d%%\n",
        ModeToString((int)InpTradeMode),
        InpTradeMode == TM_PHASE ? " [" + PhaseToString() + "]" : "",
        StrategyToString((int)InpStrategy), InpAILevel);
   s += StringFormat("REGIME: %s   atrR=%.2f   spread=%.0f%%ATR\n",
        RegimeToString((int)g_regime.regime), g_regime.atr_ratio,
        g_liq.spread_atr * 100.0);
   s += "----------------------------------------\n";

   if(target > 0.0)
   {
      double frac = (target > 0.0) ? progress / target : 0.0;
      s += StringFormat("TARGET: %.2f %s\n", target,
           InpTargetMode == TGT_PERCENT ?
           StringFormat("(%.2f%% of %.2f)", InpTargetValue, g_cycle.start_balance) : "");
      s += StringFormat("P/L:    %+.2f   (%.0f%%)\n", progress, frac * 100.0);
      s += StringFormat("DIST:   %.2f to go\n", MathMax(0.0, target - progress));
      s += ProgressBar(frac) + "\n";

      if(InpTimeLimitHours > 0.0)
      {
         long limit_sec = (long)(InpTimeLimitHours * 3600.0);
         long elapsed   = (long)(TimeCurrent() - g_cycle.anchor);
         long remain    = MathMax(0, limit_sec - elapsed);
         s += StringFormat("TIME:   %.1fh left of %.1fh\n",
              remain / 3600.0, InpTimeLimitHours);
         string pace = "ON PACE";
         if(g_cycle.urgency > 0.6)      pace = "BEHIND — pressing";
         else if(g_cycle.urgency > 0.2) pace = "BEHIND";
         else if(progress / MathMax(target, 0.01) >
                 (double)elapsed / MathMax((double)limit_sec, 1.0)) pace = "AHEAD";
         s += StringFormat("PACE:   %s   urgency=%.2f\n", pace, g_cycle.urgency);
      }

      if(g_cycle.target_hit)
         s += InpStopAfterTarget ? ">>> TARGET ACHIEVED — LOCKED <<<\n"
                                 : ">>> TARGET ACHIEVED — CONTINUING <<<\n";
   }
   else
      s += StringFormat("P/L today: %+.2f (no target set)\n",
           equity - g_daily.start_balance);

   s += "----------------------------------------\n";
   if(g_daily.loss_locked)
      s += "!! DAILY LOSS LOCK: " + g_daily.lock_reason + " !!\n";
   if(g_setup.active)
      s += StringFormat("ARMED: %s %s @ %.5f\n",
           g_setup.direction > 0 ? "LONG" : "SHORT",
           g_setup.is_daybreak ? "DAYBREAK" :
           g_setup.trigger_type == TRIGGER_BREAK ? "BREAK" : "FILL",
           g_setup.trigger_price);
   else
      s += StringFormat("No armed setup (barren bars: %d)\n", g_barren_bars);
   s += StringFormat("Open: %d/%d   Engram: %d records\n",
        CountOurPositions(), MaxPositionsNow(), g_known_count);
   s += "========================================";

   Comment(s);
}

//+------------------------------------------------------------------+
//| EVENT HANDLERS                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ZeroMemory(g_struct);
   ZeroMemory(g_mom);
   ZeroMemory(g_regime);
   ZeroMemory(g_liq);
   ResetBelief();
   ZeroMemory(g_setup);
   g_daily.day_stamp     = 0;
   g_daily.start_balance = 0.0;
   g_daily.loss_locked   = false;
   g_daily.lock_reason   = "";
   for(int i = 0; i < CQ3_TRACK_MAX; i++) g_tracks[i].used = false;
   for(int k = 0; k < CQ3_MEM_KEYS; k++) { g_mem[k].wr_ema = 0.50; g_mem[k].n = 0; }
   g_known_count = 0;
   ArrayResize(g_known_ids, 0);
   g_barren_bars = 0;
   g_seq_dir = 0; g_seq_win = false; g_seq_has_data = false;
   g_consec_wins = 0;
   g_db_day = 0; g_db_long_done = false; g_db_short_done = false;

   if(InpLotSize <= 0.0 && InpRiskPercent <= 0.0)
   {
      Print("CQ3 ERROR: either lot size or risk percent must be > 0");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_ai = Clamp(InpAILevel / 100.0, 0.0, 1.0);

   if(!BuildSymbolProfile()) return INIT_FAILED;
   BuildMTFMap();
   ApplyStrategyProfile();
   LoadCalibration();

   g_h_atr14_chart = iATR(_Symbol, g_tf.chart, 14);
   g_h_atr55_chart = iATR(_Symbol, g_tf.chart, 55);
   g_h_atr14_htf1  = iATR(_Symbol, g_tf.htf1, 14);
   g_h_macd_chart  = iMACD(_Symbol, g_tf.chart, 12, 26, 9, PRICE_CLOSE);
   g_h_macd_htf1   = iMACD(_Symbol, g_tf.htf1, 12, 26, 9, PRICE_CLOSE);
   g_h_macd_htf2   = iMACD(_Symbol, g_tf.htf2, 12, 26, 9, PRICE_CLOSE);

   if(g_h_atr14_chart == INVALID_HANDLE || g_h_atr55_chart == INVALID_HANDLE ||
      g_h_atr14_htf1 == INVALID_HANDLE || g_h_macd_chart == INVALID_HANDLE ||
      g_h_macd_htf1 == INVALID_HANDLE || g_h_macd_htf2 == INVALID_HANDLE)
   {
      Print("CQ3 ERROR: indicator handle creation failed");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(CQ3_MAGIC);
   g_trade.SetTypeFilling(g_sym.fill_mode);
   g_trade.SetAsyncMode(false);

   double a14[];
   ArraySetAsSeries(a14, true);
   if(CopyBuffer(g_h_atr14_chart, 0, 0, 2, a14) >= 2) g_atr = a14[1];
   double a14h[];
   ArraySetAsSeries(a14h, true);
   if(CopyBuffer(g_h_atr14_htf1, 0, 0, 2, a14h) >= 2) g_atr_htf1 = a14h[1];

   // Engram journal loads now; account-history backfill is deferred to
   // the first completed bar (indicator buffers are not calculated yet).
   LoadEngramFile();

   LoadOrStartCycle();
   RecoverTracksOnInit();

   string fill_str = (g_sym.fill_mode == ORDER_FILLING_FOK) ? "FOK" :
                     (g_sym.fill_mode == ORDER_FILLING_IOC) ? "IOC" : "RETURN";
   string size_str = (InpLotSize > 0.0)
                     ? StringFormat("fixed %.2f lots", InpLotSize)
                     : StringFormat("risk %.2f%% (band %.2f-%.2f%%, hard cap %.1f%%)",
                                    InpRiskPercent, InpRiskPercent * 0.60,
                                    InpRiskPercent, CQ3_RISK_HARDCAP_PCT);
   Log(StringFormat("INIT | %s chart=%s htf1=%s htf2=%s fill=%s",
       _Symbol, EnumToString(g_tf.chart), EnumToString(g_tf.htf1),
       EnumToString(g_tf.htf2), fill_str));
   Log(StringFormat("INIT | mode=%s strategy=%s AI=%d%% | %s | target=%.2f(%s) stopAfter=%s timeLimit=%.1fh",
       ModeToString((int)InpTradeMode), StrategyToString((int)InpStrategy),
       InpAILevel, size_str, InpTargetValue,
       InpTargetMode == TGT_PERCENT ? "pct" : "amt",
       InpStopAfterTarget ? "yes" : "no", InpTimeLimitHours));

   g_initialized = true;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   SaveCalibration();
   Comment("");
   if(g_h_atr14_chart != INVALID_HANDLE) IndicatorRelease(g_h_atr14_chart);
   if(g_h_atr55_chart != INVALID_HANDLE) IndicatorRelease(g_h_atr55_chart);
   if(g_h_atr14_htf1  != INVALID_HANDLE) IndicatorRelease(g_h_atr14_htf1);
   if(g_h_macd_chart  != INVALID_HANDLE) IndicatorRelease(g_h_macd_chart);
   if(g_h_macd_htf1   != INVALID_HANDLE) IndicatorRelease(g_h_macd_htf1);
   if(g_h_macd_htf2   != INVALID_HANDLE) IndicatorRelease(g_h_macd_htf2);
   Log("DEINIT | calibration saved; Engram journal persists on disk");
}

void OnNewBar()
{
   UpdateDailyState();
   UpdateTargetState();

   if(!UpdateStructure()) return;
   if(!UpdateMomentum())  return;
   if(!UpdateRegime())    return;
   UpdateLiquidity();

   if(!g_backfill_done)
   {
      g_backfill_done = true;
      HarvestAccountHistory();
   }

   UpdateBelief();

   // Anti-stall valve: count barren bars only while flat and unlocked
   if(!g_setup.active && CountOurPositions() == 0 && !TradingBlocked())
      g_barren_bars++;

   if(g_setup.active)
   {
      // Daybreak setups live on levels alone — belief flips don't kill them
      bool direction_lost = !g_setup.is_daybreak &&
         ((g_belief.candidate_dir != g_setup.direction) || g_belief.vetoed);
      if(direction_lost)
         DisarmSetup("belief no longer supports armed direction");
   }

   if(!TradingBlocked() && g_liq.tradeable &&
      CountOurPositions() < MaxPositionsNow())
   {
      if(InpStrategy == ST_DAYBREAK)
         ArmDaybreak();
      else
         ArmSetup();
   }

   if(g_belief.vetoed)
      Log("VETO | " + g_belief.veto_reason);

   Log(StringFormat("BAR | %s atrR=%.2f ext=%.2f | struct=%d bos=%s%s fvg=%s%s | pL=%.3f thr=%.3f dir=%d conv=%.2f | urg=%.2f barren=%d%s",
       RegimeToString((int)g_regime.regime), g_regime.atr_ratio, g_regime.extension,
       g_struct.structural_dir,
       g_struct.bos_bull ? "B" : "", g_struct.bos_bear ? "S" : "",
       g_struct.fvg_bull ? "B" : "", g_struct.fvg_bear ? "S" : "",
       g_belief.p_long, g_belief.threshold, g_belief.candidate_dir,
       g_belief.conviction, g_cycle.urgency, g_barren_bars,
       TradingBlocked() ? " [LOCKED]" : ""));

   RenderDashboard();
}

void OnTick()
{
   if(!g_initialized) return;

   ManagePositionsTick();
   CheckTriggersTick();

   datetime bt = iTime(_Symbol, g_tf.chart, 0);
   if(bt != g_last_bar)
   {
      g_last_bar = bt;
      OnNewBar();
   }
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTIONS — registration, calibration, mode state,      |
//| Engram harvest (every closed position on this symbol)            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long  magic      = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   long  entry_kind = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong pos_id     = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   bool  is_ours    = (magic == CQ3_MAGIC);

   if(entry_kind == DEAL_ENTRY_IN)
   {
      if(!is_ours) return;

      double price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      long   dtype = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
      int    dir   = (dtype == DEAL_TYPE_BUY) ? 1 : -1;
      datetime t_in = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

      double sl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == pos_id)
         {
            sl = PositionGetDouble(POSITION_SL);
            break;
         }
      }

      ENUM_CQ3_REGIME regime = g_pending_regime_set ? g_pending_regime
                              : (g_regime.valid ? g_regime.regime : REGIME_CHOP);
      double conv = g_pending_regime_set ? g_pending_conviction : -1.0;
      int    trig = g_pending_regime_set ? g_pending_trigger : 0;
      g_pending_regime_set = false;
      g_pending_conviction = -1.0;
      g_pending_trigger    = 0;

      RegisterTrack(pos_id, price, sl, dir, regime, conv, trig, t_in);
   }
   else if(entry_kind == DEAL_ENTRY_OUT || entry_kind == DEAL_ENTRY_INOUT ||
           entry_kind == DEAL_ENTRY_OUT_BY)
   {
      bool still_open = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong tk = PositionGetTicket(i);
         if(tk == 0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == pos_id)
         { still_open = true; break; }
      }
      if(still_open) return;

      if(is_ours)
      {
         int slot = FindTrack(pos_id);
         int regime = (slot >= 0) ? (int)g_tracks[slot].regime
                     : (g_regime.valid ? (int)g_regime.regime : REGIME_CHOP);
         int closed_dir = (slot >= 0) ? g_tracks[slot].direction : 0;

         double net = 0.0;
         if(HistorySelectByPosition((long)pos_id))
         {
            int deals = HistoryDealsTotal();
            for(int d = 0; d < deals; d++)
            {
               ulong dt = HistoryDealGetTicket(d);
               if(dt == 0) continue;
               net += HistoryDealGetDouble(dt, DEAL_PROFIT) +
                      HistoryDealGetDouble(dt, DEAL_SWAP) +
                      HistoryDealGetDouble(dt, DEAL_COMMISSION);
            }
         }
         bool win = (net > 0.0);
         UpdateCalibration(regime, win);

         // Mode-layer state updates
         if(closed_dir != 0)
         {
            g_seq_dir      = closed_dir;
            g_seq_win      = win;
            g_seq_has_data = true;
         }
         if(win) g_consec_wins++;
         else    g_consec_wins = 0;

         Log(StringFormat("CLOSED | posID=%I64u net=%.2f regime=%s %s%s",
             pos_id, net, RegimeToString(regime), win ? "WIN" : "LOSS",
             InpTradeMode == TM_PHASE ?
             StringFormat(" -> phase %s", PhaseToString()) : ""));
      }

      // Engram harvest: every position on this symbol — ours or manual.
      HarvestClosedPosition(pos_id);

      int slot2 = FindTrack(pos_id);
      if(slot2 >= 0) g_tracks[slot2].used = false;

      RenderDashboard();
   }
}
//+------------------------------------------------------------------+
