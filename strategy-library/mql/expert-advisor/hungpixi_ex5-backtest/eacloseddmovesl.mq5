//+------------------------------------------------------------------+
//|                                                   CombinedEA.mq5 |
//|                                  Copyright 2024, MetaQuotes Software |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property description "EA to monitor DD and manage breakeven SL (Special for Gold)"

// DD Monitor Parameters
input group "DD Control Settings"
input double MaxLossPercent = 5.0;    // Maximum loss percentage
input int StartHour = 0;              // Hour to start trading (0-23)
input int StartMinute = 0;            // Minute to start trading (0-59)

// Breakeven Parameters
input group "Breakeven Settings"
input int ProfitPips = 40;            // Profit in pips to trigger breakeven
input double Offset = 1.0;            // Offset in pips from entry
input bool EnablePrints = true;       // Enable print messages

// Global variables
bool positionsClosedToday = false;
datetime lastClosingDay = 0;
int pip_point;                        // Value of 1 pip in points

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate pip value based on digits
   if(_Digits == 3 || _Digits == 5)
      pip_point = 10;
   else
      pip_point = 1;
      
   if(EnablePrints)
   {
      Print("=== EA Initialized ===");
      Print("DD Monitor Settings:");
      Print("Max Loss: ", MaxLossPercent, "%");
      Print("Trading Start Time: ", StartHour, ":", StartMinute);
      Print("");
      Print("Breakeven Settings:");
      Print("Target Profit: ", ProfitPips, " pips");
      Print("Breakeven Offset: ", Offset, " pips");
      PrintAccountInfo();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentTime = TimeCurrent();
   MqlDateTime time;
   TimeToStruct(currentTime, time);
   
   // Reset flag if it's a new day and after start time
   if(lastClosingDay != 0)
   {
      MqlDateTime lastTime;
      TimeToStruct(lastClosingDay, lastTime);
      
      if(time.day != lastTime.day)
      {
         if(time.hour >= StartHour && time.min >= StartMinute)
         {
            positionsClosedToday = false;
            if(EnablePrints) Print("New trading day started - Trading enabled");
         }
      }
   }
   
   // Only check account if we haven't closed positions today
   if(!positionsClosedToday)
   {
      CheckAccountAndClosePositions();
   }
   
   // Check breakeven conditions
   CheckBreakeven();
}

//+------------------------------------------------------------------+
//| Print detailed account information                               |
//+------------------------------------------------------------------+
void PrintAccountInfo()
{
   if(!EnablePrints) return;
   
   Print("=== Account Information ===");
   Print("Account Number: ", AccountInfoInteger(ACCOUNT_LOGIN));
   Print("Account Type: ", AccountInfoString(ACCOUNT_COMPANY));
   Print("Account Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("Account Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print("Account Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
   Print("Account Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN), 2));
   Print("Free Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));
   Print("Margin Level: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2), "%");
   Print("=========================");
}

//+------------------------------------------------------------------+
//| Check account balance and close positions if necessary           |
//+------------------------------------------------------------------+
void CheckAccountAndClosePositions()
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double absoluteLoss = accountBalance - accountEquity;
   double currentLossPercent = (absoluteLoss / accountBalance) * 100;
   
   if(EnablePrints)
   {
      Print("Current Loss: $", DoubleToString(absoluteLoss, 2), 
            " (", DoubleToString(currentLossPercent, 2), "%)");
   }
   
   // Check if loss exceeds maximum allowed percentage
   if(currentLossPercent >= MaxLossPercent || absoluteLoss >= (accountBalance * MaxLossPercent / 100))
   {
      Print("=== STOP OUT TRIGGERED ===");
      Print("Balance: $", DoubleToString(accountBalance, 2));
      Print("Equity: $", DoubleToString(accountEquity, 2));
      Print("Absolute Loss: $", DoubleToString(absoluteLoss, 2));
      Print("Loss Percentage: ", DoubleToString(currentLossPercent, 2), "%");
      
      // Close all positions first
      if(CloseAllPositions())
      {
         positionsClosedToday = true;
         lastClosingDay = TimeCurrent();
         
         Print("All positions have been closed due to excessive loss");
         Print("Trading will resume tomorrow at ", StartHour, ":", StartMinute);
         
         // Disconnect from MT5 after closing all positions
         DisconnectTerminal();
      }
      Print("========================");
   }
}

//+------------------------------------------------------------------+
//| Check breakeven conditions for all positions                     |
//+------------------------------------------------------------------+
void CheckBreakeven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentPrice = 0;
         double profit_points = 0;
         
         // Xác định hệ số pip dựa vào symbol
         double pip_multiplier = 1;
         if(StringFind(symbol, "GOLD") >= 0 || StringFind(symbol, "XAUUSD") >= 0)
            pip_multiplier = 10;  // Gold 1 điểm = 10 pip
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Tính profit theo points
         if(posType == POSITION_TYPE_BUY)
         {
            currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
            profit_points = (currentPrice - openPrice) / _Point;
         }
         else
         {
            currentPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
            profit_points = (openPrice - currentPrice) / _Point;
         }
         
         // Convert points to pips với hệ số đặc biệt cho Gold
         double profit_pips = profit_points / (pip_point * pip_multiplier);
         
         // Check if profit exceeds target and SL isn't at breakeven
         double target_offset = Offset * pip_point * pip_multiplier * _Point;
         double breakeven_level = openPrice + (posType == POSITION_TYPE_SELL ? target_offset : -target_offset);
         
         if(profit_pips >= ProfitPips && currentSL != breakeven_level)
         {
            if(EnablePrints)
            {
               Print("Position ", ticket, " reached ", profit_pips, " pips profit");
               Print("Moving SL to breakeven + ", Offset, " pips");
               Print("Symbol: ", symbol, " Pip multiplier: ", pip_multiplier);
            }
            
            ModifyPosition(ticket, breakeven_level, symbol);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all open positions                                         |
//+------------------------------------------------------------------+
bool CloseAllPositions()
{
   bool allClosed = true;
   int totalPositions = PositionsTotal();
   
   for(int i = totalPositions - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(PositionSelectByTicket(ticket))
      {
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = symbol;
         request.volume = volume;
         request.deviation = 5;
         request.magic = 123456;
         request.comment = "Closed by DD Monitor";
         request.type_filling = ORDER_FILLING_FOK;
         
         if(type == POSITION_TYPE_BUY)
         {
            request.price = SymbolInfoDouble(symbol, SYMBOL_BID);
            request.type = ORDER_TYPE_SELL;
         }
         else
         {
            request.price = SymbolInfoDouble(symbol, SYMBOL_ASK);
            request.type = ORDER_TYPE_BUY;
         }
         
         bool closeResult = OrderSend(request, result);
         if(!closeResult)
         {
            Print("Failed to close position ", ticket, ". Error: ", GetLastError());
            allClosed = false;
         }
         else
         {
            if(EnablePrints)
            {
               Print("Successfully closed position ", ticket, 
                     " Symbol: ", symbol,
                     " Volume: ", volume,
                     " Price: ", request.price);
            }
         }
      }
      else
      {
         Print("Failed to select position by ticket. Error: ", GetLastError());
         allClosed = false;
      }
   }
   
   return allClosed;
}

//+------------------------------------------------------------------+
//| Modify position's SL                                            |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double newSL, string symbol)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = symbol;
   request.sl = newSL;
   request.tp = PositionGetDouble(POSITION_TP);  // Keep existing TP
   
   bool success = OrderSend(request, result);
   
   if(!success)
   {
      if(EnablePrints)
         Print("Failed to modify position ", ticket, ". Error: ", GetLastError());
      return false;
   }
   
   if(EnablePrints)
      Print("Successfully modified SL for position ", ticket);
   
   return true;
}

//+------------------------------------------------------------------+
//| Disconnect MT5 terminal                                          |
//+------------------------------------------------------------------+
void DisconnectTerminal()
{
   Print("!!! ATTENTION !!!");
   Print("Daily drawdown limit of ", MaxLossPercent, "% reached.");
   Print("Disconnecting MT5 terminal to protect your account...");
   Print("Please check your account and restart MT5 tomorrow after ", StartHour, ":", StartMinute);
   Print("!!! DISCONNECTING NOW !!!");
   
   Sleep(1000);
   
   TerminalClose(0);
}

double OnTester()
{
   if(!MQLInfoInteger(MQL_TESTER)) return 0;

   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DD_RELATIVE);

   if(dd > 0.0001) return profit / dd;
   return profit;
}
