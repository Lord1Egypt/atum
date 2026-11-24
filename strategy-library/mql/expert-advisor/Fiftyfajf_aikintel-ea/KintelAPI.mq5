//+------------------------------------------------------------------+
//| KintelAPI.mq5 — AI KINTEL Signal Trading EA (MT5)                |
//| Version: 2.00 | Build: 20260401                                  |
//| https://aikintel.com | Open Source (MIT License)                  |
//+------------------------------------------------------------------+
//| HOW TO USE:                                                      |
//| 1. Get your API key at https://aikintel.com/dashboard            |
//| 2. Add URL to: Tools → Options → Expert Advisors → Allow URL    |
//|    URL: https://api.aikintel.com                                 |
//| 3. Attach EA to ANY chart (symbol doesn't matter)                |
//| 4. Set Strategy, API Key, Risk %, and symbol mappings            |
//| 5. Run separate instance per strategy (different magic numbers)  |
//+------------------------------------------------------------------+
#property copyright   "AI KINTEL"
#property link        "https://aikintel.com"
#property version     "2.00"
#property description "AI KINTEL Signal Trading EA — Connects to KINTEL API for automated signal execution"
#property description "Strategies: SMC Trades | MOE 3.0 | Sniper (coming soon)"
#property description "Open Source — MIT License — https://github.com/aikintel/aikintel-ea"

// ─── Include Files ───
#include "../Include/KintelAPI_Config.mqh"
#include "../Include/KintelAPI_Logger.mqh"
#include "../Include/KintelAPI_SymbolMapper.mqh"
#include "../Include/KintelAPI_Connection.mqh"
#include "../Include/KintelAPI_Auth.mqh"
#include "../Include/KintelAPI_Signals.mqh"
#include "../Include/KintelAPI_RiskManager.mqh"
#include "../Include/KintelAPI_OrderManager.mqh"
#include "../Include/KintelAPI_Dashboard.mqh"
#include "../Include/KintelAPI_UserZone.mqh"

// ═══════════════════════════════════════════════════════════════════
// ─── INPUT PARAMETERS ─────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

// --- Connection ---
input string InpAPIKey       = "";                          // API Key (from aikintel.com/dashboard)
input string InpAPIUrl       = "https://api.aikintel.com";  // API URL
input string InpStrategy     = "SMC";                       // Strategy: SMC / MOE / SNIPER

// --- Risk Management ---
input double InpRiskPercent  = 1.0;                         // Risk % per trade
input int    InpMaxPositions = 10;                          // Max simultaneous positions
input int    InpSlippage     = 3;                           // Max slippage (points)

// --- Identity ---
input ulong  InpMagicNumber  = 202604;                     // Magic Number (unique per instance)
input string InpAccountNumber = "";                         // MT Account Number (auto-detect if empty)

// --- Timing ---
input int    InpPollSeconds  = 2;                           // Signal poll interval (seconds)

// --- Symbol Mappings (46 instruments) ---
// Forex Majors
input string Sym01 = "EURUSD";   // EUR/USD
input string Sym02 = "GBPUSD";   // GBP/USD
input string Sym03 = "USDJPY";   // USD/JPY
input string Sym04 = "AUDUSD";   // AUD/USD
input string Sym05 = "USDCAD";   // USD/CAD
input string Sym06 = "USDCHF";   // USD/CHF
input string Sym07 = "NZDUSD";   // NZD/USD
// Forex Crosses
input string Sym08 = "EURJPY";   // EUR/JPY
input string Sym09 = "EURGBP";   // EUR/GBP
input string Sym10 = "EURCHF";   // EUR/CHF
input string Sym11 = "GBPJPY";   // GBP/JPY
input string Sym12 = "GBPCHF";   // GBP/CHF
input string Sym13 = "AUDNZD";   // AUD/NZD
input string Sym14 = "NZDCHF";   // NZD/CHF
input string Sym15 = "CADCHF";   // CAD/CHF
input string Sym16 = "USDHKD";   // USD/HKD
// Metals
input string Sym17 = "XAUUSD";   // XAU/USD (Gold)
input string Sym18 = "XAGUSD";   // XAG/USD (Silver)
input string Sym19 = "XPTUSD";   // XPT/USD (Platinum)
// Energy
input string Sym20 = "WTIUSD";   // WTI Crude Oil
input string Sym21 = "BRENTUSD"; // Brent Crude
input string Sym22 = "";         // Copper
input string Sym23 = "NATGAS";   // Natural Gas
// Soft Commodities
input string Sym24 = "";         // Cocoa
input string Sym25 = "";         // Coffee
input string Sym26 = "";         // Soybean
// Crypto
input string Sym27 = "BTCUSD";   // BTC/USD
input string Sym28 = "ETHUSD";   // ETH/USD
input string Sym29 = "";         // ADA/USD
input string Sym30 = "";         // DOGE/USD
input string Sym31 = "";         // DOT/USD
input string Sym32 = "";         // XRP/USD
input string Sym33 = "";         // LTC/USD
// Indices
input string Sym34 = "US500";    // S&P 500
input string Sym35 = "USTEC";    // NASDAQ 100
input string Sym36 = "US30";     // Dow Jones
input string Sym37 = "GER40";    // DAX
input string Sym38 = "UK100";    // FTSE 100
input string Sym39 = "FRA40";    // CAC 40
input string Sym40 = "EU50";     // STOXX 50
input string Sym41 = "";         // ASX 200
input string Sym42 = "JP225";    // Nikkei 225
input string Sym43 = "";         // Hang Seng
input string Sym44 = "";         // China 50
// Special
input string Sym45 = "DXY";      // Dollar Index
input string Sym46 = "VIX";      // Volatility Index

// ═══════════════════════════════════════════════════════════════════
// ─── GLOBAL STATE ─────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

string g_accountNumber = "";
datetime g_lastPollTime = 0;
int g_todayTokensUsed = 0;
int g_cycleCount = 0;

// ═══════════════════════════════════════════════════════════════════
// ─── INITIALIZATION ───────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

int OnInit() {
   // Validate inputs
   if (!ValidateAPIKeyFormat(InpAPIKey)) return INIT_PARAMETERS_INCORRECT;
   if (!ValidateStrategy(InpStrategy))   {
      Alert("KINTEL API: Invalid strategy. Use SMC, MOE, or SNIPER");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Detect account number
   g_accountNumber = InpAccountNumber;
   if (StringLen(g_accountNumber) == 0)
      g_accountNumber = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   
   // Initialize modules
   LogInit(InpStrategy, (int)InpMagicNumber);
   LogInfo("═══════════════════════════════════════════════");
   LogInfo(StringFormat("KINTEL API v%s (MT5) starting...", EA_VERSION));
   LogInfo(StringFormat("Strategy: %s | Risk: %.1f%% | Magic: %d",
           InpStrategy, InpRiskPercent, InpMagicNumber));
   LogInfo(StringFormat("Account: %s @ %s",
           g_accountNumber, AccountInfoString(ACCOUNT_COMPANY)));
   
   // Initialize order manager
   InitOrderManager(InpMagicNumber, InpSlippage);
   
   // Initialize symbol map
   InitSymbolMap(
      Sym01, Sym02, Sym03, Sym04, Sym05, Sym06, Sym07, Sym08, Sym09, Sym10,
      Sym11, Sym12, Sym13, Sym14, Sym15, Sym16, Sym17, Sym18, Sym19, Sym20,
      Sym21, Sym22, Sym23, Sym24, Sym25, Sym26, Sym27, Sym28, Sym29, Sym30,
      Sym31, Sym32, Sym33, Sym34, Sym35, Sym36, Sym37, Sym38, Sym39, Sym40,
      Sym41, Sym42, Sym43, Sym44, Sym45, Sym46
   );
   
   // UserZone init
   UserZone_OnInit();
   
   // Initial heartbeat
   if (!SendHeartbeat(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber)) {
      LogError("Initial heartbeat failed — will retry on next tick");
   }
   
   // Setup dashboard
   g_dash.strategy = InpStrategy;
   g_dash.riskPercent = InpRiskPercent;
   g_dash.maxPositions = InpMaxPositions;
   g_dash.pollSeconds = InpPollSeconds;
   DrawDashboard();
   
   // Set timer for polling
   EventSetTimer(InpPollSeconds);
   
   LogInfo("Initialization complete — waiting for signals...");
   return INIT_SUCCEEDED;
}

// ═══════════════════════════════════════════════════════════════════
// ─── MAIN TICK HANDLER ────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

void OnTick() {
   // UserZone tick
   UserZone_OnTick();
   
   // Update dashboard positions every tick
   UpdateDashPositions(InpMagicNumber);
   g_dash.openPositionCount = CountOpenPositions(InpMagicNumber);
   g_dash.isConnected = g_isConnected;
   g_dash.tokenBalance = g_tokenBalance;
   g_dash.lastLatencyMs = g_lastLatencyMs;
   g_dash.authError = g_authError;
   DrawDashboard();
}

// ═══════════════════════════════════════════════════════════════════
// ─── TIMER — SIGNAL POLLING ──────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

void OnTimer() {
   g_cycleCount++;
   
   // ── Heartbeat ──
   if (g_cycleCount % (HEARTBEAT_INTERVAL / InpPollSeconds) == 0 || !g_isConnected) {
      SendHeartbeat(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber);
   }
   
   if (!g_isConnected) return;
   if (g_tokenBalance == 0) {
      g_dash.authError = "NO TOKENS";
      DrawDashboard();
      return;
   }
   
   // ── Poll for CLOSE/MODIFY signals (free, no tokens) ──
   int closeCount = PollCloseSignals(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber);
   if (closeCount > 0) ProcessCloseSignals();
   
   // ── Poll for OPEN signals ──
   if (!CanOpenPosition(InpMaxPositions, InpMagicNumber)) return;
   
   int signalCount = PollSignals(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber);
   if (signalCount > 0) ProcessOpenSignals();
   
   // ── Update today stats ──
   int trades, wins, losses;
   double totalR;
   GetTodayStats(InpMagicNumber, trades, wins, losses, totalR);
   g_dash.todayTrades = trades;
   g_dash.todayWins = wins;
   g_dash.todayLosses = losses;
   g_dash.todayResultR = totalR;
   g_dash.todayTokensUsed = g_todayTokensUsed;
   
   DrawDashboard();
}

// ═══════════════════════════════════════════════════════════════════
// ─── SIGNAL PROCESSING ───────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

void ProcessOpenSignals() {
   for (int i = 0; i < g_pendingSignalCount; i++) {
      if (g_pendingSignals[i].processed) continue;
      
      string kintelSym = g_pendingSignals[i].kintelSymbol;
      string brokerSym = TranslateSymbol(kintelSym);
      
      if (StringLen(brokerSym) == 0) {
         LogWarn(StringFormat("No mapping for %s — skipping signal #%d", kintelSym, g_pendingSignals[i].id));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                   g_pendingSignals[i].id, g_pendingSignals[i].deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // Check if already have position on this symbol
      if (HasPositionOnSymbol(brokerSym, InpMagicNumber)) {
         LogInfo(StringFormat("Already have position on %s — skipping", brokerSym));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                   g_pendingSignals[i].id, g_pendingSignals[i].deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // Spread check
      if (!IsSpreadAcceptable(brokerSym, g_pendingSignals[i].entryPrice, g_pendingSignals[i].stopLoss)) {
         LogWarn(StringFormat("Spread too wide for %s — skipping", brokerSym));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                   g_pendingSignals[i].id, g_pendingSignals[i].deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // UserZone filter
      if (!UserZone_FilterSignal(kintelSym, g_pendingSignals[i].direction,
                                  g_pendingSignals[i].entryPrice, g_pendingSignals[i].stopLoss,
                                  g_pendingSignals[i].takeProfit, g_pendingSignals[i].confidence)) {
         LogInfo(StringFormat("UserZone rejected signal #%d on %s", g_pendingSignals[i].id, kintelSym));
         AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                   g_pendingSignals[i].id, g_pendingSignals[i].deliveryId);
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // Calculate lot size
      double lots = CalculateLotSize(brokerSym, InpRiskPercent,
                    g_pendingSignals[i].entryPrice, g_pendingSignals[i].stopLoss);
      if (lots <= 0) {
         LogError(StringFormat("Lot calculation failed for %s", brokerSym));
         g_pendingSignals[i].processed = true;
         continue;
      }
      
      // Validate stop levels
      if (!ValidateStopLevels(brokerSym, g_pendingSignals[i].entryPrice,
                               g_pendingSignals[i].stopLoss, g_pendingSignals[i].takeProfit)) {
         LogWarn(StringFormat("Stop levels too close for %s — adjusting", brokerSym));
      }
      
      // Execute
      string comment = StringFormat("KINTEL|%s|%d", InpStrategy, g_pendingSignals[i].id);
      ulong ticket = 0;
      double execPrice = 0;
      
      if (g_pendingSignals[i].direction == "LONG" || g_pendingSignals[i].direction == "BUY") {
         ticket = ExecuteBuy(brokerSym, lots, g_pendingSignals[i].stopLoss,
                  g_pendingSignals[i].takeProfit, InpMagicNumber, InpSlippage, comment);
         if (ticket > 0) execPrice = SymbolInfoDouble(brokerSym, SYMBOL_ASK);
      } else {
         ticket = ExecuteSell(brokerSym, lots, g_pendingSignals[i].stopLoss,
                  g_pendingSignals[i].takeProfit, InpMagicNumber, InpSlippage, comment);
         if (ticket > 0) execPrice = SymbolInfoDouble(brokerSym, SYMBOL_BID);
      }
      
      if (ticket > 0) {
         MapSignalToTicket(g_pendingSignals[i].id, g_pendingSignals[i].deliveryId,
                           ticket, brokerSym, g_pendingSignals[i].direction);
         
         double slippage = MathAbs(execPrice - g_pendingSignals[i].entryPrice);
         ReportExecution(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                        g_pendingSignals[i].id, g_pendingSignals[i].deliveryId,
                        ticket, execPrice, slippage, lots);
         
         g_todayTokensUsed += g_pendingSignals[i].tokenCost;
         
         // Update dashboard last signal
         g_dash.lastSignalTime = TimeToString(TimeCurrent(), TIME_MINUTES);
         g_dash.lastSignalDir = g_pendingSignals[i].direction;
         g_dash.lastSignalSymbol = kintelSym;
         g_dash.lastSignalBlueprint = g_pendingSignals[i].blueprint;
         g_dash.lastSignalConfidence = g_pendingSignals[i].confidence;
         
         LogInfo(StringFormat("✓ EXECUTED signal #%d: %s %s @ %.5f | Ticket #%d | Lots %.2f",
                 g_pendingSignals[i].id, g_pendingSignals[i].direction,
                 brokerSym, execPrice, ticket, lots));
      } else {
         LogError(StringFormat("✗ FAILED signal #%d: %s %s",
                  g_pendingSignals[i].id, g_pendingSignals[i].direction, brokerSym));
      }
      
      AckSignal(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                g_pendingSignals[i].id, g_pendingSignals[i].deliveryId);
      g_pendingSignals[i].processed = true;
   }
}

void ProcessCloseSignals() {
   for (int i = 0; i < g_pendingCloseCount; i++) {
      if (g_pendingCloseSignals[i].processed) continue;
      
      string kintelSym = g_pendingCloseSignals[i].kintelSymbol;
      string brokerSym = TranslateSymbol(kintelSym);
      if (StringLen(brokerSym) == 0) {
         g_pendingCloseSignals[i].processed = true;
         continue;
      }
      
      if (g_pendingCloseSignals[i].action == "CLOSE") {
         // Find and close all positions on this symbol
         for (int p = PositionsTotal() - 1; p >= 0; p--) {
            ulong ticket = PositionGetTicket(p);
            if (ticket == 0) continue;
            if (PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
            if (PositionGetString(POSITION_SYMBOL) != brokerSym) continue;
            
            double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            ClosePosition(ticket, InpSlippage);
            
            int signalId = FindSignalByTicket(ticket);
            int deliveryId = FindDeliveryBySignal(signalId);
            if (signalId > 0) {
               double closePrice = PositionGetDouble(POSITION_PRICE_CURRENT);
               ReportClose(InpAPIUrl, InpAPIKey, InpStrategy, g_accountNumber,
                          signalId, deliveryId, ticket, closePrice, profit, 0);
            }
         }
      } else if (g_pendingCloseSignals[i].action == "MODIFY") {
         for (int p = PositionsTotal() - 1; p >= 0; p--) {
            ulong ticket = PositionGetTicket(p);
            if (ticket == 0) continue;
            if (PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber) continue;
            if (PositionGetString(POSITION_SYMBOL) != brokerSym) continue;
            
            double newSL = g_pendingCloseSignals[i].newSL;
            double newTP = g_pendingCloseSignals[i].newTP;
            if (newSL <= 0) newSL = PositionGetDouble(POSITION_SL);
            if (newTP <= 0) newTP = PositionGetDouble(POSITION_TP);
            ModifyPosition(ticket, newSL, newTP);
         }
      }
      
      g_pendingCloseSignals[i].processed = true;
   }
}

// ═══════════════════════════════════════════════════════════════════
// ─── DEINITIALIZATION ────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

void OnDeinit(const int reason) {
   EventKillTimer();
   UserZone_OnDeinit();
   CleanupDashboard();
   LogInfo(StringFormat("EA stopped. Reason: %d | Trades today: %d", reason, g_dash.todayTrades));
   LogDeinit();
}

//+------------------------------------------------------------------+
