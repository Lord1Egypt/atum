//+------------------------------------------------------------------+
//| KintelAPI.mq4 — AI KINTEL Trading Intelligence Receiver          |
//| Copyright 2026, AI KINTEL                                        |
//| https://aikintel.com                                             |
//+------------------------------------------------------------------+
#property copyright "AI KINTEL"
#property link      "https://aikintel.com"
#property version   "2.00"
#property description "KINTEL API — Receive AI trading signals from AI KINTEL"
#property description "Supports: SMC Trades, MOE 3.0, Sniper (coming soon)"
#property description "Open Source — github.com/Fiftyfajf/aikintel-ea"
#property strict

// ─── Include Files ───
#include <KintelAPI_Config.mqh>
#include <KintelAPI_Logger.mqh>
#include <KintelAPI_Connection.mqh>
#include <KintelAPI_Auth.mqh>
#include <KintelAPI_Signals.mqh>
#include <KintelAPI_SymbolMapper.mqh>
#include <KintelAPI_RiskManager.mqh>
#include <KintelAPI_OrderManager.mqh>
#include <KintelAPI_Dashboard.mqh>
#include <KintelAPI_UserZone.mqh>

// ═══════════════════════════════════════════════════════════════════
// INPUT PARAMETERS
// ═══════════════════════════════════════════════════════════════════

// ─── Connection ───
input string InpAPIKey        = "";                    // API Key (from aikintel.com/dashboard)
input string InpAPIUrl        = DEFAULT_API_URL;       // API URL (default: api.aikintel.com)
input string InpStrategy      = "SMC";                 // Strategy: SMC / MOE / SNIPER

// ─── Risk Management ───
input double InpRiskPercent   = 1.0;                   // Risk % per trade
input int    InpMaxPositions  = 5;                     // Max simultaneous positions
input int    InpMagicNumber   = 202601;                // Magic Number (unique per instance!)
input int    InpSlippage      = 3;                     // Max slippage (points)

// ─── Polling ───
input int    InpPollSeconds   = 3;                     // Poll interval (seconds)

// ─── Symbol Mapping (Your Broker → AI KINTEL) ───
// Fill ONLY the symbols your broker offers. Leave empty to skip.
// Example: If your broker uses "EURUSDm" for EUR/USD, type "EURUSDm"
input string InpMapEURUSD     = "EURUSD";              // EUR/USD → Broker symbol
input string InpMapGBPUSD     = "GBPUSD";              // GBP/USD → Broker symbol
input string InpMapUSDJPY     = "USDJPY";              // USD/JPY → Broker symbol
input string InpMapAUDUSD     = "AUDUSD";              // AUD/USD → Broker symbol
input string InpMapUSDCAD     = "USDCAD";              // USD/CAD → Broker symbol
input string InpMapUSDCHF     = "USDCHF";              // USD/CHF → Broker symbol
input string InpMapNZDUSD     = "NZDUSD";              // NZD/USD → Broker symbol
input string InpMapEURJPY     = "EURJPY";              // EUR/JPY → Broker symbol
input string InpMapEURGBP     = "EURGBP";              // EUR/GBP → Broker symbol
input string InpMapEURCHF     = "EURCHF";              // EUR/CHF → Broker symbol
input string InpMapGBPJPY     = "GBPJPY";              // GBP/JPY → Broker symbol
input string InpMapGBPCHF     = "GBPCHF";              // GBP/CHF → Broker symbol
input string InpMapAUDNZD     = "AUDNZD";              // AUD/NZD → Broker symbol
input string InpMapNZDCHF     = "NZDCHF";              // NZD/CHF → Broker symbol
input string InpMapCADCHF     = "CADCHF";              // CAD/CHF → Broker symbol
input string InpMapUSDHKD     = "";                    // USD/HKD → Broker symbol
input string InpMapXAUUSD     = "XAUUSD";              // XAU/USD (Gold) → Broker symbol
input string InpMapXAGUSD     = "XAGUSD";              // XAG/USD (Silver) → Broker symbol
input string InpMapXPTUSD     = "";                    // XPT/USD (Platinum) → Broker symbol
input string InpMapWTIUSD     = "";                    // WTI/USD (Oil) → Broker symbol
input string InpMapBRENTUSD   = "";                    // BRENT/USD → Broker symbol
input string InpMapCOPPERUSD  = "";                    // COPPER/USD → Broker symbol
input string InpMapNATGASUSD  = "";                    // NATGAS/USD → Broker symbol
input string InpMapCOCOAUSD   = "";                    // COCOA/USD → Broker symbol
input string InpMapCOFFEEUSD  = "";                    // COFFEE/USD → Broker symbol
input string InpMapSOYBEANUSD = "";                    // SOYBEAN/USD → Broker symbol
input string InpMapBTCUSD     = "";                    // BTC/USD → Broker symbol
input string InpMapETHUSD     = "";                    // ETH/USD → Broker symbol
input string InpMapADAUSD     = "";                    // ADA/USD → Broker symbol
input string InpMapDOGEUSD    = "";                    // DOGE/USD → Broker symbol
input string InpMapDOTUSD     = "";                    // DOT/USD → Broker symbol
input string InpMapXRPUSD     = "";                    // XRP/USD → Broker symbol
input string InpMapLTCUSD     = "";                    // LTC/USD → Broker symbol
input string InpMapSPX        = "";                    // S&P 500 → Broker symbol
input string InpMapNDX        = "";                    // NASDAQ 100 → Broker symbol
input string InpMapDJI        = "";                    // Dow Jones → Broker symbol
input string InpMapDAX        = "";                    // DAX 40 → Broker symbol
input string InpMapFTSE       = "";                    // FTSE 100 → Broker symbol
input string InpMapCAC        = "";                    // CAC 40 → Broker symbol
input string InpMapSTOXX      = "";                    // EURO STOXX 50 → Broker symbol
input string InpMapASX        = "";                    // ASX 200 → Broker symbol
input string InpMapNKY        = "";                    // Nikkei 225 → Broker symbol
input string InpMapHSI        = "";                    // Hang Seng → Broker symbol
input string InpMapCHINA50    = "";                    // China A50 → Broker symbol
input string InpMapDXY        = "";                    // US Dollar Index → Broker symbol
input string InpMapVIX        = "";                    // VIX → Broker symbol

// ═══════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════
datetime g_lastPollTime     = 0;
datetime g_lastHeartbeatTime = 0;
int      g_todayTokensUsed  = 0;
int      g_cycleCount       = 0;
bool     g_initialized      = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   // ─── Validate inputs ───
   if (StringLen(InpAPIKey) == 0) {
      Alert("KINTEL API: Please enter your API Key in EA settings.\nGet your key at aikintel.com/dashboard");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (!ValidateAPIKeyFormat(InpAPIKey)) {
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (!ValidateStrategy(InpStrategy)) {
      Alert("KINTEL API: Invalid strategy. Use SMC, MOE, or SNIPER.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (InpStrategy == STRATEGY_SNIPER) {
      Alert("KINTEL API: Sniper strategy is not yet available. Coming soon!");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (InpRiskPercent <= 0 || InpRiskPercent > 10) {
      Alert("KINTEL API: Risk % must be between 0.1 and 10.0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // ─── Initialize logger ───
   LogInit(InpStrategy, InpMagicNumber);
   LogInfo("═══════════════════════════════════════════════");
   LogInfo(StringFormat("KINTEL API v%s — %s", EA_VERSION, EA_NAME));
   LogInfo(StringFormat("Strategy: %s | Risk: %.1f%% | MaxPos: %d | Magic: %d",
           InpStrategy, InpRiskPercent, InpMaxPositions, InpMagicNumber));
   LogInfo("═══════════════════════════════════════════════");
   
   // ─── Initialize symbol mapper ───
   InitSymbolMap(
      InpMapEURUSD, InpMapGBPUSD, InpMapUSDJPY, InpMapAUDUSD,
      InpMapUSDCAD, InpMapUSDCHF, InpMapNZDUSD, InpMapEURJPY,
      InpMapEURGBP, InpMapEURCHF, InpMapGBPJPY, InpMapGBPCHF,
      InpMapAUDNZD, InpMapNZDCHF, InpMapCADCHF, InpMapUSDHKD,
      InpMapXAUUSD, InpMapXAGUSD, InpMapXPTUSD, InpMapWTIUSD,
      InpMapBRENTUSD, InpMapCOPPERUSD, InpMapNATGASUSD,
      InpMapCOCOAUSD, InpMapCOFFEEUSD, InpMapSOYBEANUSD,
      InpMapBTCUSD, InpMapETHUSD, InpMapADAUSD, InpMapDOGEUSD,
      InpMapDOTUSD, InpMapXRPUSD, InpMapLTCUSD,
      InpMapSPX, InpMapNDX, InpMapDJI, InpMapDAX,
      InpMapFTSE, InpMapCAC, InpMapSTOXX, InpMapASX,
      InpMapNKY, InpMapHSI, InpMapCHINA50, InpMapDXY, InpMapVIX
   );
   
   int validSymbols = GetValidMapCount();
   if (validSymbols == 0) {
      LogError("No valid symbol mappings! Check your broker symbol names.");
      Alert("KINTEL API: No valid symbol mappings found. Check EA settings.");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   LogInfo(StringFormat("Valid symbol mappings: %d", validSymbols));
   
   // ─── Initialize UserZone ───
   UserZone_Init();
   
   // ─── Initialize dashboard data ───
   g_dash.isConnected = false;
   g_dash.strategy = InpStrategy;
   g_dash.riskPercent = InpRiskPercent;
   g_dash.tokenBalance = -1;
   g_dash.openPositionCount = 0;
   g_dash.maxPositions = InpMaxPositions;
   g_dash.todayTrades = 0;
   g_dash.todayWins = 0;
   g_dash.todayLosses = 0;
   g_dash.todayResultR = 0;
   g_dash.todayTokensUsed = 0;
   g_dash.lastSignalTime = "";
   g_dash.lastSignalDir = "";
   g_dash.lastSignalSymbol = "";
   g_dash.lastSignalBlueprint = "";
   g_dash.lastSignalConfidence = 0;
   g_dash.pollSeconds = InpPollSeconds;
   g_dash.lastLatencyMs = 0;
   g_dash.authError = "";
   
   // ─── First heartbeat ───
   string accountNumber = IntegerToString(AccountNumber());
   bool hbOk = SendHeartbeat(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber);
   
   if (hbOk) {
      LogInfo("Initial heartbeat successful. EA ready.");
      g_dash.isConnected = true;
      g_dash.tokenBalance = g_tokenBalance;
   } else {
      LogWarn("Initial heartbeat failed. Will retry on next cycle.");
      g_dash.authError = g_authError;
   }
   
   g_lastHeartbeatTime = TimeCurrent();
   g_initialized = true;
   
   // ─── Draw initial dashboard ───
   DrawDashboard();
   
   // ─── Set timer for polling ───
   EventSetTimer(InpPollSeconds);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   
   // ─── UserZone cleanup ───
   UserZone_Deinit();
   
   // ─── Dashboard cleanup ───
   CleanupDashboard();
   
   // ─── Logger cleanup ───
   LogInfo(StringFormat("EA shutdown. Reason: %d | Cycles: %d", reason, g_cycleCount));
   LogDeinit();
}

//+------------------------------------------------------------------+
//| Timer event — main polling loop                                  |
//+------------------------------------------------------------------+
void OnTimer() {
   if (!g_initialized) return;
   
   g_cycleCount++;
   string accountNumber = IntegerToString(AccountNumber());
   
   // ─── Heartbeat check ───
   if (IsHeartbeatDue()) {
      bool hbOk = SendHeartbeat(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber);
      g_dash.isConnected = hbOk;
      g_dash.tokenBalance = g_tokenBalance;
      g_dash.lastLatencyMs = g_lastLatencyMs;
      if (!hbOk) {
         g_dash.authError = g_authError;
      } else {
         g_dash.authError = "";
      }
      g_lastHeartbeatTime = TimeCurrent();
   }
   
   // ─── Skip if not connected ───
   if (!IsConnectionHealthy()) {
      UpdateDashboardState();
      DrawDashboard();
      return;
   }
   
   // ─── Poll for OPEN signals ───
   if (CanOpenPosition(InpMaxPositions, InpMagicNumber)) {
      int signalCount = PollSignals(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber);
      
      if (signalCount > 0) {
         ProcessOpenSignals(accountNumber);
      }
   }
   
   // ─── Poll for CLOSE/MODIFY signals ───
   int closeCount = PollCloseSignals(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber);
   if (closeCount > 0) {
      ProcessCloseSignals(accountNumber);
   }
   
   // ─── UserZone tick ───
   UserZone_OnTick();
   
   // ─── Update dashboard ───
   UpdateDashboardState();
   DrawDashboard();
}

//+------------------------------------------------------------------+
//| OnTick — forward to UserZone only (main logic is in OnTimer)     |
//+------------------------------------------------------------------+
void OnTick() {
   // Main logic runs on timer, not on tick
   // UserZone gets tick updates for custom indicators
}

//+------------------------------------------------------------------+
//| Process received OPEN signals                                    |
//+------------------------------------------------------------------+
void ProcessOpenSignals(string accountNumber) {
   for (int i = 0; i < g_pendingSignalCount; i++) {
      if (g_pendingSignals[i].processed) continue;
      
      KintelSignal sig = g_pendingSignals[i];
      
      // ─── Translate symbol ───
      string brokerSymbol = TranslateSymbol(sig.kintelSymbol);
      if (StringLen(brokerSymbol) == 0) {
         LogWarn(StringFormat("Signal #%d: %s not mapped — skipping", sig.id, sig.kintelSymbol));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // ─── Check if already have position on this symbol ───
      if (HasPositionOnSymbol(brokerSymbol, InpMagicNumber)) {
         LogInfo(StringFormat("Signal #%d: Already have position on %s — skipping", sig.id, brokerSymbol));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // ─── UserZone filter ───
      bool rejected = UserZone_FilterSignal(
         brokerSymbol, sig.direction, sig.entryPrice,
         sig.stopLoss, sig.takeProfit, sig.confidence, sig.blueprint
      );
      
      if (rejected) {
         LogInfo(StringFormat("Signal #%d: Rejected by UserZone filter", sig.id));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // ─── Spread check ───
      if (!IsSpreadAcceptable(brokerSymbol, sig.entryPrice, sig.stopLoss)) {
         LogWarn(StringFormat("Signal #%d: Spread too wide for %s — skipping", sig.id, brokerSymbol));
         // Don't ACK — might retry next cycle if spread narrows
         continue;
      }
      
      // ─── Validate stop levels ───
      if (!ValidateStopLevels(brokerSymbol, sig.entryPrice, sig.stopLoss, sig.takeProfit)) {
         LogWarn(StringFormat("Signal #%d: Stop levels too close for %s — skipping", sig.id, brokerSymbol));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // ─── Calculate lot size ───
      double lots = CalculateLotSize(brokerSymbol, InpRiskPercent, sig.entryPrice, sig.stopLoss);
      if (lots <= 0) {
         LogError(StringFormat("Signal #%d: Cannot calculate lot size for %s", sig.id, brokerSymbol));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // ─── Execute order ───
      string comment = StringFormat("KINTEL_%s_%d", InpStrategy, sig.id);
      int ticket = -1;
      
      if (sig.direction == "BUY") {
         ticket = ExecuteBuy(brokerSymbol, lots, sig.stopLoss, sig.takeProfit,
                            InpMagicNumber, InpSlippage, comment);
      } else if (sig.direction == "SELL") {
         ticket = ExecuteSell(brokerSymbol, lots, sig.stopLoss, sig.takeProfit,
                             InpMagicNumber, InpSlippage, comment);
      }
      
      if (ticket > 0) {
         // ─── Map signal to ticket ───
         MapSignalToTicket(sig.id, sig.deliveryId, ticket, brokerSymbol, sig.direction);
         
         // ─── ACK signal ───
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
         
         // ─── Report execution ───
         double execPrice = 0;
         if (OrderSelect(ticket, SELECT_BY_TICKET)) {
            execPrice = OrderOpenPrice();
         }
         double slippage = MathAbs(execPrice - sig.entryPrice);
         ReportExecution(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber,
                        sig.id, sig.deliveryId, ticket, execPrice, slippage, lots);
         
         // ─── Update dashboard ───
         g_dash.lastSignalTime = TimeToString(TimeCurrent(), TIME_SECONDS);
         g_dash.lastSignalDir = sig.direction;
         g_dash.lastSignalSymbol = sig.kintelSymbol;
         g_dash.lastSignalBlueprint = sig.blueprint;
         g_dash.lastSignalConfidence = sig.confidence;
         g_todayTokensUsed += sig.tokenCost;
         
         LogInfo(StringFormat("✓ Signal #%d executed: %s %s @ %.5f → Ticket #%d",
                 sig.id, sig.direction, brokerSymbol, execPrice, ticket));
      } else {
         LogError(StringFormat("✗ Signal #%d execution failed for %s", sig.id, brokerSymbol));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber, sig.id, sig.deliveryId);
      }
      
      g_pendingSignals[i].processed = true;
   }
}

//+------------------------------------------------------------------+
//| Process received CLOSE/MODIFY signals                            |
//+------------------------------------------------------------------+
void ProcessCloseSignals(string accountNumber) {
   for (int i = 0; i < g_pendingCloseCount; i++) {
      if (g_pendingCloseSignals[i].processed) continue;
      
      KintelCloseSignal csig = g_pendingCloseSignals[i];
      
      // ─── Find the ticket for this signal ───
      int ticket = FindTicketBySignal(csig.id);
      if (ticket < 0) {
         // Try to find by symbol and magic number
         string brokerSymbol = TranslateSymbol(csig.kintelSymbol);
         if (StringLen(brokerSymbol) > 0) {
            for (int j = OrdersTotal() - 1; j >= 0; j--) {
               if (OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) {
                  if (OrderMagicNumber() == InpMagicNumber && OrderSymbol() == brokerSymbol) {
                     ticket = OrderTicket();
                     break;
                  }
               }
            }
         }
      }
      
      if (ticket < 0) {
         LogWarn(StringFormat("Close signal #%d: No matching ticket found for %s", csig.id, csig.kintelSymbol));
         g_pendingCloseSignals[i].processed = true;
         continue;
      }
      
      if (csig.action == "CLOSE") {
         // ─── Close the position ───
         bool closed = CloseOrder(ticket, InpSlippage);
         if (closed) {
            // Report close to server
            if (OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY)) {
               double profit = OrderProfit() + OrderSwap() + OrderCommission();
               double pips = 0;
               double point = MarketInfo(OrderSymbol(), MODE_POINT);
               if (point > 0) {
                  if (OrderType() == OP_BUY)
                     pips = (OrderClosePrice() - OrderOpenPrice()) / point;
                  else
                     pips = (OrderOpenPrice() - OrderClosePrice()) / point;
               }
               
               int deliveryId = FindDeliveryBySignal(csig.id);
               ReportClose(InpAPIUrl, InpAPIKey, InpStrategy, accountNumber,
                          csig.id, deliveryId, ticket, OrderClosePrice(), profit, pips);
            }
         }
      } else if (csig.action == "MODIFY") {
         // ─── Modify SL/TP ───
         double newSL = csig.newSL > 0 ? csig.newSL : 0;
         double newTP = csig.newTP > 0 ? csig.newTP : 0;
         
         if (OrderSelect(ticket, SELECT_BY_TICKET)) {
            if (newSL <= 0) newSL = OrderStopLoss();
            if (newTP <= 0) newTP = OrderTakeProfit();
            ModifyOrder(ticket, newSL, newTP);
         }
      }
      
      g_pendingCloseSignals[i].processed = true;
   }
}

//+------------------------------------------------------------------+
//| Update dashboard state from current positions                    |
//+------------------------------------------------------------------+
void UpdateDashboardState() {
   // ─── Open positions ───
   g_dash.openPositionCount = CountOpenPositions(InpMagicNumber);
   UpdateDashPositions(InpMagicNumber);
   
   // ─── Today stats ───
   int trades, wins, losses;
   double totalR;
   GetTodayStats(InpMagicNumber, trades, wins, losses, totalR);
   g_dash.todayTrades = trades;
   g_dash.todayWins = wins;
   g_dash.todayLosses = losses;
   g_dash.todayResultR = totalR;
   g_dash.todayTokensUsed = g_todayTokensUsed;
   
   // ─── Connection ───
   g_dash.isConnected = g_isConnected;
   g_dash.tokenBalance = g_tokenBalance;
   g_dash.lastLatencyMs = g_lastLatencyMs;
}

//+------------------------------------------------------------------+
