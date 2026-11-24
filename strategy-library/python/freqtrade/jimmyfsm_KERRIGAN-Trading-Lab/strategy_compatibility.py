"""Freqtrade API compatibility: Modern / Legacy / Obsolete."""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from core.strategy_scanner import _class_looks_like_strategy


class CompatibilityLevel(str, Enum):
    MODERN = "Modern"
    LEGACY = "Legacy"
    OBSOLETE = "Obsolete"


LEVEL_EMOJI = {
    CompatibilityLevel.MODERN: "🟢",
    CompatibilityLevel.LEGACY: "🟡",
    CompatibilityLevel.OBSOLETE: "🔴",
}


LEGACY_SOURCE_MARKERS = (
    "populate_buy_trend",
    "populate_sell_trend",
    "sell_profit_only",
    "ignore_roi_if_buy_signal",
    "use_sell_signal",
)

OLD_IMPORT_PATTERNS = (
    "from freqtrade.strategy.interface import",
    "freqtrade.strategy.interface",
    "from freqtrade.freqtradebot import",
    "from freqtrade.exchange import Exchange",
)


@dataclass
class CompatibilityResult:
    level: CompatibilityLevel
    reasons: list[str] = field(default_factory=list)
    interface_version: int | None = None

    @property
    def emoji(self) -> str:
        return LEVEL_EMOJI[self.level]

    @property
    def label(self) -> str:
        return self.level.value

    @property
    def display(self) -> str:
        return f"{self.emoji} {self.label}"

    @property
    def log_line(self) -> str:
        extra = ""
        if self.reasons:
            extra = f" ({'; '.join(self.reasons[:3])})"
        return f"{self.emoji} {self.label}{extra}"


def _read_source(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def _int_from_ast(node: ast.expr | None) -> int | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return int(node.value)
    return None


def _extract_interface_version(tree: ast.AST) -> int | None:
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "INTERFACE_VERSION":
                    return _int_from_ast(node.value)
        elif isinstance(node, ast.AnnAssign):
            if isinstance(node.target, ast.Name) and node.target.id == "INTERFACE_VERSION":
                return _int_from_ast(node.value)
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        if not _class_looks_like_strategy(node):
            continue
        for item in node.body:
            if isinstance(item, ast.Assign):
                for target in item.targets:
                    if isinstance(target, ast.Name) and target.id == "INTERFACE_VERSION":
                        return _int_from_ast(item.value)
            elif isinstance(item, ast.AnnAssign):
                if isinstance(item.target, ast.Name) and item.target.id == "INTERFACE_VERSION":
                    return _int_from_ast(item.value)
    return None


def _strategy_methods(tree: ast.AST) -> set[str]:
    methods: set[str] = set()
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        if not _class_looks_like_strategy(node):
            continue
        for item in node.body:
            if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                methods.add(item.name)
    return methods


def _legacy_markers_in_source(source: str) -> list[str]:
    found: list[str] = []
    for marker in LEGACY_SOURCE_MARKERS:
        if re.search(rf"\b{re.escape(marker)}\b", source):
            found.append(marker)
    for pat in OLD_IMPORT_PATTERNS:
        if pat in source:
            found.append("старый импорт freqtrade")
            break
    return found


def analyze_compatibility(
    source: str,
    *,
    syntax_ok: bool = True,
    validation_broken: bool = False,
) -> CompatibilityResult:
    reasons: list[str] = []

    if validation_broken:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=["не проходит проверку / не загружается"],
        )

    if not syntax_ok:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=["синтаксическая ошибка"],
        )

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=[f"синтаксис: {e}"],
        )
    return analyze_compatibility_from_tree(source, tree)


def analyze_compatibility_from_tree(
    source: str, tree: ast.AST
) -> CompatibilityResult:
    reasons: list[str] = []

    iv = _extract_interface_version(tree)
    methods = _strategy_methods(tree)
    legacy = _legacy_markers_in_source(source)

    has_entry = "populate_entry_trend" in methods
    has_exit = "populate_exit_trend" in methods
    has_buy = "populate_buy_trend" in methods
    has_sell = "populate_sell_trend" in methods
    has_indicators = "populate_indicators" in methods

    if iv is not None and iv < 3:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=[f"INTERFACE_VERSION={iv}"],
            interface_version=iv,
        )

    if (has_buy or "populate_buy_trend" in legacy) and not has_entry:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=["populate_buy_trend без populate_entry_trend"],
            interface_version=iv,
        )

    if (has_sell or "populate_sell_trend" in legacy) and not has_exit:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=["populate_sell_trend без populate_exit_trend"],
            interface_version=iv,
        )

    if not has_indicators and not has_entry and not has_buy:
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=["нет методов Freqtrade стратегии"],
            interface_version=iv,
        )

    modern = (
        iv is not None
        and iv >= 3
        and has_entry
        and has_exit
        and not legacy
        and not has_buy
        and not has_sell
    )
    if modern:
        return CompatibilityResult(
            CompatibilityLevel.MODERN,
            interface_version=iv,
        )

    if legacy:
        reasons.extend(legacy[:5])

    if iv is None:
        reasons.append("нет INTERFACE_VERSION")

    if has_buy or has_sell:
        reasons.append("buy/sell API")

    if has_entry and has_exit and not legacy and iv is None:
        return CompatibilityResult(
            CompatibilityLevel.LEGACY,
            reasons=reasons or ["нет INTERFACE_VERSION"],
            interface_version=iv,
        )

    if legacy or iv is None or has_buy or has_sell:
        return CompatibilityResult(
            CompatibilityLevel.LEGACY,
            reasons=reasons or ["устаревшие конструкции"],
            interface_version=iv,
        )

    return CompatibilityResult(
        CompatibilityLevel.OBSOLETE,
        reasons=reasons or ["несовместимый API"],
        interface_version=iv,
    )


def analyze_strategy_file(
    path: str | Path,
    *,
    validation_broken: bool = False,
) -> CompatibilityResult:
    p = Path(path)
    if not p.is_file():
        return CompatibilityResult(
            CompatibilityLevel.OBSOLETE,
            reasons=["файл не найден"],
        )
    source = _read_source(p)
    syntax_ok = True
    try:
        ast.parse(source)
    except SyntaxError:
        syntax_ok = False
    return analyze_compatibility(
        source,
        syntax_ok=syntax_ok,
        validation_broken=validation_broken,
    )


def analyze_scanned(
    strategy_path: str,
    *,
    validation_broken: bool = False,
) -> CompatibilityResult:
    return analyze_strategy_file(strategy_path, validation_broken=validation_broken)


def apply_compatibility_to_scan(
    strategies: list,
) -> dict[str, CompatibilityResult]:
    """Заполняет strategy.compatibility и возвращает map path -> result."""
    from core.strategy_scanner import ScannedStrategy  # noqa: PLC0415

    out: dict[str, CompatibilityResult] = {}
    for s in strategies:
        if not isinstance(s, ScannedStrategy):
            continue
        cr = analyze_strategy_file(s.path)
        s.compatibility = cr.level.value
        out[s.path] = cr
    return out
