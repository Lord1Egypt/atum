//+------------------------------------------------------------------+
//| FxMultiStyle.mq5 - マルチスタイルFX EA                            |
//| 1EA/1チャート方式: 各ペアのチャートにアタッチ                       |
//| Pythonバックエンドと通信してMLシグナルを受信                        |
//+------------------------------------------------------------------+
#property copyright "FxMultiStyle"
#property version   "1.00"
#property strict

#include <../Include/SocketClient.mqh>
#include <../Include/JsonParser.mqh>

//--- Input Parameters
input string InpHost         = "127.0.0.1";   // Python Server Host
input int    InpBasePort     = 5555;           // Base Port
input int    InpPairIndex    = 0;              // Pair Index (port offset)
input int    InpMagicBase    = 100000;         // Magic Number Base
input double InpLotSize      = 0.01;          // Lot Size
input int    InpMaxPositions = 5;              // Max Positions
input int    InpMaxDailyTrades = 50;           // Max Daily Trades
input double InpMaxDailyLossPct = 2.0;        // Max Daily Loss %
input double InpMaxSpreadPips = 3.0;          // Max Spread (pips)
input int    InpSlippage     = 10;            // Max Slippage (points)

//--- Global Variables
CSocketClient  g_socket;
int            g_magic;
int            g_port;
string         g_symbol;
double         g_pip_size;
double         g_pip_value;
int            g_daily_trades;
double         g_daily_pnl;
datetime       g_last_bar_time;
datetime       g_last_daily_reset;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = Symbol();
   g_magic = InpMagicBase + InpPairIndex;
   g_port = InpBasePort + InpPairIndex;
   g_daily_trades = 0;
   g_daily_pnl = 0.0;
   g_last_bar_time = 0;
   g_last_daily_reset = 0;

   // ペア設定
   g_pip_size = SymbolInfoDouble(g_symbol, SYMBOL_POINT) * 10;
   if(StringFind(g_symbol, "JPY") >= 0)
      g_pip_size = 0.01;
   else
      g_pip_size = 0.0001;

   g_pip_value = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE) * (g_pip_size / SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE));

   // ソケット接続
   g_socket.SetParams(InpHost, g_port, 100);
   if(!g_socket.Connect())
   {
      Print("[FxMS] Failed to connect to Python server at ", InpHost, ":", g_port);
      // 接続失敗しても動作継続（再接続試行）
   }
   else
   {
      Print("[FxMS] Connected: ", g_symbol, " @ port ", g_port, " magic=", g_magic);
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_socket.Disconnect();
   Print("[FxMS] Disconnected: ", g_symbol);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 日次リセット
   DailyReset();

   // 新しいM1バー確定チェック
   datetime current_bar = iTime(g_symbol, PERIOD_M1, 0);
   if(current_bar != g_last_bar_time && g_last_bar_time != 0)
   {
      // 前のバーが確定
      OnBarClose();
   }
   g_last_bar_time = current_bar;
}

//+------------------------------------------------------------------+
//| M1バー確定時の処理                                                |
//+------------------------------------------------------------------+
void OnBarClose()
{
   if(!g_socket.IsConnected())
   {
      g_socket.Connect();
      if(!g_socket.IsConnected()) return;
   }

   // スプレッドチェック
   double spread = SymbolInfoInteger(g_symbol, SYMBOL_SPREAD) * SymbolInfoDouble(g_symbol, SYMBOL_POINT) / g_pip_size;
   if(spread > InpMaxSpreadPips) return;

   // バーデータ送信
   CJsonBuilder builder;
   builder.AddString("action", "bar_close");
   builder.AddString("symbol", g_symbol);
   builder.AddDouble("open",   iOpen(g_symbol, PERIOD_M1, 1));
   builder.AddDouble("high",   iHigh(g_symbol, PERIOD_M1, 1));
   builder.AddDouble("low",    iLow(g_symbol, PERIOD_M1, 1));
   builder.AddDouble("close",  iClose(g_symbol, PERIOD_M1, 1));
   builder.AddLong("volume",   (long)iVolume(g_symbol, PERIOD_M1, 1));
   builder.AddString("time",   TimeToString(iTime(g_symbol, PERIOD_M1, 1), TIME_DATE|TIME_SECONDS));
   builder.AddDouble("bid",    SymbolInfoDouble(g_symbol, SYMBOL_BID));
   builder.AddDouble("ask",    SymbolInfoDouble(g_symbol, SYMBOL_ASK));
   builder.AddDouble("spread", spread);
   builder.AddInt("positions", CountOpenPositions());

   string response = g_socket.SendAndReceive(builder.Build());
   if(response == "") return;

   ProcessSignal(response);
}

//+------------------------------------------------------------------+
//| シグナル処理                                                      |
//+------------------------------------------------------------------+
void ProcessSignal(string json)
{
   string action = CJsonParser::GetStringValue(json, "action");

   if(action == "signal")
   {
      int direction      = CJsonParser::GetIntValue(json, "direction");
      double confidence  = CJsonParser::GetDoubleValue(json, "confidence");
      double sl_pips     = CJsonParser::GetDoubleValue(json, "sl_pips");
      double tp_pips     = CJsonParser::GetDoubleValue(json, "tp_pips");
      double lots        = CJsonParser::GetDoubleValue(json, "lots");

      if(lots <= 0) lots = InpLotSize;

      if(!CanTrade(direction)) return;

      OpenPosition(direction, lots, sl_pips, tp_pips);
   }
}

//+------------------------------------------------------------------+
//| トレード可能チェック                                              |
//+------------------------------------------------------------------+
bool CanTrade(int direction)
{
   if(CountOpenPositions() >= InpMaxPositions) return false;
   if(g_daily_trades >= InpMaxDailyTrades) return false;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > 0 && (-g_daily_pnl / balance * 100) >= InpMaxDailyLossPct) return false;

   return true;
}

//+------------------------------------------------------------------+
//| ポジションオープン                                                |
//+------------------------------------------------------------------+
void OpenPosition(int direction, double lots, double sl_pips, double tp_pips)
{
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   double entry_price, sl, tp;
   ENUM_ORDER_TYPE order_type;

   if(direction == 1)  // Buy
   {
      order_type = ORDER_TYPE_BUY;
      entry_price = ask;
      sl = entry_price - sl_pips * g_pip_size;
      tp = entry_price + tp_pips * g_pip_size;
   }
   else  // Sell
   {
      order_type = ORDER_TYPE_SELL;
      entry_price = bid;
      sl = entry_price + sl_pips * g_pip_size;
      tp = entry_price - tp_pips * g_pip_size;
   }

   // 注文正規化
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = g_symbol;
   request.volume    = lots;
   request.type      = order_type;
   request.price     = entry_price;
   request.sl        = sl;
   request.tp        = tp;
   request.magic     = g_magic;
   request.deviation = InpSlippage;
   request.comment   = "FxMS_" + IntegerToString(direction);

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         g_daily_trades++;
         Print("[FxMS] Opened ", (direction == 1 ? "BUY" : "SELL"),
               " ", lots, " lots @ ", entry_price,
               " SL=", sl, " TP=", tp);
      }
      else
      {
         Print("[FxMS] Order failed: ", result.retcode, " - ", result.comment);
      }
   }
}

//+------------------------------------------------------------------+
//| オープンポジション数                                              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == g_symbol &&
         PositionGetInteger(POSITION_MAGIC) == g_magic)
      {
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| 日次リセット                                                      |
//+------------------------------------------------------------------+
void DailyReset()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   datetime today_start = now - dt.hour * 3600 - dt.min * 60 - dt.sec;

   if(today_start != g_last_daily_reset)
   {
      g_daily_trades = 0;
      g_daily_pnl = 0.0;
      g_last_daily_reset = today_start;
   }
}
//+------------------------------------------------------------------+
