# n8n 工作流程：每日行程提醒 / 每日摘要 / 每週項目時間統計

這份文件說明如何用 n8n 建立三個排程工作流程，取代原本 Rails 內建的每日摘要排程（FR-007），並新增「每日行程提醒」（FR-009）跟「每週項目時間統計」（FR-010）。目的是在面試 demo 時展示「用 n8n 串接既有 API + LLM + LINE + Google Sheets 做自動化工作流程」的能力，不追求正式產品等級的錯誤處理或安全性。

工作流程 A、B 呼叫 Rails 的 `GET /api/v1/schedules?date=YYYY-MM-DD` 拿資料；工作流程 C（每週項目時間統計）**不經過 Rails**，直接用 n8n 內建的 Google Calendar node 讀 Google Calendar 的 `primary` 日曆（跟 `GoogleCalendarService::CALENDAR_ID` 是同一顆日曆）。呼叫 Gemini 做摘要、呼叫 LINE 推播訊息、寫入 Google Sheets，都直接在 n8n 裡用 HTTP Request / Google Sheets / Google Calendar node 完成。

## 前置準備

1. Rails 跑起來，並用 `ngrok http 3000` 開一個公開網址（跟設定 LINE webhook 用的是同一條 tunnel，`https://<你的 ngrok domain>`）。工作流程 C 不需要 Rails/ngrok，只有 A、B 需要。
2. 準備好：
   - LINE `channel_access_token`（跟 `bin/rails credentials:edit` 裡 `line.channel_access_token` 同一組）
   - LINE 要推播的 `user_id`（跟 `credentials.line.user_id` 同一組，取得方式見 README）
   - Gemini API Key（跟 `credentials.gemini.api_key` 同一組）
   - 一份 Google 試算表（工作流程 C 用，見下方「工作流程 C」的說明）跟一組有權限編輯它的 n8n Google Sheets OAuth2 credential
   - 一組 n8n 的 Google Calendar OAuth2 credential（工作流程 C 用，見下方「工作流程 C」的說明）
3. 工作流程 A、B 會呼叫 `GET /api/v1/schedules?date=...`，這個 endpoint 目前沒有身份驗證（demo 用途；正式環境要加）。

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

## [TODO]工作流程 B：每日摘要（23:00）

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

## 工作流程 C：每週項目時間統計（週一 08:00）

**用途**：每週一早上 08:00，直接讀 Google Calendar `primary` 日曆（跟 `GoogleCalendarService::CALENDAR_ID` 是同一顆日曆）上「上週一～上週日」這完整一週的所有事件，依事件標題（`summary`）分組加總時數，寫進 Google Sheet 做累積統計，並推播一則簡短摘要到 LINE。

**跟工作流程 A/B 的資料來源不一樣**：A、B 讀的是 Rails 本地 DB（`Schedule` table，只有這個系統建立的行程），工作流程 C 讀的是 Google Calendar 本身，所以除了這個系統建立、也會同步進日曆的行程之外，**使用者自己手動加在 `primary` 日曆上的事件也會被算進統計**。這是刻意的選擇——目的是統計「這個人這週時間實際花在哪些事情上」的完整全貌，不是只看這個系統管理的那一小部分。

**事前準備一份 Google 試算表**：建一份新的 Google Sheet，其中一個工作表（例如命名 `週統計`）第一列放表頭 `週期`、`項目`、`總時數`、`行程數`，把它的網址記下來，等下設定 Google Sheets node 時會用到；n8n 要用一組有這份試算表編輯權限的 Google Sheets OAuth2 credential。

**事前準備 n8n 的 Google Calendar OAuth2 credential**：跟 Rails 讀寫日曆用的是同一顆日曆，但 n8n 要自己走一次獨立的 OAuth 授權，不能直接借用 Rails 存在 `credentials.google.refresh_token` 裡的那組（那組 refresh token 是綁在 Rails 自己的 OAuth flow 上，n8n 沒辦法讀取 Rails 的 encrypted credentials）：

1. n8n 裡新增一個 Credential：`Google Calendar OAuth2 API`。
2. Client ID / Client Secret 可以直接重用 Rails 這邊 `config/google/credentials.json` 裡的同一組（一個 Google Cloud OAuth Client 本來就可以給多個服務共用，n8n 跟 Rails 走各自的授權流程，互不影響）。
3. 到 Google Cloud Console，替這個 OAuth Client 的「已授權的重新導向 URI」多加一筆 n8n 這個 credential 編輯畫面上顯示的 OAuth Redirect URL（本機跑 n8n 預設通常是 `http://localhost:5678/rest/oauth2-credential/callback`；用 ngrok/正式站台跑則是對應的網域）——這跟 Rails `bin/rails google:authorize` 用的 `http://localhost:8123/oauth2callback` 是分開的兩筆，都要各自加進同一個 OAuth Client。
4. 存檔後點 credential 畫面上的「Connect my account」，用同一個 Google 帳號（就是 Rails `google:authorize` 授權的那個帳號）走一次瀏覽器登入/同意畫面，跟 n8n 建立好連線。

**上週沒有行程時，不要整條工作流程跳過，而是明確寫一筆「無」**：上週完全沒行程也算一種正常結果，不是錯誤，所以 Google Sheet 跟 LINE 都應該看得到「這週有算過、結果是 0」，而不是安安靜靜什麼都不做。做法是讓 Node 4（分組加總）**一律輸出至少 1 個 item**：有事件就照項目分組輸出多筆，沒有事件就固定輸出 1 筆 `項目="無"`、`總時數=0`、`行程數=0`，Google Sheets／LINE 兩個 node 永遠都會執行，不需要額外的 If node 判斷要不要繼續。同一個原則也用來避免假資料：Node 4 只挑「真的有 `summary` 跟明確起訖時間」的事件來分組，其他不完整的項目（例如全天事件只有 `date` 沒有 `dateTime`，沒有明確時數可以算）一律過濾掉，不會被誤當成一筆有效資料。

| # | Node | 設定 |
| --- | --- | --- |
| 1 | **Schedule Trigger** | Trigger Interval: Weeks；Trigger on Weekdays: Monday；Trigger at Hour: `8`，Minute: `0` |
| 2 | **Code**（算出上週一～上週日的日期範圍） | 見下方程式碼，命名為「算出上週區間」，後面節點會用 `$('算出上週區間')` 取值 |
| 3 | **Google Calendar**（取得上週的日曆事件） | Resource: `Event`；Operation: `Get Many`；Credential: 上面設定好的 Google Calendar OAuth2；Calendar: `primary`；時間範圍（依你的 n8n 版本，欄位可能叫 After/Before 或 Start Time/End Time）：起點 `={{$('算出上週區間').item.json.start_date}}T00:00:00+08:00`，終點 `={{$('算出上週區間').item.json.end_date}}T23:59:59+08:00`；記得把 **Single Events** 選項打開（對應 Google Calendar API 的 `singleEvents=true`），不然重複性事件只會回傳一筆代表整條重複規則的 event，展開後才會是「上週實際發生的每一次」個別事件，加總時數才準確；「Get Many」會自動幫你把分頁抓完，不用自己處理 `nextPageToken` |
| 4 | **Code**（過濾非事件資料、依項目分組加總時數；沒有行程時固定輸出 1 筆「無」） | 見下方程式碼，命名為「分組加總」 |
| 5 | **Google Sheets**（寫入統計，每次都會執行） | Operation: `Append or Update Row`；Document: 上面建立的試算表；Sheet: `週統計`；Matching Columns: `週期`、`項目`（同一週重跑不會產生重複列，會直接更新該列；沒行程的那週會被記成 `項目="無"` 這一列）；`週期`/`項目`/`總時數`/`行程數` 四個欄位**每一個都要用表達式綁定** `={{$json.週期}}` / `={{$json.項目}}` / `={{$json.總時數}}` / `={{$json.行程數}}`，**不要留著 n8n 預設帶出來的欄位範例值**（字串欄位預設會顯示 `MyString` 這類 placeholder，忘記綁表達式、直接照預設值送出就是假資料跑進 Google Sheet 的成因之一） |
| 6 | **Code**（組出 LINE 摘要訊息，沒行程時改成提醒文字） | 見下方程式碼 |
| 7 | **HTTP Request**（推播到 LINE，每次都會執行） | 見下方「推播到 LINE」設定 |

Node 2 的程式碼：

```javascript
// 找出「上週一~上週日」
const now = new Date();

// getDay(): 0=週日,1=週一,...,6=週六 → 換算成距離「本週一」的天數
const dayOfWeek = now.getDay();
const diffToThisMonday = (dayOfWeek + 6) % 7;

const thisMonday = new Date(now);
thisMonday.setDate(now.getDate() - diffToThisMonday);
thisMonday.setHours(0, 0, 0, 0);

const lastMonday = new Date(thisMonday);
lastMonday.setDate(thisMonday.getDate() - 7);

const lastSunday = new Date(thisMonday);
lastSunday.setDate(thisMonday.getDate() - 1);
lastSunday.setHours(23, 59, 59, 999);

const fmt = (d) => d.toISOString().slice(0, 10);

return [{
  json: {
    start_date: fmt(lastMonday),
    end_date: fmt(lastSunday),
    week_label: `${fmt(lastMonday)} ~ ${fmt(lastSunday)}`
  }
}];
```

Node 4（「分組加總」）的程式碼：

```javascript
// Google Calendar node 的 Get Many 本來就是一個 event 一個 item，
// 不需要再猜測「陣列包一包」還是「一筆一個 item」這種格式問題
const items = $input.all().map(item => item.json);

// 只挑真的有標題、也有明確起訖時刻的事件；全天事件只有 date（沒有 dateTime），
// 沒有明確時數可以算，這裡直接跳過，不會被誤當成一筆有效資料
const events = items.filter(
  (e) => e && e.summary && e.start?.dateTime && e.end?.dateTime
);

const weekLabel = $('算出上週區間').item.json.week_label;

const totals = {};
for (const e of events) {
  const minutes = (new Date(e.end.dateTime) - new Date(e.start.dateTime)) / 60000;
  if (!totals[e.summary]) totals[e.summary] = { minutes: 0, count: 0 };
  totals[e.summary].minutes += minutes;
  totals[e.summary].count += 1;
}

let rows = Object.entries(totals).map(([title, { minutes, count }]) => ({
  週期: weekLabel,
  項目: title,
  總時數: Math.round((minutes / 60) * 10) / 10,
  行程數: count
}));

rows.sort((a, b) => b.總時數 - a.總時數);

// 上週完全沒有事件時，固定輸出這一筆「無」，讓 Google Sheet 跟 LINE 都能明確看到
// 「這週有統計過、結果是 0」，而不是讓工作流程沒東西可傳
if (rows.length === 0) {
  rows = [{ 週期: weekLabel, 項目: "無", 總時數: 0, 行程數: 0 }];
}

return rows.map(row => ({ json: row }));
```

Node 6（組出 LINE 摘要訊息）的程式碼：

```javascript
const rows = $input.all().map(item => item.json);
const weekLabel = rows[0]?.週期 ?? $('算出上週區間').item.json.week_label;

const isEmptyWeek = rows.length === 1 && rows[0].項目 === "無" && rows[0].行程數 === 0;

const message = isEmptyWeek
  ? `📊 上週（${weekLabel}）沒有任何行程紀錄，上週無行程。`
  : `📊 上週（${weekLabel}）時間統計已更新到 Google Sheet\n${
      rows.map(r => `🏆 ${r.項目}：${r.總時數} 小時（${r.行程數} 筆）`).join("\n")
    }`;

return [{ json: { message } }];
```

## 共用設定：推播到 LINE

三個工作流程最後一步都是同一種 HTTP Request 設定（工作流程 C 不管上週有沒有行程都會推播，只是訊息內容不同）：

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
| FR-009 每日行程提醒（09:00） | n8n 工作流程 A | 單純「讀資料 → 格式化 → 推播」，n8n 最擅長的形狀 |
| FR-007 每日摘要（23:00） | n8n 工作流程 B | 「讀資料 → 呼叫 LLM → 推播」，展示 n8n 串 AI 的能力 |
| FR-010 每週項目時間統計（週一 08:00） | n8n 工作流程 C | 「直接讀 Google Calendar API → 分組加總 → 寫 Google Sheets → 推播」，完全不經過 Rails，展示 n8n 串接 Google Calendar + Google Sheets 兩個外部服務做累積統計報表的能力 |
