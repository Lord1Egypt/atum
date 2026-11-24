#property strict

void OnTick()
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   while(true)
   {
      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.volume = 0.10;
      OrderSend(request, result);
   }
}
