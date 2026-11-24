"""Strategy export bundles — freqtrade and nautilus variants."""
from __future__ import annotations

import io
import json
import zipfile
from pathlib import Path

import pytest

from strathunter import export as export_mod
from strathunter import models
from strathunter.config import Config


FT_STRATEGY = '''
from freqtrade.strategy import IStrategy

class Iter042(IStrategy):
    INTERFACE_VERSION = 3
    timeframe = "4h"
    stoploss = -0.1
'''

NAUT_STRATEGY = '''
from nautilus_trader.trading.strategy import Strategy

class Iter007(Strategy):
    pass
'''


@pytest.fixture
def fresh_db(tmp_path, monkeypatch):
    from strathunter import db as db_module
    engine = db_module.create_engine(
        f"sqlite:///{tmp_path / 'lineage.sqlite'}",
        connect_args={"check_same_thread": False},
    )
    monkeypatch.setattr(db_module, "engine", engine)
    monkeypatch.setattr(db_module, "SessionLocal",
                        db_module.sessionmaker(bind=engine, autoflush=False, autocommit=False))
    db_module.Base.metadata.create_all(bind=engine)
    yield db_module.SessionLocal()


def _mk(db, tmp_path, *, engine: str, universe: dict, code: str,
        extra_files: dict[str, str] | None = None) -> models.Strategy:
    workdir = tmp_path / "job"
    (workdir / "strategies").mkdir(parents=True, exist_ok=True)
    code_path = workdir / "strategies" / "iter_042.py"
    code_path.write_text(code)
    for name, content in (extra_files or {}).items():
        (workdir / name).write_text(content)
    j = models.Job(
        mode=models.JobMode.A_USER_IDEA, status=models.JobStatus.DONE,
        hypothesis="test hypothesis", universe=universe,
        workdir=str(workdir), agent="claude", model="", engine=engine,
    )
    db.add(j); db.flush()
    s = models.Strategy(
        job_id=j.id, name=f"A_user_idea-job{j.id}-iter_042",
        code_path=str(code_path), claude_return_pct=180.0,
        claude_win_rate=61.0, claude_max_dd=12.0, claude_trades=88,
        oos_return_pct=95.0, oos_trades=40,
    )
    db.add(s); db.commit()
    return s


def _unzip(data: bytes) -> dict[str, str]:
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        return {n: zf.read(n).decode() for n in zf.namelist()}


def test_freqtrade_bundle(fresh_db, tmp_path):
    s = _mk(fresh_db, tmp_path, engine="freqtrade",
            universe={"pairs": ["SOL/USDT:USDT", "AVAX/USDT:USDT"], "timeframe": "1h"},
            code=FT_STRATEGY)
    data, filename = export_mod.build_strategy_export(s, s.job, Config())
    assert filename.endswith(".zip")
    files = _unzip(data)
    assert set(files) == {"iter_042.py", "config.export.json", "README.md", "metrics.json"}

    cfg = json.loads(files["config.export.json"])
    assert cfg["exchange"]["pair_whitelist"] == ["SOL/USDT:USDT", "AVAX/USDT:USDT"]
    assert cfg["dry_run"] is True
    # timeframe extracted from the strategy file wins over the universe's
    assert cfg["timeframe"] == "4h"

    readme = files["README.md"]
    assert "--strategy Iter042" in readme
    assert "freqtrade backtesting" in readme and "freqtrade trade" in readme
    assert "180.0%" in readme and "95.0%" in readme

    metrics = json.loads(files["metrics.json"])
    assert metrics["engine"] == "freqtrade" and metrics["market"] == "crypto"
    assert metrics["discovery"]["return_pct"] == 180.0


def test_nautilus_bundle_includes_runner(fresh_db, tmp_path):
    s = _mk(fresh_db, tmp_path, engine="nautilus",
            universe={"market": "fx", "instruments": ["EUR/USD", "GBP/USD"], "timeframe": "1h"},
            code=NAUT_STRATEGY,
            extra_files={"backtest.py": "# frozen CLI runner\n",
                         "data_prep.py": "# data helper\n"})
    data, _ = export_mod.build_strategy_export(s, s.job, Config())
    files = _unzip(data)
    assert set(files) == {"iter_042.py", "backtest.py", "data_prep.py", "README.md", "metrics.json"}

    readme = files["README.md"]
    assert "python backtest.py --strategy iter_042.py" in readme
    assert "Iter007" in readme
    assert "nautilus_trader" in readme and "TradingNode" in readme
    assert json.loads(files["metrics.json"])["market"] == "fx"


def test_nautilus_bundle_without_runner_still_exports(fresh_db, tmp_path):
    s = _mk(fresh_db, tmp_path, engine="nautilus",
            universe={"market": "etf", "instruments": ["SPY"]}, code=NAUT_STRATEGY)
    data, _ = export_mod.build_strategy_export(s, s.job, Config())
    files = _unzip(data)
    assert "backtest.py" not in files
    assert "BacktestEngine" in files["README.md"]   # fallback instructions


def test_missing_code_file_raises(fresh_db, tmp_path):
    s = _mk(fresh_db, tmp_path, engine="freqtrade", universe={}, code=FT_STRATEGY)
    Path(s.code_path).unlink()
    with pytest.raises(FileNotFoundError):
        export_mod.build_strategy_export(s, s.job, Config())


def test_export_endpoint_serves_zip(fresh_db, tmp_path):
    from strathunter.api.lineage import export_strategy
    s = _mk(fresh_db, tmp_path, engine="freqtrade",
            universe={"pair": "BTC/USDT:USDT"}, code=FT_STRATEGY)
    resp = export_strategy(s.id, db=fresh_db)
    assert resp.media_type == "application/zip"
    assert "attachment" in resp.headers["content-disposition"]
    assert _unzip(resp.body)["metrics.json"]


def test_export_endpoint_404s(fresh_db):
    from fastapi import HTTPException
    from strathunter.api.lineage import export_strategy
    with pytest.raises(HTTPException) as e:
        export_strategy(99999, db=fresh_db)
    assert e.value.status_code == 404
