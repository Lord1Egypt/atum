#!/usr/bin/env python3
"""
Unit tests for StrategyAnalyzer
"""

import unittest
import tempfile
import os
import sys

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from strategy_analyzer import StrategyAnalyzer, StrategyAnalysis, StrategyIssue

class TestStrategyAnalyzer(unittest.TestCase):
    
    def setUp(self):
        self.analyzer = StrategyAnalyzer()
    
    def test_analyzer_initialization(self):
        """Test that analyzer initializes correctly"""
        self.assertIsInstance(self.analyzer, StrategyAnalyzer)
        self.assertIn('lookahead_bias', self.analyzer.critical_patterns)
        self.assertIn('hardcoded_values', self.analyzer.warning_patterns)
    
    def test_lookahead_bias_detection(self):
        """Test lookahead bias detection"""
        content = """
def custom_exit(self, pair, trade, current_time, current_rate, current_profit, **kwargs):
    dataframe, _ = self.dp.get_analyzed_dataframe(pair=pair, timeframe=self.timeframe)
    current_candle = dataframe.iloc[-1].squeeze()
    return None
        """
        
        issues = self.analyzer._check_lookahead_bias(content)
        self.assertTrue(any('lookahead_bias' in issue.category for issue in issues))
    
    def test_strategy_structure_check(self):
        """Test strategy structure validation"""
        # Mock AST with required methods
        import ast
        code = """
class TestStrategy(IStrategy):
    def populate_indicators(self, dataframe, metadata):
        return dataframe
    
    def populate_entry_trend(self, dataframe, metadata):
        return dataframe
        """
        
        tree = ast.parse(code)
        issues = self.analyzer._check_strategy_structure(tree)
        
        # Should not have missing method issues
        missing_method_issues = [i for i in issues if 'Missing required method' in i.description]
        self.assertEqual(len(missing_method_issues), 0)
    
    def test_file_analysis(self):
        """Test analyzing a complete strategy file"""
        strategy_content = """
from freqtrade.strategy.interface import IStrategy
from pandas import DataFrame

class TestStrategy(IStrategy):
    minimal_roi = {"0": 0.1}
    stoploss = -0.1
    timeframe = '5m'
    
    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        return dataframe
    
    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe['enter_long'] = 0
        return dataframe
        """
        
        # Create temporary file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(strategy_content)
            temp_path = f.name
        
        try:
            analysis = self.analyzer.analyze_file(temp_path)
            self.assertIsInstance(analysis, StrategyAnalysis)
            self.assertEqual(analysis.strategy_name, "TestStrategy")
            self.assertTrue(analysis.is_valid)
        finally:
            os.unlink(temp_path)

if __name__ == '__main__':
    unittest.main()
