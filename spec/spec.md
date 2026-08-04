# 開發文件

# AI Schedule Assistant

> AI Agent for Smart Calendar & Workflow Automation
> 

---

# 📌 專案資訊

| 項目 | 說明 |
| --- | --- |
| 專案名稱 | AI Schedule Assistant |
| 作者 | Joie |
| 專案類型 | AI Workflow / Automation / LLM Agent |
| 開發目標 | 建立 AI 自動化排程助理 |
| 預計開發時間 | 5~7 天 |
| 狀態 | Planning |

---

# 一、專案背景（Background）

現代人每天需要管理工作、運動、學習與生活行程。

雖然 Google Calendar 能夠管理行程，但仍有許多痛點：

- 必須手動新增事件
- 無法理解自然語言
- 不會依照使用者目標安排空檔
- 行程衝突需要自己調整
- 習慣養成需要自行安排

因此，希望打造一個 **AI 智慧排程助理**，讓使用者只需透過 LINE 傳送一句話，即可完成整個排程流程。

---

# 二、專案目標（Objective）

打造一套 AI Workflow，完成以下功能：

- ✅ 自然語言建立 Google Calendar
- ✅ 修改 Google Calendar
- ✅ 刪除 Google Calendar
- ✅ 自動找空檔安排想養成的習慣
- ✅ AI 分析空檔
- ✅ 每日摘要
- ✅ 每日建議

降低人工建立行程成本，提高時間管理效率。

---

# 三、作品亮點（Portfolio Highlights）

本作品展示：

- AI Agent Workflow
- LLM API 串接
- Google Calendar API
- LINE Bot
- Prompt Engineering
- n8n Workflow
- Business Process Automation
- Workflow Design
- API Integration
- AI Decision Making

---

# 四、使用情境（User Story）

## User Story 1

身為一位上班族，

我希望透過 LINE 傳一句話：

> 明天下午五點健身
> 

即可建立 Google Calendar 行程。

---

## User Story 2

身為需要培養習慣的人，

我希望 AI 能自動找到今天空檔，

安排：

- 閱讀
- 散步
- 英文
- 重訓

而不用自己思考。

---

## User Story 3

如果今天已經排滿，

AI 可以自動改排明天。

---

## User Story 4

每天晚上收到：

- 今天完成哪些事情
- 哪些尚未完成
- 明天建議安排

---

# 五、系統架構（Architecture）

```
LINE
↓
Webhook
↓
n8n
↓
LLM
↓
Intent Parser
↓
Google Calendar API
↓
AI Decision
↓
Google Calendar
↓
LINE Reply
```

---

# 六、技術架構

| Layer | Technology |
| --- | --- |
| Bot | LINE Messaging API |
| Workflow | n8n |
| AI | Gemini API |
| Calendar | Google Calendar API |
| Database | Supabase |
| Backend（Optional） | Spring Boot |
| Hosting | Railway / Render |
| Version Control | GitHub |

---

# 七、系統流程

## 建立行程

```
LINE
↓
Webhook
↓
LLM 解析
↓
JSON
↓
Google Calendar
↓
建立 Event
↓
LINE 回覆
```

---

## AI 自動安排

```
Cron Trigger
↓
讀取 Google Calendar
↓
分析空檔
↓
LLM 排程
↓
Create Event
↓
LINE 通知
```

---

## 每日摘要

```
Cron Trigger
↓
取得今日 Event
↓
LLM Summary
↓
LINE 推播
```

---

# 八、功能需求（Functional Requirements）

## FR-001 建立行程

### Input

> 明天下午五點健身
> 

### Output

Google Calendar 新增：

| Title | Time |
| --- | --- |
| 健身 | Tomorrow 17:00 |

---

## FR-002 修改行程

### Input

> 今天健身改七點
> 

系統：

- 搜尋今日健身
- 更新時間
- 回覆成功

---

## FR-003 刪除行程

### Input

> 取消今天健身
> 

系統：

- 搜尋 Event
- Delete Event

---

## FR-004 查詢行程

### Input

> 今天有什麼安排？
> 

系統：

讀取 Google Calendar

↓

整理成訊息

↓

LINE 回覆

### 實作備註

- 查詢的資料來源是本地資料庫（`Schedule` table），不是即時打 Google Calendar API。因為目前所有由本系統建立的行程，本來就會同時寫入 Google Calendar 與本地 DB（兩邊互為鏡像），查本地 DB 更快、也不受 Google API 額度限制。
- Gemini 解析出 `action: "QUERY"` 時，會一併給出查詢區間的 `start_time` / `end_time`（例如「今天」→ 當天 00:00–23:59；「這週」→ 週一–週日），交給 `Schedules::QueryService` 查詢並依開始時間排序整理成訊息。
- 目前只有 LINE 對話（`Schedules::CommandService`）支援 QUERY；REST API 的 `POST /api/v1/schedules/parse` 目前仍固定只走建立流程（`Schedules::CreationService`），尚未串接完整的意圖分派。

---

## FR-005 AI 安排固定習慣

### Input

> 幫我安排本週三次重訓
> 

AI：

- 查詢 Calendar
- 找空檔
- 建立三筆 Event

### 實作備註（v1.0 範圍調整）

- v1.0 只實作了 FR-006「每天自動排固定習慣」，這種**使用者在對話中臨時要求**排程（例如「幫我安排本週三次重訓」）尚未實作，`Schedules::CommandService` 收到這類意圖時仍會回覆「這個功能還在開發中」。
- `ParsedIntent::ACTIONS` 已經預留 `FIND_FREE_TIME`，之後要做這個功能時可以直接沿用。

---

## FR-006 每日固定行程

每天 07:00

系統：

- 讀取今日 Calendar
- 若有空檔
- AI 安排：
    - 閱讀
    - 散步
    - 英文
    - 冥想

### 實作備註

- 由 `DailyHabitSchedulingJob` 執行，核心邏輯在 `Schedules::HabitSchedulingService`：
  1. `Schedules::FreeSlotFinder` 呼叫 `GoogleCalendarService#find_free_busy` 取得當天 08:00–22:00 的忙碌時段，算出空檔。
  2. 依序把「閱讀 30 分 / 散步 30 分 / 英文 30 分 / 冥想 15 分」塞進空檔（今天已經有同名行程就跳過；空檔不夠長也會跳過）。
  3. 成功建立的行程會同時寫入 Google Calendar 與本地 DB（`source: "habit_auto"`），並透過 LINE Push Message 通知結果（含跳過的項目與原因）。
- 固定習慣清單目前是程式常數 `Schedules::HabitSchedulingService::DAILY_HABITS`（寫死在程式碼），還沒有做十一、資料模型章節的 `Habit` 資料表 —— 那屬於 Roadmap v1.5「Habit Management」的範圍。
- 排程時間對照 `config/recurring.yml` 的 `schedule_daily_habits`（正式環境 07:00，時區依 `config.time_zone`／`Asia/Taipei`）。

---

## FR-007 每日摘要

每天 23:00

AI 整理：

- 完成事項
- 未完成事項
- 明日建議

LINE 推播。

### 實作備註

- 由 `DailySummaryJob` 執行，核心邏輯在 `Schedules::DailySummaryService`。
- 目前資料模型沒有「完成狀態」欄位，因此用 `end_time <= 現在時間` 當作「已完成」的判斷依據，其餘視為「尚未完成」。
- 摘要文字交給 Gemini（AI-004）依 `prompts/daily_summary.txt.erb` 產生；若 Gemini 呼叫失敗或回傳空白，會自動退回程式產生的純文字版本，確保每天的推播不會因為 AI 服務問題而整個失敗。
- 明日建議目前用「固定習慣清單裡，今天還沒排過的第一項」帶出（例如今天沒做「英文」，就建議明天安排英文）。
- 排程時間對照 `config/recurring.yml` 的 `send_daily_summary`（正式環境 23:00）。

---

## FR-006 / FR-007 共通：LINE 主動推播

- 這兩個排程都是系統主動發訊息（不是回覆使用者訊息），走的是 LINE Messaging API 的 **Push Message**，跟 FR-001~004 用的 Reply Message（需要 `reply_token`，且有時效限制）不同，實作在 `Line::WebhookService#push_text`。
- 推播對象是 `Rails.application.credentials.dig(:line, :user_id)`，需要先跟機器人互動過一次、從 server log 取得 `user_id` 後手動設定（見 README「首次設定」第 4 步）。
- 正式環境靠 `config/recurring.yml` + Solid Queue 觸發（`SOLID_QUEUE_IN_PUMA`，見 `config/deploy.yml`）；本機開發環境預設不會自動排程，需要用 `bin/rails runner` 手動觸發測試（見 README「測試每日固定行程 / 每日摘要」）。

---

# 九、AI 功能

## AI-001 Intent Detection

辨識：

- 建立
- 修改
- 刪除
- 查詢
- 安排

---

## AI-002 Natural Language Parsing

Input

> 今天晚上七點吃飯
> 

Output

```json
{
  "title":"吃飯",
  "date":"2026-08-02",
  "start":"19:00",
  "duration":90
}
```

---

## AI-003 Schedule Planning

依據：

- Google Calendar
- Habit
- Priority
- Deadline
- Time Preference

決定最佳安排。

---

## AI-004 Daily Summary

整理：

- 今日完成事項
- 今日未完成事項
- 明日建議

---

# 十、Prompt Design

## System Prompt

```
你是一位智慧生活助理。
請依照：
Google Calendar
目前所有事件
Habit
Priority
Deadline
分析最佳空檔。
若今天沒有空檔，
請安排明天。
回傳 JSON。
不要輸出 Markdown。
```

---

# 十一、資料模型

## Habit

> v1.0 尚未建立這張表，FR-006 的固定習慣清單目前是寫死在 `Schedules::HabitSchedulingService::DAILY_HABITS`。這張表屬於 Roadmap v1.5「Habit Management」的範圍。

| Field | Type |
| --- | --- |
| id | UUID |
| name | String |
| frequency | Enum |
| duration | Integer |
| priority | Integer |
| preferredTime | Enum |
| enabled | Boolean |

---

## Calendar Event

| Field | Type |
| --- | --- |
| title | String |
| start | DateTime |
| end | DateTime |
| category | String |
| source | String |
| createdAt | DateTime |

---

# 十二、Workflow

## Workflow A

建立行程

```
LINE
↓
Webhook
↓
LLM
↓
Google Calendar
↓
Reply
```

---

## Workflow B

AI 安排行程

```
Cron
↓
Calendar
↓
LLM
↓
Create Events
```

---

## Workflow C

每日摘要

```
Cron
↓
Calendar
↓
LLM Summary
↓
LINE
```

---

# 十三、錯誤處理

## Google API Error

- Retry 3 次
- Log Error
- LINE 通知失敗

---

## AI Parsing Error

LINE 回覆：

> 我無法判斷你的時間。
> 

例如可以輸入：

> 明天下午三點開會
> 

---

# 十四、Non-Functional Requirements

| 項目 | 需求 |
| --- | --- |
| API Response | < 5 秒 |
| AI Parsing Success | >90% |
| Calendar Success | >99% |
| Retry | 3 次 |
| Logging | 所有 Workflow |

---

# 十五、Business Value

| 使用者痛點 | AI 解決方案 | 商業價值 |
| --- | --- | --- |
| 手動建立行程 | LINE 自然語言 | 降低操作成本 |
| 空檔不知道做什麼 | AI 自動安排 | 提高時間利用率 |
| 行程衝突 | AI 自動重新安排 | 減少人工調整 |
| 習慣難以維持 | 每日自動排程 | 提高養成率 |
| 缺乏每日回顧 | AI Summary | 提升效率 |

---

# 十六、Roadmap

## v1.0 MVP

- LINE 建立 Calendar
- 修改 Calendar
- 刪除 Calendar
- 每日固定行程
- 每日摘要

---

## v1.5

- Habit Management
- AI 自動重新排程
- 多 Calendar 支援
- Dashboard

---

## v2.0

- Notion 同步
- Gmail 行程解析
- AI 每週分析
- AI 每月效率分析
- AI 學習使用者排程習慣
- RAG Knowledge Base

---

# 十七、Demo Scenario

## Demo 1

LINE：

> 明天下午五點重訓
> 

↓

Google Calendar 建立事件

---

## Demo 2

LINE：

> 今天重訓改七點
> 

↓

Google Calendar 更新事件

---

## Demo 3

LINE：

> 幫我安排這週三次閱讀
> 

↓

AI 找空檔

↓

建立三筆事件

---

## Demo 4

每天 23:00

LINE 收到：

```
📅 今日摘要

✅ 重訓 90 分鐘

✅ 散步 2 小時

✅ 閱讀 30 分鐘

今天完成率：92%

建議：

明天可以安排英文 30 分鐘。
```

---

# 十八、未來擴充方向

- AI 根據歷史完成率調整排程策略
- AI 分析工作與生活平衡
- AI 偵測過度排程並建議休息
- AI 根據天氣調整戶外活動
- 支援多人家庭共享行程
- 支援 Slack、Discord、Telegram Bot
- 支援 MCP（Model Context Protocol）工具整合
- 支援 AI Agent 多工具協作
