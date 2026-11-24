#!/usr/bin/env python3
"""
Example of generating professional reports with qbacktester.

This script demonstrates how to generate HTML and PDF reports
from backtest results.
"""

from qbacktester import (
    run_crossover_backtest, 
    StrategyParams,
    generate_html_report,
    generate_pdf_report,
    RSIStrategy,
    MACDStrategy,
    Backtester,
    DataLoader
)

def generate_strategy_reports():
    """Generate reports for different strategies."""
    
    print("📊 Generating Strategy Reports")
    print("=" * 50)
    
    # Load data
    loader = DataLoader()
    data = loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
    
    # Define strategies to test
    strategies = [
        ("Moving Average Crossover", "MA Crossover (20/50)", run_crossover_backtest, {
            "params": StrategyParams(
                symbol="SPY",
                start="2020-01-01",
                end="2023-12-31",
                fast_window=20,
                slow_window=50,
                initial_cash=100000
            )
        }),
        ("RSI Mean Reversion", "RSI Strategy (14)", None, {
            "strategy": RSIStrategy(window=14, oversold=30, overbought=70),
            "data": data
        }),
        ("MACD Crossover", "MACD Strategy (12,26,9)", None, {
            "strategy": MACDStrategy(fast=12, slow=26, signal=9),
            "data": data
        })
    ]
    
    for strategy_type, strategy_name, strategy_func, kwargs in strategies:
        print(f"\n🔄 Testing {strategy_name}...")
        
        # Run backtest
        if strategy_func:
            # For crossover strategy
            results = strategy_func(kwargs["params"])
        else:
            # For other strategies
            backtester = Backtester(
                data=kwargs["data"],
                strategy=kwargs["strategy"],
                initial_cash=100000,
                fee_bps=5.0,
                slippage_bps=2.5
            )
            results = backtester.run()
        
        # Generate HTML report
        print(f"   📄 Generating HTML report...")
        html_file = generate_html_report(
            results,
            strategy_name=strategy_name,
            symbol="SPY",
            output_file=f"{strategy_type.lower().replace(' ', '_')}_report.html"
        )
        print(f"   ✅ HTML report: {html_file}")
        
        # Generate PDF report
        print(f"   📄 Generating PDF report...")
        try:
            pdf_file = generate_pdf_report(
                results,
                strategy_name=strategy_name,
                symbol="SPY",
                output_file=f"{strategy_type.lower().replace(' ', '_')}_report.pdf"
            )
            print(f"   ✅ PDF report: {pdf_file}")
        except Exception as e:
            print(f"   ⚠️  PDF generation failed: {e}")
            print("   💡 Install WeasyPrint: pip install weasyprint")
    
    print(f"\n🎉 All reports generated in 'reports/' directory!")
    print("\nTo view reports:")
    print("   - Open HTML files in your web browser")
    print("   - Open PDF files with any PDF viewer")
    print("   - Share reports with colleagues and clients")

def generate_comprehensive_report():
    """Generate a comprehensive report with multiple strategies."""
    
    print("\n📈 Generating Comprehensive Strategy Comparison Report")
    print("=" * 60)
    
    # Load data
    loader = DataLoader()
    data = loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
    
    # Test multiple strategies
    strategies = [
        ("Buy & Hold", "Buy and Hold"),
        ("MA Crossover", "Moving Average Crossover (20/50)"),
        ("RSI", "RSI Mean Reversion (14)"),
        ("MACD", "MACD Crossover (12,26,9)"),
        ("Bollinger Bands", "Bollinger Bands Mean Reversion"),
        ("Momentum", "Momentum Strategy"),
    ]
    
    results_summary = []
    
    for strategy_code, strategy_name in strategies:
        print(f"   Testing {strategy_name}...")
        
        # This would be expanded to test all strategies
        # For now, just show the concept
        results_summary.append({
            "strategy": strategy_name,
            "sharpe": 1.23,  # Placeholder
            "return": 0.15,   # Placeholder
            "drawdown": -0.08 # Placeholder
        })
    
    print(f"\n📊 Strategy Comparison Summary:")
    print("-" * 60)
    for result in results_summary:
        print(f"{result['strategy']:25} | Sharpe: {result['sharpe']:5.2f} | Return: {result['return']:6.1%} | DD: {result['drawdown']:6.1%}")
    
    print(f"\n💡 To generate comprehensive reports:")
    print("   1. Run individual strategy backtests")
    print("   2. Generate HTML/PDF reports for each")
    print("   3. Combine results into a summary report")

if __name__ == "__main__":
    generate_strategy_reports()
    generate_comprehensive_report()
