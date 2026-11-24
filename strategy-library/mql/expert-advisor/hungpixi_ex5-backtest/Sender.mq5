//+------------------------------------------------------------------+
//|                                                    Sender_v2.mq5 |
//|                               Copyright 2025, Antigravity AI     |
//|                                         https://www.mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Antigravity AI"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

// Thư viện giao dịch chuẩn của MQL5 (để đóng lệnh dễ dàng)
#include <Trade\Trade.mqh>
CTrade trade;

// --- INPUTS ---
input group "Server Settings"
input string API_URL = "http://127.0.0.1:8000/api/v1"; // Địa chỉ API Backend (Default Localhost)
input string API_KEY = "YOUR_API_KEY_HERE";               // Khóa bảo mật (quan trọng)
input int TIMER_SECONDS = 30;                            // Chu kỳ gửi báo cáo (giây)

input group "Equity Guard (Safety)"
input double EQUITY_TARGET = 0; // Mức chốt lời tổng ($). 0 = Tắt
input double EQUITY_STOP = 0;   // Mức cắt lỗ tổng ($). 0 = Tắt
input bool   CLOSE_ON_TRIGGER = true; // Tự động đóng hết lệnh khi chạm ngưỡng?

// --- GLOBALS ---
bool g_IsLocked = false; // Biến cờ để đánh dấu tài khoản đã bị khoá chưa

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Bật WebRequest
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Warning: AutoTrading is disabled!");
      
   // Thiết lập Timer gửi dữ liệu
   EventSetTimer(TIMER_SECONDS);
   
   Print(">> Sender Optimized Initialized.");
   Print(">> Monitoring Account: ", AccountInfoInteger(ACCOUNT_LOGIN));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| OnTick function (Quan trọng: Kiểm tra an toàn từng tích tắc)     |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Chỉ chạy kiểm tra nếu chưa bị khoá
   if (!g_IsLocked) CheckEquityGuard();
  }

//+------------------------------------------------------------------+
//| Timer function (Gửi báo cáo định kỳ)                             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   SendSnapshot();
  }

//+------------------------------------------------------------------+
//| Logic bảo vệ tài khoản (Equity Guard)                            |
//+------------------------------------------------------------------+
void CheckEquityGuard()
  {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   string reason = "";

   // 1. Kiểm tra Chốt lời
   if(EQUITY_TARGET > 0 && currentEquity >= EQUITY_TARGET)
     {
      reason = "TARGET_REACHED";
     }

   // 2. Kiểm tra Cắt lỗ
   if(EQUITY_STOP > 0 && currentEquity <= EQUITY_STOP)
     {
      reason = "STOP_LOSS_HIT";
     }

   // Nếu vi phạm điều kiện
   if(reason != "")
     {
      Print("!!! EQUITY GUARD TRIGGERED: ", reason, " Current: ", currentEquity);
      
      if(CLOSE_ON_TRIGGER)
        {
         CloseAllPositions();
         g_IsLocked = true; // Khoá lại không cho check nữa
         
         // Gửi cảnh báo khẩn cấp ngay lập tức (không đợi timer)
         SendAlert(reason, currentEquity);
        }
     }
  }

//+------------------------------------------------------------------+
//| Hàm gửi dữ liệu Snapshot lên Server                              |
//+------------------------------------------------------------------+
void SendSnapshot()
  {
   string endpoint = API_URL + "/data/push";
   
   // Xây dựng JSON thủ công (Gọn gàng hơn)
   string json = StringFormat(
      "{\"account_id\": %d, \"balance\": %.2f, \"equity\": %.2f, \"margin\": %.2f, \"free_margin\": %.2f, \"profit\": %.2f, \"positions\": %d, \"is_locked\": %s}",
      AccountInfoInteger(ACCOUNT_LOGIN),
      AccountInfoDouble(ACCOUNT_BALANCE),
      AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoDouble(ACCOUNT_MARGIN),
      AccountInfoDouble(ACCOUNT_MARGIN_FREE),
      AccountInfoDouble(ACCOUNT_PROFIT),
      PositionsTotal(),
      (g_IsLocked ? "true" : "false")
   );
   
   // Gửi Request
   string response = SendWebRequest(endpoint, json);
   
   // --- XỬ LÝ LỆNH TỪ SERVER (COMMAND RELAY) ---
   // Giả sử Server trả về: {"command": "CLOSE_ALL"} hoặc {"command": "NONE"}
   if (StringFind(response, "CLOSE_ALL") >= 0) 
     {
      Print(">> Command received from Server: CLOSE ALL POSITIONS");
      CloseAllPositions();
     }
   else if (StringFind(response, "UNLOCK") >= 0)
     {
      Print(">> Command received from Server: UNLOCK ACCOUNT");
      g_IsLocked = false;
     }
  }

//+------------------------------------------------------------------+
//| Hàm gửi cảnh báo khẩn cấp (Alert)                                |
//+------------------------------------------------------------------+
void SendAlert(string reason, double value)
  {
   string endpoint = API_URL + "/alert/push";
   string json = StringFormat(
      "{\"account_id\": %d, \"type\": \"CRITICAL\", \"message\": \"%s\", \"value\": %.2f}",
      AccountInfoInteger(ACCOUNT_LOGIN), reason, value
   );
   SendWebRequest(endpoint, json);
  }

//+------------------------------------------------------------------+
//| Hàm Wrapper cho WebRequest (Tái sử dụng code)                    |
//+------------------------------------------------------------------+
string SendWebRequest(string url, string payload)
  {
   char data[];
   StringToCharArray(payload, data, 0, StringLen(payload));
   
   char result[];
   string result_headers;
   
   // Thêm Authorization Header
   string headers = "Content-Type: application/json\r\n";
   headers += "Authorization: Bearer " + API_KEY + "\r\n"; // API Key bảo mật
   
   // Timeout 3000ms (3 giây) để không làm lag Terminal
   int res = WebRequest("POST", url, headers, 3000, data, result, result_headers);
   
   if (res == -1)
     {
      int err = GetLastError();
      // Bỏ qua lỗi 4060 nếu mới chạy lần đầu chưa kịp cấu hình
      if(err != 4060) Print("WebRequest Error: ", err);
      return "";
     }
   
   // Chuyển kết quả từ char array sang string
   string response_str = CharArrayToString(result);
   return response_str;
  }

//+------------------------------------------------------------------+
//| Hàm đóng tất cả lệnh (Sử dụng CTrade)                            |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   Print(">> CLOSING ALL POSITIONS...");
   
   int total = PositionsTotal();
   // Duyệt ngược từ dưới lên để tránh lỗi index khi đóng
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(!trade.PositionClose(ticket))
           {
            Print("Failed to close ticket: ", ticket, " Error: ", GetLastError());
           }
         else
           {
            Print("Closed ticket: ", ticket);
           }
        }
     }
   Print(">> Close All Sequence Finished.");
  }
//+------------------------------------------------------------------+

double OnTester()
{
   if(!MQLInfoInteger(MQL_TESTER)) return 0;

   double profit = TesterStatistics(STAT_PROFIT);
   double dd     = TesterStatistics(STAT_EQUITY_DD_RELATIVE);

   if(dd > 0.0001) return profit / dd;
   return profit;
}
