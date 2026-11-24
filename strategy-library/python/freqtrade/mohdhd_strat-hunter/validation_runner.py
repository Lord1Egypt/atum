"""Background validation runner — runs OOS + dup detection after DONE.json.

Triggered by `_promote_strategy()` in job.py. Runs in a background thread so the
HTTP poll that detected DONE.json returns quickly.

Design ref: spec §10.2 + §11.
"""
from __future__ import annotations

import logging
import re
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path

from strathunter import config as config_module
from strathunter import db as db_module
from strathunter import models
from strathunter.config import Config
from strathunter.validators import dup, oos


log = logging.getLogger(__name__)


# Cheap heuristic: the strategy class name == the first `class Foo(IStrategy):` in the file.
_CLASS_RE = re.compile(r"^class\s+(\w+)\s*\(\s*IStrategy\s*\)", re.MULTILINE)


def _extract_strategy_class(py_path: Path) -> str | None:
    if not py_path.exists():
        return None
    m = _CLASS_RE.search(py_path.read_text())
    return m.group(1) if m else None


def _resolve_windows(cfg: Config) -> tuple[str, str, str, str]:
    """Recompute discovery + validation windows from config — same logic as render.py."""
    end = datetime.now(timezone.utc)
    def back(months: str) -> datetime:
        n = {"6mo": 6, "1y": 12, "2y": 24}.get(months, 6)
        return end - timedelta(days=30 * n)
    disc_start = back(cfg.discovery.window).strftime("%Y%m%d")
    disc_end = end.strftime("%Y%m%d")
    val_start = back(cfg.validation.window).strftime("%Y%m%d")
    val_end = end.strftime("%Y%m%d")
    return disc_start, disc_end, val_start, val_end


def run_validation_for_strategy(strategy_id: int) -> None:
    """Sync entry point — runs OOS + dup detect for a freshly-promoted strategy."""
    db = db_module.SessionLocal()
    try:
        s = db.get(models.Strategy, strategy_id)
        if s is None:
            log.warning("validation_runner: strategy %d not found", strategy_id)
            return
        cfg = config_module.load_config()
        job = db.get(models.Job, s.job_id)
        if job is not None and job.overrides:
            # Honor per-job limit overrides (validation window, degradation
            # thresholds, …) when re-running the strategy out-of-sample.
            cfg = config_module.apply_overrides(cfg, job.overrides)

        # ── OOS check — nautilus jobs re-run the workdir's frozen-CLI
        # backtest.py on a random unseen window; freqtrade jobs re-run the
        # freqtrade binary. Same divergence gate either way. ────────────────
        if job is not None and getattr(job, "engine", "") == models.ENGINE_NAUTILUS:
            try:
                _run_nautilus_oos(db, s, job, cfg)
            except Exception as e:
                log.exception("nautilus OOS failed for strategy %d: %s", s.id, e)
            # Dup detection relies on freqtrade trade exports — not available
            # for nautilus jobs (their runs/*.json are metrics, not trades).
            db.commit()
            return

        try:
            code_path = Path(s.code_path)
            strategy_class = _extract_strategy_class(code_path)
            if not strategy_class:
                log.warning("strategy %d: could not extract class name from %s", s.id, code_path)
            else:
                disc_s, disc_e, val_s, val_e = _resolve_windows(cfg)
                explicit_config = (job.universe or {}).get("config_path") if job else None
                config_path = Path(explicit_config or cfg.orchestrator.resolved_default_config())
                if not config_path.is_file():
                    config_path = Path(cfg.orchestrator.resolved_default_config())

                # Patch the freqtrade binary lookup in oos.py to use our resolved one
                # by setting PATH or using which — easier: monkey-shutil the binary check.
                freqtrade_bin = cfg.orchestrator.resolved_freqtrade_bin()
                if not Path(freqtrade_bin).exists() and freqtrade_bin != "freqtrade":
                    log.warning("freqtrade binary not found at %s; OOS will be skipped", freqtrade_bin)
                    s.oos_divergent = False
                else:
                    result = _run_oos_with_binary(
                        freqtrade_bin=freqtrade_bin,
                        strategy_path=code_path,
                        strategy_class=strategy_class,
                        config_path=config_path,
                        claude_disc_start=disc_s, claude_disc_end=disc_e,
                        claude_val_start=val_s, claude_val_end=val_e,
                        out_log_path=Path(job.workdir) / "runs" / f"oos_strategy_{s.id}.log",
                        freqtrade_dir=Path(cfg.orchestrator.freqtrade_dir),
                    )
                    s.oos_return_pct = result.return_pct
                    s.oos_win_rate = result.win_rate
                    s.oos_max_dd = result.max_dd
                    s.oos_trades = result.trades
                    s.oos_window = f"{result.window_start}-{result.window_end}"
                    s.oos_divergent = oos.is_divergent(
                        claude_return=s.claude_return_pct,
                        oos_return=result.return_pct,
                        max_degradation_pct=cfg.validation.max_degradation,
                    )
                    if s.oos_divergent:
                        db.add(models.InboxItem(
                            kind="oos_divergent",
                            job_id=s.job_id,
                            strategy_id=s.id,
                            title=f"Strategy {s.name} — OOS divergent",
                            snippet=f"Claude: +{s.claude_return_pct:.0f}%  vs  OOS: "
                                    f"{'+' if (result.return_pct or 0) >= 0 else ''}{result.return_pct}%",
                            badges=["OOS divergent"],
                        ))
        except Exception as e:
            log.exception("OOS check failed for strategy %d: %s", s.id, e)

        # ── Dup detection ──────────────────────────────────────────────
        try:
            trades_json = Path(s.code_path).parent.parent / "runs" / f"{Path(s.code_path).stem}.json"
            if trades_json.exists():
                new_set = dup.trade_set_from_path(trades_json)
                matches = dup.find_near_duplicates(db, new_trade_set=new_set, threshold=0.7,
                                                   exclude_strategy_id=s.id)
                if matches:
                    dup.assign_to_cluster(db, new_strategy=s, matches=matches)
                    db.add(models.InboxItem(
                        kind="dup_flag",
                        job_id=s.job_id,
                        strategy_id=s.id,
                        title=f"Strategy {s.name} — near-duplicate detected",
                        snippet=f"{int(matches[0].jaccard*100)}% trade overlap with {matches[0].other_name}",
                        badges=[f"near-dup of {matches[0].other_name}"],
                    ))
        except Exception as e:
            log.exception("Dup detection failed for strategy %d: %s", s.id, e)

        db.commit()
    finally:
        db.close()


def _iso(yyyymmdd: str) -> str:
    return f"{yyyymmdd[:4]}-{yyyymmdd[4:6]}-{yyyymmdd[6:]}"


def _run_nautilus_oos(db, s: models.Strategy, job: models.Job, cfg: Config) -> None:
    """Independent OOS for a nautilus-engine strategy: invoke the job's own
    `backtest.py` (frozen CLI — see JOB_NAUTILUS.md.j2) on a random window
    that overlaps neither discovery nor validation, and read the metrics JSON
    it emits. No log parsing, no engine knowledge needed here."""
    import json
    import subprocess

    workdir = Path(job.workdir)
    runner = workdir / "backtest.py"
    if not runner.exists():
        log.warning("strategy %d: no backtest.py in %s — OOS skipped", s.id, workdir)
        return

    disc_s, disc_e, val_s, val_e = _resolve_windows(cfg)
    win_start, win_end = oos.pick_oos_window(disc_s, disc_e, val_s, val_e)
    out_json = workdir / "runs" / f"oos_strategy_{s.id}.json"
    out_log = workdir / "runs" / f"oos_strategy_{s.id}.log"
    out_json.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        cfg.nautilus.resolved_python_bin(), str(runner),
        "--strategy", str(s.code_path),
        "--start", _iso(win_start), "--end", _iso(win_end),
        "--out", str(out_json),
    ]
    try:
        with out_log.open("w") as logf:
            proc = subprocess.run(cmd, cwd=workdir, stdout=logf,
                                  stderr=subprocess.STDOUT, timeout=900, check=False)
    except subprocess.TimeoutExpired:
        log.warning("strategy %d: nautilus OOS timed out (>15min)", s.id)
        return
    if proc.returncode != 0 or not out_json.exists():
        log.warning("strategy %d: nautilus OOS exited %s without metrics (%s)",
                    s.id, proc.returncode, out_log)
        return

    try:
        metrics = json.loads(out_json.read_text())
    except (json.JSONDecodeError, OSError) as e:
        log.warning("strategy %d: unreadable OOS metrics %s: %s", s.id, out_json, e)
        return

    def num(key):
        v = metrics.get(key)
        return float(v) if isinstance(v, (int, float)) else None

    s.oos_return_pct = num("return_pct")
    s.oos_win_rate = num("win_rate")
    s.oos_max_dd = num("max_dd")
    s.oos_trades = int(metrics["trades"]) if isinstance(metrics.get("trades"), (int, float)) else None
    s.oos_window = f"{win_start}-{win_end}"
    s.oos_divergent = oos.is_divergent(
        claude_return=s.claude_return_pct,
        oos_return=s.oos_return_pct,
        max_degradation_pct=cfg.validation.max_degradation,
    )
    if s.oos_divergent:
        db.add(models.InboxItem(
            kind="oos_divergent",
            job_id=s.job_id,
            strategy_id=s.id,
            title=f"Strategy {s.name} — OOS divergent",
            snippet=f"Agent: +{s.claude_return_pct:.0f}%  vs  OOS: "
                    f"{'+' if (s.oos_return_pct or 0) >= 0 else ''}{s.oos_return_pct}%",
            badges=["OOS divergent"],
        ))


def _run_oos_with_binary(
    *,
    freqtrade_bin: str,
    strategy_path: Path,
    strategy_class: str,
    config_path: Path,
    claude_disc_start: str, claude_disc_end: str,
    claude_val_start: str, claude_val_end: str,
    out_log_path: Path,
    freqtrade_dir: Path,
) -> oos.OOSResult:
    """Run OOS using an explicit freqtrade binary path (works with venv installs)."""
    import subprocess

    win_start, win_end = oos.pick_oos_window(
        claude_disc_start, claude_disc_end, claude_val_start, claude_val_end,
    )

    cmd = [
        freqtrade_bin, "backtesting",
        "--strategy-path", str(strategy_path.parent),
        "--strategy", strategy_class,
        "--config", str(config_path),
        "--timerange", f"{win_start}-{win_end}",
    ]
    out_log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with out_log_path.open("w") as logf:
            proc = subprocess.run(cmd, cwd=freqtrade_dir, stdout=logf,
                           stderr=subprocess.STDOUT, timeout=900, check=False)
    except subprocess.TimeoutExpired:
        return oos.OOSResult(
            window_start=win_start, window_end=win_end,
            return_pct=None, win_rate=None, max_dd=None, trades=None,
            log_path=str(out_log_path), error="freqtrade timeout (>15min)",
        )
    except Exception as e:
        return oos.OOSResult(
            window_start=win_start, window_end=win_end,
            return_pct=None, win_rate=None, max_dd=None, trades=None,
            log_path=str(out_log_path), error=str(e),
        )

    if proc.returncode != 0:
        return oos.OOSResult(
            window_start=win_start, window_end=win_end,
            return_pct=None, win_rate=None, max_dd=None, trades=None,
            log_path=str(out_log_path), error=f"freqtrade exited {proc.returncode}; see log",
        )
    metrics = oos.parse_freqtrade_log(out_log_path)
    return oos.OOSResult(
        window_start=win_start, window_end=win_end,
        return_pct=metrics.get("return_pct"),
        win_rate=metrics.get("win_rate"),
        max_dd=metrics.get("max_dd"),
        trades=metrics.get("trades"),
        log_path=str(out_log_path),
    )


def kick_off_validation(strategy_id: int) -> threading.Thread:
    """Fire-and-forget background validation. Returns the thread so tests can join()."""
    t = threading.Thread(target=run_validation_for_strategy,
                         args=(strategy_id,), daemon=True)
    t.start()
    return t
