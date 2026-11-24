"""Sidekick conversation — runs in the job's own workdir, can take actions,
streams responses to the dashboard as they form.

Design changes from v1:
- The sidekick session lives IN /tmp/jobs/<id>/, not a sidekick/ subdir.
  This means it can read AND write iteration files, append to STATUS.md,
  and run backtests — exactly what the admin steers it to do.
- Sidekick output streams to the dashboard via progressive DB updates:
  the assistant ChatMessage row is created upfront with in_progress=True,
  content="", and the background runner appends to .content as the tmux
  pane fills. The frontend polls fast while in_progress is true.
"""
from __future__ import annotations

import re
import json
import os
import uuid
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from strathunter import models
from strathunter.config import load_config
from strathunter.orchestrator import tmux
from strathunter.orchestrator.agent import make_agent


QUIET_PERIOD_SECONDS = 4.0
POLL_INTERVAL_SECONDS = 0.6
DEFAULT_TIMEOUT_SECONDS = 600   # 10min cap — long enough for a backtest


@dataclass(slots=True)
class ChatResult:
    text: str
    error: str | None = None


def _session_name(job_id: int) -> str:
    return f"chat_{job_id}"


def session_exists(job_id: int) -> bool:
    return tmux.session_exists(_session_name(job_id))


def kill_session(job_id: int) -> None:
    tmux.kill(_session_name(job_id))


# ── BRIEF — what the sidekick knows about its role ────────────────────────

def _write_brief(job: models.Job, workdir: Path) -> Path:
    brief_path = workdir / "SIDEKICK_BRIEF.md"
    brief = f"""# Sidekick Brief — Job {job.id}

You ARE Claude. The admin is talking to YOU through the dashboard chat panel.
There is no other Claude session you can "delegate to" or "ask" — when the
admin asks for something, YOU do it. The main iteration loop that produced
job {job.id} already finished (status: **{job.status.value}**). Its tmux
session may still be idle, but it is no longer driving any work.

## What was already done

- Hypothesis: {job.hypothesis}
- Iterations completed: {job.iter_count}
- Status: {job.status.value}
- Workdir (your CWD): {workdir}
- Iteration log: STATUS.md
- All strategies: strategies/iter_NN.py
- All backtest logs: runs/iter_NN.log
- The protocol the main loop followed: JOB.md
- Project domain rules: CLAUDE.md

## What you do — analyze AND act

**Analysis questions** ("which iter was best?", "summarize what we learned"):
read the relevant files, answer in Markdown with citations.

**Action requests** — ANY of these you handle yourself:
- "run a backtest [for window X / on validation window / for the last year]"
- "test a variant with [3x leverage / -4% stop / different timeframe]"
- "try iter N's strategy with a tweak"
- "what if we [change something]"
- "tell the running Claude to do X" — there is no other Claude; you do X.

For action requests:
1. Pick the next available iter number N (highest existing
   `strategies/iter_NN.py` + 1; pad to 2 digits).
2. Write `strategies/iter_NN.py` — full IStrategy class, no placeholders.
   If just running an existing strategy on a different window, copy/adapt
   the existing file and rename the class.
3. Follow the engine-specific commands in CLAUDE.md and the dates and
   instruments in JOB.md. For Freqtrade use the configured executable and
   config documented there. For Nautilus use the existing backtest.py CLI.
   Redirect output into runs/iter_NN.log; quote filesystem paths.
4. Verify: log exists, `grep "Total profit"` returns a number, trade count
   parsed correctly. Cite the source line.
5. APPEND ONE row to STATUS.md in the existing table format:
   `| NN | mm | <one-line tweak> | <return%> | <WR%> | <DD%> | <trades> | KEEP/KILL/MUTATE | (admin-driven) |`
6. `cd {workdir} && git add -A && git commit -m "iter NN: admin-driven via sidekick"`
7. Tell the admin the result in chat.

The dashboard polls STATUS.md and your new iter row will appear in the
iterations table + chart automatically.

## What you must NOT do

- Don't modify JOB.md or CLAUDE.md.
- Don't delete iters, logs, or commits.
- Don't write to DONE.json / FALSIFIED.json / REPORT.md — those are the
  main loop's terminal-state markers and would re-trigger orchestrator
  logic on an already-finished job.
- Don't emit the `<promise>ITER_NN_VERIFIED</promise>` etc markers —
  those are for the main iteration loop's Stop hook, which you are not
  driving.

## Style

- Be direct. Use Markdown — tables, code blocks, lists.
- Cite source lines from the backtest log when you claim metrics.
- If the admin asks "are we close to the floor?" — answer with the data.
- Never fabricate numbers. Every metric must come from a real grep.
"""
    brief_path.write_text(brief)
    return brief_path


def _accept_trust_dialog(session: str, max_wait: float = 6.0) -> None:
    """Dismiss the workspace-trust prompt any coding-agent CLI may show on
    first use of a new dir. Shares detection with the job orchestrator so
    every agent (Claude, Antigravity, Codex, custom tools) is covered."""
    from strathunter.orchestrator.job import _accept_workspace_trust_dialog
    _accept_workspace_trust_dialog(session, max_wait_seconds=max_wait)


_SIDEKICK_HOOK_GUARD = '\n# Q&A sessions finish answers without research-loop markers.\nif [ "${STRATHUNTER_SIDEKICK:-0}" = "1" ]; then\n  exit 0\nfi\n'


def _prepare_sidekick_hook(workdir: Path) -> None:
    """Migrate our generated Stop hook for old jobs; preserve custom scripts."""
    path = workdir / "scripts" / "verify-promise.sh"
    if not path.is_file():
        return
    source = path.read_text()
    if ("# Strat Hunter — Stop hook." not in source[:100]
            or "STRATHUNTER_SIDEKICK" in source or "set -u\n" not in source):
        return
    path.write_text(source.replace("set -u\n", "set -u\n" + _SIDEKICK_HOOK_GUARD, 1))


def _sidekick_transcript_path(workdir: Path) -> Path | None:
    marker = workdir / ".sidekick-claude-session"
    try:
        session_id = str(uuid.UUID(marker.read_text().strip()))
    except (OSError, ValueError):
        return None
    config_dir = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    return next((config_dir / "projects").glob(f"*/{session_id}.jsonl"), None)


def _read_claude_response(path: Path, offset: int) -> str:
    """Read public assistant text only; never expose thinking/tool payloads."""
    messages: dict[str, str] = {}
    try:
        with path.open("rb") as source:
            source.seek(offset)
            for line in source:
                try:
                    row = json.loads(line)
                except (ValueError, UnicodeError):
                    continue  # writer may still be appending the last record
                if row.get("type") != "assistant":
                    continue
                message = row.get("message", {})
                content = message.get("content", [])
                texts = [item["text"] for item in content
                         if isinstance(item, dict) and item.get("type") == "text"
                         and isinstance(item.get("text"), str)]
                if texts:
                    messages[str(message.get("id") or len(messages))] = "\n\n".join(texts)
    except OSError:
        return ""
    return "\n\n".join(messages.values()).strip()


def ensure_session(
    job: models.Job, job_workdir: Path, claude_bin: str = "claude"
) -> str:
    """Ensure a sidekick tmux session is running. Returns session name.

    The sidekick mirrors the parent job's agent + model selection so the Q&A
    session has the same capabilities/context the main loop did.
    """
    session = _session_name(job.id)
    if tmux.session_exists(session):
        return session

    # Resolve agent from the job. Fall back to legacy claude_bin if the job
    # pre-dates the agent column.
    cfg = load_config()
    if getattr(job, "agent", None):
        if claude_bin != "claude":
            cfg.orchestrator.claude_bin = claude_bin
        spec = make_agent(agent=job.agent, cfg=cfg)
        agent_command = spec.shell_string()
    else:
        agent_command = f"{claude_bin} --dangerously-skip-permissions"

    if getattr(job, "agent", None) in (None, "", "claude"):
        session_id = str(uuid.uuid4())
        agent_command += f" --session-id {session_id}"
        (job_workdir / ".sidekick-claude-session").write_text(session_id)

    _write_brief(job, job_workdir)
    _prepare_sidekick_hook(job_workdir)
    tmux.spawn(tmux.TmuxSpec(
        session_name=session,
        workdir=str(job_workdir),
        agent_command=agent_command,
        env={"STRATHUNTER_SIDEKICK": "1"},
    ))
    # Every agent gets the trust-dialog accept pass; harmless no-op timeout
    # for CLIs that don't show one.
    _accept_trust_dialog(session)

    # Prime: tell it to read its brief once
    tmux.send_text(
        session,
        "Read SIDEKICK_BRIEF.md to understand your role. Acknowledge briefly; "
        "wait for the admin's first real question.",
    )
    # Let it acknowledge before the real interaction starts
    _wait_for_quiet(session, quiet_period=2.0, timeout=60.0)
    return session


# ── pane diff helpers ─────────────────────────────────────────────────────

_ANSI_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")


def _strip_ansi(s: str) -> str:
    return _ANSI_RE.sub("", s)


def _wait_for_quiet(
    session: str,
    quiet_period: float = QUIET_PERIOD_SECONDS,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    on_chunk: Callable[[str], None] | None = None,
    pane_before: str | None = None,
    user_message: str = "",
    transcript_path: Path | None = None,
    transcript_offset: int = 0,
) -> str:
    """Poll the pane until output is quiet for `quiet_period` seconds.

    If `on_chunk` is given, it is called with the LATEST partial response
    (everything new since `pane_before` minus the user_message echo) every
    time the pane changes. This is what enables streaming to the dashboard.
    """
    deadline = time.monotonic() + timeout
    last = ""
    last_change = time.monotonic()
    while time.monotonic() < deadline:
        current = tmux.capture_pane(session, lines=8000)
        if current != last:
            last = current
            last_change = time.monotonic()
            if on_chunk is not None and pane_before is not None:
                partial = (_read_claude_response(transcript_path, transcript_offset)
                           if transcript_path else "")
                partial = partial or _extract_response(pane_before, current, user_message)
                if partial:
                    try:
                        on_chunk(partial)
                    except Exception:
                        pass
        elif time.monotonic() - last_change >= quiet_period:
            return current
        time.sleep(POLL_INTERVAL_SECONDS)
    return last


def _extract_response(pane_before: str, pane_after: str, user_message: str) -> str:
    after = _strip_ansi(pane_after)
    before = _strip_ansi(pane_before)

    user_idx = after.rfind(user_message) if user_message else -1
    if user_idx >= 0:
        body = after[user_idx + len(user_message) :]
    elif before and after.startswith(before):
        body = after[len(before) :]
    else:
        body = after

    lines = body.splitlines()
    drop_patterns = (
        re.compile(r"^\s*\d+\s+git:\("),
        re.compile(r"^\s*⏵⏵\s+bypass"),
        re.compile(r"^\s*tmux focus-events"),
        re.compile(r"^\s*Tip:"),
        re.compile(r"^\s*[─━│┃─━│┃]+$"),
        re.compile(r"^\s*❯\s*$"),
        re.compile(r"^\s*/remote-control"),
        re.compile(r"https://claude\.ai/code/session_"),
        re.compile(r"Claude in Chrome"),
        re.compile(r"·\s*/effort"),
    )
    cleaned: list[str] = []
    for ln in lines:
        if any(p.search(ln) for p in drop_patterns):
            continue
        cleaned.append(ln)

    text = "\n".join(cleaned).strip()
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


# ── public ────────────────────────────────────────────────────────────────


def _ask_in_session(
    *,
    session: str,
    user_message: str,
    on_chunk: Callable[[str], None] | None,
    quiet_period: float,
    timeout_seconds: int,
    transcript_path: Path | None = None,
) -> ChatResult:
    """Send a message to a known tmux session and stream the response.
    Shared core between main-session steering and sidekick Q&A.
    """
    if not tmux.session_exists(session):
        return ChatResult(text="", error=f"tmux session {session!r} is not running")
    pane_before = tmux.capture_pane(session, lines=8000)
    transcript_offset = transcript_path.stat().st_size if transcript_path and transcript_path.exists() else 0
    try:
        tmux.send_text(session, user_message)
    except Exception as e:
        return ChatResult(text="", error=f"send_text failed: {e}")
    pane_after = _wait_for_quiet(
        session,
        quiet_period=quiet_period,
        timeout=timeout_seconds,
        on_chunk=on_chunk,
        pane_before=pane_before,
        user_message=user_message,
        transcript_path=transcript_path,
        transcript_offset=transcript_offset,
    )
    response = (_read_claude_response(transcript_path, transcript_offset) if transcript_path else "")
    response = response or _extract_response(pane_before, pane_after, user_message)
    if not response:
        return ChatResult(
            text="",
            error=(
                "no response captured before timeout — Claude may still be "
                f"working. Attach: `tmux attach -t {session}`."
            ),
        )
    return ChatResult(text=response, error=None)


def ask_main_streaming(
    *,
    job: models.Job,
    user_message: str,
    on_chunk: Callable[[str], None] | None = None,
) -> ChatResult:
    """Send a chat message into the job's main tmux session — i.e. steer the
    running Claude. Shorter quiet/timeout than the sidekick path because the
    main session is usually mid-iteration and won't go fully quiet.
    """
    if not job.tmux_session:
        return ChatResult(text="", error="job has no tmux session")
    return _ask_in_session(
        session=job.tmux_session,
        user_message=user_message,
        on_chunk=on_chunk,
        quiet_period=1.5,
        timeout_seconds=120,
    )


def ask_sidekick_streaming(
    *,
    job: models.Job,
    user_message: str,
    claude_bin: str = "claude",
    workdir: Path | None = None,
    on_chunk: Callable[[str], None] | None = None,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
) -> ChatResult:
    """Send a message to the dedicated sidekick session. As the response
    forms in the tmux pane, `on_chunk` is called with progressively-longer
    partial responses. Returns the final ChatResult once the pane is quiet.
    """
    wd = workdir or Path(job.workdir)
    if not wd.exists():
        return ChatResult(text="", error=f"workdir {wd} does not exist")
    try:
        session = ensure_session(job, wd, claude_bin=claude_bin)
    except Exception as e:
        return ChatResult(text="", error=f"could not start sidekick session: {e}")
    return _ask_in_session(
        session=session,
        user_message=user_message,
        on_chunk=on_chunk,
        quiet_period=QUIET_PERIOD_SECONDS,
        timeout_seconds=timeout_seconds,
        transcript_path=(_sidekick_transcript_path(wd)
                         if getattr(job, "agent", None) in (None, "", "claude") else None),
    )


# Backwards-compat shim
def ask_sidekick(
    *,
    job: models.Job,
    user_message: str,
    claude_bin: str = "claude",
    workdir: Path | None = None,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    history=None,           # accepted, ignored — Claude has its own context
    pane_preview: str = "",  # accepted, ignored
) -> ChatResult:
    _ = history, pane_preview
    return ask_sidekick_streaming(
        job=job,
        user_message=user_message,
        claude_bin=claude_bin,
        workdir=workdir,
        timeout_seconds=timeout_seconds,
    )
