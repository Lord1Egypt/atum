"""Validate strategies: READY / WARNING / BROKEN."""

from __future__ import annotations

import ast
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from core.strategy_scanner import ScannedStrategy


class ValidationStatus(str, Enum):
    READY = "READY"
    WARNING = "WARNING"
    BROKEN = "BROKEN"


@dataclass
class ValidationResult:
    strategy: ScannedStrategy
    status: ValidationStatus
    message: str
    emoji: str

    @property
    def display_status(self) -> str:
        return f"{self.emoji} {self.status.value}"


def _status_emoji(status: ValidationStatus) -> str:
    return {
        ValidationStatus.READY: "🟢",
        ValidationStatus.WARNING: "🟡",
        ValidationStatus.BROKEN: "🔴",
    }[status]


def validate_syntax(file_path: Path) -> tuple[ValidationStatus, str]:
    try:
        source = file_path.read_text(encoding="utf-8", errors="ignore")
        ast.parse(source)
    except SyntaxError as e:
        return ValidationStatus.BROKEN, f"Синтаксическая ошибка: {e}"
    except OSError as e:
        return ValidationStatus.BROKEN, f"Не удалось прочитать файл: {e}"

    warnings: list[str] = []
    if "IStrategy" not in source and "import IStrategy" not in source:
        if "freqtrade.strategy" not in source:
            warnings.append("Не найден импорт IStrategy")

    if "def populate_indicators" not in source:
        warnings.append("Отсутствует populate_indicators")

    if "def populate_entry_trend" not in source and "def populate_buy_trend" not in source:
        warnings.append("Отсутствует populate_entry_trend")

    if warnings:
        return ValidationStatus.WARNING, "; ".join(warnings)
    return ValidationStatus.READY, "OK"


def validate_with_freqtrade(
    strategy_name: str,
    strategies_path: Path,
    freqtrade_cmd: str,
    config_path: Path | None,
    timeout: int = 60,
) -> tuple[ValidationStatus, str]:
    cmd = [
        freqtrade_cmd,
        "list-strategies",
        "--strategy-path",
        str(strategies_path),
        "--no-color",
    ]
    if config_path and config_path.is_file():
        cmd.extend(["--config", str(config_path)])

    creationflags = 0
    if sys.platform == "win32":
        creationflags = subprocess.CREATE_NO_WINDOW  # type: ignore[attr-defined]

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
            creationflags=creationflags,
        )
        output = (proc.stdout or "") + (proc.stderr or "")
        if strategy_name in output:
            if proc.returncode == 0:
                return ValidationStatus.READY, "Freqtrade видит стратегию"
            return ValidationStatus.WARNING, "Стратегия найдена, но есть предупреждения"
        if proc.returncode != 0 and "error" in output.lower():
            return ValidationStatus.BROKEN, output[-500:]
        return ValidationStatus.WARNING, "Стратегия не подтверждена list-strategies"
    except FileNotFoundError:
        return ValidationStatus.WARNING, "Freqtrade не найден — только проверка синтаксиса"
    except subprocess.TimeoutExpired:
        return ValidationStatus.WARNING, "Таймаут проверки Freqtrade"
    except Exception as e:
        return ValidationStatus.WARNING, str(e)


def validate_strategy(
    strategy: ScannedStrategy,
    freqtrade_cmd: str = "freqtrade",
    strategies_root: Path | None = None,
    config_path: Path | None = None,
    use_freqtrade: bool = True,
) -> ValidationResult:
    file_path = Path(strategy.path)
    status, message = validate_syntax(file_path)

    if status == ValidationStatus.BROKEN:
        return ValidationResult(
            strategy=strategy,
            status=status,
            message=message,
            emoji=_status_emoji(status),
        )

    if use_freqtrade and strategies_root:
        ft_status, ft_msg = validate_with_freqtrade(
            strategy.name,
            strategies_root,
            freqtrade_cmd,
            config_path,
        )
        if ft_status == ValidationStatus.BROKEN:
            status = ValidationStatus.BROKEN
            message = ft_msg
        elif ft_status == ValidationStatus.WARNING and status == ValidationStatus.READY:
            status = ValidationStatus.WARNING
            message = ft_msg
        elif ft_status == ValidationStatus.READY:
            message = ft_msg

    return ValidationResult(
        strategy=strategy,
        status=status,
        message=message,
        emoji=_status_emoji(status),
    )


def validate_all(
    strategies: list[ScannedStrategy],
    freqtrade_cmd: str = "freqtrade",
    strategies_root: Path | None = None,
    config_path: Path | None = None,
) -> list[ValidationResult]:
    results: list[ValidationResult] = []
    for s in strategies:
        try:
            results.append(
                validate_strategy(
                    s,
                    freqtrade_cmd=freqtrade_cmd,
                    strategies_root=strategies_root,
                    config_path=config_path,
                    use_freqtrade=len(strategies) <= 50,
                )
            )
        except Exception as e:
            results.append(
                ValidationResult(
                    strategy=s,
                    status=ValidationStatus.BROKEN,
                    message=str(e),
                    emoji="🔴",
                )
            )
    return results
