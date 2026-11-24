"""Scan user_data/strategies (including subfolders) for Freqtrade strategy files."""

from __future__ import annotations

import ast
import re
import warnings
from dataclasses import dataclass, field
from pathlib import Path

if False:  # type hints only
    from core.strategy_compatibility import CompatibilityResult

_TF_RE = re.compile(r"^\d+[mhdw]$", re.IGNORECASE)

SKIP_DIR_NAMES = {
    "__pycache__",
    ".git",
    ".venv",
    "venv",
    "node_modules",
    ".mypy_cache",
    ".pytest_cache",
    "strategies_obsolete",
    "_kerrigan_obsolete",
}


@dataclass
class ScannedStrategy:
    name: str
    path: str
    file_name: str
    class_name: str | None
    relative_path: str = ""
    folder: str = ""
    status: str = "unknown"
    timeframe: str | None = None
    compatibility: str = ""
    can_short: bool = False
    compat_result: object | None = field(default=None, repr=False)

    @property
    def display_name(self) -> str:
        if self.folder:
            return f"{self.folder}/{self.name}"
        return self.name

    @property
    def list_label(self) -> str:
        return self.display_name

    @property
    def backtest_strategy_path(self) -> str:
        """Папка файла стратегии для --strategy-path Freqtrade."""
        return str(Path(self.path).parent.resolve())


def _ast_base_name(node: ast.expr) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    if isinstance(node, ast.Subscript):
        return _ast_base_name(node.value)
    return ""


def _class_looks_like_strategy(node: ast.ClassDef) -> bool:
    if node.name.startswith("_"):
        return False
    if node.name in ("IStrategy", "BaseStrategy", "HyperStrategy"):
        return False

    for base in node.bases:
        bname = _ast_base_name(base)
        if "IStrategy" in bname or bname.endswith("Strategy"):
            return True

    methods: set[str] = set()
    for item in node.body:
        if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
            methods.add(item.name)

    ft_methods = {
        "populate_indicators",
        "populate_entry_trend",
        "populate_buy_trend",
        "populate_exit_trend",
        "populate_sell_trend",
    }
    return bool(methods & ft_methods)


def _extract_class_name_from_tree(
    tree: ast.AST, file_path: Path | None = None
) -> str | None:
    strategy_classes: list[str] = []
    any_classes: list[str] = []

    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        any_classes.append(node.name)
        if _class_looks_like_strategy(node):
            strategy_classes.append(node.name)

    stem = file_path.stem if file_path else ""

    def _pick(candidates: list[str]) -> str | None:
        if not candidates:
            return None
        if stem:
            for name in candidates:
                if name == stem:
                    return name
            for name in candidates:
                if name.lower() == stem.lower():
                    return name
        return candidates[0]

    picked = _pick(strategy_classes)
    if picked:
        return picked
    return _pick(any_classes)


def _extract_class_name(source: str, file_path: Path | None = None) -> str | None:
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    return _extract_class_name_from_tree(tree, file_path)


def _name_from_file(path: Path) -> str:
    stem = path.stem
    if stem.endswith("_strategy"):
        return stem[: -len("_strategy")]
    return stem


def _is_valid_module_stem(stem: str) -> bool:
    if not stem:
        return False
    if re.search(r"[\s()]", stem):
        return False
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", stem):
        return False
    return True


def _is_valid_class_name(name: str) -> bool:
    return bool(name) and name.isidentifier()


def _str_from_ast(node: ast.expr | None) -> str | None:
    if node is None:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value.strip()
    return None


def _is_valid_timeframe(value: str) -> bool:
    v = value.strip().lower()
    return bool(v) and bool(_TF_RE.match(v))


def _timeframe_from_class(node: ast.ClassDef) -> str | None:
    for item in node.body:
        if isinstance(item, ast.Assign):
            for target in item.targets:
                if isinstance(target, ast.Name) and target.id == "timeframe":
                    raw = _str_from_ast(item.value)
                    if raw and _is_valid_timeframe(raw):
                        return raw.lower()
        elif isinstance(item, ast.AnnAssign):
            if isinstance(item.target, ast.Name) and item.target.id == "timeframe":
                raw = _str_from_ast(item.value)
                if raw and _is_valid_timeframe(raw):
                    return raw.lower()
    return None


def extract_timeframe_from_tree(
    tree: ast.AST, class_name: str | None = None
) -> str | None:
    strategy_classes: list[ast.ClassDef] = []
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and _class_looks_like_strategy(node):
            strategy_classes.append(node)

    if class_name:
        for node in strategy_classes:
            if node.name == class_name:
                tf = _timeframe_from_class(node)
                if tf:
                    return tf

    for node in strategy_classes:
        tf = _timeframe_from_class(node)
        if tf:
            return tf

    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "timeframe":
                    raw = _str_from_ast(node.value)
                    if raw and _is_valid_timeframe(raw):
                        return raw.lower()
    return None


def extract_timeframe_from_source(
    source: str, class_name: str | None = None
) -> str | None:
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    return extract_timeframe_from_tree(tree, class_name)


def find_strategy_py_file(name: str, root: Path) -> Path | None:
    """Find strategy .py by class/file name under root (recursive)."""
    target = (name or "").strip()
    if not target or not root.is_dir():
        return None
    target_lower = target.lower()
    for py_file in sorted(root.rglob("*.py"), key=lambda p: str(p).lower()):
        if _should_skip_path(py_file):
            continue
        if py_file.stem == target or py_file.stem.lower() == target_lower:
            return py_file.resolve()
    return None


def _should_skip_path(py_file: Path) -> bool:
    if py_file.name.startswith("_"):
        return True
    for part in py_file.parts:
        if part in SKIP_DIR_NAMES:
            return True
    if not _is_valid_module_stem(py_file.stem):
        return True
    return False


def is_strategy_loadable(scanned: ScannedStrategy) -> bool:
    """Можно ли передать имя в freqtrade backtesting."""
    return _is_valid_class_name(scanned.name)


def scan_strategies(
    strategies_path: str | Path,
    *,
    with_compatibility: bool = True,
) -> tuple[list[ScannedStrategy], dict[str, object], int]:
    from core.strategy_compatibility import (
        CompatibilityResult,
        analyze_compatibility_from_tree,
    )
    from core.strategy_traits import extract_can_short_from_tree

    root = Path(strategies_path).resolve()
    if not root.is_dir():
        return [], {}, 0

    results: list[ScannedStrategy] = []
    compat_map: dict[str, CompatibilityResult] = {}
    seen_paths: set[str] = set()
    py_file_count = 0

    py_files = sorted(root.rglob("*.py"), key=lambda p: str(p).lower())

    for py_file in py_files:
        if _should_skip_path(py_file):
            continue
        py_file_count += 1

        resolved = str(py_file.resolve())
        if resolved in seen_paths:
            continue

        try:
            source = py_file.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        if "IStrategy" not in source and "populate_indicators" not in source:
            if "class " not in source:
                continue

        try:
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", SyntaxWarning)
                tree = ast.parse(source)
        except SyntaxError:
            continue

        class_name = _extract_class_name_from_tree(tree, py_file)
        if not class_name:
            class_name = _name_from_file(py_file)

        if not _is_valid_class_name(class_name):
            continue

        tf = extract_timeframe_from_tree(tree, class_name)
        can_short = extract_can_short_from_tree(tree, class_name)
        cr: CompatibilityResult | None = None
        if with_compatibility:
            cr = analyze_compatibility_from_tree(source, tree)

        try:
            rel = py_file.relative_to(root)
            relative_path = str(rel)
            folder = str(rel.parent) if rel.parent != Path(".") else ""
        except ValueError:
            relative_path = py_file.name
            folder = ""

        seen_paths.add(resolved)
        if cr:
            compat_map[resolved] = cr
        results.append(
            ScannedStrategy(
                name=class_name,
                path=resolved,
                file_name=py_file.name,
                class_name=class_name,
                relative_path=relative_path,
                folder=folder.replace("\\", "/"),
                status="scanned",
                timeframe=tf,
                compatibility=cr.level.value if cr else "",
                can_short=can_short,
                compat_result=cr,
            )
        )

    return sorted(results, key=lambda s: s.list_label.lower()), compat_map, py_file_count


def count_py_files(strategies_path: str | Path) -> int:
    root = Path(strategies_path)
    if not root.is_dir():
        return 0
    n = 0
    for py_file in root.rglob("*.py"):
        if not _should_skip_path(py_file):
            n += 1
    return n


def filter_strategies(
    strategies: list[ScannedStrategy], query: str
) -> list[ScannedStrategy]:
    q = query.strip().lower()
    if not q:
        return strategies
    return [
        s
        for s in strategies
        if q in s.name.lower()
        or q in s.file_name.lower()
        or q in s.path.lower()
        or q in s.folder.lower()
        or q in s.relative_path.lower()
    ]
