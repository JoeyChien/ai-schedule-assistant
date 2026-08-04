# n8n 工作流程：每日行程提醒 / 每日摘要

這份文件說明如何用 n8n 建立兩個排程工作流程，取代原本 Rails 內建的每日摘要排程（FR-007），並新增一個「每日行程提醒」。目的是在面試 demo 時展示「用 n8n 串接既有 API + LLM + LINE 做自動化工作流程」的能力，不追求正式產品等級的錯誤處理或安全性。

Rails 這邊只負責提供資料（`GET /api/v1/schedules?date=YYYY-MM-DD`），呼叫 Gemini 做摘要、呼叫 LINE 推播訊息，都直接在 n8n 裡用 HTTP Request node 完成，不需要另外幫 n8n 開任何新的 Rails endpoint。

## 前置準備

1. Rails 跑起來，並用 `ngrok http 3000` 開一個公開網址（跟設定 LINE webhook 用的是同一條 tunnel，`https://<你的 ngrok domain>`）。
2. 準備好：
   - LINE `channel_access_token`（跟 `bin/rails credentials:edit` 裡 `line.channel_access_token` 同一組）
   - LINE 要推播的 `user_id`（跟 `credentials.line.user_id` 同一組，取得方式見 README）
   - Gemini API Key（跟 `credentials.gemini.api_key` 同一組）
3. 這兩個工作流程都會呼叫 `GET /api/v1/schedules?date=...`，這個 endpoint 目前沒有身份驗證（demo 用途；正式環境要加）。

## 工作流程 A：每日行程提醒（09:00）

**用途**：每天早上 09:00，把當天已經排定的行程整理成清單推播到 LINE。純資料轉換，不需要呼叫 AI。

| # | Node | 設定 |
| --- | --- | --- |
| 1 | **Schedule Trigger** | Trigger Interval: Days；Trigger at Hour: `9`，Minute: `0` |
| 2 | **HTTP Request**（取得今日行程） | Method: `GET`；URL: `https://<ngrok-domain>/api/v1/schedules`；Query Parameter：`date` = `{{$now.format('yyyy-LL-dd')}}` |
| 3 | **Code**（格式化訊息，JavaScript） | 見下方程式碼 |
| 4 | **HTTP Request**（推播到 LINE） | 見下方「推播到 LINE」設定 |

Node 3 的程式碼：

```javascript
// HTTP Request 回傳 JSON 陣列時，依 n8n 版本可能是「一個 item 裝整個陣列」
// 或「每筆資料各自一個 item」，這裡兩種都相容
const raw = $input.all();
const schedules = raw.length === 1 && Array.isArray(raw[0].json)
  ? raw[0].json
  : raw.map(item => item.json);

if (schedules.length === 0) {
  return [{ json: { message: "📅 今天目前沒有安排的行程，好好安排一下吧！" } }];
}

const lines = schedules.map(s => {
  const start = new Date(s.start_time);
  const hh = String(start.getHours()).padStart(2, "0");
  const mm = String(start.getMinutes()).padStart(2, "0");
  return `⏰ ${hh}:${mm} 📌 ${s.title}`;
});

return [{ json: { message: `☀️ 早安！今天的安排：\n${lines.join("\n")}` } }];
```

## 工作流程 B：每日摘要（23:00）

**用途**：每天晚上 23:00，讀取當天行程，交給 Gemini 整理成「完成／未完成／明日建議」的摘要文字，推播到 LINE。對照 Rails 裡原本的 `Schedules::DailySummaryService`（現在改由這個 n8n 工作流程負責觸發，Rails 那份程式碼還在、也還有測試，只是不再自動排程）。

| # | Node | 設定 |
| --- | --- | --- |
| 1 | **Schedule Trigger** | Trigger Interval: Days；Trigger at Hour: `23`，Minute: `0` |
| 2 | **HTTP Request**（取得今日行程） | 跟工作流程 A 的 Node 2 相同 |
| 3 | **Code**（組出摘要用的 Prompt） | 見下方程式碼 |
| 4 | **HTTP Request**（呼叫 Gemini） | Method: `POST`；URL: `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key=<你的 Gemini API Key>`；Body（JSON）：`{ "contents": [ { "parts": [ { "text": "={{$json.prompt}}" } ] } ] }` |
| 5 | **Code**（取出摘要文字） | 見下方程式碼 |
| 6 | **HTTP Request**（推播到 LINE） | 見下方「推播到 LINE」設定 |

Node 3 的程式碼：

```javascript
const raw = $input.all();
const schedules = raw.length === 1 && Array.isArray(raw[0].json)
  ? raw[0].json
  : raw.map(item => item.json);

const now = new Date();
const completed = schedules.filter(s => new Date(s.end_time) <= now);
const upcoming = schedules.filter(s => new Date(s.end_time) > now);

const listText = (items) => items.length ? items.map(s => `- ${s.title}`).join("\n") : "（無）";

const prompt = `你是一位貼心的生活助理，請用溫暖簡短的語氣整理今天的行程摘要，用繁體中文回覆，不要輸出 Markdown。

已完成的行程：
${listText(completed)}

尚未完成的行程：
${listText(upcoming)}

請用以下格式輸出：
📅 今日摘要

✅ <已完成事項>

🕒 <尚未完成事項>

📊 今天完成率：<百分比>%

建議：<給明天的一句簡短建議>`;

return [{ json: { prompt } }];
```

Node 5 的程式碼（Gemini 回傳的是巢狀 JSON，要把純文字挖出來）：

```javascript
const text = $json.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
return [{ json: { message: text || "📅 今日摘要整理失敗，請自行查看 Google Calendar。" } }];
```

## 共用設定：推播到 LINE

兩個工作流程最後一步都是同一種 HTTP Request 設定：

- Method: `POST`
- URL: `https://api.line.me/v2/bot/message/push`
- Headers：
  - `Authorization`: `Bearer <LINE channel_access_token>`
  - `Content-Type`: `application/json`
- Body（JSON）：
  ```json
  {
    "to": "<LINE user_id>",
    "messages": [
      { "type": "text", "text": "={{$json.message}}" }
    ]
  }
  ```

建議把 `channel_access_token` 存成 n8n 的 Header Auth credential（而不是直接寫死在 node 參數裡），Gemini API Key 同理可以用 n8n 的 credential 管理，demo 時比較不會不小心截圖洩漏金鑰。

## 跟 Rails 原生排程的分工

| 功能 | 觸發方式 | 為什麼 |
| --- | --- | --- |
| FR-005/006 每日固定行程自動排空檔（07:00） | Rails `config/recurring.yml` + `DailyHabitSchedulingJob` | 需要撞期檢查、空檔演算法這類「有狀態的業務邏輯」，比較適合寫在程式碼裡，n8n 節點硬做會很勉強 |
| 每日行程提醒（09:00） | n8n 工作流程 A | 單純「讀資料 → 格式化 → 推播」，n8n 最擅長的形狀 |
| FR-007 每日摘要（23:00） | n8n 工作流程 B | 「讀資料 → 呼叫 LLM → 推播」，展示 n8n 串 AI 的能力 |
