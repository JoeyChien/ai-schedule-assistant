# n8n 工作流程：每日行程提醒 / 每日摘要 / 每週項目時間統計

這份文件說明如何用 n8n 建立三個排程工作流程，取代原本 Rails 內建的每日摘要排程（FR-007），並新增「每日行程提醒」（FR-009）跟「每週項目時間統計」（FR-010）。目的是在面試 demo 時展示「用 n8n 串接既有 API + LLM + LINE + Google Sheets 做自動化工作流程」的能力，不追求正式產品等級的錯誤處理或安全性。

Rails 這邊只負責提供資料（`GET /api/v1/schedules?date=YYYY-MM-DD` 或 `?start_date=...&end_date=...`），呼叫 Gemini 做摘要、呼叫 LINE 推播訊息、寫入 Google Sheets，都直接在 n8n 裡用 HTTP Request / Google Sheets node 完成，不需要另外幫 n8n 開任何新的 Rails endpoint。

## 前置準備

1. Rails 跑起來，並用 `ngrok http 3000` 開一個公開網址（跟設定 LINE webhook 用的是同一條 tunnel，`https://<你的 ngrok domain>`）。
2. 準備好：
   - LINE `channel_access_token`（跟 `bin/rails credentials:edit` 裡 `line.channel_access_token` 同一組）
   - LINE 要推播的 `user_id`（跟 `credentials.line.user_id` 同一組，取得方式見 README）
   - Gemini API Key（跟 `credentials.gemini.api_key` 同一組）
   - 一份 Google試算表（工作流程 C 用，見下方「工作流程 C」的說明）跟一組有權限編輯它的 n8n Google Sheets OAuth2 credential
3. 這三個工作流程都會呼叫 `GET /api/v1/schedules`（帶 `date` 或 `start_date`/`end_date`），這個 endpoint 目前沒有身份驗證（demo 用途；正式環境要加）。

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

**用途**：每週一早上 08:00，抓「上週一～上週日」這完整一週的行程，依 `title`（行程標題，例如「健身」「閱讀」「開會」）分組加總時數，寫進 Google Sheet 做累積統計，並推播一則簡短摘要到 LINE。目前 `Schedule` 資料表沒有獨立的「項目／分類」欄位，這裡直接把 `title` 當作項目名稱使用。

**事前準備一份 Google 試算表**：建一份新的 Google Sheet，其中一個工作表（例如命名 `週統計`）第一列放表頭 `週期`、`項目`、`總時數`、`行程數`，把它的網址記下來，等下設定 Google Sheets node 時會用到；n8n 要用一組有這份試算表編輯權限的 Google Sheets OAuth2 credential。

| # | Node | 設定 |
| --- | --- | --- |
| 1 | **Schedule Trigger** | Trigger Interval: Weeks；Trigger on Weekdays: Monday；Trigger at Hour: `8`，Minute: `0` |
| 2 | **Code**（算出上週一～上週日的日期範圍） | 見下方程式碼，命名為「算出上週區間」，後面節點會用 `$('算出上週區間')` 取值 |
| 3 | **HTTP Request**（取得上週行程） | Method: `GET`；URL: `https://<ngrok-domain>/api/v1/schedules`；Query Parameter：`start_date` = `={{$('算出上週區間').item.json.start_date}}`，`end_date` = `={{$('算出上週區間').item.json.end_date}}` |
| 4 | **Code**（依項目分組加總時數） | 見下方程式碼 |
| 5 | **Google Sheets**（寫入統計） | Operation: `Append or Update Row`；Document: 上面建立的試算表；Sheet: `週統計`；Matching Columns: `週期`、`項目`（同一週重跑不會產生重複列，會直接更新該列）；其餘欄位 `總時數`、`行程數` 對應 Node 4 輸出的同名欄位 |
| 6 | **Code**（組出 LINE 摘要訊息） | 見下方程式碼 |
| 7 | **HTTP Request**（推播到 LINE） | 見下方「推播到 LINE」設定 |

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

Node 4 的程式碼：

```javascript
const raw = $input.all();
const schedules = raw.length === 1 && Array.isArray(raw[0].json)
  ? raw[0].json
  : raw.map(item => item.json);

const weekLabel = $('算出上週區間').item.json.week_label;

const totals = {};
for (const s of schedules) {
  const minutes = (new Date(s.end_time) - new Date(s.start_time)) / 60000;
  if (!totals[s.title]) totals[s.title] = { minutes: 0, count: 0 };
  totals[s.title].minutes += minutes;
  totals[s.title].count += 1;
}

const rows = Object.entries(totals).map(([title, { minutes, count }]) => ({
  週期: weekLabel,
  項目: title,
  總時數: Math.round((minutes / 60) * 10) / 10,
  行程數: count
}));

rows.sort((a, b) => b.總時數 - a.總時數);

return rows.map(row => ({ json: row }));
```

如果上週完全沒有任何行程，Node 4 會回傳 0 個 item，後面的 Google Sheets／LINE node 也就不會執行（不會新增空列，也不會推播）——這是刻意的行為，demo 用途暫不特別處理這個邊界情況。

Node 6 的程式碼：

```javascript
const rows = $input.all().map(item => item.json);
const weekLabel = rows[0]?.週期 ?? $('算出上週區間').item.json.week_label;

const top = rows.slice(0, 3)
  .map(r => `🏆 ${r.項目}：${r.總時數} 小時（${r.行程數} 筆）`);

return [{
  json: {
    message: `📊 上週（${weekLabel}）時間統計已更新到 Google Sheet\n${top.join("\n")}`
  }
}];
```

## 共用設定：推播到 LINE

三個工作流程最後一步（工作流程 C 是「有資料才推播」）都是同一種 HTTP Request 設定：

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
| FR-010 每週項目時間統計（週一 08:00） | n8n 工作流程 C | 「讀資料（區間查詢）→ 分組加總 → 寫 Google Sheets → 推播」，展示 n8n 串接 Google Sheets 做累積統計報表的能力，同樣不需要在 Rails 端寫任何額外的統計邏輯 |
