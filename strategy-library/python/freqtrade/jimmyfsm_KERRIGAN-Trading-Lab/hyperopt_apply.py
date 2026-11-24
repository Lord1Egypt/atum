"""Apply Freqtrade hyperopt results to a strategy copy (original stays untouched)."""

from __future__ import annotations

import ast
import json
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass
class ApplyHyperoptResult:
    ok: bool
    message: str
    copy_path: str = ""
    info_path: str = ""
    original_path: str = ""
    changes: list[str] | None = None


def find_hyperopt_params_json(
    strategy_py: Path,
    strategy_name: str,
    *,
    since_mtime: float | None = None,
) -> Path | None:
    """Locate StrategyName.json written by Freqtrade after hyperopt."""
    folder = strategy_py.parent
    candidates: list[Path] = []
    for path in (folder / f"{strategy_name}.json", folder / f"{strategy_py.stem}.json"):
        if path.is_file():
            if since_mtime is None or path.stat().st_mtime >= since_mtime - 5.0:
                candidates.append(path)
    if not candidates:
        for path in folder.rglob("*.json"):
            if path.stem == strategy_name or path.stem == strategy_py.stem:
                if since_mtime is None or path.stat().st_mtime >= since_mtime - 5.0:
                    candidates.append(path)
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def load_hyperopt_params(json_path: Path) -> dict:
    data = json.loads(json_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {}
    params = data.get("params")
    if isinstance(params, dict):
        return params
    # Older / alternate export shape
    details = data.get("params_details") or {}
    not_opt = data.get("params_not_optimized") or {}
    merged: dict = {}
    if isinstance(details, dict):
        merged.update(details)
    if isinstance(not_opt, dict):
        for key, val in not_opt.items():
            if key not in merged:
                merged[key] = val
    return merged


def _format_py_dict(d: dict) -> str:
    if not d:
        return "{}"
    lines: list[str] = []
    for key in sorted(d.keys(), key=lambda x: int(str(x)) if str(x).isdigit() else str(x)):
        val = d[key]
        if isinstance(val, bool):
            rendered = "True" if val else "False"
        elif isinstance(val, (int, float)):
            rendered = repr(val)
        else:
            rendered = repr(val)
        lines.append(f'        "{key}": {rendered}')
    return "{\n" + ",\n".join(lines) + "\n    }"


def _strategy_class_name(source: str) -> str | None:
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            for base in node.bases:
                b = getattr(base, "id", None) or getattr(base, "attr", "")
                if b == "IStrategy" or str(b).endswith("Strategy"):
                    return node.name
    return None


def _replace_assignment(content: str, name: str, new_rhs: str) -> tuple[str, bool]:
    pattern = re.compile(
        rf"^(\s*{re.escape(name)}\s*=\s*).*$",
        re.MULTILINE,
    )
    if not pattern.search(content):
        return content, False
    return pattern.sub(rf"\g<1>{new_rhs}", content, count=1), True


def _replace_minimal_roi(content: str, roi: dict) -> tuple[str, bool]:
    if not roi:
        return content, False
    block = re.search(
        r"^(\s*minimal_roi\s*=\s*)\{.*?\}",
        content,
        flags=re.MULTILINE | re.DOTALL,
    )
    if not block:
        return content, False
    new_block = block.group(1) + _format_py_dict(roi)
    return content[: block.start()] + new_block + content[block.end() :], True


def _replace_trailing_block(content: str, trailing: dict) -> tuple[str, list[str]]:
    changes: list[str] = []
    mapping = {
        "trailing_stop": trailing.get("trailing_stop"),
        "trailing_stop_positive": trailing.get("trailing_stop_positive"),
        "trailing_stop_positive_offset": trailing.get("trailing_stop_positive_offset"),
        "trailing_only_offset_is_reached": trailing.get("trailing_only_offset_is_reached"),
    }
    out = content
    for key, val in mapping.items():
        if val is None:
            continue
        rhs = "True" if val is True else "False" if val is False else repr(val)
        out, ok = _replace_assignment(out, key, rhs)
        if ok:
            changes.append(f"{key} = {rhs}")
    return out, changes


def apply_hyperopt_to_strategy_copy(
    strategy_py: Path,
    params_json: Path,
    *,
    class_name: str | None = None,
) -> ApplyHyperoptResult:
    original = strategy_py.resolve()
    if not original.is_file():
        return ApplyHyperoptResult(False, f"Файл стратегии не найден: {original}")

    try:
        params = load_hyperopt_params(params_json)
    except (OSError, json.JSONDecodeError) as e:
        return ApplyHyperoptResult(False, f"Не удалось прочитать JSON hyperopt: {e}")

    if not params:
        return ApplyHyperoptResult(False, "JSON hyperopt пустой — нечего применять.")

    source = original.read_text(encoding="utf-8")
    old_class = class_name or _strategy_class_name(source) or original.stem
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    new_class = f"{old_class}_Opt_{ts}"
    copy_name = f"{original.stem}_opt_{ts}{original.suffix}"
    copy_path = original.with_name(copy_name)
    info_path = original.with_name(f"{original.stem}_opt_{ts}.txt")

    changes: list[str] = []
    updated = source

    # Rename strategy class so Freqtrade sees it as a separate strategy.
    updated = re.sub(rf"\b{re.escape(old_class)}\b", new_class, updated)
    changes.append(f"Класс переименован: {old_class} → {new_class}")

    stoploss = params.get("stoploss")
    if isinstance(stoploss, dict):
        stoploss = stoploss.get("stoploss", stoploss.get("value"))
    if stoploss is not None:
        updated, ok = _replace_assignment(updated, "stoploss", repr(float(stoploss)))
        if ok:
            changes.append(f"stoploss → {stoploss}")

    roi = params.get("roi")
    if isinstance(roi, dict) and roi:
        updated, ok = _replace_minimal_roi(updated, roi)
        if ok:
            changes.append(f"minimal_roi обновлён ({len(roi)} уровней)")

    trailing = params.get("trailing")
    if isinstance(trailing, dict):
        updated, tr_changes = _replace_trailing_block(updated, trailing)
        changes.extend(tr_changes)

    buy = params.get("buy")
    sell = params.get("sell")
    buy_sell_lines: list[str] = []
    if isinstance(buy, dict) and buy:
        buy_sell_lines.append("Параметры входа (buy) из hyperopt:")
        for k, v in buy.items():
            buy_sell_lines.append(f"  - {k} = {v}")
    if isinstance(sell, dict) and sell:
        buy_sell_lines.append("Параметры выхода (sell) из hyperopt:")
        for k, v in sell.items():
            buy_sell_lines.append(f"  - {k} = {v}")

    header = (
        '"""\n'
        "KERRIGAN — копия стратегии после Hyperopt\n"
        f"Оригинал (не изменён): {original}\n"
        f"Источник параметров: {params_json}\n"
        f"Создано: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        "Изменения в этой копии:\n"
        + "".join(f"  • {line}\n" for line in changes)
        + "\nПараметры buy/sell (если стратегия с IntParameter/DecimalParameter) "
        "смотри в файле .txt рядом или в JSON.\n"
        '"""\n\n'
    )
    if not updated.lstrip().startswith('"""'):
        updated = header + updated
    else:
        updated = header + updated

    copy_path.write_text(updated, encoding="utf-8")

    info_text = [
        "KERRIGAN Trading Lab — отчёт Hyperopt",
        f"Оригинал: {original}",
        f"Копия с изменениями: {copy_path}",
        f"JSON параметров: {params_json}",
        "",
        "Что изменено в копии:",
        *[f"- {c}" for c in changes],
        "",
    ]
    if buy_sell_lines:
        info_text.append("Рекомендованные buy/sell (вручную или через hyperoptable params):")
        info_text.extend(buy_sell_lines)
    info_text.append("")
    info_text.append("Оригинальный файл НЕ изменялся.")

    info_path.write_text("\n".join(info_text), encoding="utf-8")

    return ApplyHyperoptResult(
        ok=True,
        message="Копия стратегии создана, оригинал сохранён без изменений.",
        copy_path=str(copy_path),
        info_path=str(info_path),
        original_path=str(original),
        changes=changes,
    )
