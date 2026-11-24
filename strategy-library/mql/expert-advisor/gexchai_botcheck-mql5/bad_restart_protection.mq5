#property strict
#include <Trade/Trade.mqh>
CTrade trade;

int OnInit()
{
   Print("EA started");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(SymbolInfoDouble(_Symbol, SYMBOL_BID) > 0)
   {
      trade.Buy(1.0, _Symbol);
      trade.PositionModify(_Symbol, 100.0, 120.0);
   }
}
