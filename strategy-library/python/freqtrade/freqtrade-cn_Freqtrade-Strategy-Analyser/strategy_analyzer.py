#!/usr/bin/env python3
"""
FreqTrade Strategy Analyzer
Recursively analyzes trading strategies and generates a comprehensive report
"""

import os
import ast
import re
import json
import csv
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
import argparse


@dataclass
class StrategyIssue:
    severity: str  # 'critical', 'warning', 'info'
    category: str
    description: str
    line_number: Optional[int] = None
    code_snippet: Optional[str] = None


@dataclass
class StrategyAnalysis:
    file_path: str
    strategy_name: str
    is_valid: bool
    overall_rating: str  # 'excellent', 'good', 'poor', 'broken'
    issues: List[StrategyIssue]
    features: Dict[str, Any]
    recommendations: List[str]


class StrategyAnalyzer:
    def __init__(self):
        self.critical_patterns = {
            'lookahead_bias': [
                r'dataframe\.iloc\[-1\]',
                r'current_candle\s*=.*\.iloc\[-1\]',
                r'\.shift\(-\d+\)',
                r'\.iloc\[len\(.*\)-1\]'
            ],
            'global_variables': [
                r'^[A-Z_][A-Z0-9_]*\s*=',
                r'global\s+\w+',
                r'^tmp_hold\s*=',
                r'^tmp_hold1\s*='
            ],
            'dangerous_operations': [
                r'del\s+\w+',
                r'\.remove\(',
                r'\.pop\(\)',
                r'exec\(',
                r'eval\('
            ]
        }
        
        self.warning_patterns = {
            'hardcoded_values': [
                r'dataframe\[.*\]\s*[<>=!]+\s*\d+\.?\d*',
                r'current_profit\s*[<>=!]+\s*\d+\.?\d*',
                r'current_candle\[.*\]\s*[<>=!]+\s*\d+\.?\d*'
            ],
            'memory_leaks': [
                r'tmp_hold.*\.add\(',
                r'self\.\w+.*\.append\(',
                r'global.*list',
                r'global.*dict'
            ],
            'missing_error_handling': [
                r'dataframe\.iloc\[.*\](?!.*try)',
                r'self\.dp\.get_analyzed_dataframe\((?!.*try)',
                r'Trade\.get_open_trades\(\)(?!.*try)'
            ]
        }

    def analyze_file(self, file_path: str) -> Optional[StrategyAnalysis]:
        """Analyze a single strategy file"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Try to parse the AST
            try:
                tree = ast.parse(content)
            except SyntaxError as e:
                return StrategyAnalysis(
                    file_path=file_path,
                    strategy_name="SYNTAX_ERROR",
                    is_valid=False,
                    overall_rating="broken",
                    issues=[StrategyIssue("critical", "syntax", f"Syntax error: {e}", e.lineno)],
                    features={},
                    recommendations=["Fix syntax errors before analysis"]
                )
            
            analysis = self._analyze_strategy_content(file_path, content, tree)
            return analysis
            
        except Exception as e:
            return StrategyAnalysis(
                file_path=file_path,
                strategy_name="READ_ERROR",
                is_valid=False,
                overall_rating="broken",
                issues=[StrategyIssue("critical", "file_access", f"Cannot read file: {e}")],
                features={},
                recommendations=["Check file permissions and encoding"]
            )

    def _analyze_strategy_content(self, file_path: str, content: str, tree: ast.AST) -> StrategyAnalysis:
        """Perform detailed analysis of strategy content"""
        issues = []
        features = {}
        
        # Extract strategy class name
        strategy_name = self._extract_strategy_name(tree)
        
        # Check for critical issues
        issues.extend(self._check_lookahead_bias(content))
        issues.extend(self._check_global_variables(content, tree))
        issues.extend(self._check_dangerous_operations(content))
        
        # Check for warnings
        issues.extend(self._check_hardcoded_values(content))
        issues.extend(self._check_memory_leaks(content, tree))
        issues.extend(self._check_error_handling(content))
        
        # Analyze strategy features
        features = self._extract_features(content, tree)
        
        # Check optimization capabilities
        issues.extend(self._check_optimization(content, tree))
        
        # Check strategy structure
        issues.extend(self._check_strategy_structure(tree))
        
        # Determine overall rating
        overall_rating = self._calculate_rating(issues, features)
        
        # Generate recommendations
        recommendations = self._generate_recommendations(issues, features)
        
        return StrategyAnalysis(
            file_path=file_path,
            strategy_name=strategy_name,
            is_valid=len([i for i in issues if i.severity == "critical"]) == 0,
            overall_rating=overall_rating,
            issues=issues,
            features=features,
            recommendations=recommendations
        )

    def _extract_strategy_name(self, tree: ast.AST) -> str:
        """Extract strategy class name from AST"""
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                # Check if it inherits from IStrategy
                for base in node.bases:
                    if isinstance(base, ast.Name) and base.id == 'IStrategy':
                        return node.name
                    elif isinstance(base, ast.Attribute) and base.attr == 'IStrategy':
                        return node.name
        return "UNKNOWN"

    def _check_lookahead_bias(self, content: str) -> List[StrategyIssue]:
        """Check for lookahead bias patterns"""
        issues = []
        lines = content.split('\n')
        
        for pattern in self.critical_patterns['lookahead_bias']:
            for i, line in enumerate(lines, 1):
                if re.search(pattern, line):
                    # Check if it's in custom_exit (more lenient) or populate methods (critical)
                    context = self._get_function_context(lines, i)
                    severity = "warning" if context == "custom_exit" else "critical"
                    
                    issues.append(StrategyIssue(
                        severity=severity,
                        category="lookahead_bias",
                        description=f"Potential lookahead bias: {pattern}",
                        line_number=i,
                        code_snippet=line.strip()
                    ))
        
        return issues

    def _check_global_variables(self, content: str, tree: ast.AST) -> List[StrategyIssue]:
        """Check for global variable usage"""
        issues = []
        lines = content.split('\n')
        
        # Check for global variables in module scope
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
                # Check if it's at module level (not in a class or function)
                if not any(isinstance(parent, (ast.FunctionDef, ast.ClassDef)) 
                          for parent in ast.walk(tree) if hasattr(parent, 'body') and node in parent.body):
                    var_name = node.targets[0].id
                    if var_name.isupper() or var_name.startswith('tmp_'):
                        issues.append(StrategyIssue(
                            severity="critical",
                            category="global_variables",
                            description=f"Global variable '{var_name}' should be instance variable",
                            line_number=getattr(node, 'lineno', None)
                        ))
        
        return issues

    def _check_dangerous_operations(self, content: str) -> List[StrategyIssue]:
        """Check for dangerous operations"""
        issues = []
        lines = content.split('\n')
        
        for pattern in self.critical_patterns['dangerous_operations']:
            for i, line in enumerate(lines, 1):
                if re.search(pattern, line):
                    issues.append(StrategyIssue(
                        severity="critical",
                        category="dangerous_operations",
                        description=f"Dangerous operation detected: {pattern}",
                        line_number=i,
                        code_snippet=line.strip()
                    ))
        
        return issues

    def _check_hardcoded_values(self, content: str) -> List[StrategyIssue]:
        """Check for hardcoded values instead of parameters"""
        issues = []
        lines = content.split('\n')
        
        # Look for hardcoded values in buy/sell conditions
        for i, line in enumerate(lines, 1):
            if ('populate_entry_trend' in content[max(0, content.find('\n', 0, content.find(line))-200):
                                                 content.find('\n', content.find(line))+200] or
                'populate_exit_trend' in content[max(0, content.find('\n', 0, content.find(line))-200):
                                               content.find('\n', content.find(line))+200] or
                'custom_exit' in content[max(0, content.find('\n', 0, content.find(line))-200):
                                       content.find('\n', content.find(line))+200]):
                
                # Check for hardcoded numbers
                hardcoded_pattern = r'[<>=!]+\s*\d+\.?\d*(?!\s*\)|\s*,|\s*\])'
                if re.search(hardcoded_pattern, line) and 'self.' not in line:
                    issues.append(StrategyIssue(
                        severity="warning",
                        category="hardcoded_values",
                        description="Hardcoded value found - consider using parameters",
                        line_number=i,
                        code_snippet=line.strip()
                    ))
        
        return issues

    def _check_memory_leaks(self, content: str, tree: ast.AST) -> List[StrategyIssue]:
        """Check for potential memory leaks"""
        issues = []
        
        # Check for growing data structures without cleanup
        if 'tmp_hold' in content and 'discard' not in content and 'remove' not in content:
            issues.append(StrategyIssue(
                severity="warning",
                category="memory_leaks",
                description="tmp_hold sets may grow indefinitely without cleanup",
            ))
        
        # Check for cleanup methods
        if 'def _cleanup' in content or 'def cleanup' in content:
            issues.append(StrategyIssue(
                severity="info",
                category="memory_management",
                description="Good: Cleanup method found",
            ))
        
        return issues

    def _check_error_handling(self, content: str) -> List[StrategyIssue]:
        """Check for proper error handling"""
        issues = []
        
        # Check for try-except blocks around risky operations
        risky_ops = ['dataframe.iloc', 'get_analyzed_dataframe', 'Trade.get_open_trades']
        
        for op in risky_ops:
            if op in content:
                # Simple check - is there a try block somewhere nearby?
                lines = content.split('\n')
                for i, line in enumerate(lines):
                    if op in line:
                        # Look for try block in surrounding lines
                        start = max(0, i-5)
                        end = min(len(lines), i+5)
                        surrounding = '\n'.join(lines[start:end])
                        
                        if 'try:' not in surrounding and 'except' not in surrounding:
                            issues.append(StrategyIssue(
                                severity="warning",
                                category="error_handling",
                                description=f"Missing error handling for {op}",
                                line_number=i+1,
                                code_snippet=line.strip()
                            ))
                        break
        
        return issues

    def _check_optimization(self, content: str, tree: ast.AST) -> List[StrategyIssue]:
        """Check optimization capabilities"""
        issues = []
        
        # Check for parameter definitions
        param_types = ['IntParameter', 'DecimalParameter', 'CategoricalParameter']
        has_params = any(param_type in content for param_type in param_types)
        
        if not has_params:
            issues.append(StrategyIssue(
                severity="warning",
                category="optimization",
                description="No optimization parameters found - strategy not hyperoptable",
            ))
        
        # Check for optimize flags
        if 'optimize=' in content:
            if 'optimize=False' in content:
                issues.append(StrategyIssue(
                    severity="info",
                    category="optimization",
                    description="Some parameters have optimization disabled",
                ))
            if 'optimize=True' in content:
                issues.append(StrategyIssue(
                    severity="info",
                    category="optimization",
                    description="Good: Optimization enabled for parameters",
                ))
        
        return issues

    def _check_strategy_structure(self, tree: ast.AST) -> List[StrategyIssue]:
        """Check basic strategy structure"""
        issues = []
        required_methods = ['populate_indicators', 'populate_entry_trend']
        optional_methods = ['populate_exit_trend', 'custom_exit', 'leverage']
        
        found_methods = []
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                found_methods.append(node.name)
        
        # Check required methods
        for method in required_methods:
            if method not in found_methods:
                issues.append(StrategyIssue(
                    severity="critical",
                    category="structure",
                    description=f"Missing required method: {method}",
                ))
        
        # Check for good practices
        if 'custom_exit' in found_methods:
            issues.append(StrategyIssue(
                severity="info",
                category="structure",
                description="Good: Custom exit logic implemented",
            ))
        
        if 'leverage' in found_methods:
            issues.append(StrategyIssue(
                severity="info",
                category="structure",
                description="Good: Leverage method implemented",
            ))
        
        return issues

    def _extract_features(self, content: str, tree: ast.AST) -> Dict[str, Any]:
        """Extract strategy features"""
        features = {}
        
        # Basic info
        features['has_roi'] = 'minimal_roi' in content
        features['has_stoploss'] = 'stoploss' in content
        features['has_trailing_stop'] = 'trailing_stop' in content
        features['has_custom_exit'] = 'def custom_exit' in content
        features['has_leverage'] = 'def leverage' in content
        
        # Count parameters
        param_count = content.count('Parameter(')
        features['parameter_count'] = param_count
        features['is_hyperoptable'] = param_count > 0
        
        # Indicators used
        indicators = []
        indicator_patterns = [
            r'ta\.(\w+)\(', r'pta\.(\w+)\(', r'dataframe\[[\'"]([\w_]+)[\'"]\]'
        ]
        
        for pattern in indicator_patterns:
            matches = re.findall(pattern, content)
            indicators.extend(matches)
        
        features['indicators_used'] = list(set(indicators))
        features['indicator_count'] = len(set(indicators))
        
        # Timeframe
        timeframe_match = re.search(r'timeframe\s*=\s*[\'"](\w+)[\'"]', content)
        features['timeframe'] = timeframe_match.group(1) if timeframe_match else 'unknown'
        
        return features

    def _get_function_context(self, lines: List[str], line_num: int) -> str:
        """Get the function context for a line"""
        for i in range(line_num-1, -1, -1):
            if re.match(r'\s*def\s+(\w+)', lines[i]):
                match = re.match(r'\s*def\s+(\w+)', lines[i])
                return match.group(1) if match else "unknown"
        return "module"

    def _calculate_rating(self, issues: List[StrategyIssue], features: Dict[str, Any]) -> str:
        """Calculate overall strategy rating"""
        critical_count = len([i for i in issues if i.severity == "critical"])
        warning_count = len([i for i in issues if i.severity == "warning"])
        
        if critical_count > 0:
            return "broken"
        elif warning_count > 3:
            return "poor"
        elif warning_count > 1:
            return "good"
        elif features.get('is_hyperoptable', False) and features.get('has_custom_exit', False):
            return "excellent"
        else:
            return "good"

    def _generate_recommendations(self, issues: List[StrategyIssue], features: Dict[str, Any]) -> List[str]:
        """Generate recommendations based on analysis"""
        recommendations = []
        
        critical_issues = [i for i in issues if i.severity == "critical"]
        if critical_issues:
            recommendations.append("Fix critical issues before using in production")
        
        if not features.get('is_hyperoptable', False):
            recommendations.append("Add optimization parameters for better performance")
        
        if not features.get('has_custom_exit', False):
            recommendations.append("Consider implementing custom exit logic")
        
        lookahead_issues = [i for i in issues if i.category == "lookahead_bias"]
        if lookahead_issues:
            recommendations.append("Fix lookahead bias - use iloc[-2] instead of iloc[-1]")
        
        memory_issues = [i for i in issues if i.category == "memory_leaks"]
        if memory_issues:
            recommendations.append("Implement cleanup mechanism for growing data structures")
        
        if features.get('indicator_count', 0) > 15:
            recommendations.append("Consider reducing number of indicators for better performance")
        
        return recommendations

    def analyze_directory(self, directory: str) -> List[StrategyAnalysis]:
        """Recursively analyze all strategy files in directory"""
        results = []
        
        for root, dirs, files in os.walk(directory):
            for file in files:
                if file.endswith('.py') and not file.startswith('__'):
                    file_path = os.path.join(root, file)
                    analysis = self.analyze_file(file_path)
                    if analysis:
                        results.append(analysis)
        
        return results

    def generate_csv_summary(self, analyses: List[StrategyAnalysis], output_file: str):
        """Generate CSV summary of all strategies"""
        with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
            fieldnames = [
                'strategy_name', 'file_path', 'rating', 'is_valid', 'critical_issues', 
                'warning_issues', 'info_issues', 'is_hyperoptable', 'has_custom_exit',
                'has_leverage', 'indicator_count', 'parameter_count', 'timeframe',
                'has_roi', 'has_stoploss', 'has_trailing_stop', 'top_issues', 'recommendations_count'
            ]
            
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            
            for analysis in analyses:
                # Count issues by severity
                critical_count = len([i for i in analysis.issues if i.severity == "critical"])
                warning_count = len([i for i in analysis.issues if i.severity == "warning"])
                info_count = len([i for i in analysis.issues if i.severity == "info"])
                
                # Get top 3 issues
                top_issues = []
                for issue in sorted(analysis.issues, key=lambda x: {"critical": 0, "warning": 1, "info": 2}.get(x.severity, 3))[:3]:
                    top_issues.append(f"{issue.category}({issue.severity})")
                
                writer.writerow({
                    'strategy_name': analysis.strategy_name,
                    'file_path': analysis.file_path,
                    'rating': analysis.overall_rating,
                    'is_valid': analysis.is_valid,
                    'critical_issues': critical_count,
                    'warning_issues': warning_count,
                    'info_issues': info_count,
                    'is_hyperoptable': analysis.features.get('is_hyperoptable', False),
                    'has_custom_exit': analysis.features.get('has_custom_exit', False),
                    'has_leverage': analysis.features.get('has_leverage', False),
                    'indicator_count': analysis.features.get('indicator_count', 0),
                    'parameter_count': analysis.features.get('parameter_count', 0),
                    'timeframe': analysis.features.get('timeframe', 'unknown'),
                    'has_roi': analysis.features.get('has_roi', False),
                    'has_stoploss': analysis.features.get('has_stoploss', False),
                    'has_trailing_stop': analysis.features.get('has_trailing_stop', False),
                    'top_issues': '; '.join(top_issues),
                    'recommendations_count': len(analysis.recommendations)
                })

    def generate_markdown_report(self, analyses: List[StrategyAnalysis], output_file: str):
        """Generate markdown report for better readability"""
        report = []
        
        # Summary table
        total = len(analyses)
        valid = len([a for a in analyses if a.is_valid])
        excellent = len([a for a in analyses if a.overall_rating == "excellent"])
        good = len([a for a in analyses if a.overall_rating == "good"])
        poor = len([a for a in analyses if a.overall_rating == "poor"])
        broken = len([a for a in analyses if a.overall_rating == "broken"])
        
        report.append("# FreqTrade Strategy Analysis Report")
        report.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        
        report.append("## Summary")
        report.append("| Metric | Count | Percentage |")
        report.append("|--------|-------|------------|")
        report.append(f"| Total Strategies | {total} | 100.0% |")
        report.append(f"| Valid Strategies | {valid} | {valid/total*100:.1f}% |")
        report.append(f"| Excellent | {excellent} | {excellent/total*100:.1f}% |")
        report.append(f"| Good | {good} | {good/total*100:.1f}% |")
        report.append(f"| Poor | {poor} | {poor/total*100:.1f}% |")
        report.append(f"| Broken | {broken} | {broken/total*100:.1f}% |")
        report.append("")
        
        # Quick overview table
        report.append("## Strategy Overview")
        report.append("| Strategy | Rating | Issues | Hyperoptable | Custom Exit | Issues Summary |")
        report.append("|----------|--------|--------|--------------|-------------|----------------|")
        
        for analysis in sorted(analyses, key=lambda x: {"excellent": 0, "good": 1, "poor": 2, "broken": 3}.get(x.overall_rating, 4)):
            critical_count = len([i for i in analysis.issues if i.severity == "critical"])
            warning_count = len([i for i in analysis.issues if i.severity == "warning"])
            
            rating_emoji = {"excellent": "🟢", "good": "🔵", "poor": "🟡", "broken": "🔴"}.get(analysis.overall_rating, "⚪")
            hyperopt_status = "✅" if analysis.features.get('is_hyperoptable', False) else "❌"
            custom_exit_status = "✅" if analysis.features.get('has_custom_exit', False) else "❌"
            
            issues_summary = f"🔴{critical_count} ⚠️{warning_count}"
            top_issues = [i.category for i in analysis.issues if i.severity in ["critical", "warning"]][:2]
            if top_issues:
                issues_summary += f" ({', '.join(top_issues)})"
            
            report.append(f"| {analysis.strategy_name} | {rating_emoji} {analysis.overall_rating} | {issues_summary} | {hyperopt_status} | {custom_exit_status} | {', '.join(top_issues[:3])} |")
        
        report.append("")
        
        # Detailed sections for each rating
        for rating in ["excellent", "good", "poor", "broken"]:
            strategies = [a for a in analyses if a.overall_rating == rating]
            if strategies:
                rating_emoji = {"excellent": "🟢", "good": "🔵", "poor": "🟡", "broken": "🔴"}[rating]
                report.append(f"## {rating_emoji} {rating.capitalize()} Strategies ({len(strategies)})")
                
                for analysis in strategies:
                    report.append(f"### {analysis.strategy_name}")
                    report.append(f"**File:** `{analysis.file_path}`")
                    
                    # Key features
                    features_list = []
                    if analysis.features.get('is_hyperoptable'): features_list.append("Hyperoptable")
                    if analysis.features.get('has_custom_exit'): features_list.append("Custom Exit")
                    if analysis.features.get('has_leverage'): features_list.append("Leverage Support")
                    if analysis.features.get('timeframe'): features_list.append(f"Timeframe: {analysis.features['timeframe']}")
                    
                    if features_list:
                        report.append(f"**Features:** {', '.join(features_list)}")
                    
                    # Issues
                    critical_issues = [i for i in analysis.issues if i.severity == "critical"]
                    warning_issues = [i for i in analysis.issues if i.severity == "warning"]
                    
                    if critical_issues:
                        report.append("**🔴 Critical Issues:**")
                        for issue in critical_issues:
                            report.append(f"- {issue.description}")
                    
                    if warning_issues:
                        report.append("**⚠️ Warnings:**")
                        for issue in warning_issues[:3]:  # Limit to top 3
                            report.append(f"- {issue.description}")
                    
                    # Recommendations
                    if analysis.recommendations:
                        report.append("**Recommendations:**")
                        for rec in analysis.recommendations[:3]:  # Limit to top 3
                            report.append(f"- {rec}")
                    
                    report.append("")
        
        # Statistics
        report.append("## Statistics")
        
        # Most common issues
        all_issues = [issue for analysis in analyses for issue in analysis.issues]
        issue_counts = {}
        for issue in all_issues:
            key = f"{issue.category}"
            issue_counts[key] = issue_counts.get(key, 0) + 1
        
        if issue_counts:
            report.append("### Most Common Issues")
            report.append("| Issue | Count |")
            report.append("|-------|-------|")
            for issue, count in sorted(issue_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
                report.append(f"| {issue} | {count} |")
        
        # Feature adoption
        feature_stats = {}
        for analysis in analyses:
            for key, value in analysis.features.items():
                if isinstance(value, bool):
                    if key not in feature_stats:
                        feature_stats[key] = {"true": 0, "false": 0}
                    feature_stats[key]["true" if value else "false"] += 1
        
        if feature_stats:
            report.append("\n### Feature Adoption")
            report.append("| Feature | Adoption | Count |")
            report.append("|---------|----------|-------|")
            for feature, counts in sorted(feature_stats.items()):
                total_count = counts["true"] + counts["false"]
                percentage = counts["true"] / total_count * 100
                report.append(f"| {feature.replace('_', ' ').title()} | {percentage:.1f}% | {counts['true']}/{total_count} |")
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(report))

    def generate_html_report(self, analyses: List[StrategyAnalysis], output_file: str):
        """Generate HTML report with better formatting"""
        
        # Calculate statistics
        total = len(analyses)
        excellent = len([a for a in analyses if a.overall_rating == "excellent"])
        good = len([a for a in analyses if a.overall_rating == "good"])
        poor = len([a for a in analyses if a.overall_rating == "poor"])
        broken = len([a for a in analyses if a.overall_rating == "broken"])
        
        # Generate overview table rows
        overview_rows = ""
        for analysis in sorted(analyses, key=lambda x: {"excellent": 0, "good": 1, "poor": 2, "broken": 3}.get(x.overall_rating, 4)):
            critical_count = len([i for i in analysis.issues if i.severity == "critical"])
            warning_count = len([i for i in analysis.issues if i.severity == "warning"])
            
            features = []
            if analysis.features.get('is_hyperoptable'): features.append("Hyperopt")
            if analysis.features.get('has_custom_exit'): features.append("Custom Exit")
            if analysis.features.get('has_leverage'): features.append("Leverage")
            
            overview_rows += f"""
                <tr>
                    <td>{analysis.strategy_name}</td>
                    <td><span class="rating-badge rating-{analysis.overall_rating}">{analysis.overall_rating}</span></td>
                    <td>🔴{critical_count} ⚠️{warning_count}</td>
                    <td>{', '.join(features) if features else 'Basic'}</td>
                    <td><code>{analysis.file_path}</code></td>
                </tr>
            """
        
        # Generate strategy cards
        strategy_cards = ""
        for analysis in analyses:
            critical_issues = [i for i in analysis.issues if i.severity == "critical"]
            warning_issues = [i for i in analysis.issues if i.severity == "warning"]
            
        # Generate strategy cards
        strategy_cards = ""
        for analysis in analyses:
            critical_issues = [i for i in analysis.issues if i.severity == "critical"]
            warning_issues = [i for i in analysis.issues if i.severity == "warning"]
            
            issues_html = ""
            if critical_issues:
                issues_html += "<div class='issue-critical'>Critical: " + ", ".join([i.category for i in critical_issues[:3]]) + "</div>"
            if warning_issues:
                issues_html += "<div class='issue-warning'>Warnings: " + ", ".join([i.category for i in warning_issues[:3]]) + "</div>"
            
            features_html = ""
            if analysis.features.get('is_hyperoptable'):
                features_html += "<span class='feature-tag feature-positive'>Hyperoptable</span>"
            if analysis.features.get('has_custom_exit'):
                features_html += "<span class='feature-tag feature-positive'>Custom Exit</span>"
            if analysis.features.get('has_leverage'):
                features_html += "<span class='feature-tag feature-positive'>Leverage</span>"
            if analysis.features.get('timeframe'):
                features_html += f"<span class='feature-tag'>TF: {analysis.features['timeframe']}</span>"
            
            strategy_cards += f"""
                <div class="strategy-card">
                    <div class="strategy-header">
                        <h3>{analysis.strategy_name}</h3>
                        <span class="rating-badge rating-{analysis.overall_rating}">{analysis.overall_rating}</span>
                    </div>
                    <div class="features">{features_html}</div>
                    <div><strong>File:</strong> <code>{analysis.file_path}</code></div>
                    {issues_html}
                </div>
            """
        
        # Create the complete HTML content
        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>FreqTrade Strategy Analysis Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
        .summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }}
        .stat-card {{ background: #f8f9fa; padding: 15px; border-radius: 6px; text-align: center; border-left: 4px solid #007bff; }}
        .excellent {{ border-left-color: #28a745; }}
        .good {{ border-left-color: #007bff; }}
        .poor {{ border-left-color: #ffc107; }}
        .broken {{ border-left-color: #dc3545; }}
        .strategy-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 20px; }}
        .strategy-card {{ background: white; border: 1px solid #ddd; border-radius: 6px; padding: 15px; margin-bottom: 15px; }}
        .strategy-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }}
        .rating-badge {{ padding: 4px 8px; border-radius: 4px; color: white; font-weight: bold; }}
        .rating-excellent {{ background: #28a745; }}
        .rating-good {{ background: #007bff; }}
        .rating-poor {{ background: #ffc107; color: black; }}
        .rating-broken {{ background: #dc3545; }}
        .issue-critical {{ color: #dc3545; font-weight: bold; }}
        .issue-warning {{ color: #ffc107; }}
        .issue-info {{ color: #17a2b8; }}
        .features {{ display: flex; flex-wrap: wrap; gap: 5px; margin: 10px 0; }}
        .feature-tag {{ background: #e9ecef; padding: 2px 6px; border-radius: 3px; font-size: 0.85em; }}
        .feature-positive {{ background: #d4edda; color: #155724; }}
        table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        th {{ background: #f8f9fa; }}
        .overview-table {{ font-size: 0.9em; }}
        .overview-table td:first-child {{ font-weight: bold; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>FreqTrade Strategy Analysis Report</h1>
        <p><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        
        <div class="summary">
            <div class="stat-card">
                <h3>Total Strategies</h3>
                <div style="font-size: 2em; font-weight: bold;">{total}</div>
            </div>
            <div class="stat-card excellent">
                <h3>Excellent</h3>
                <div style="font-size: 2em; font-weight: bold;">{excellent}</div>
                <div>{excellent/total*100:.1f}%</div>
            </div>
            <div class="stat-card good">
                <h3>Good</h3>
                <div style="font-size: 2em; font-weight: bold;">{good}</div>
                <div>{good/total*100:.1f}%</div>
            </div>
            <div class="stat-card poor">
                <h3>Poor</h3>
                <div style="font-size: 2em; font-weight: bold;">{poor}</div>
                <div>{poor/total*100:.1f}%</div>
            </div>
            <div class="stat-card broken">
                <h3>Broken</h3>
                <div style="font-size: 2em; font-weight: bold;">{broken}</div>
                <div>{broken/total*100:.1f}%</div>
            </div>
        </div>
        
        <h2>Strategy Overview</h2>
        <table class="overview-table">
            <thead>
                <tr>
                    <th>Strategy</th>
                    <th>Rating</th>
                    <th>Issues</th>
                    <th>Features</th>
                    <th>File</th>
                </tr>
            </thead>
            <tbody>
                {overview_rows}
            </tbody>
        </table>
        
        <h2>Detailed Analysis</h2>
        <div class="strategy-grid">
            {strategy_cards}
        </div>
    </div>
</body>
</html>"""
        
        # Write the HTML file
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(html_content)

    def generate_report(self, analyses: List[StrategyAnalysis], output_file: str = None) -> str:
        """Generate comprehensive report"""
        report = []
        
        # Summary
        total = len(analyses)
        valid = len([a for a in analyses if a.is_valid])
        excellent = len([a for a in analyses if a.overall_rating == "excellent"])
        good = len([a for a in analyses if a.overall_rating == "good"])
        poor = len([a for a in analyses if a.overall_rating == "poor"])
        broken = len([a for a in analyses if a.overall_rating == "broken"])
        
        report.append("=" * 80)
        report.append("FREQTRADE STRATEGY ANALYSIS REPORT")
        report.append("=" * 80)
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")
        report.append("SUMMARY:")
        report.append(f"  Total strategies analyzed: {total}")
        report.append(f"  Valid strategies: {valid} ({valid/total*100:.1f}%)")
        report.append(f"  Excellent: {excellent}")
        report.append(f"  Good: {good}")
        report.append(f"  Poor: {poor}")
        report.append(f"  Broken: {broken}")
        report.append("")
        
        # Sort by rating
        rating_order = {"excellent": 0, "good": 1, "poor": 2, "broken": 3}
        analyses.sort(key=lambda x: rating_order.get(x.overall_rating, 4))
        
        # Detailed analysis
        for analysis in analyses:
            report.append("-" * 80)
            report.append(f"STRATEGY: {analysis.strategy_name}")
            report.append(f"File: {analysis.file_path}")
            report.append(f"Rating: {analysis.overall_rating.upper()}")
            report.append(f"Valid: {'YES' if analysis.is_valid else 'NO'}")
            
            # Features
            if analysis.features:
                report.append("\nFEATURES:")
                for key, value in analysis.features.items():
                    if isinstance(value, bool):
                        report.append(f"  {key}: {'YES' if value else 'NO'}")
                    elif isinstance(value, list) and len(value) < 10:
                        report.append(f"  {key}: {', '.join(map(str, value))}")
                    else:
                        report.append(f"  {key}: {value}")
            
            # Issues
            if analysis.issues:
                report.append("\nISSUES:")
                for issue in sorted(analysis.issues, key=lambda x: (x.severity, x.category)):
                    severity_symbol = {"critical": "❌", "warning": "⚠️", "info": "ℹ️"}.get(issue.severity, "")
                    report.append(f"  {severity_symbol} [{issue.severity.upper()}] {issue.description}")
                    if issue.line_number:
                        report.append(f"    Line {issue.line_number}: {issue.code_snippet}")
            
            # Recommendations
            if analysis.recommendations:
                report.append("\nRECOMMENDATIONS:")
                for rec in analysis.recommendations:
                    report.append(f"  • {rec}")
            
            report.append("")
        
        # Generate statistics
        report.append("=" * 80)
        report.append("STATISTICS")
        report.append("=" * 80)
        
        # Most common issues
        all_issues = [issue for analysis in analyses for issue in analysis.issues]
        issue_counts = {}
        for issue in all_issues:
            key = f"{issue.category} ({issue.severity})"
            issue_counts[key] = issue_counts.get(key, 0) + 1
        
        if issue_counts:
            report.append("\nMOST COMMON ISSUES:")
            for issue, count in sorted(issue_counts.items(), key=lambda x: x[1], reverse=True)[:10]:
                report.append(f"  {count:3d} - {issue}")
        
        # Feature statistics
        feature_stats = {}
        for analysis in analyses:
            for key, value in analysis.features.items():
                if isinstance(value, bool):
                    if key not in feature_stats:
                        feature_stats[key] = {"true": 0, "false": 0}
                    feature_stats[key]["true" if value else "false"] += 1
        
        if feature_stats:
            report.append("\nFEATURE ADOPTION:")
            for feature, counts in sorted(feature_stats.items()):
                total_count = counts["true"] + counts["false"]
                percentage = counts["true"] / total_count * 100
                report.append(f"  {feature}: {counts['true']}/{total_count} ({percentage:.1f}%)")
        
        report_text = "\n".join(report)
        
        if output_file:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(report_text)
            print(f"Report saved to: {output_file}")
        
        return report_text


def main():
    parser = argparse.ArgumentParser(description="Analyze FreqTrade strategies")
    parser.add_argument("directory", help="Directory to analyze recursively")
    parser.add_argument("-o", "--output", help="Output file for report")
    parser.add_argument("-f", "--format", choices=["text", "csv", "json", "markdown", "html"], 
                       default="text", help="Output format (default: text)")
    parser.add_argument("--csv", help="Export summary as CSV")
    parser.add_argument("--json", help="Export detailed results as JSON")
    parser.add_argument("--markdown", help="Export as Markdown")
    parser.add_argument("--html", help="Export as HTML")
    parser.add_argument("--all-formats", action="store_true", 
                       help="Generate all formats with auto-naming")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.directory):
        print(f"Error: Directory '{args.directory}' does not exist")
        return 1
    
    print(f"Analyzing strategies in: {args.directory}")
    analyzer = StrategyAnalyzer()
    analyses = analyzer.analyze_directory(args.directory)
    
    if not analyses:
        print("No strategy files found!")
        return 1
    
    print(f"Found {len(analyses)} strategy files")
    
    # Generate outputs based on arguments
    base_name = args.output.rsplit('.', 1)[0] if args.output else "strategy_analysis"
    
    if args.all_formats:
        # Generate all formats
        print("Generating all formats...")
        
        # Text report
        text_file = f"{base_name}.txt"
        report = analyzer.generate_report(analyses, text_file)
        print(f"✅ Text report: {text_file}")
        
        # CSV summary
        csv_file = f"{base_name}.csv"
        analyzer.generate_csv_summary(analyses, csv_file)
        print(f"✅ CSV summary: {csv_file}")
        
        # JSON data
        json_file = f"{base_name}.json"
        json_data = [asdict(analysis) for analysis in analyses]
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, indent=2, default=str)
        print(f"✅ JSON data: {json_file}")
        
        # Markdown report
        md_file = f"{base_name}.md"
        analyzer.generate_markdown_report(analyses, md_file)
        print(f"✅ Markdown report: {md_file}")
        
        # HTML report
        html_file = f"{base_name}.html"
        analyzer.generate_html_report(analyses, html_file)
        print(f"✅ HTML report: {html_file}")
        
    else:
        # Generate based on format or individual flags
        if args.format == "text" or args.output:
            report = analyzer.generate_report(analyses, args.output)
            if not args.output:
                print(report)
        
        if args.csv:
            analyzer.generate_csv_summary(analyses, args.csv)
            print(f"CSV summary exported to: {args.csv}")
        
        if args.json:
            json_data = [asdict(analysis) for analysis in analyses]
            with open(args.json, 'w', encoding='utf-8') as f:
                json.dump(json_data, f, indent=2, default=str)
            print(f"JSON data exported to: {args.json}")
        
        if args.markdown:
            analyzer.generate_markdown_report(analyses, args.markdown)
            print(f"Markdown report exported to: {args.markdown}")
        
        if args.html:
            analyzer.generate_html_report(analyses, args.html)
            print(f"HTML report exported to: {args.html}")
        
        if args.format == "csv":
            output_file = args.output or "strategy_analysis.csv"
            analyzer.generate_csv_summary(analyses, output_file)
            print(f"CSV summary saved to: {output_file}")
        
        elif args.format == "json":
            output_file = args.output or "strategy_analysis.json"
            json_data = [asdict(analysis) for analysis in analyses]
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(json_data, f, indent=2, default=str)
            print(f"JSON data saved to: {output_file}")
        
        elif args.format == "markdown":
            output_file = args.output or "strategy_analysis.md"
            analyzer.generate_markdown_report(analyses, output_file)
            print(f"Markdown report saved to: {output_file}")
        
        elif args.format == "html":
            output_file = args.output or "strategy_analysis.html"
            analyzer.generate_html_report(analyses, output_file)
            print(f"HTML report saved to: {output_file}")
    
    # Print quick summary
    total = len(analyses)
    valid = len([a for a in analyses if a.is_valid])
    excellent = len([a for a in analyses if a.overall_rating == "excellent"])
    good = len([a for a in analyses if a.overall_rating == "good"])
    poor = len([a for a in analyses if a.overall_rating == "poor"])
    broken = len([a for a in analyses if a.overall_rating == "broken"])
    
    print("\n" + "="*50)
    print("QUICK SUMMARY")
    print("="*50)
    print(f"📊 Total strategies: {total}")
    print(f"✅ Valid: {valid} ({valid/total*100:.1f}%)")
    print(f"🟢 Excellent: {excellent}")
    print(f"🔵 Good: {good}")
    print(f"🟡 Poor: {poor}")
    print(f"🔴 Broken: {broken}")
    
    return 0


if __name__ == "__main__":
    exit(main())