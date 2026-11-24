// Disposable, non-trading EA for BotPulse instrumentation validation only.
#property strict
#property version   "1.00"
#property description "Emits BotPulse evaluation heartbeats. Never sends trade requests."

#include <BotPulse.mqh>

input int  ExpectedHeartbeatSeconds=60;
input bool EnableTimedSuppression=true;
input int  SuppressAfterSeconds=180;
input int  ValidationEvidenceSeconds=5;

ulong    g_demo_tick_count=0;
ulong g_demo_evaluation_count=0;
ulong g_demo_timer_count=0;
datetime g_demo_started_at=0;
datetime g_demo_suppression_started_at=0;
datetime g_demo_last_tick_observed_at=0;
datetime g_demo_last_evidence_emit=0;
bool     g_demo_suppression_active=false;
string   g_demo_evidence_file="";

bool DemoAppendEvidence(const string line)
  {
   const int flags=FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_COMMON;
   const int handle=FileOpen(g_demo_evidence_file,flags,0,CP_UTF8);
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("BotPulse demo validation: FileOpen failed for %s, error=%d",g_demo_evidence_file,GetLastError());
      return false;
     }
   if(!FileSeek(handle,0,SEEK_END))
     {
      PrintFormat("BotPulse demo validation: FileSeek failed for %s, error=%d",g_demo_evidence_file,GetLastError());
      FileClose(handle);
      return false;
     }
   const uint written=FileWriteString(handle,line+"\n");
   FileFlush(handle);
   FileClose(handle);
   return written>0;
  }

bool DemoEmitEvidence(const string event_name)
  {
   const datetime now=TimeGMT();
   if(now<=0)
      return false;
   const bool connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   const string payload=StringFormat(
      "{\"validation_schema_version\":1,\"event\":\"%s\","
      "\"instance_id\":\"%s\",\"session_epoch\":\"%s\","
      "\"timestamp_unix\":%I64d,\"terminal_alive\":true,\"broker_connected\":%s,"
      "\"last_tick_observed_at_unix\":%I64d,\"tick_count\":%I64u,"
      "\"evaluation_loop_count\":%I64u,\"timer_count\":%I64u,"
      "\"suppression_active\":%s,\"suppression_started_at_unix\":%I64d}",
      event_name,
      BotPulseInstanceId(),
      BotPulseSessionEpoch(),
      (long)now,
      (connected ? "true" : "false"),
      (long)g_demo_last_tick_observed_at,
      g_demo_tick_count,
      g_demo_evaluation_count,
      g_demo_timer_count,
      (g_demo_suppression_active ? "true" : "false"),
      (long)g_demo_suppression_started_at);
   const bool emitted=DemoAppendEvidence(payload);
   if(emitted)
      g_demo_last_evidence_emit=now;
   return emitted;
  }

int OnInit()
  {
   if(ExpectedHeartbeatSeconds<=0 || SuppressAfterSeconds<=0 || ValidationEvidenceSeconds<=0)
     {
      Print("BotPulse demo validation: all timing inputs must be positive");
      return INIT_PARAMETERS_INCORRECT;
     }
   // Monitoring is fail-open: an emission failure is logged but does not alter EA behavior.
   BotPulseInit("BotPulseDemoEA",ExpectedHeartbeatSeconds);
   g_demo_started_at=TimeGMT();
   g_demo_evidence_file=StringFormat("BotPulseValidation\\%s.jsonl",BPHash(BotPulseSessionEpoch()));
   DemoEmitEvidence("VALIDATION_INIT");
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   // This counter is the disposable demo's entire "evaluation loop".
   g_demo_tick_count++;
   g_demo_evaluation_count++;
   g_demo_last_tick_observed_at=TimeGMT();
   if(!g_demo_suppression_active)
      BotPulseBeat();
  }

void OnTimer()
  {
   // Visible proof that the EA event queue remains responsive during simulated heartbeat stall.
   g_demo_timer_count++;
   const datetime now=TimeGMT();
   if(EnableTimedSuppression && !g_demo_suppression_active &&
      now>0 && g_demo_started_at>0 && (now-g_demo_started_at)>=SuppressAfterSeconds)
     {
      g_demo_suppression_active=true;
      g_demo_suppression_started_at=now;
      DemoEmitEvidence("SUPPRESSION_START");
     }
   if(g_demo_last_evidence_emit<=0 || (now-g_demo_last_evidence_emit)>=ValidationEvidenceSeconds)
      DemoEmitEvidence("PLATFORM_EVIDENCE");
   Comment(StringFormat("BotPulse validation only\nTicks: %I64u\nEvaluations: %I64u\nTimer events: %I64u\nInstance: %s\nEpoch: %s\nHeartbeat suppressed: %s\nSuppressed at UTC: %s",
                        g_demo_tick_count,
                        g_demo_evaluation_count,
                        g_demo_timer_count,
                        BotPulseInstanceId(),
                        BotPulseSessionEpoch(),
                        (g_demo_suppression_active ? "YES" : "NO"),
                        TimeToString(g_demo_suppression_started_at,TIME_DATE|TIME_SECONDS)));
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DemoEmitEvidence("VALIDATION_DEINIT");
   BotPulseShutdown(reason);
   Comment("");
  }
