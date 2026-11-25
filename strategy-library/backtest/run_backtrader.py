import sys, os, re, json, importlib.util, warnings
import backtrader as bt, pandas as pd
warnings.filterwarnings("ignore")

rel, sym = sys.argv[1], sys.argv[2]
LIB = "/home/lordegypt/CLaw/strategy-library"
src = open(os.path.join(LIB, rel), encoding="utf-8", errors="ignore").read()

# ---- 1. leverage from the expert's own settings, else 1:100 ----
lev = None
for pat in (r"leverage\s*[=:]\s*([0-9]+)", r"([0-9]{1,3})\s*x\s*leverage",
            r"Leverage[^0-9]{0,12}([0-9]{1,3})"):
    m = re.search(pat, src, re.I)
    if m:
        v = int(m.group(1))
        if 1 <= v <= 500:
            lev = v
            break
lev_source = "declared"
if lev is None:
    lev, lev_source = 100, "default"

# ---- 2. data ----
d = pd.read_csv(f"/tmp/mktdata/{sym}.csv", index_col=0, parse_dates=True)
d.columns = [c.strip() for c in d.columns]
if len(d) < 200:
    print(json.dumps({"ok": False, "err": "thin data"})); sys.exit(0)

# ---- 3. import ----
p = os.path.join(LIB, rel)
name = "m_" + re.sub(r"\W", "_", rel)[-50:]
try:
    spec = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    classes = [getattr(m, n) for n in dir(m)
               if isinstance(getattr(m, n), type)
               and issubclass(getattr(m, n), bt.Strategy)
               and getattr(m, n) is not bt.Strategy
               and getattr(m, n).__module__ == m.__name__]
    if not classes:
        print(json.dumps({"ok": False, "err": "no Strategy"})); sys.exit(0)
except Exception as e:
    print(json.dumps({"ok": False, "err": f"import {type(e).__name__}"})); sys.exit(0)

class TR(bt.Analyzer):
    def start(self):
        self.t = []
    def notify_trade(self, t):
        closed = t.isclosed() if callable(t.isclosed) else t.isclosed
        if closed:
            self.t.append(t.pnlcomm)
    def get_analysis(self):
        return {"t": self.t}

for cls in classes:
    try:
        c = bt.Cerebro(stdstats=False)
        c.adddata(bt.feeds.PandasData(dataname=d))
        c.addstrategy(cls)
        c.addanalyzer(TR, _name="tr")
        c.broker.setcash(10000)
        c.broker.setcommission(commission=0.0002, leverage=lev)
        c.addsizer(bt.sizers.PercentSizer, percents=95)
        v0 = c.broker.getvalue()
        st = c.run()[0]
        v1 = c.broker.getvalue()
        pnls = st.analyzers.tr.get_analysis()["t"]
        wins = [x for x in pnls if x > 0]
        ret = (v1 / v0 - 1) * 100

        # unbounded position stacking at high leverage produces impossible curves
        degenerate = (not (abs(ret) < 1e6)) or ret > 10000 or ret < -100

        print(json.dumps({
            "ok": True, "class": cls.__name__, "symbol": sym,
            "leverage": lev, "leverage_source": lev_source,
            "return_pct": round(ret, 2), "trades": len(pnls),
            "win_rate": round(100 * len(wins) / len(pnls), 1) if pnls else None,
            "bars": len(d), "degenerate": degenerate,
        }))
        sys.exit(0)
    except Exception:
        continue
print(json.dumps({"ok": False, "err": "run failed"}))
