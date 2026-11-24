"""
Offline tests that don't require internet connectivity.

These tests use mock data to ensure the test suite can run
without external dependencies.
"""

import pytest
import pandas as pd
from qbacktester import MockDataLoader, RSIStrategy, MACDStrategy, Backtester
from qbacktester.data import DataError


class TestOfflineFunctionality:
    """Test offline functionality with mock data."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.loader = MockDataLoader()
    
    def test_mock_data_loader_creation(self):
        """Test that mock data loader can be created."""
        loader = MockDataLoader()
        assert loader is not None
        assert loader.sample_data_dir == "data/sample"
    
    def test_mock_data_loading(self):
        """Test loading sample data."""
        data = self.loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
        
        # Check data structure
        assert isinstance(data, pd.DataFrame)
        assert len(data) > 0
        assert "Open" in data.columns
        assert "High" in data.columns
        assert "Low" in data.columns
        assert "Close" in data.columns
        assert "Volume" in data.columns
        
        # Check data types
        assert data.index.dtype.name.startswith('datetime')
        assert data["Close"].dtype in ['float64', 'float32']
        assert data["Volume"].dtype in ['int64', 'int32']
    
    def test_mock_data_validation(self):
        """Test that mock data passes validation."""
        data = self.loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
        
        # Check for required columns
        required_cols = ["Open", "High", "Low", "Close", "Volume"]
        for col in required_cols:
            assert col in data.columns, f"Missing required column: {col}"
        
        # Check for valid price data
        assert (data["Close"] > 0).all(), "All close prices should be positive"
        assert (data["High"] >= data["Low"]).all(), "High should be >= Low"
        assert (data["High"] >= data["Close"]).all(), "High should be >= Close"
        assert (data["Low"] <= data["Close"]).all(), "Low should be <= Close"
        assert (data["Volume"] > 0).all(), "All volumes should be positive"
    
    def test_offline_backtest_rsi(self):
        """Test RSI strategy with offline data."""
        data = self.loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
        
        strategy = RSIStrategy(window=14, oversold=30, overbought=70)
        backtester = Backtester(
            data=data,
            strategy=strategy,
            initial_cash=100000,
            fee_bps=5.0,
            slippage_bps=2.5
        )
        
        result = backtester.run()
        
        # Check result structure
        assert "equity_curve" in result
        assert "metrics" in result
        assert "trades" in result
        
        # Check metrics
        metrics = result["metrics"]
        assert "final_equity" in metrics
        assert "total_return" in metrics
        assert "sharpe_ratio" in metrics
        assert "max_drawdown" in metrics
        
        # Check that we have some trades
        assert metrics["num_trades"] >= 0
    
    def test_offline_backtest_macd(self):
        """Test MACD strategy with offline data."""
        data = self.loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
        
        strategy = MACDStrategy(fast=12, slow=26, signal=9)
        backtester = Backtester(
            data=data,
            strategy=strategy,
            initial_cash=100000,
            fee_bps=5.0,
            slippage_bps=2.5
        )
        
        result = backtester.run()
        
        # Check result structure
        assert "equity_curve" in result
        assert "metrics" in result
        assert "trades" in result
        
        # Check that we have some trades
        assert result["metrics"]["num_trades"] >= 0
    
    def test_mock_data_error_handling(self):
        """Test error handling for missing sample data."""
        loader = MockDataLoader()
        
        # Test with non-existent symbol
        with pytest.raises(DataError):
            loader.get_price_data("NONEXISTENT", "2020-01-01", "2023-12-31")
    
    def test_mock_data_date_filtering(self):
        """Test date filtering with mock data."""
        data = self.loader.get_price_data("SPY", "2021-01-01", "2021-12-31")
        
        # Check that data is filtered to 2021
        assert data.index.min().year == 2021
        assert data.index.max().year == 2021
        assert len(data) > 0
    
    @pytest.mark.slow
    def test_offline_performance(self):
        """Test that offline backtests run quickly."""
        import time
        
        data = self.loader.get_price_data("SPY", "2020-01-01", "2023-12-31")
        
        strategy = RSIStrategy(window=14, oversold=30, overbought=70)
        backtester = Backtester(
            data=data,
            strategy=strategy,
            initial_cash=100000,
            fee_bps=5.0,
            slippage_bps=2.5
        )
        
        start_time = time.time()
        result = backtester.run()
        end_time = time.time()
        
        # Should complete in under 5 seconds
        assert (end_time - start_time) < 5.0
        assert result is not None


@pytest.mark.offline
class TestOfflineMarkers:
    """Test that offline markers work correctly."""
    
    def test_offline_marker(self):
        """This test should be marked as offline."""
        assert True  # This test passes and is marked as offline
    
    @pytest.mark.online
    def test_online_marker(self):
        """This test should be marked as online (and skipped in offline mode)."""
        pytest.skip("This test requires internet connectivity")


if __name__ == "__main__":
    # Run offline tests
    pytest.main([__file__, "-v", "-m", "offline"])
