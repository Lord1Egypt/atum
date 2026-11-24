"""Tests that the freqtrade connection is actually wired."""
from __future__ import annotations

import json
import os
import shutil
import re
import threading
import time
from pathlib import Path

import pytest

from strathunter import db as db_module
from strathunter import models
from strathunter.config import Config, OrchestratorConfig, load_config
from strathunter.db import Base, create_engine, sessionmaker
from strathunter.orchestrator import validation_runner


# ── resolved freqtrade binary ─────────────────────────────────────────

def test_resolved_freqtrade_bin_uses_venv_when_present(tmp_path: Path):
    ft = tmp_path / "freqtrade"
    venv_bin = ft / ".venv" / "bin"
    venv_bin.mkdir(parents=True)
    fake = venv_bin / "freqtrade"
    fake.write_text("#!/bin/bash\necho fake\n"); fake.chmod(0o755)

    cfg = OrchestratorConfig(freqtrade_dir=str(ft))
    assert cfg.resolved_freqtrade_bin() == str(fake)


def test_resolved_freqtrade_bin_falls_back_to_plain(tmp_path: Path):
    cfg = OrchestratorConfig(freqtrade_dir=str(tmp_path / "nope"))
    assert cfg.resolved_freqtrade_bin() == "freqtrade"


def test_resolved_freqtrade_bin_respects_explicit(tmp_path: Path):
    cfg = OrchestratorConfig(freqtrade_dir=str(tmp_path), freqtrade_bin="/usr/local/bin/ftx")
    assert cfg.resolved_freqtrade_bin() == "/usr/local/bin/ftx"


def test_resolved_default_config_picks_existing(tmp_path: Path):
    ud = tmp_path / "user_data"
    ud.mkdir()
    (ud / "config_200pairs.json").write_text("{}")
    cfg = OrchestratorConfig(freqtrade_dir=str(tmp_path))
    assert cfg.resolved_default_config().endswith("config_200pairs.json")


def test_resolved_default_config_falls_back(tmp_path: Path):
    cfg = OrchestratorConfig(freqtrade_dir=str(tmp_path / "empty"))
    assert cfg.resolved_default_config() == ""


# ── real-machine smoke (skips unless setup is present) ───────────────

REAL_FREQTRADE = Path(os.environ.get("STRATHUNTER_TEST_FREQTRADE", "/nonexistent/freqtrade"))


@pytest.mark.skipif(not REAL_FREQTRADE.exists(), reason="real freqtrade venv not installed")
def test_real_freqtrade_binary_resolved():
    cfg = Config(orchestrator=OrchestratorConfig(freqtrade_bin=str(REAL_FREQTRADE)))
    resolved = cfg.orchestrator.resolved_freqtrade_bin()
    assert Path(resolved).exists(), f"resolved {resolved} should exist"
    assert resolved.endswith("/freqtrade")


@pytest.mark.skipif(not REAL_FREQTRADE.exists(), reason="real freqtrade venv not installed")
def test_real_freqtrade_executable():
    """Make sure we can at least exec freqtrade --version with the resolved binary."""
    import subprocess
    cfg = Config(orchestrator=OrchestratorConfig(freqtrade_bin=str(REAL_FREQTRADE)))
    r = subprocess.run([cfg.orchestrator.resolved_freqtrade_bin(), "--version"],
                       capture_output=True, text=True, timeout=15)
    assert r.returncode == 0
    assert "freqtrade" in (r.stdout + r.stderr).lower()


# ── strategy class extraction ─────────────────────────────────────────

def test_extract_strategy_class(tmp_path: Path):
    p = tmp_path / "iter_003.py"
    p.write_text("""
from freqtrade.strategy import IStrategy
import pandas as pd

class MyStratV3(IStrategy):
    INTERFACE_VERSION = 3
    timeframe = "1h"
    def populate_indicators(self, df, metadata): return df
""")
    assert validation_runner._extract_strategy_class(p) == "MyStratV3"


def test_extract_strategy_class_returns_none_when_absent(tmp_path: Path):
    p = tmp_path / "x.py"
    p.write_text("def foo(): pass")
    assert validation_runner._extract_strategy_class(p) is None


def test_extract_strategy_class_missing_file(tmp_path: Path):
    assert validation_runner._extract_strategy_class(tmp_path / "nope.py") is None


# ── _promote_strategy actually kicks off validation ──────────────────

@pytest.fixture
def fresh_db(tmp_path: Path, monkeypatch):
    eng = create_engine(f"sqlite:///{tmp_path}/db.sqlite", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=eng)
    Session = sessionmaker(bind=eng, autoflush=False, autocommit=False)
    monkeypatch.setattr(db_module, "engine", eng)
    monkeypatch.setattr(db_module, "SessionLocal", Session)
    return Session()


def test_promote_strategy_kicks_off_validation(fresh_db, monkeypatch, tmp_path):
    """When _promote_strategy runs, it should schedule a background validation thread."""
    from strathunter.orchestrator import job as job_svc

    called = {}
    def fake_kick(strategy_id: int) -> threading.Thread:
        with db_module.SessionLocal() as independent_db:
            assert independent_db.get(models.Strategy, strategy_id) is not None
        called["id"] = strategy_id
        t = threading.Thread(target=lambda: None)
        t.start()
        return t

    monkeypatch.setattr(validation_runner, "kick_off_validation", fake_kick)

    # Build a job manually (no tmux)
    j = models.Job(
        mode=models.JobMode.A_USER_IDEA,
        status=models.JobStatus.RUNNING,
        hypothesis="x",
        universe={"config_path": "/tmp/c.json"},
        workdir=str(tmp_path),
    )
    fresh_db.add(j); fresh_db.flush()

    import json
    (tmp_path / "DONE.json").write_text(json.dumps({
        "best_strategy": "strategies/iter_007.py",
        "discovery_metrics": {"return_pct": 200.0, "trades": 50, "win_rate": 45.0, "max_dd": -15.0},
    }))
    fresh_db.commit()
    job_svc.poll_and_update(fresh_db, j)

    # Strategy was created
    strats = fresh_db.query(models.Strategy).all()
    assert len(strats) == 1
    assert called.get("id") == strats[0].id


# ── validation_runner end-to-end with a fake freqtrade ───────────────

@pytest.fixture
def fake_freqtrade(tmp_path: Path, monkeypatch):
    """A 'freqtrade' that writes a plausible backtest summary to its stdout."""
    ft = tmp_path / "fakeft"
    venv_bin = ft / ".venv" / "bin"
    venv_bin.mkdir(parents=True)
    fake = venv_bin / "freqtrade"
    fake.write_text("""#!/bin/bash
# Fake freqtrade — emits a summary we can parse, ignores all args
echo "Result for strategy"
echo "============================= BACKTESTING REPORT ============================="
echo "| Total profit %     | 142.5                                                |"
echo "| Win Rate           | 38.2                                                 |"
echo "| Max Drawdown       | -22.4                                                |"
echo "| Total trades       | 48                                                   |"
""")
    fake.chmod(0o755)

    # Also create a user_data/config_200pairs.json so the default-config picker works
    ud = ft / "user_data"
    ud.mkdir()
    (ud / "config_200pairs.json").write_text("{}")

    # Patch load_config to return a config pointing here
    from strathunter import config as config_module
    orig = config_module.load_config
    def patched(path=None):
        cfg = orig(path)
        cfg.orchestrator = OrchestratorConfig(
            sandbox_root=str(tmp_path / "jobs"),
            freqtrade_dir=str(ft),
        )
        return cfg
    monkeypatch.setattr(config_module, "load_config", patched)
    return ft


def test_validation_runner_records_oos_and_flags_divergent(fresh_db, fake_freqtrade, tmp_path: Path):
    """End-to-end: build a strategy, run validation, verify OOS fields populated + divergent tag."""
    # fresh_db already patches db_module.SessionLocal to point at the test DB,
    # which is what validation_runner uses internally.

    # Build a workdir + a strategy file
    wd = tmp_path / "jobs" / "9"
    (wd / "strategies").mkdir(parents=True)
    (wd / "runs").mkdir(parents=True)
    code = wd / "strategies" / "iter_001.py"
    code.write_text("""
from freqtrade.strategy import IStrategy
class IterX1(IStrategy):
    INTERFACE_VERSION = 3
""")

    j = models.Job(
        mode=models.JobMode.A_USER_IDEA, status=models.JobStatus.DONE,
        hypothesis="x", universe={"config_path": str(fake_freqtrade / "user_data" / "config_200pairs.json")},
        workdir=str(wd),
    )
    fresh_db.add(j); fresh_db.flush()
    s = models.Strategy(
        job_id=j.id, name="test-strategy",
        code_path=str(code),
        claude_return_pct=500.0,  # very high → fake OOS of 142.5 should be divergent
    )
    fresh_db.add(s); fresh_db.commit()

    # Run validation synchronously (don't background)
    validation_runner.run_validation_for_strategy(s.id)

    fresh_db.refresh(s)
    assert s.oos_return_pct == 142.5
    assert s.oos_win_rate == 38.2
    assert s.oos_trades == 48
    # Claude said 500%, OOS got 142.5% → drop of (500-142.5)/500 = 71.5% > 60% cap → divergent
    assert s.oos_divergent is True

    # Inbox got an "OOS divergent" item
    items = fresh_db.query(models.InboxItem).filter_by(strategy_id=s.id).all()
    assert any(it.kind == "oos_divergent" for it in items)


def test_connectivity_endpoint_reflects_state(tmp_path: Path, monkeypatch):
    """The /connectivity endpoint should report what's actually available."""
    from fastapi.testclient import TestClient
    from strathunter.main import app
    from strathunter import db as db_module

    eng = create_engine(f"sqlite:///{tmp_path}/conn.sqlite", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=eng)
    monkeypatch.setattr(db_module, "engine", eng)
    monkeypatch.setattr(db_module, "SessionLocal", sessionmaker(bind=eng, autoflush=False, autocommit=False))

    client = TestClient(app)
    r = client.get("/connectivity")
    assert r.status_code == 200
    body = r.json()

    for key in ["freqtrade_bin", "freqtrade_bin_exists", "default_config",
                "default_config_exists", "claude_bin", "claude_bin_exists",
                "tmux_bin", "tmux_bin_exists", "data_dir", "data_dir_exists"]:
        assert key in body, f"missing {key} in /connectivity response"

    # Report availability accurately on contributors' machines, including CI.
    assert body["tmux_bin_exists"] == bool(shutil.which("tmux"))
    assert body["claude_bin_exists"] == bool(shutil.which("claude"))


def test_validation_without_explicit_job_config_uses_default(fresh_db, fake_freqtrade, tmp_path):
    """A nonempty universe without config_path must not resolve to Path('.')."""
    wd = tmp_path / 'job'
    (wd / 'strategies').mkdir(parents=True)
    source = wd / 'strategies' / 'iter.py'
    source.write_text('class Example(IStrategy):\n    pass\n')
    binary = fake_freqtrade / '.venv/bin/freqtrade'
    binary.write_text('''#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--config" ]; then
    shift
    if [ ! -f "$1" ]; then exit 2; fi
  fi
  shift
done
printf '| Total profit %% | 42.0 |\\n| Total trades | 40 |\\n'
''')
    j = models.Job(mode=models.JobMode.A_USER_IDEA, status=models.JobStatus.DONE,
                   hypothesis='test', universe={'pairs': ['BTC/USDT:USDT']}, workdir=str(wd))
    fresh_db.add(j); fresh_db.flush()
    s = models.Strategy(job_id=j.id, name='test', code_path=str(source), claude_return_pct=50)
    fresh_db.add(s); fresh_db.commit()
    validation_runner.run_validation_for_strategy(s.id)
    fresh_db.refresh(s)
    assert s.oos_return_pct == 42.0


def test_failed_backtest_must_not_publish_metrics(tmp_path):
    binary = tmp_path / 'bad-freqtrade'
    binary.write_text("#!/bin/sh\nprintf '| Total profit %% | 99.0 |\\n'\nexit 2\n")
    binary.chmod(0o755)
    result = validation_runner._run_oos_with_binary(
        freqtrade_bin=str(binary), strategy_path=tmp_path / 'iter.py',
        strategy_class='Example', config_path=tmp_path / 'config.json',
        claude_disc_start='20260101', claude_disc_end='20260701',
        claude_val_start='20250101', claude_val_end='20260701',
        out_log_path=tmp_path / 'oos.log', freqtrade_dir=tmp_path,
    )
    assert result.error
    assert result.return_pct is None
