#property strict

void OnTick()
{
   double currentBarHigh = iHigh(_Symbol, PERIOD_M5, 0);
   PrintFormat("current in-progress bar high=%.5f", currentBarHigh);
}
