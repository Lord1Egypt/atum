"""
策略生成器

基于回测结果和优化建议自动生成下一版本的策略文件
"""

import json
import logging
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime

from ..backtest.config import BacktestResult


class StrategyGenerator:
    """
    策略文件生成器
    
    根据回测结果和优化建议自动生成新版本的策略文件和配置
    """
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
    
    def generate_next_version(
        self,
        current_result: BacktestResult,
        current_strategy_path: str,
        current_config_path: str,
        optimization_suggestions: Dict,
        version_increment: str = "auto"
    ) -> Tuple[str, str]:
        """
        生成下一版本的策略和配置
        
        Args:
            current_result: 当前版本回测结果
            current_strategy_path: 当前策略文件路径
            current_config_path: 当前配置文件路径
            optimization_suggestions: 优化建议
            version_increment: 版本递增方式 ("auto", "major", "minor")
            
        Returns:
            (新策略文件路径, 新配置文件路径)
        """
        # 解析当前版本号
        current_version = self._extract_version(current_strategy_path)
        next_version = self._increment_version(current_version, version_increment)
        
        # 生成新策略文件
        new_strategy_path = self._generate_strategy_file(
            current_strategy_path, 
            next_version, 
            current_result,
            optimization_suggestions
        )
        
        # 生成新配置文件
        new_config_path = self._generate_config_file(
            current_config_path,
            next_version,
            optimization_suggestions
        )
        
        self.logger.info(f"生成新版本: {next_version}")
        self.logger.info(f"策略文件: {new_strategy_path}")
        self.logger.info(f"配置文件: {new_config_path}")
        
        return new_strategy_path, new_config_path
    
    def _extract_version(self, strategy_path: str) -> str:
        """从策略文件路径中提取版本号"""
        filename = Path(strategy_path).stem
        
        # 匹配版本号模式 (如 V7c, V8a, V10b)
        version_match = re.search(r'V(\d+)([a-z]?)', filename, re.IGNORECASE)
        
        if version_match:
            major = int(version_match.group(1))
            minor = version_match.group(2) or 'a'
            return f"V{major}{minor}"
        
        return "V1a"  # 默认版本
    
    def _increment_version(self, current_version: str, increment_type: str) -> str:
        """递增版本号"""
        match = re.match(r'V(\d+)([a-z]?)', current_version, re.IGNORECASE)
        
        if not match:
            return "V1a"
        
        major = int(match.group(1))
        minor = match.group(2) or 'a'
        
        if increment_type == "major":
            return f"V{major + 1}a"
        elif increment_type == "minor":
            next_minor = chr(ord(minor) + 1) if minor < 'z' else 'a'
            if next_minor == 'a':
                major += 1
            return f"V{major}{next_minor}"
        else:  # auto
            # 根据改进程度决定版本递增
            next_minor = chr(ord(minor) + 1) if minor < 'z' else 'a'
            if next_minor == 'a':
                major += 1
            return f"V{major}{next_minor}"
    
    def _generate_strategy_file(
        self,
        current_path: str,
        new_version: str,
        result: BacktestResult,
        suggestions: Dict
    ) -> str:
        """生成新的策略文件"""
        
        # 读取当前策略文件
        with open(current_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 更新类名
        old_class_name = self._extract_class_name(content)
        new_class_name = re.sub(r'V\d+[a-z]?', new_version, old_class_name, flags=re.IGNORECASE)
        
        # 替换类名
        content = content.replace(old_class_name, new_class_name)
        
        # 应用优化建议
        content = self._apply_strategy_optimizations(content, suggestions, result)
        
        # 添加版本注释
        version_comment = self._generate_version_comment(new_version, suggestions, result)
        content = self._insert_version_comment(content, version_comment)
        
        # 生成新文件路径
        current_file = Path(current_path)
        new_filename = re.sub(r'V\d+[a-z]?', new_version, current_file.stem, flags=re.IGNORECASE)
        new_path = current_file.parent / f"{new_filename}.py"
        
        # 写入新文件
        with open(new_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        return str(new_path)
    
    def _generate_config_file(
        self,
        current_path: str,
        new_version: str,
        suggestions: Dict
    ) -> str:
        """生成新的配置文件"""
        
        # 读取当前配置
        with open(current_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        # 应用配置优化
        config = self._apply_config_optimizations(config, suggestions)
        
        # 生成新文件路径
        current_file = Path(current_path)
        new_filename = re.sub(r'v\d+[a-z]?', new_version.lower(), current_file.stem, flags=re.IGNORECASE)
        new_path = current_file.parent / f"{new_filename}.json"
        
        # 写入新配置
        with open(new_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        return str(new_path)
    
    def _extract_class_name(self, content: str) -> str:
        """提取策略类名"""
        match = re.search(r'class\s+(\w+)\s*\(', content)
        return match.group(1) if match else "Strategy"
    
    def _apply_strategy_optimizations(
        self,
        content: str,
        suggestions: Dict,
        result: BacktestResult
    ) -> str:
        """应用策略优化建议"""
        
        # 应用止损调整
        if 'stop_loss_adjustment' in suggestions:
            content = self._adjust_stop_loss(content, suggestions['stop_loss_adjustment'])
        
        # 应用入场条件调整
        if 'entry_adjustments' in suggestions:
            content = self._adjust_entry_conditions(content, suggestions['entry_adjustments'])
        
        # 应用ROI调整
        if 'roi_adjustment' in suggestions:
            content = self._adjust_roi_settings(content, suggestions['roi_adjustment'])
        
        # 应用追踪止损调整
        if 'trailing_stop_adjustment' in suggestions:
            content = self._adjust_trailing_stop(content, suggestions['trailing_stop_adjustment'])
        
        # 应用杠杆调整
        if 'leverage_adjustment' in suggestions:
            content = self._adjust_leverage(content, suggestions['leverage_adjustment'])
        
        return content
    
    def _adjust_roi_settings(self, content: str, adjustment: float) -> str:
        """调整ROI设置"""
        import re
        
        def adjust_roi_value(match):
            key = match.group(1)
            current_value = float(match.group(2))
            new_value = max(0.005, current_value + adjustment)  # 最小0.5%
            return f'"{key}": {new_value:.3f}'
        
        # 调整ROI字典中的值
        roi_pattern = r'"(\d+)":\s*([0-9.]+)'
        content = re.sub(roi_pattern, adjust_roi_value, content)
        
        return content
    
    def _adjust_trailing_stop(self, content: str, adjustment: float) -> str:
        """调整追踪止损参数"""
        # 调整trailing_stop_positive
        pattern = r'trailing_stop_positive\s*=\s*([0-9.]+)'
        
        def adjust_value(match):
            current_value = float(match.group(1))
            new_value = max(0.005, current_value + adjustment)
            return f'trailing_stop_positive = {new_value:.3f}'
        
        content = re.sub(pattern, adjust_value, content)
        
        # 调整trailing_stop_positive_offset
        pattern = r'trailing_stop_positive_offset\s*=\s*([0-9.]+)'
        
        def adjust_offset(match):
            current_value = float(match.group(1))
            new_value = max(0.01, current_value + adjustment)
            return f'trailing_stop_positive_offset = {new_value:.3f}'
        
        content = re.sub(pattern, adjust_offset, content)
        
        return content
    
    def _adjust_leverage(self, content: str, adjustment: float) -> str:
        """调整杠杆设置"""
        pattern = r'custom_leverage\s*=\s*([0-9.]+)'
        
        def adjust_value(match):
            current_value = float(match.group(1))
            new_value = max(1.0, min(10.0, current_value + adjustment))  # 限制在1-10倍
            return f'custom_leverage = {new_value:.1f}'
        
        return re.sub(pattern, adjust_value, content)
    
    def _adjust_stop_loss(self, content: str, adjustment: float) -> str:
        """调整止损参数"""
        # 查找并调整stoploss值
        pattern = r'stoploss\s*=\s*(-?\d+\.?\d*)'
        
        def adjust_value(match):
            current_value = float(match.group(1))
            new_value = current_value - adjustment  # 放宽止损
            return f'stoploss = {new_value:.3f}'
        
        return re.sub(pattern, adjust_value, content)
    
    def _adjust_entry_conditions(self, content: str, adjustments: Dict) -> str:
        """调整入场条件"""
        
        # RSI阈值调整
        if 'rsi_threshold_adjustment' in adjustments:
            adjustment = adjustments['rsi_threshold_adjustment']
            
            # 调整买入RSI阈值
            pattern = r'buy_rsi\s*=\s*IntParameter\([^,]+,\s*[^,]+,\s*default=(\d+)'
            def adjust_rsi(match):
                current_value = int(match.group(1))
                new_value = max(15, min(35, current_value + adjustment))
                return match.group(0).replace(f'default={current_value}', f'default={new_value}')
            content = re.sub(pattern, adjust_rsi, content)
            
            # 调整直接的RSI条件
            pattern = r'rsi.*?<\s*(\d+)'
            def adjust_direct_rsi(match):
                current_value = int(match.group(1))
                new_value = max(15, min(35, current_value + adjustment))
                return match.group(0).replace(str(current_value), str(new_value))
            content = re.sub(pattern, adjust_direct_rsi, content)
        
        # 成交量阈值调整
        if 'volume_threshold_adjustment' in adjustments:
            adjustment = adjustments['volume_threshold_adjustment']
            
            # 调整成交量倍数
            pattern = r'volume_ratio\s*>\s*([0-9.]+)'
            def adjust_volume(match):
                current_value = float(match.group(1))
                new_value = max(1.0, current_value + adjustment)
                return f'volume_ratio > {new_value:.1f}'
            content = re.sub(pattern, adjust_volume, content)
        
        # 添加趋势过滤
        if adjustments.get('add_trend_filter'):
            # 在入场条件中添加趋势确认
            # 这里可以添加更复杂的趋势过滤逻辑
            pass
        
        # 添加波动率过滤
        if adjustments.get('add_volatility_filter'):
            # 添加ATR或其他波动率指标
            pass
        
        # 传统的RSI阈值调整（向后兼容）
        if 'rsi_threshold' in adjustments:
            pattern = r'rsi_1h\s*<\s*(\d+)'
            new_threshold = adjustments['rsi_threshold']
            content = re.sub(pattern, f'rsi_1h < {new_threshold}', content)
        
        # EMA周期调整（向后兼容）
        if 'ema_period' in adjustments:
            pattern = r'EMA\((\d+)\)'
            new_period = adjustments['ema_period']
            content = re.sub(pattern, f'EMA({new_period})', content)
        
        return content
    
    def _apply_conservative_optimizations(self, content: str, suggestions: Dict) -> str:
        """应用保守优化策略"""
        # 减少交易频率，提高入场门槛
        
        # 增加额外的确认条件
        if 'add_volume_filter' in suggestions:
            # 在入场条件中添加成交量过滤
            pattern = r'(def populate_entry_trend.*?return dataframe)'
            # 这里需要更复杂的逻辑来插入新条件
        
        return content
    
    def _apply_config_optimizations(self, config: Dict, suggestions: Dict) -> Dict:
        """应用配置优化"""
        
        # 调整止损
        if 'stop_loss' in suggestions:
            config['stoploss'] = suggestions['stop_loss']
        
        # 调整ROI
        if 'roi_adjustment' in suggestions:
            roi_adj = suggestions['roi_adjustment']
            for key, value in config.get('minimal_roi', {}).items():
                config['minimal_roi'][key] = value + roi_adj
        
        # 调整交易对
        if 'pair_adjustments' in suggestions:
            pair_adj = suggestions['pair_adjustments']
            
            # 移除表现差的币种
            if 'remove_pairs' in pair_adj:
                current_pairs = config.get('exchange', {}).get('pair_whitelist', [])
                for pair in pair_adj['remove_pairs']:
                    if pair in current_pairs:
                        current_pairs.remove(pair)
            
            # 添加新的币种
            if 'add_pairs' in pair_adj:
                current_pairs = config.get('exchange', {}).get('pair_whitelist', [])
                for pair in pair_adj['add_pairs']:
                    if pair not in current_pairs:
                        current_pairs.append(pair)
        
        return config
    
    def _generate_version_comment(
        self,
        version: str,
        suggestions: Dict,
        result: BacktestResult
    ) -> str:
        """生成版本注释"""
        
        comment = f'''"""
{version} 版本更新 ({datetime.now().strftime('%Y-%m-%d')})

基于 {result.strategy_name} 的优化结果:
- 总收益率: {result.total_return:.2%}
- 胜率: {result.win_rate:.1%}
- 交易次数: {result.trade_count}
- 最大回撤: {result.max_drawdown:.2%}

主要优化方向:
'''
        
        # 添加具体优化内容
        if result.stop_loss_count > result.trade_count * 0.4:
            comment += "- 调整止损策略，减少过度止损\n"
        
        if result.win_rate < 0.55:
            comment += "- 优化入场条件，提高胜率\n"
        
        if result.total_return < -0.05:
            comment += "- 应用保守策略，控制风险\n"
        
        comment += '"""\n'
        
        return comment
    
    def _insert_version_comment(self, content: str, comment: str) -> str:
        """在策略文件中插入版本注释"""
        
        # 在类定义之前插入注释
        class_pattern = r'(class\s+\w+.*?:)'
        
        def insert_comment(match):
            return comment + '\n' + match.group(1)
        
        return re.sub(class_pattern, insert_comment, content, count=1)

    def generate_optimization_suggestions(self, result: BacktestResult, version_history: list = None, preference: str = "balanced") -> Dict:
        """
        基于回测结果和历史版本生成智能优化建议
        
        Args:
            result: 回测结果
            version_history: 历史版本列表，用于避免重复优化
            preference: 优化偏好 ("conservative", "balanced", "aggressive", "high_freq", "low_freq")
            
        Returns:
            优化建议字典
        """
        suggestions = {}
        
        # 分析当前策略状态
        performance_level = self._classify_performance(result)
        
        # 根据偏好和性能水平选择优化策略
        if preference == "conservative":
            suggestions = self._generate_conservative_suggestions(result, performance_level)
        elif preference == "aggressive":
            suggestions = self._generate_aggressive_suggestions(result, performance_level)
        elif preference == "high_freq":
            suggestions = self._generate_high_frequency_suggestions(result, performance_level)
        elif preference == "low_freq":
            suggestions = self._generate_low_frequency_suggestions(result, performance_level)
        else:  # balanced (default)
            suggestions = self._generate_balanced_suggestions(result, performance_level)
        
        # 避免重复优化
        if version_history:
            suggestions = self._filter_repeated_optimizations(suggestions, version_history)
        
        # 币种优化 (基于原始数据分析)
        if hasattr(result, 'raw_results') and result.raw_results:
            pair_suggestions = self._analyze_pair_performance(result.raw_results)
            if pair_suggestions:
                suggestions['pair_adjustments'] = pair_suggestions
        
        return suggestions
    
    def _classify_performance(self, result: BacktestResult) -> str:
        """分类策略性能水平"""
        if result.total_return > 0.02:
            return "excellent"
        elif result.total_return > 0:
            return "good"
        elif result.total_return > -0.01:
            return "near_breakeven"
        elif result.total_return > -0.05:
            return "poor"
        else:
            return "very_poor"
    
    def _generate_fine_tuning_suggestions(self, result: BacktestResult) -> Dict:
        """优秀策略的微调建议"""
        suggestions = {}
        
        # 微调ROI，提高目标
        suggestions['roi_adjustment'] = 0.002  # 小幅提高0.2%
        
        # 如果胜率很高，可以适当提高入场门槛
        if result.win_rate > 0.7:
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': -2,  # RSI更严格
                'volume_threshold_adjustment': 0.1  # 成交量要求提高
            }
        
        return suggestions
    
    def _generate_stability_suggestions(self, result: BacktestResult) -> Dict:
        """盈利策略的稳定性建议"""
        suggestions = {}
        
        # 保守的ROI调整
        suggestions['roi_adjustment'] = 0.001  # 微调0.1%
        
        # 如果交易次数过多，提高过滤条件
        if result.trade_count > 150:
            suggestions['entry_adjustments'] = {
                'volume_threshold_adjustment': 0.2
            }
        
        return suggestions
    
    def _generate_breakthrough_suggestions(self, result: BacktestResult) -> Dict:
        """接近盈亏平衡策略的突破建议"""
        suggestions = {}
        
        # 多维度优化尝试
        if result.win_rate > 0.6:
            # 胜率高但收益低，可能是止盈过早
            suggestions['roi_adjustment'] = -0.003  # 降低ROI目标，延长持仓
            suggestions['trailing_stop_adjustment'] = 0.002  # 放宽追踪止损
        else:
            # 胜率不高，需要提高入场质量
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': -3,  # 更严格的RSI
                'add_trend_filter': True
            }
        
        # 止损优化
        if result.stop_loss_count > result.trade_count * 0.3:
            suggestions['stop_loss_adjustment'] = 0.003  # 放宽止损0.3%
        
        return suggestions
    
    def _generate_major_optimization_suggestions(self, result: BacktestResult) -> Dict:
        """表现较差策略的主要优化建议"""
        suggestions = {}
        
        # 止损优化 - 优先级最高
        if result.stop_loss_count > result.trade_count * 0.4:
            suggestions['stop_loss_adjustment'] = 0.008  # 放宽0.8%
        
        # 入场条件优化
        if result.win_rate < 0.55:
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': -5,  # 更严格的RSI
                'volume_threshold_adjustment': 0.3,  # 提高成交量要求
                'add_volatility_filter': True
            }
        
        # ROI策略调整
        suggestions['roi_adjustment'] = 0.008  # 提高ROI目标
        
        return suggestions
    
    def _generate_fundamental_changes(self, result: BacktestResult) -> Dict:
        """表现很差策略的根本性改变建议"""
        suggestions = {}
        
        # 大幅调整止损
        suggestions['stop_loss_adjustment'] = 0.015  # 放宽1.5%
        
        # 重新设计入场条件
        suggestions['entry_adjustments'] = {
            'rsi_threshold_adjustment': -8,  # 大幅收紧RSI
            'add_multiple_timeframe': True,  # 添加多时间框架确认
            'add_momentum_filter': True  # 添加动量过滤
        }
        
        # 考虑币种重新筛选
        suggestions['major_pair_review'] = True
        
        return suggestions
    
    def _generate_conservative_suggestions(self, result: BacktestResult, performance_level: str) -> Dict:
        """保守优化策略 - 优先风险控制"""
        suggestions = {}
        
        if performance_level in ["poor", "very_poor"]:
            # 大幅收紧止损，降低风险
            suggestions['stop_loss_adjustment'] = 0.015  # 放宽1.5%
            suggestions['leverage_adjustment'] = -0.5  # 降低杠杆
            
            # 严格入场条件
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': -8,  # 更严格RSI
                'volume_threshold_adjustment': 0.5,  # 大幅提高成交量要求
                'add_trend_confirmation': True
            }
        elif performance_level == "near_breakeven":
            # 微调优化，保持稳定
            suggestions['roi_adjustment'] = 0.001  # 小幅调整ROI
            suggestions['trailing_stop_adjustment'] = 0.001  # 微调追踪止损
        else:
            # 优秀策略保持现状，只做微调
            suggestions['roi_adjustment'] = 0.0005
        
        return suggestions
    
    def _generate_aggressive_suggestions(self, result: BacktestResult, performance_level: str) -> Dict:
        """激进优化策略 - 追求高收益"""
        suggestions = {}
        
        if performance_level in ["excellent", "good"]:
            # 提高杠杆和风险敞口
            suggestions['leverage_adjustment'] = 0.5  # 提高杠杆
            suggestions['roi_adjustment'] = 0.005  # 提高ROI目标
            
            # 放宽入场条件，增加交易机会
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': 3,  # 放宽RSI
                'volume_threshold_adjustment': -0.2  # 降低成交量要求
            }
        elif performance_level == "near_breakeven":
            # 大胆突破，追求盈利
            suggestions['stop_loss_adjustment'] = -0.005  # 收紧止损
            suggestions['roi_adjustment'] = 0.008  # 大幅提高ROI
            
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': 2,
                'add_momentum_signals': True
            }
        else:
            # 表现差时也要激进改变
            suggestions['stop_loss_adjustment'] = 0.02  # 大幅放宽止损
            suggestions['leverage_adjustment'] = 1.0  # 大幅提高杠杆
            
            suggestions['entry_adjustments'] = {
                'rsi_threshold_adjustment': -10,  # 极严格条件
                'add_multiple_confirmations': True
            }
        
        return suggestions
    
    def _generate_high_frequency_suggestions(self, result: BacktestResult, performance_level: str) -> Dict:
        """高频交易优化 - 增加交易机会"""
        suggestions = {}
        
        # 放宽入场条件，增加交易频率
        suggestions['entry_adjustments'] = {
            'rsi_threshold_adjustment': 5,  # 放宽RSI条件
            'volume_threshold_adjustment': -0.3,  # 降低成交量要求
            'reduce_confirmation_requirements': True
        }
        
        # 快速止盈止损
        suggestions['roi_adjustment'] = -0.005  # 降低ROI目标，快速获利
        suggestions['stop_loss_adjustment'] = -0.003  # 收紧止损，快速止损
        
        # 如果当前交易频率已经很高，进一步优化
        if result.trade_count > 200:
            suggestions['entry_adjustments']['rsi_threshold_adjustment'] = 8
            suggestions['roi_adjustment'] = -0.008
        
        return suggestions
    
    def _generate_low_frequency_suggestions(self, result: BacktestResult, performance_level: str) -> Dict:
        """低频交易优化 - 提高交易质量"""
        suggestions = {}
        
        # 严格入场条件，减少交易频率
        suggestions['entry_adjustments'] = {
            'rsi_threshold_adjustment': -8,  # 严格RSI条件
            'volume_threshold_adjustment': 0.5,  # 提高成交量要求
            'add_multiple_confirmations': True,
            'add_trend_strength_filter': True
        }
        
        # 更高的盈利目标和更宽的止损
        suggestions['roi_adjustment'] = 0.01  # 提高ROI目标
        suggestions['stop_loss_adjustment'] = 0.01  # 放宽止损
        suggestions['trailing_stop_adjustment'] = 0.005  # 放宽追踪止损
        
        # 如果当前交易频率已经很低，适度放宽
        if result.trade_count < 50:
            suggestions['entry_adjustments']['rsi_threshold_adjustment'] = -5
            suggestions['entry_adjustments']['volume_threshold_adjustment'] = 0.2
        
        return suggestions
    
    def _generate_balanced_suggestions(self, result: BacktestResult, performance_level: str) -> Dict:
        """平衡优化策略 - 原有逻辑"""
        # 使用原有的性能等级优化逻辑
        if performance_level == "excellent":
            return self._generate_fine_tuning_suggestions(result)
        elif performance_level == "good":
            return self._generate_stability_suggestions(result)
        elif performance_level == "near_breakeven":
            return self._generate_breakthrough_suggestions(result)
        elif performance_level == "poor":
            return self._generate_major_optimization_suggestions(result)
        else:
            return self._generate_fundamental_changes(result)
    
    def _analyze_pair_performance(self, raw_results: Dict) -> Dict:
        """分析币种表现并生成调整建议"""
        try:
            strategy_data = list(raw_results.get('strategy', {}).values())[0]
            trades = strategy_data.get('trades', [])
            
            if not trades:
                return {}
            
            # 统计各币种表现
            pair_stats = {}
            for trade in trades:
                pair = trade.get('pair', 'Unknown')
                profit = trade.get('profit_abs', 0)
                
                if pair not in pair_stats:
                    pair_stats[pair] = {'profit': 0, 'count': 0}
                
                pair_stats[pair]['profit'] += profit
                pair_stats[pair]['count'] += 1
            
            # 生成调整建议
            suggestions = {}
            
            # 找出表现最差的币种
            worst_pairs = []
            for pair, stats in pair_stats.items():
                if stats['profit'] < -15 and stats['count'] > 5:  # 亏损超过15U且交易次数较多
                    worst_pairs.append(pair)
            
            if worst_pairs:
                suggestions['remove_pairs'] = worst_pairs[:2]  # 最多移除2个
            
            return suggestions
            
        except Exception as e:
            self.logger.error(f"分析币种表现失败: {e}")
            return {}
    
    def _filter_repeated_optimizations(self, suggestions: Dict, version_history: list) -> Dict:
        """过滤重复的优化建议"""
        # 这里可以实现更复杂的逻辑来避免重复优化
        # 暂时返回原建议，后续可以扩展
        return suggestions