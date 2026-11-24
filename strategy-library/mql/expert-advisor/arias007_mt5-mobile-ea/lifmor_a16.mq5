//+------------------------------------------------------------------+
//|                                                   lifmor.mq5      |
//|                     经典 lifmor 交易方法的直接交易法              |
//|                                                   Copyright 2026  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <Trade/Trade.mqh>

input group "基础交易参数"
input int    InpMagic                 = 20260111;    // 魔术数字
input int    InpPointsPerU            = 1000;        // 1U = 多少 points（黄金常用 1000）
input double InpEntryDistanceU        = 10.0;        // 入场间距（单位：U）
input double InpExitDistanceU         = 20.0;        // 止损距离（单位：U）

input group "启动 / 加仓 / 追踪止损"
input bool   InpManualStart           = true;        // 手动首单启动：平掉手动单并替换为EA首单
input bool   InpEnableMultiRound      = false;       // 是否开启多轮
input int    InpMaxLayers             = 10;          // 最大层数
input int    InpPercentTrailStartLayer= 4;           // 第X单起启用百分比追踪止损
input double InpPercentTrailPercent   = 50.0;        // 百分比追踪比例，50=最高/最低与首单中间

input group "订单类型 / 跟单方向"
enum ENUM_LIFMOR_ORDER_MODE
{
   LIFMOR_LONG_ONLY = 0,       // 多单
   LIFMOR_SHORT_ONLY = 1,      // 空单
   LIFMOR_LONG_SHORT_MIXED = 2 // 多空混合
};
input ENUM_LIFMOR_ORDER_MODE InpOrderMode = LIFMOR_LONG_SHORT_MIXED; // 订单类型
input bool InpReverseFollow = false; // 反向跟单（false=否, true=是）

input group "交易手数"
input double InpLots                  = 0.01;        // 统一手数
input bool   InpUseMoneyManagement    = true;        // 使用资金管理手数
input double InpMoneyPer001Lot        = 100.0;       // 每多少钱下0.01手

const bool InpEnableLogging = false;




// --- 持仓跟踪结构体 ---
struct PositionTrack
{
   ulong ticket;           // 持仓票据
   double peak_price;      // 峰值价格（多单用）或谷底价格（空单用）
};

// --- 全局变量 ---
CTrade trade;
datetime g_last_bar_time = 0;
datetime g_last_entry_time = 0;

// 分方向状态（支持多/空/多空混合）
int g_buy_entry_count = 0;            // 多头入场次数（层数）
int g_sell_entry_count = 0;           // 空头入场次数（层数）
int g_buy_entry_progress = 0;         // 多头已走到的最高层数（不因手动删单回退）
int g_sell_entry_progress = 0;        // 空头已走到的最高层数（不因手动删单回退）
double g_buy_first_entry_price = 0;   // 多头首次入场价格
double g_sell_first_entry_price = 0;  // 空头首次入场价格
double g_buy_last_layer_price = 0;    // 多头最新层入场价（用于统一止损）
double g_sell_last_layer_price = 0;   // 空头最新层入场价（用于统一止损）
double g_buy_stop_distance = 0;       // 多头基础止损距离（手动首单有SL时继承）
double g_sell_stop_distance = 0;      // 空头基础止损距离（手动首单有SL时继承）
double g_buy_extreme_price = 0;       // 多头百分比追踪最高价
double g_sell_extreme_price = 0;      // 空头百分比追踪最低价
bool g_buy_initial_pending_disabled = false;   // 用户删除多头入场挂单后不再补
bool g_sell_initial_pending_disabled = false;  // 用户删除空头入场挂单后不再补

PositionTrack g_tracks[];  // 持仓跟踪数组（按ticket跟踪峰值/谷底）
bool g_has_positions = false;    // 是否有持仓（任意方向）
bool g_manual_adoption_requested = false; // 手动单成交后由Tick/Timer接管


//+------------------------------------------------------------------+
//| 工具函数                                                           |
//+------------------------------------------------------------------+
string GetTradeSymbol()
{
   return _Symbol;
}

// 将"U"单位转换为价格偏移
double UToPrice(const string sym, double u_value)
{
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   return u_value * point * InpPointsPerU;
}

double NormPrice(const string sym, double price)
{
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

double ClampVolume(const string sym, double vol)
{
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   if(step <= 0) step = 0.01;
   vol = MathMax(vmin, MathMin(vmax, vol));
   vol = MathFloor(vol / step) * step;

   // 处理浮点误差
   int vdigits = 2;
   vol = NormalizeDouble(vol, vdigits);
   return vol;
}

int MaxLayers()
{
   if(InpMaxLayers < 1)
      return 1;
   return InpMaxLayers;
}

double ClampPercent(double value)
{
   if(value < 0.0)
      return 0.0;
   if(value > 100.0)
      return 100.0;
   return value;
}

double GetLots(const string sym)
{
   double lots = InpLots;

   if(InpUseMoneyManagement && InpMoneyPer001Lot > 0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      lots = (equity / InpMoneyPer001Lot) * 0.01;
   }

   return ClampVolume(sym, lots);
}

bool IsManagedPositionSelected(const string sym)
{
   if(PositionGetString(POSITION_SYMBOL) != sym)
      return false;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY && !(InpOrderMode == LIFMOR_LONG_ONLY || InpOrderMode == LIFMOR_LONG_SHORT_MIXED))
      return false;
   if(type == POSITION_TYPE_SELL && !(InpOrderMode == LIFMOR_SHORT_ONLY || InpOrderMode == LIFMOR_LONG_SHORT_MIXED))
      return false;

   int magic = (int)PositionGetInteger(POSITION_MAGIC);
   if(magic == InpMagic)
      return true;

   return false;
}

bool IsManualPositionSelected(const string sym)
{
   if(!InpManualStart)
      return false;
   if(PositionGetString(POSITION_SYMBOL) != sym)
      return false;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY && !AllowBuySide())
      return false;
   if(type == POSITION_TYPE_SELL && !AllowSellSide())
      return false;

   return ((int)PositionGetInteger(POSITION_MAGIC) == 0);
}

bool HasManualStartPosition(const string sym)
{
   if(!InpManualStart)
      return false;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsManualPositionSelected(sym))
         return true;
   }

   return false;
}

ENUM_POSITION_TYPE TradeSideForSignalSide(ENUM_POSITION_TYPE signal_side)
{
   if(!InpReverseFollow)
      return signal_side;
   return (signal_side == POSITION_TYPE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
}

ENUM_POSITION_TYPE SignalSideForTradeSide(ENUM_POSITION_TYPE trade_side)
{
   if(!InpReverseFollow)
      return trade_side;
   return (trade_side == POSITION_TYPE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
}

bool IsOurPosition(const string sym)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(IsManagedPositionSelected(sym))
         {
            return true;
         }
      }
   }
   return false;
}

int GetOurPositionCount(const string sym)
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(IsManagedPositionSelected(sym))
         {
            count++;
         }
      }
   }
   return count;
}

bool IsMixedMode()
{
   return (InpOrderMode == LIFMOR_LONG_SHORT_MIXED);
}

bool AllowBuySide()
{
   return (InpOrderMode == LIFMOR_LONG_ONLY || InpOrderMode == LIFMOR_LONG_SHORT_MIXED);
}

bool AllowSellSide()
{
   return (InpOrderMode == LIFMOR_SHORT_ONLY || InpOrderMode == LIFMOR_LONG_SHORT_MIXED);
}

bool IsEntryPendingOrderType(ENUM_ORDER_TYPE type)
{
   return (type == ORDER_TYPE_BUY_STOP ||
           type == ORDER_TYPE_SELL_STOP ||
           type == ORDER_TYPE_BUY_LIMIT ||
           type == ORDER_TYPE_SELL_LIMIT);
}

ENUM_POSITION_TYPE SignalSideForPendingEntryOrder(ENUM_ORDER_TYPE type, const string comment)
{
   if(comment == "lifmor_entry_buy" || comment == "lifmor_reverse_entry_sell")
      return POSITION_TYPE_BUY;
   if(comment == "lifmor_entry_sell" || comment == "lifmor_reverse_entry_buy")
      return POSITION_TYPE_SELL;

   ENUM_POSITION_TYPE trade_side = WRONG_VALUE;
   if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT)
      trade_side = POSITION_TYPE_BUY;
   else if(type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_LIMIT)
      trade_side = POSITION_TYPE_SELL;

   if(trade_side == WRONG_VALUE)
      return WRONG_VALUE;

   return SignalSideForTradeSide(trade_side);
}

int GetOurPositionCountByType(const string sym, ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(IsManagedPositionSelected(sym) &&
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
         {
            count++;
         }
      }
   }
   return count;
}

double GetOldestPositionOpenPriceByType(const string sym, ENUM_POSITION_TYPE type)
{
   datetime oldest_time = 0;
   double oldest_price = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPositionSelected(sym))
         continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(ptype != type)
         continue;

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest_time == 0 || t < oldest_time)
      {
         oldest_time = t;
         oldest_price = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }

   return oldest_price;
}

double GetWeightedAverageOpenPriceByType(const string sym, ENUM_POSITION_TYPE type)
{
   double vol_sum = 0;
   double pv_sum = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPositionSelected(sym))
         continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(ptype != type)
         continue;

      double vol = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      if(vol <= 0)
         continue;

      vol_sum += vol;
      pv_sum += vol * price;
   }

   if(vol_sum <= 0)
      return 0;

   return pv_sum / vol_sum;
}


// 删除某个方向的“入场挂单”（Stop/Limit 都清理，避免用户切换反向跟单后残留）
void DeletePendingEntryOrdersForSide(const string sym, ENUM_POSITION_TYPE side)
{
   trade.SetExpertMagicNumber(InpMagic);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != sym ||
         (int)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsEntryPendingOrderType(type))
         continue;

      if(SignalSideForPendingEntryOrder(type, OrderGetString(ORDER_COMMENT)) != side)
         continue;

      if(trade.OrderDelete(ticket))
      {
         if(InpEnableLogging)
            Print("删除入场挂单成功 ticket=", ticket, " signal_side=", EnumToString(side));
      }
      else
      {
         if(InpEnableLogging)
            Print("删除入场挂单失败 ticket=", ticket, " ret=", trade.ResultRetcode());
      }
   }
}

// 删除所有挂单
void DeleteAllPendingOrders(const string sym)
{
   trade.SetExpertMagicNumber(InpMagic);
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      
      if(IsOurOrderTicket(sym, ticket))
      {
         if(trade.OrderDelete(ticket))
         {
            if(InpEnableLogging)
               Print("删除挂单成功 ticket=", ticket);
         }
         else
         {
            if(InpEnableLogging)
               Print("删除挂单失败 ticket=", ticket, " ret=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
         }
      }
   }
}

// 删除指定类型的挂单
void DeletePendingOrdersByType(const string sym, ENUM_ORDER_TYPE order_type)
{
   trade.SetExpertMagicNumber(InpMagic);
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      
      if(OrderSelect(ticket))
      {
         if(OrderGetString(ORDER_SYMBOL) == sym && 
            (int)OrderGetInteger(ORDER_MAGIC) == InpMagic &&
            OrderGetInteger(ORDER_TYPE) == order_type)
         {
            if(trade.OrderDelete(ticket))
            {
               if(InpEnableLogging)
                  Print("删除挂单成功 ticket=", ticket, " type=", EnumToString(order_type));
            }
            else
            {
               if(InpEnableLogging)
                  Print("删除挂单失败 ticket=", ticket, " type=", EnumToString(order_type), " ret=", trade.ResultRetcode());
            }
         }
      }
   }
}


double GetTotalPositionVolume(const string sym)
{
   double total_volume = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(IsManagedPositionSelected(sym))
         {
            total_volume += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return total_volume;
}

// --- 持仓跟踪管理函数 ---

// 通过ticket查找跟踪索引
int TrackIndexByTicket(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_tracks); i++)
   {
      if(g_tracks[i].ticket == ticket)
         return i;
   }
   return -1;
}

// 创建或更新持仓跟踪
void TrackEnsure(const string sym, ulong ticket, ENUM_POSITION_TYPE type)
{
   int idx = TrackIndexByTicket(ticket);
   double current_ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(sym, SYMBOL_BID);
   
   if(idx < 0)
   {
      // 创建新的跟踪记录
      int n = ArraySize(g_tracks);
      ArrayResize(g_tracks, n + 1);
      g_tracks[n].ticket = ticket;
      
      // 初始化峰值/谷底价格为当前价格
      if(type == POSITION_TYPE_BUY)
         g_tracks[n].peak_price = current_ask;
      else
         g_tracks[n].peak_price = current_bid;
      
      if(InpEnableLogging)
         Print("创建持仓跟踪: ticket=", ticket, " 初始价格=", g_tracks[n].peak_price);
      return;
   }
   
   // 更新峰值/谷底价格
   if(type == POSITION_TYPE_BUY)
   {
      // 多单：更新峰值（取最高价）
      if(current_ask > g_tracks[idx].peak_price)
         g_tracks[idx].peak_price = current_ask;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      // 空单：更新谷底（取最低价，peak_price实际上存储的是谷底价格）
      if(current_bid < g_tracks[idx].peak_price)
         g_tracks[idx].peak_price = current_bid;
   }
}

// 清理不存在的持仓跟踪记录
void TrackCleanupMissingPositions(const string sym)
{
   for(int i = ArraySize(g_tracks) - 1; i >= 0; i--)
   {
      ulong ticket = g_tracks[i].ticket;
      
      // 检查持仓是否还存在
      if(!PositionSelectByTicket(ticket))
      {
         // 持仓不存在，删除跟踪记录
         if(InpEnableLogging)
            Print("删除持仓跟踪: ticket=", ticket, " (持仓已不存在)");
         
         for(int j = i; j < ArraySize(g_tracks) - 1; j++)
            g_tracks[j] = g_tracks[j + 1];
         ArrayResize(g_tracks, ArraySize(g_tracks) - 1);
         continue;
      }
      
      // 检查是否是本EA管理的持仓
      if(!IsManagedPositionSelected(sym))
      {
         // 不是本EA管理的持仓，删除跟踪记录
         if(InpEnableLogging)
            Print("删除持仓跟踪: ticket=", ticket, " (不是本EA管理的持仓)");
         
         for(int j = i; j < ArraySize(g_tracks) - 1; j++)
            g_tracks[j] = g_tracks[j + 1];
         ArrayResize(g_tracks, ArraySize(g_tracks) - 1);
      }
   }
}

// 获取持仓方向
ENUM_POSITION_TYPE GetPositionType(const string sym)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(IsManagedPositionSelected(sym))
         {
            return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         }
      }
   }
   return WRONG_VALUE;
}

// 检查挂单是否属于本EA
bool IsOurOrderTicket(const string sym, ulong ticket)
{
   if(ticket == 0)
      return false;
   
   if(OrderSelect(ticket))
   {
      if(OrderGetString(ORDER_SYMBOL) == sym && 
         (int)OrderGetInteger(ORDER_MAGIC) == InpMagic)
      {
         return true;
      }
   }
   return false;
}

bool HasPendingEntryOrderForSide(const string sym, ENUM_POSITION_TYPE side)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;

      if(OrderGetString(ORDER_SYMBOL) != sym ||
         (int)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!IsEntryPendingOrderType(type))
         continue;

      if(SignalSideForPendingEntryOrder(type, OrderGetString(ORDER_COMMENT)) == side)
         return true;
   }

   return false;
}

bool ShouldPlaceInitialPendingForSide(const string sym, ENUM_POSITION_TYPE side)
{
   if(InpManualStart && !g_has_positions)
      return false;

   if(side == POSITION_TYPE_BUY)
   {
      if(!AllowBuySide() || g_buy_initial_pending_disabled)
         return false;
      return InpEnableMultiRound || g_buy_entry_count == 0;
   }

   if(side == POSITION_TYPE_SELL)
   {
      if(!AllowSellSide() || g_sell_initial_pending_disabled)
         return false;
      return InpEnableMultiRound || g_sell_entry_count == 0;
   }

   return false;
}

void SyncInitialPendingOrders(const string sym, const bool force_refresh = false)
{
   bool place_buy = ShouldPlaceInitialPendingForSide(sym, POSITION_TYPE_BUY) &&
                    (force_refresh || !HasPendingEntryOrderForSide(sym, POSITION_TYPE_BUY));
   bool place_sell = ShouldPlaceInitialPendingForSide(sym, POSITION_TYPE_SELL) &&
                     (force_refresh || !HasPendingEntryOrderForSide(sym, POSITION_TYPE_SELL));

   if(!InpEnableMultiRound && g_has_positions)
   {
      DeleteAllPendingOrders(sym);
      return;
   }

   PlacePendingOrdersOnNewBar(sym, place_buy, place_sell);
}

// 在新K线时下“入场挂单”
void PlacePendingOrdersOnNewBar(const string sym, bool place_buy, bool place_sell)
{
   if(!place_buy && !place_sell)
      return;

   double current_ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double mid_price = (current_ask + current_bid) / 2.0;

   double dist_entry = UToPrice(sym, InpEntryDistanceU);
   double dist_exit = UToPrice(sym, InpExitDistanceU);

   double upper_price = NormPrice(sym, mid_price + dist_entry);
   double lower_price = NormPrice(sym, mid_price - dist_entry);

   double lots = GetLots(sym);

   double upper_trade_sl = 0, lower_trade_sl = 0;
   if(!InpReverseFollow)
   {
      upper_trade_sl = NormPrice(sym, upper_price - dist_exit);
      lower_trade_sl = NormPrice(sym, lower_price + dist_exit);
   }
   else
   {
      upper_trade_sl = NormPrice(sym, upper_price + dist_exit);
      lower_trade_sl = NormPrice(sym, lower_price - dist_exit);
   }

   trade.SetExpertMagicNumber(InpMagic);

   // 尝试不同的填充模式
   ENUM_ORDER_TYPE_FILLING fill_modes[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};

   if(place_buy)
   {
      DeletePendingEntryOrdersForSide(sym, POSITION_TYPE_BUY);

      bool buy_ok = false;
      for(int i = 0; i < ArraySize(fill_modes); i++)
      {
         trade.SetTypeFilling(fill_modes[i]);
         if(!InpReverseFollow)
            buy_ok = trade.BuyStop(lots, upper_price, sym, upper_trade_sl, 0, ORDER_TIME_GTC, 0, "lifmor_entry_buy");
         else
            buy_ok = trade.SellLimit(lots, upper_price, sym, upper_trade_sl, 0, ORDER_TIME_GTC, 0, "lifmor_reverse_entry_sell");
         if(buy_ok)
            break;
      }
   }

   if(place_sell)
   {
      DeletePendingEntryOrdersForSide(sym, POSITION_TYPE_SELL);

      bool sell_ok = false;
      for(int i = 0; i < ArraySize(fill_modes); i++)
      {
         trade.SetTypeFilling(fill_modes[i]);
         if(!InpReverseFollow)
            sell_ok = trade.SellStop(lots, lower_price, sym, lower_trade_sl, 0, ORDER_TIME_GTC, 0, "lifmor_entry_sell");
         else
            sell_ok = trade.BuyLimit(lots, lower_price, sym, lower_trade_sl, 0, ORDER_TIME_GTC, 0, "lifmor_reverse_entry_buy");
         if(sell_ok)
            break;
      }
   }
}



bool ExecuteMarketEntry(const string sym, ENUM_POSITION_TYPE signal_side, double lots, string comment)
{
   lots = ClampVolume(sym, lots);
   if(lots <= 0)
      return false;

   trade.SetExpertMagicNumber(InpMagic);

   ENUM_POSITION_TYPE trade_side = TradeSideForSignalSide(signal_side);
   double sl = 0;
   double tp = 0;
   ENUM_ORDER_TYPE_FILLING fill_modes[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};

   bool ok = false;
   for(int i = 0; i < ArraySize(fill_modes); i++)
   {
      trade.SetTypeFilling(fill_modes[i]);
      if(trade_side == POSITION_TYPE_BUY)
         ok = trade.Buy(lots, sym, 0, sl, tp, comment);
      else
         ok = trade.Sell(lots, sym, 0, sl, tp, comment);
      if(ok)
         break;
   }

   if(ok)
   {
      g_last_entry_time = TimeCurrent();
      UpdatePositionStatus(sym);
      return true;
   }

   return false;
}

// 执行入场交易（多单信号）
bool ExecuteEntryBuy(const string sym, double lots, string comment)
{
   return ExecuteMarketEntry(sym, POSITION_TYPE_BUY, lots, comment);
}

double GetOldestPositionStopLossByType(const string sym, ENUM_POSITION_TYPE type)
{
   datetime oldest_time = 0;
   double oldest_sl = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPositionSelected(sym))
         continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(ptype != type)
         continue;

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest_time == 0 || t < oldest_time)
      {
         oldest_time = t;
         oldest_sl = PositionGetDouble(POSITION_SL);
      }
   }

   return oldest_sl;
}

double GetNewestPositionOpenPriceByType(const string sym, ENUM_POSITION_TYPE type)
{
   datetime newest_time = 0;
   double newest_price = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPositionSelected(sym))
         continue;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(ptype != type)
         continue;

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(newest_time == 0 || t > newest_time)
      {
         newest_time = t;
         newest_price = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }

   return newest_price;
}



// 执行入场交易（空单信号）
bool ExecuteEntrySell(const string sym, double lots, string comment)
{
   return ExecuteMarketEntry(sym, POSITION_TYPE_SELL, lots, comment);
}



// 平仓单个持仓
bool CloseSinglePosition(const string sym, ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   if(!IsManagedPositionSelected(sym))
      return false;
   
   double volume = PositionGetDouble(POSITION_VOLUME);
   bool ok = trade.PositionClose(ticket);
   
   if(ok)
   {
      if(InpEnableLogging)
         Print("平仓成功: ticket=", ticket, " volume=", volume);
      
      // 删除跟踪记录
      int idx = TrackIndexByTicket(ticket);
      if(idx >= 0)
      {
         for(int i = idx; i < ArraySize(g_tracks) - 1; i++)
            g_tracks[i] = g_tracks[i + 1];
         ArrayResize(g_tracks, ArraySize(g_tracks) - 1);
      }
   }
   else
   {
      if(InpEnableLogging)
         Print("平仓失败: ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
   
   return ok;
}

// 平仓所有持仓
bool CloseAllPositions(const string sym)
{
   bool all_closed = true;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsManagedPositionSelected(sym))
         continue;
      if(!CloseSinglePosition(sym, ticket))
         all_closed = false;
   }
   
   if(all_closed)
   {
      g_has_positions = false;
      g_buy_entry_count = 0;
      g_sell_entry_count = 0;
      g_buy_entry_progress = 0;
      g_sell_entry_progress = 0;
      g_buy_first_entry_price = 0;
      g_sell_first_entry_price = 0;
      g_buy_last_layer_price = 0;
      g_sell_last_layer_price = 0;
      g_buy_stop_distance = 0;
      g_sell_stop_distance = 0;
      g_buy_extreme_price = 0;
      g_sell_extreme_price = 0;
      ArrayResize(g_tracks, 0);  // 清空跟踪数组
      if(InpEnableLogging)
         Print("所有持仓已平仓");
   }

   
   return all_closed;
}

bool AdoptManualPositionAsEaFirstLayer(const string sym)
{
   if(!InpManualStart)
      return false;
   if(g_has_positions)
      return false;

   ulong manual_ticket = 0;
   ENUM_POSITION_TYPE manual_type = WRONG_VALUE;
   double manual_price = 0;
   double manual_sl = 0;
   datetime oldest_time = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsManualPositionSelected(sym))
         continue;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      if(oldest_time == 0 || open_time < oldest_time)
      {
         oldest_time = open_time;
         manual_ticket = ticket;
         manual_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         manual_price = PositionGetDouble(POSITION_PRICE_OPEN);
         manual_sl = PositionGetDouble(POSITION_SL);
      }
   }

   if(manual_ticket == 0 || manual_type == WRONG_VALUE)
      return false;

   double stop_distance = (manual_sl > 0 ? MathAbs(manual_price - manual_sl) : UToPrice(sym, InpExitDistanceU));
   double lots = GetLots(sym);
   ENUM_POSITION_TYPE signal_side = manual_type;

   trade.SetExpertMagicNumber(InpMagic);
   if(!trade.PositionClose(manual_ticket))
      return false;

   Sleep(100);

   bool ok = ExecuteMarketEntry(sym, signal_side, lots, "lifmor_manual_replace_1");
   if(!ok)
      return false;

   if(signal_side == POSITION_TYPE_BUY)
   {
      g_buy_entry_progress = 1;
      g_buy_first_entry_price = manual_price;
      g_buy_last_layer_price = manual_price;
      g_buy_stop_distance = stop_distance;
      g_buy_extreme_price = MathMax(SymbolInfoDouble(sym, SYMBOL_BID), manual_price);
   }
   else
   {
      g_sell_entry_progress = 1;
      g_sell_first_entry_price = manual_price;
      g_sell_last_layer_price = manual_price;
      g_sell_stop_distance = stop_distance;
      g_sell_extreme_price = MathMin(SymbolInfoDouble(sym, SYMBOL_ASK), manual_price);
   }

   UpdatePositionStatus(sym);
   ManageExits(sym);
   return true;
}

void ProcessManualAdoption(const string sym, const bool force_scan)
{
   if(!InpManualStart)
   {
      g_manual_adoption_requested = false;
      return;
   }

   if(!force_scan && !g_manual_adoption_requested)
      return;

   UpdatePositionStatus(sym);

   if(g_has_positions)
   {
      g_manual_adoption_requested = false;
      return;
   }

   if(AdoptManualPositionAsEaFirstLayer(sym))
   {
      g_manual_adoption_requested = false;
      UpdatePositionStatus(sym);

      if(!InpEnableMultiRound)
         DeleteAllPendingOrders(sym);

      return;
   }

   g_manual_adoption_requested = HasManualStartPosition(sym);
}

// 检查是否满足加仓条件（按方向分别判断）
bool ShouldAddPositionForSide(const string sym, ENUM_POSITION_TYPE side)
{
   int position_count = (side == POSITION_TYPE_BUY ? g_buy_entry_count : g_sell_entry_count);
   int progress = (side == POSITION_TYPE_BUY ? g_buy_entry_progress : g_sell_entry_progress);
   if(position_count <= 0 || progress <= 0)
      return false;

   if(progress >= MaxLayers())
      return false;

   double first_entry_price = (side == POSITION_TYPE_BUY ? g_buy_first_entry_price : g_sell_first_entry_price);
   if(first_entry_price <= 0)
      return false;

   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double required_distance = progress * InpEntryDistanceU;

   ENUM_POSITION_TYPE trade_side = TradeSideForSignalSide(side);
   double current_price = (trade_side == POSITION_TYPE_BUY ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID));

   // 按信号方向计算层距；反向开启时，实际订单方向已反过来。
   double distance_u = 0;
   if(side == POSITION_TYPE_BUY)
      distance_u = (current_price - first_entry_price) / (point * InpPointsPerU);
   else if(side == POSITION_TYPE_SELL)
      distance_u = (first_entry_price - current_price) / (point * InpPointsPerU);

   if(distance_u >= required_distance)
   {
      if(InpEnableLogging)
      {
         Print("满足", (side == POSITION_TYPE_BUY ? "多单" : "空单"), "加仓条件: 当前价格=", current_price,
               " 首次入场价格=", first_entry_price,
               " 距离=", DoubleToString(distance_u, 1), "U 需要=", DoubleToString(required_distance, 1), "U",
               " 当前进度=", progress,
               " 反向跟单=", (InpReverseFollow ? "是" : "否"));
      }
      return true;
   }

   return false;
}


// 检查单个持仓是否满足出场条件
bool ShouldExitSinglePosition(const string sym, ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   if(!IsManagedPositionSelected(sym))
      return false;
   
   ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(pos_type == WRONG_VALUE)
      return false;
   
   // 查找跟踪记录
   int idx = TrackIndexByTicket(ticket);
   if(idx < 0)
      return false;  // 没有跟踪记录
   
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double peak_trough_price = g_tracks[idx].peak_price;
   
   if(pos_type == POSITION_TYPE_BUY)
   {
      // 多单：从峰值回撤出场
      double current_price = SymbolInfoDouble(sym, SYMBOL_BID);
      
      // 检查是否从峰值回撤了指定距离
      double distance_from_peak = (peak_trough_price - current_price) / (point * InpPointsPerU);
      
      if(distance_from_peak >= InpExitDistanceU)
      {
         if(InpEnableLogging)
            Print("满足多单出场条件: ticket=", ticket, " 当前价格=", current_price, 
                  " 峰值价格=", peak_trough_price, " 回撤距离=", DoubleToString(distance_from_peak, 1), "U");
         return true;
      }
   }
   else if(pos_type == POSITION_TYPE_SELL)
   {
      // 空单：从谷底反弹出场（peak_price存储的是谷底价格）
      double current_price = SymbolInfoDouble(sym, SYMBOL_ASK);
      
      // 检查是否从谷底反弹了指定距离
      double distance_from_trough = (current_price - peak_trough_price) / (point * InpPointsPerU);
      
      if(distance_from_trough >= InpExitDistanceU)
      {
         if(InpEnableLogging)
            Print("满足空单出场条件: ticket=", ticket, " 当前价格=", current_price, 
                  " 谷底价格=", peak_trough_price, " 反弹距离=", DoubleToString(distance_from_trough, 1), "U");
         return true;
      }
   }
   
   return false;
}

// 管理加仓逻辑（按方向分别加仓，所有层使用同一手数）
void ManageAddPositionsForSide(const string sym, ENUM_POSITION_TYPE side)
{
   int position_count = (side == POSITION_TYPE_BUY ? g_buy_entry_count : g_sell_entry_count);
   int progress = (side == POSITION_TYPE_BUY ? g_buy_entry_progress : g_sell_entry_progress);
   if(position_count <= 0 || progress <= 0 || progress >= MaxLayers())
      return;

   int next_layer = progress + 1;
   double lots = GetLots(sym);

   double current_price = (side == POSITION_TYPE_BUY ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID));
   string comment = (side == POSITION_TYPE_BUY ? "lifmor_add_buy_" : "lifmor_add_sell_") + IntegerToString(next_layer);

   bool ok = false;
   if(side == POSITION_TYPE_BUY)
      ok = ExecuteEntryBuy(sym, lots, comment);
   else if(side == POSITION_TYPE_SELL)
      ok = ExecuteEntrySell(sym, lots, comment);

   if(ok && InpEnableLogging)
      Print((side == POSITION_TYPE_BUY ? "多单" : "空单"), "加仓执行: 第", next_layer, "层 价格=", current_price, " 手数=", lots);

   if(ok)
   {
      if(side == POSITION_TYPE_BUY)
      {
         g_buy_entry_progress = MathMax(g_buy_entry_progress, next_layer);
      }
      else if(side == POSITION_TYPE_SELL)
      {
         g_sell_entry_progress = MathMax(g_sell_entry_progress, next_layer);
      }

      UpdatePositionStatus(sym);
      ManageExits(sym);
   }
}


// 修改持仓止损
bool ModifyPositionStopLoss(const string sym, ulong ticket, double new_sl)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   
   if(!IsManagedPositionSelected(sym))
      return false;
   
   double cur_sl = PositionGetDouble(POSITION_SL);
   double cur_tp = PositionGetDouble(POSITION_TP);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   // 检查新止损是否更有利（多单：新止损更高，空单：新止损更低）
   bool should_modify = false;
   if(type == POSITION_TYPE_BUY)
   {
      if(cur_sl == 0 || new_sl > cur_sl)
         should_modify = true;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(cur_sl == 0 || new_sl < cur_sl)
         should_modify = true;
   }
   
   if(!should_modify)
      return false;
   
   new_sl = NormPrice(sym, new_sl);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(type == POSITION_TYPE_BUY && bid > 0 && new_sl >= bid)
      return false;
   if(type == POSITION_TYPE_SELL && ask > 0 && new_sl <= ask)
      return false;
   
   if(trade.PositionModify(ticket, new_sl, cur_tp))
   {
      if(InpEnableLogging)
         Print("修改止损成功: ticket=", ticket, " 新止损=", new_sl);
      return true;
   }
   else
   {
      if(InpEnableLogging)
         Print("修改止损失败: ticket=", ticket, " retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }
}

// 计算峰值跟随止损价格
double CalculatePeakTrailingStopLoss(const string sym, ulong ticket, double peak_price, ENUM_POSITION_TYPE type)
{
   double dist = UToPrice(sym, InpExitDistanceU);
   
   if(type == POSITION_TYPE_BUY)
   {
      // 多单：止损 = 峰值 - 回撤距离
      return peak_price - dist;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      // 空单：止损 = 谷底 + 回撤距离
      return peak_price + dist;
   }
   
   return 0;
}

double CalculateSideStopLoss(const string sym, ENUM_POSITION_TYPE side)
{
   int count = (side == POSITION_TYPE_BUY ? g_buy_entry_count : g_sell_entry_count);
   int progress = (side == POSITION_TYPE_BUY ? g_buy_entry_progress : g_sell_entry_progress);
   if(count <= 0 || progress <= 0)
      return 0;

   double first_price = (side == POSITION_TYPE_BUY ? g_buy_first_entry_price : g_sell_first_entry_price);
   double last_price = (side == POSITION_TYPE_BUY ? g_buy_last_layer_price : g_sell_last_layer_price);
   double stop_dist = (side == POSITION_TYPE_BUY ? g_buy_stop_distance : g_sell_stop_distance);
   ENUM_POSITION_TYPE trade_side = TradeSideForSignalSide(side);
   if(first_price <= 0)
      return 0;

   int start_layer = MathMax(1, InpPercentTrailStartLayer);
   double sl = 0;

   if(progress >= start_layer)
   {
      double ratio = ClampPercent(InpPercentTrailPercent) / 100.0;

      if(trade_side == POSITION_TYPE_BUY)
      {
         double current = SymbolInfoDouble(sym, SYMBOL_BID);
         double extreme = g_buy_extreme_price;
         if(extreme <= 0)
            extreme = MathMax(current, last_price);
         if(current > extreme)
            extreme = current;
         g_buy_extreme_price = extreme;
         sl = first_price + (extreme - first_price) * ratio;
      }
      else if(trade_side == POSITION_TYPE_SELL)
      {
         double current = SymbolInfoDouble(sym, SYMBOL_ASK);
         double extreme = g_sell_extreme_price;
         if(extreme <= 0)
            extreme = MathMin(current, last_price);
         if(current < extreme)
            extreme = current;
         g_sell_extreme_price = extreme;
         sl = first_price - (first_price - extreme) * ratio;
      }
   }
   else
   {
      if(last_price <= 0)
         return 0;

      if(stop_dist <= 0)
         stop_dist = UToPrice(sym, InpExitDistanceU);

      sl = (trade_side == POSITION_TYPE_BUY ? last_price - stop_dist : last_price + stop_dist);
   }

   return (sl > 0 ? NormPrice(sym, sl) : 0);
}

void ApplySideStopLoss(const string sym, ENUM_POSITION_TYPE side, double sl)
{
   if(sl <= 0)
      return;

   trade.SetExpertMagicNumber(InpMagic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPositionSelected(sym))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(SignalSideForTradeSide(type) != side)
         continue;

      ModifyPositionStopLoss(sym, ticket, sl);
   }
}

// 管理出场逻辑
// - 正向：峰值/谷底跟随止损
// - 反向跟单：只保留止盈、无止损（由TP触发出场）
void ManageExits(const string sym)
{
   // 清理不存在的持仓跟踪记录
   TrackCleanupMissingPositions(sym);

   // 同向所有单共用一条止损线：未到百分比层数前跟最新层固定距离，到达后按最高/最低百分比追踪。
   if(g_buy_entry_count > 0)
      ApplySideStopLoss(sym, POSITION_TYPE_BUY, CalculateSideStopLoss(sym, POSITION_TYPE_BUY));
   if(g_sell_entry_count > 0)
      ApplySideStopLoss(sym, POSITION_TYPE_SELL, CalculateSideStopLoss(sym, POSITION_TYPE_SELL));

   // 更新峰值/谷底记录，保留原跟踪数组用于持仓生命周期清理。
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      
      // 更新持仓跟踪（峰值/谷底）
      if(PositionSelectByTicket(ticket))
      {
         if(IsManagedPositionSelected(sym))
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            TrackEnsure(sym, ticket, type);
         }
      }
   }
}


// 更新持仓状态（分方向统计，支持多空混合）
void UpdatePositionStatus(const string sym)
{
   // 先清理不存在的跟踪记录
   TrackCleanupMissingPositions(sym);

   int buy_count = 0;
   int sell_count = 0;
   int old_buy_progress = g_buy_entry_progress;
   int old_sell_progress = g_sell_entry_progress;
   double oldest_buy = 0;
   double oldest_sell = 0;
   double newest_buy = 0;
   double newest_sell = 0;
   double oldest_buy_sl = 0;
   double oldest_sell_sl = 0;
   datetime oldest_buy_time = 0;
   datetime oldest_sell_time = 0;
   datetime newest_buy_time = 0;
   datetime newest_sell_time = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(!IsManagedPositionSelected(sym))
         continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE signal_side = SignalSideForTradeSide(type);

      if(signal_side == POSITION_TYPE_BUY)
      {
         buy_count++;
         if(oldest_buy_time == 0 || open_time < oldest_buy_time)
         {
            oldest_buy_time = open_time;
            oldest_buy = open_price;
            oldest_buy_sl = sl;
         }
         if(newest_buy_time == 0 || open_time > newest_buy_time)
         {
            newest_buy_time = open_time;
            newest_buy = open_price;
         }
      }
      else if(signal_side == POSITION_TYPE_SELL)
      {
         sell_count++;
         if(oldest_sell_time == 0 || open_time < oldest_sell_time)
         {
            oldest_sell_time = open_time;
            oldest_sell = open_price;
            oldest_sell_sl = sl;
         }
         if(newest_sell_time == 0 || open_time > newest_sell_time)
         {
            newest_sell_time = open_time;
            newest_sell = open_price;
         }
      }

      // 为每个持仓维护峰值/谷底跟踪
      TrackEnsure(sym, ticket, type);
   }

   g_buy_entry_count = buy_count;
   g_sell_entry_count = sell_count;
   g_has_positions = (buy_count + sell_count) > 0;

   if(buy_count > 0)
   {
      if(g_buy_first_entry_price <= 0)
         g_buy_first_entry_price = oldest_buy;
      if(buy_count > old_buy_progress)
         g_buy_last_layer_price = newest_buy;
      else if(g_buy_last_layer_price <= 0)
         g_buy_last_layer_price = newest_buy;
      if(g_buy_stop_distance <= 0)
      {
         g_buy_stop_distance = (oldest_buy_sl > 0 ? MathAbs(oldest_buy - oldest_buy_sl) : UToPrice(sym, InpExitDistanceU));
         if(g_buy_stop_distance <= 0)
            g_buy_stop_distance = UToPrice(sym, InpExitDistanceU);
      }
      if(g_buy_entry_progress < buy_count)
         g_buy_entry_progress = buy_count;
      if(g_buy_extreme_price <= 0)
         g_buy_extreme_price = MathMax(SymbolInfoDouble(sym, SYMBOL_BID), g_buy_last_layer_price);
   }
   else
   {
      g_buy_entry_progress = 0;
      g_buy_first_entry_price = 0;
      g_buy_last_layer_price = 0;
      g_buy_stop_distance = 0;
      g_buy_extreme_price = 0;
   }

   if(sell_count > 0)
   {
      if(g_sell_first_entry_price <= 0)
         g_sell_first_entry_price = oldest_sell;
      if(sell_count > old_sell_progress)
         g_sell_last_layer_price = newest_sell;
      else if(g_sell_last_layer_price <= 0)
         g_sell_last_layer_price = newest_sell;
      if(g_sell_stop_distance <= 0)
      {
         g_sell_stop_distance = (oldest_sell_sl > 0 ? MathAbs(oldest_sell - oldest_sell_sl) : UToPrice(sym, InpExitDistanceU));
         if(g_sell_stop_distance <= 0)
            g_sell_stop_distance = UToPrice(sym, InpExitDistanceU);
      }
      if(g_sell_entry_progress < sell_count)
         g_sell_entry_progress = sell_count;
      if(g_sell_extreme_price <= 0)
         g_sell_extreme_price = MathMin(SymbolInfoDouble(sym, SYMBOL_ASK), g_sell_last_layer_price);
   }
   else
   {
      g_sell_entry_progress = 0;
      g_sell_first_entry_price = 0;
      g_sell_last_layer_price = 0;
      g_sell_stop_distance = 0;
      g_sell_extreme_price = 0;
   }

   if(!g_has_positions)
   {
      // 没有持仓时，清空跟踪数组与首次入场价
      ArrayResize(g_tracks, 0);
   }
}


//+------------------------------------------------------------------+
//| MT5 事件处理                                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   string sym = GetTradeSymbol();

   // 检查自动交易权限
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("终端禁用自动交易！请在工具->选项->EA交易中启用");
      return INIT_FAILED;
   }
   
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Alert("EA没有交易权限！请检查EA属性设置");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   trade.SetAsyncMode(false);

   // 验证品种是否存在和可用
   if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
   {
      Print("品种未在市场观察中，尝试添加：", sym);
      if(!SymbolSelect(sym, true))
      {
         Alert("无法添加品种到市场观察：", sym);
         return INIT_FAILED;
      }
   }
   
   // 等待品种数据准备
   int retry = 0;
   while(retry < 10)
   {
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      if(ask > 0 && bid > 0)
         break;
      Sleep(100);
      retry++;
   }
   
   double test_ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double test_bid = SymbolInfoDouble(sym, SYMBOL_BID);
   if(test_ask <= 0 || test_bid <= 0)
   {
      Alert("品种价格数据无效：", sym, " ask=", test_ask, " bid=", test_bid);
      return INIT_FAILED;
   }

   g_last_bar_time = iTime(sym, _Period, 0);

   // 账户模式提示：多空混合仅对“对冲(Hedging)账户”完整有效
   long margin_mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(InpEnableLogging && InpOrderMode == LIFMOR_LONG_SHORT_MIXED && margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("警告: 当前账户不是对冲(Hedging)模式，多空混合可能无法同时持有多/空仓位（会被净额化/反向对冲）。");
   }

   if(InpEnableLogging)

   {
      Print("lifmor 初始化完成 symbol=", sym, " TF=", EnumToString(_Period), " PointsPerU=", InpPointsPerU);
      Print("订单类型=", EnumToString(InpOrderMode), " 反向跟单=", (InpReverseFollow ? "是" : "否"));
      Print("统一手数=", InpLots, " 资金管理=", (InpUseMoneyManagement ? "是" : "否"));
      Print("当前价格 ask=", test_ask, " bid=", test_bid);
      Print("入场间距=", InpEntryDistanceU, "U", " 退出距离=", InpExitDistanceU, "U");
   }

   // 重置跟踪/状态（最终以实际持仓统计为准）
   ArrayResize(g_tracks, 0);
   g_buy_entry_count = 0;
   g_sell_entry_count = 0;
   g_buy_entry_progress = 0;
   g_sell_entry_progress = 0;
   g_buy_first_entry_price = 0;
   g_sell_first_entry_price = 0;
   g_buy_last_layer_price = 0;
   g_sell_last_layer_price = 0;
   g_buy_stop_distance = 0;
   g_sell_stop_distance = 0;
   g_buy_extreme_price = 0;
   g_sell_extreme_price = 0;
   g_buy_initial_pending_disabled = false;
   g_sell_initial_pending_disabled = false;
   g_manual_adoption_requested = false;
   g_has_positions = false;

   // 更新持仓状态
   UpdatePositionStatus(sym);
   g_manual_adoption_requested = HasManualStartPosition(sym);
   ProcessManualAdoption(sym, true);
   UpdatePositionStatus(sym);

   // 初始化挂单同步
   SyncInitialPendingOrders(sym);
   if(!InpEnableMultiRound && g_has_positions)
      DeleteAllPendingOrders(sym);

   
   EventSetTimer(1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(InpEnableLogging)
      Print("lifmor 停止 reason=", reason, " 多单层数=", g_buy_entry_count, " 空单层数=", g_sell_entry_count);
}

void OnTimer()
{
   ProcessManualAdoption(GetTradeSymbol(), false);
}


void OnTick()
{
   string sym = GetTradeSymbol();

   // 检查新K线
   datetime bar_time = iTime(sym, _Period, 0);
   bool is_new_bar = (bar_time != 0 && bar_time != g_last_bar_time);

   if(is_new_bar)
   {
      g_last_bar_time = bar_time;

      // 更新持仓状态
      UpdatePositionStatus(sym);

      if(InpEnableLogging)
      {
         Print("新K线: 时间=", TimeToString(bar_time),
               " 总持仓=", GetOurPositionCount(sym),
               " 多=", g_buy_entry_count,
               " 空=", g_sell_entry_count,
               " 模式=", EnumToString(InpOrderMode),
               " 反向=", (InpReverseFollow ? "是" : "否"));
      }

      // 新K线时同步入场挂单；手动启动或用户删除挂单时不会自动补。
      SyncInitialPendingOrders(sym, true);
   }

   // 定期更新持仓状态
   UpdatePositionStatus(sym);
   ProcessManualAdoption(sym, true);
   UpdatePositionStatus(sym);

   // 多轮关闭：有持仓后不再保留预订单，只允许市价加仓。
   // 多轮开启：持仓期间也允许新K线继续刷新预订单。
   if(!InpEnableMultiRound && g_has_positions)
      DeleteAllPendingOrders(sym);

   if(!g_has_positions)
      return;

   // 管理出场（包含峰值跟踪更新）
   ManageExits(sym);

   // 检查并执行加仓（分方向）
   if(AllowBuySide() && g_buy_entry_count > 0 && ShouldAddPositionForSide(sym, POSITION_TYPE_BUY))
      ManageAddPositionsForSide(sym, POSITION_TYPE_BUY);

   if(AllowSellSide() && g_sell_entry_count > 0 && ShouldAddPositionForSide(sym, POSITION_TYPE_SELL))
      ManageAddPositionsForSide(sym, POSITION_TYPE_SELL);
}


// 交易回报处理
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   string sym = GetTradeSymbol();

   // 只关心本EA、本品种
   if(trans.symbol != sym)
      return;

   // 识别成交（deal entry in 或 out）
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal == 0)
         return;
      if(!HistoryDealSelect(trans.deal))
         return;

      int deal_magic = (int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(deal_magic != InpMagic && !(InpManualStart && deal_magic == 0))
         return;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      
      if(entry == DEAL_ENTRY_IN)
      {
         if(InpManualStart && deal_magic == 0)
         {
            g_manual_adoption_requested = true;
            return;
         }

         ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         ENUM_POSITION_TYPE trade_side = (deal_type == DEAL_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
         ENUM_POSITION_TYPE signal_side = SignalSideForTradeSide(trade_side);
         string deal_comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
         ulong position_ticket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         double deal_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
         
         if(InpEnableLogging)
            Print("入场成交: deal=", trans.deal, " type=", EnumToString(deal_type), 
                  " volume=", HistoryDealGetDouble(trans.deal, DEAL_VOLUME), " comment=", deal_comment,
                  " position=", position_ticket, " price=", deal_price);
         
         // 多轮关闭：预订单一旦成交，就清掉其他预订单，后续只允许加仓。
         // 多轮开启：保留预订单，新K线仍可继续刷新/放置预订单。
         if(!InpEnableMultiRound)
            DeleteAllPendingOrders(sym);

         // 等待持仓创建并更新状态
         if(position_ticket > 0)
         {
            Sleep(50);  // 等待持仓创建

            UpdatePositionStatus(sym);

            // 创建/更新持仓跟踪记录
            if(PositionSelectByTicket(position_ticket))
            {
               ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               TrackEnsure(sym, position_ticket, pos_type);
            }
         }

         if(signal_side == POSITION_TYPE_BUY)
         {
            g_buy_initial_pending_disabled = false;
            int previous_progress = g_buy_entry_progress;
            int new_progress = MathMax(1, MathMax(g_buy_entry_progress, g_buy_entry_count));
            g_buy_last_layer_price = deal_price;
            g_buy_entry_progress = new_progress;
            if(g_buy_first_entry_price <= 0)
               g_buy_first_entry_price = deal_price;
            if(g_buy_stop_distance <= 0 && PositionSelectByTicket(position_ticket))
            {
               double sl = PositionGetDouble(POSITION_SL);
               g_buy_stop_distance = (sl > 0 ? MathAbs(deal_price - sl) : UToPrice(sym, InpExitDistanceU));
            }
            if(g_buy_extreme_price <= 0)
               g_buy_extreme_price = MathMax(SymbolInfoDouble(sym, SYMBOL_BID), deal_price);
            if(previous_progress < InpPercentTrailStartLayer && g_buy_entry_progress >= InpPercentTrailStartLayer)
               g_buy_extreme_price = MathMax(SymbolInfoDouble(sym, SYMBOL_BID), deal_price);
         }
         else if(signal_side == POSITION_TYPE_SELL)
         {
            g_sell_initial_pending_disabled = false;
            int previous_progress = g_sell_entry_progress;
            int new_progress = MathMax(1, MathMax(g_sell_entry_progress, g_sell_entry_count));
            g_sell_last_layer_price = deal_price;
            g_sell_entry_progress = new_progress;
            if(g_sell_first_entry_price <= 0)
               g_sell_first_entry_price = deal_price;
            if(g_sell_stop_distance <= 0 && PositionSelectByTicket(position_ticket))
            {
               double sl = PositionGetDouble(POSITION_SL);
               g_sell_stop_distance = (sl > 0 ? MathAbs(deal_price - sl) : UToPrice(sym, InpExitDistanceU));
            }
            if(g_sell_extreme_price <= 0)
               g_sell_extreme_price = MathMin(SymbolInfoDouble(sym, SYMBOL_ASK), deal_price);
            if(previous_progress < InpPercentTrailStartLayer && g_sell_entry_progress >= InpPercentTrailStartLayer)
               g_sell_extreme_price = MathMin(SymbolInfoDouble(sym, SYMBOL_ASK), deal_price);
         }

         ManageExits(sym);

      }
      else if(entry == DEAL_ENTRY_OUT)
      {
         ulong position_ticket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         if(InpEnableLogging)
            Print("平仓成交: deal=", trans.deal, " volume=", HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                  " position=", position_ticket);
         
         // 删除持仓跟踪记录（如果还存在）
         int idx = TrackIndexByTicket(position_ticket);
         if(idx >= 0)
         {
            for(int i = idx; i < ArraySize(g_tracks) - 1; i++)
               g_tracks[i] = g_tracks[i + 1];
            ArrayResize(g_tracks, ArraySize(g_tracks) - 1);
            if(InpEnableLogging)
               Print("删除持仓跟踪: ticket=", position_ticket);
         }
         
         // 检查是否还有持仓，更新状态
         UpdatePositionStatus(sym);
      }
   }
   // 挂单被删除或修改
   else if(trans.type == TRADE_TRANSACTION_ORDER_DELETE || trans.type == TRADE_TRANSACTION_ORDER_UPDATE)
   {
      ulong order_ticket = trans.order;
      bool is_our_order = (order_ticket > 0 && IsOurOrderTicket(sym, order_ticket));

      bool was_initial_entry_pending = false;
      ENUM_ORDER_TYPE order_type = WRONG_VALUE;
      if(trans.type == TRADE_TRANSACTION_ORDER_DELETE && HistoryOrderSelect(order_ticket))
      {
         string order_sym = HistoryOrderGetString(order_ticket, ORDER_SYMBOL);
         int order_magic = (int)HistoryOrderGetInteger(order_ticket, ORDER_MAGIC);
         order_type = (ENUM_ORDER_TYPE)HistoryOrderGetInteger(order_ticket, ORDER_TYPE);
         string order_comment = HistoryOrderGetString(order_ticket, ORDER_COMMENT);
         ENUM_ORDER_STATE order_state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(order_ticket, ORDER_STATE);
         ENUM_ORDER_REASON order_reason = (ENUM_ORDER_REASON)HistoryOrderGetInteger(order_ticket, ORDER_REASON);
         bool manual_cancel = (order_state == ORDER_STATE_CANCELED &&
                               (order_reason == ORDER_REASON_CLIENT ||
                                order_reason == ORDER_REASON_MOBILE ||
                                order_reason == ORDER_REASON_WEB));
         was_initial_entry_pending = (order_sym == sym && order_magic == InpMagic && manual_cancel);

         ENUM_POSITION_TYPE pending_signal_side = SignalSideForPendingEntryOrder(order_type, order_comment);
         if(was_initial_entry_pending && pending_signal_side == POSITION_TYPE_BUY)
            g_buy_initial_pending_disabled = true;
         else if(was_initial_entry_pending && pending_signal_side == POSITION_TYPE_SELL)
            g_sell_initial_pending_disabled = true;
      }

      if(InpEnableLogging)
      {
         if(is_our_order || was_initial_entry_pending)
         {
            Print("挂单变化: ticket=", order_ticket, " type=", EnumToString(trans.type));
         }
      }
   }
   // 持仓变化
   else if(trans.type == TRADE_TRANSACTION_POSITION)
   {
      // 更新持仓状态
      UpdatePositionStatus(sym);
   }
}
