#!/usr/bin/env python3
"""
Example usage of different trading strategies in qbacktester.

This script demonstrates how to use the various built-in strategies
including RSI, MACD, Bollinger Bands, Momentum, and Stochastic.
"""

import pandas as pd
from qbacktester import (
    RSIStrategy,
    MACDStrategy,
    BollingerBandsStrategy,
    MomentumStrategy,
    StochasticStrategy,
    MovingAverageCrossoverStrategy,
    BuyAndHoldStrategy,
    DataLoader,
    Backtester,
    print_backtest_report
)

def run_strategy_example():
    """Run examples of different trading strategies."""
    
    # Load sample data
    loader = DataLoader()
    data = loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
    
    print("🚀 Running Strategy Examples on SPY (2020-2023)")
    print("=" * 60)
    
    # Define strategies to test
    strategies = [
        ("Buy & Hold", BuyAndHoldStrategy()),
        ("MA Crossover (20/50)", MovingAverageCrossoverStrategy(20, 50)),
        ("RSI Mean Reversion", RSIStrategy(window=14, oversold=30, overbought=70)),
        ("MACD Crossover", MACDStrategy(fast=12, slow=26, signal=9)),
        ("Bollinger Bands", BollingerBandsStrategy(window=20, std_dev=2.0)),
        ("Momentum", MomentumStrategy(window=10, threshold=0.02)),
        ("Stochastic", StochasticStrategy(k_window=14, d_window=3, oversold=20, overbought=80)),
    ]
    
    results = {}
    
    for name, strategy in strategies:
        print(f"\n📊 Testing {name}...")
        
        # Create backtester
        backtester = Backtester(
            data=data,
            strategy=strategy,
            initial_cash=100000,
            fee_bps=5.0,
            slippage_bps=2.5
        )
        
        # Run backtest
        result = backtester.run()
        results[name] = result
        
        # Print summary
        metrics = result['metrics']
        print(f"   Final Equity: ${metrics['final_equity']:,.2f}")
        print(f"   Total Return: {metrics['total_return']:.2%}")
        print(f"   Sharpe Ratio: {metrics['sharpe_ratio']:.3f}")
        print(f"   Max Drawdown: {metrics['max_drawdown']:.2%}")
        print(f"   Total Trades: {metrics['num_trades']}")
    
    # Compare results
    print("\n" + "=" * 60)
    print("📈 STRATEGY COMPARISON")
    print("=" * 60)
    
    comparison_data = []
    for name, result in results.items():
        metrics = result['metrics']
        comparison_data.append({
            'Strategy': name,
            'Final Equity': f"${metrics['final_equity']:,.0f}",
            'Total Return': f"{metrics['total_return']:.1%}",
            'Sharpe Ratio': f"{metrics['sharpe_ratio']:.2f}",
            'Max Drawdown': f"{metrics['max_drawdown']:.1%}",
            'Trades': metrics['num_trades']
        })
    
    comparison_df = pd.DataFrame(comparison_data)
    print(comparison_df.to_string(index=False))
    
    # Find best performing strategy
    best_strategy = max(results.items(), key=lambda x: x[1]['metrics']['sharpe_ratio'])
    print(f"\n🏆 Best Strategy: {best_strategy[0]}")
    print(f"   Sharpe Ratio: {best_strategy[1]['metrics']['sharpe_ratio']:.3f}")
    
    return results

if __name__ == "__main__":
    results = run_strategy_example()
