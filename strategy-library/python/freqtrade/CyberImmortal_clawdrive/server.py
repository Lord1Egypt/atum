#!/usr/bin/env python3
"""
Signal Server — extracts Freqtrade strategy logic into an HTTP server.

Deployed by ClawDrive's Strategy Manager after a strategy passes evaluation.
Fetches OHLCV data directly from Binance via ccxt, runs strategy indicators
and signal logic, and pushes signal changes to the Manager for execution.

Usage:
  python3 server.py \
      --strategy-dir /path/to/strategy \
      --port 9902 \
      --manager-url http://localhost:9876 \
      --pair BNB/USDT \
      --timeframe 15m

Endpoints:
  GET  /signal  — latest signal: { action: "entry_long"|"exit_long"|"entry_short"|"exit_short"|"hold" }
  GET  /info    — strategy metadata
  GET  /stats   — basic stats
  GET  /health  — liveness
  POST /stop    — pause signal generation
  POST /start   — resume signal generation
"""

import argparse
import importlib.util
import json
import os
import sys
import threading
import time
import traceback
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from urllib.request import urlopen


def load_strategy_class(strategy_dir):
    """Dynamically import the IStrategy subclass from strategy.py."""
    strat_path = os.path.join(strategy_dir, 'strategy.py')
    spec = importlib.util.spec_from_file_location('user_strategy', strat_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    for attr_name in dir(mod):
        attr = getattr(mod, attr_name)
        if (isinstance(attr, type)
                and hasattr(attr, 'populate_indicators')
                and hasattr(attr, 'populate_entry_trend')
                and attr_name != 'IStrategy'):
            return attr
    raise RuntimeError('No IStrategy subclass found in strategy.py')


def load_best_params(strategy_dir):
    """Read best_params from backtest_result.json if available."""
    result_path = os.path.join(strategy_dir, 'backtest_result.json')
    if not os.path.exists(result_path):
        return {}
    try:
        with open(result_path) as f:
            data = json.load(f)
        return data.get('best_params', {})
    except Exception:
        return {}


_exchange = None

def _get_exchange():
    global _exchange
    if _exchange is None:
        import ccxt
        _exchange = ccxt.binance({'enableRateLimit': True})
    return _exchange


def fetch_candles(pair, interval, limit=200):
    """Fetch OHLCV candles directly from Binance via ccxt."""
    try:
        exchange = _get_exchange()
        ohlcv = exchange.fetch_ohlcv(pair, timeframe=interval, limit=limit)
        candles = []
        for row in ohlcv:
            candles.append({
                'open_time': row[0],
                'open': row[1],
                'high': row[2],
                'low': row[3],
                'close': row[4],
                'volume': row[5],
            })
        return candles
    except Exception as e:
        print(f'[signal-server] fetch candles error: {e}')
        return []


class SignalEngine:
    """Runs the Freqtrade strategy logic on live candle data."""

    def __init__(self, strategy_class, best_params, pair, timeframe, manager_url,
                 name='', trading_type='spot', leverage=3):
        self.strategy_class = strategy_class
        self.best_params = best_params
        self.pair = pair
        self.timeframe = timeframe
        self.manager_url = manager_url
        self.name = name
        self.trading_type = trading_type
        self.leverage = leverage
        self.can_short = getattr(strategy_class, 'can_short', False)

        self.strategy = self._init_strategy()
        self.last_signal = {'action': 'hold', 'timestamp': None}
        self.signal_count = {'entry_long': 0, 'exit_long': 0, 'entry_short': 0, 'exit_short': 0, 'hold': 0}
        self.running = True
        self.last_update = None
        self.error = None

    def _push_signal(self, signal):
        """Push signal change to Manager for immediate execution."""
        try:
            import urllib.request
            payload = json.dumps({
                'name': self.name,
                'pair': self.pair,
                'trading_type': self.trading_type,
                **signal,
            }).encode()
            req = urllib.request.Request(
                f'{self.manager_url}/signals',
                data=payload,
                headers={'Content-Type': 'application/json'},
                method='POST',
            )
            urllib.request.urlopen(req, timeout=5)
            print(f'[signal-server] pushed {signal["action"]} to manager')
        except Exception as e:
            print(f'[signal-server] push failed: {e}')

    def _init_strategy(self):
        """Instantiate the strategy and apply best params."""
        try:
            strat = self.strategy_class()
        except TypeError:
            strat = self.strategy_class.__new__(self.strategy_class)

        params = self.best_params
        if 'params' in params and isinstance(params['params'], dict):
            params = {**params, **params['params']}

        applied = []
        for key, val in params.items():
            if key == 'params':
                continue
            if hasattr(strat, key):
                attr = getattr(strat, key)
                if hasattr(attr, 'value'):
                    attr.value = val
                    applied.append(f'{key}={val}')
                elif not callable(attr):
                    setattr(strat, key, val)
                    applied.append(f'{key}={val}')

        if applied:
            print(f'[signal-server] applied params: {", ".join(applied)}')
        return strat

    def update(self):
        """Fetch latest candles and compute signal."""
        if not self.running:
            return

        try:
            import pandas as pd

            candles = fetch_candles(
                self.pair,
                self.timeframe,
            )
            if not candles:
                return

            df = pd.DataFrame(candles)
            df.rename(columns={'open_time': 'date'}, inplace=True)
            df['date'] = pd.to_datetime(df['date'], unit='ms', utc=True)
            for col in ['open', 'high', 'low', 'close', 'volume']:
                df[col] = pd.to_numeric(df[col], errors='coerce')

            metadata = {'pair': self.pair, 'timeframe': self.timeframe}
            df = self.strategy.populate_indicators(df, metadata)
            df = self.strategy.populate_entry_trend(df, metadata)
            df = self.strategy.populate_exit_trend(df, metadata)

            last_row = df.iloc[-1]
            action = 'hold'
            if last_row.get('enter_long', 0) == 1:
                action = 'entry_long'
            elif last_row.get('exit_long', 0) == 1:
                action = 'exit_long'
            elif self.can_short and last_row.get('enter_short', 0) == 1:
                action = 'entry_short'
            elif self.can_short and last_row.get('exit_short', 0) == 1:
                action = 'exit_short'

            new_signal = {
                'action': action,
                'price': float(last_row['close']),
                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            }

            prev_action = self.last_signal.get('action') if self.last_signal else None
            self.last_signal = new_signal
            self.signal_count[action] = self.signal_count.get(action, 0) + 1
            self.last_update = time.time()
            self.error = None

            if action != prev_action and action != 'hold':
                self._push_signal(new_signal)

        except Exception as e:
            self.error = str(e)
            traceback.print_exc()

    def get_info(self):
        return {
            'name': self.strategy_class.__name__,
            'pair': self.pair,
            'timeframe': self.timeframe,
            'language': 'python',
            'type': 'freqtrade-signal',
            'trading_type': self.trading_type,
            'leverage': self.leverage,
            'can_short': self.can_short,
            'running': self.running,
        }

    def get_stats(self):
        return {
            'last_signal': self.last_signal,
            'signal_count': self.signal_count,
            'last_update': self.last_update,
            'running': self.running,
            'error': self.error,
        }


class SignalHandler(BaseHTTPRequestHandler):
    engine: SignalEngine = None
    strategy_name: str = ''

    def log_message(self, fmt, *args):
        pass

    def _json(self, code, data):
        body = json.dumps(data, default=str).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path.rstrip('/')
        if path == '/signal':
            self._json(200, self.engine.last_signal)
        elif path == '/info':
            self._json(200, self.engine.get_info())
        elif path == '/stats':
            self._json(200, self.engine.get_stats())
        elif path == '/health':
            self._json(200, {'status': 'ok'})
        else:
            self._json(404, {'error': 'not found'})

    def do_POST(self):
        path = urlparse(self.path).path.rstrip('/')
        if path == '/stop':
            self.engine.running = False
            self._json(200, {'status': 'stopped'})
        elif path == '/start':
            self.engine.running = True
            self._json(200, {'status': 'running'})
        else:
            self._json(404, {'error': 'not found'})


def register_with_manager(manager_url, name, port, pair, trading_type='spot', leverage=3):
    """Register this signal server with the Strategy Manager."""
    import urllib.request
    payload = json.dumps({
        'name': name, 'port': port,
        'pair': pair, 'language': 'python',
        'version': '1.0.0',
        'trading_type': trading_type,
        'leverage': leverage,
    }).encode()
    req = urllib.request.Request(
        f'{manager_url}/register',
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        resp = urllib.request.urlopen(req, timeout=5)
        print(f'[signal-server] registered with manager: {resp.read().decode()}')
    except Exception as e:
        print(f'[signal-server] registration failed: {e}')


def signal_loop(engine, interval_seconds):
    """Background thread that updates signals at regular intervals."""
    while True:
        now = time.time()
        next_tick = (int(now) // interval_seconds + 1) * interval_seconds
        time.sleep(max(next_tick - now, 0.1))
        engine.update()


POLL_INTERVAL = 60


def main():
    parser = argparse.ArgumentParser(description='Freqtrade Signal Server')
    parser.add_argument('--strategy-dir', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--manager-url', default='http://localhost:9876')
    parser.add_argument('--pair', required=True)
    parser.add_argument('--timeframe', required=True)
    parser.add_argument('--name', default='')
    parser.add_argument('--trading-type', default='spot', choices=['spot', 'futures'])
    parser.add_argument('--leverage', type=int, default=3)
    args = parser.parse_args()

    strategy_class = load_strategy_class(args.strategy_dir)
    best_params = load_best_params(args.strategy_dir)
    name = args.name or os.path.basename(args.strategy_dir)

    print(f'[signal-server] strategy: {strategy_class.__name__}')
    print(f'[signal-server] pair: {args.pair}, timeframe: {args.timeframe}')
    print(f'[signal-server] trading_type: {args.trading_type}, leverage: {args.leverage}')
    print(f'[signal-server] best_params: {best_params}')

    engine = SignalEngine(
        strategy_class, best_params,
        args.pair, args.timeframe, args.manager_url,
        name=name,
        trading_type=args.trading_type,
        leverage=args.leverage,
    )

    t = threading.Thread(target=signal_loop, args=(engine, POLL_INTERVAL), daemon=True)
    t.start()

    engine.update()

    SignalHandler.engine = engine
    SignalHandler.strategy_name = name

    register_with_manager(args.manager_url, name, args.port, args.pair,
                          trading_type=args.trading_type, leverage=args.leverage)

    server = HTTPServer(('0.0.0.0', args.port), SignalHandler)
    print(f'[signal-server] listening on :{args.port}')

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('[signal-server] shutting down')
        server.shutdown()


if __name__ == '__main__':
    main()
