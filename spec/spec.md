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
- Google Sheets API
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

### 實作備註：n8n 實際的角色（v1.0）

上面這張圖是原始規劃，實際 v1.0 的 LINE 建立/修改/刪除/查詢行程（FR-001~004）**沒有經過 n8n**，是 LINE Webhook 直接打 Rails（`LineBotController` → `Schedules::CommandService`），Gemini/Google Calendar 都是 Rails 直接呼叫，理由是這條路徑有撞期檢查、自動排空檔這類需要「讀狀態、寫兩個系統（DB + Google Calendar）」的業務邏輯，用程式碼實作比較可靠，也比較好寫測試。

n8n 實際承擔的是三個**排程觸發、不會寫入 Rails 資料**的工作流程（FR-007/FR-009 讀 Rails 提供的唯讀 API，FR-010 則完全不經過 Rails、直接讀 Google Calendar API，兩種都是「讀資料 → 推播 LINE／寫進 Google Sheet」，不會反過來修改任何系統的資料），細節見 [docs/n8n_workflows.md](../docs/n8n_workflows.md)：

- 每日行程提醒（FR-009，09:00）
- 每日摘要（FR-007，23:00，取代原本 Rails 自己排程觸發的方式）
- 每週項目時間統計（FR-010，週一 08:00，寫入 Google Sheet）

這樣分工同時展示了「核心業務邏輯用程式碼實作＋測試」跟「排程通知/報表類工作流程用 n8n 編排」兩種能力。

---

# 六、技術架構

| Layer | Technology |
| --- | --- |
| Bot | LINE Messaging API |
| Workflow | n8n |
| AI | Gemini API |
| Calendar | Google Calendar API |
| 統計報表 | Google Sheets API |
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

### 實作備註：撞期檢查

- 建立前會先檢查這個時間區間跟現有行程（本地 DB）有沒有重疊，若有撞期（例如「看中醫」剛好也排在 19:00-19:30，這時使用者又說「今天晚上做伸展30分」，時間都落在 19:00-19:30），系統會**拒絕建立**、回覆撞到哪個行程，請使用者自己換時間，不會自動疊加或幫忙搬移。實作在 `Schedules::ConflictChecker`。

### 實作備註：沒給明確時間時自動找空檔排入

- 使用者的訊息如果只給模糊時段或完全沒提時間（例如「今天晚上做伸展30分」，只有「晚上」沒有明確時間點），Gemini 會回傳 `time_specified: false`，這時系統**不會用一個猜測出來的時間點建立行程**，而是改用 `Schedules::CreationService#auto_schedule` 在「自動排程設定」（見下方「自動排程設定」章節）允許的空檔範圍內，找一個排得下、也不會跟其他行程撞期的位置：
  1. 若訊息裡有提到模糊時段（早上/中午/下午/晚上），優先在該時段對應的範圍內找空檔（例如「晚上」對應 18:00 到可排程時間的結束）。
  2. 該時段內排不下，退回整個「可排程時間」（預設 10:00-22:00）重新找位置。
  3. 兩種情況都排不下，就回覆「今天沒有空檔可以排＜行程名稱＞了，麻煩指定明確時間」，不會硬塞或跳過檢查。
- 空檔判斷跟撞期檢查一樣是讀 Google Calendar 的忙碌時段（`Schedules::FreeSlotFinder`），所以已經寫進 Google Calendar 的行程（不管是這個系統建立的還是使用者手動加的）都會被正確避開。
- 排定後的回覆會明確告知「已幫您找空檔安排」，讓使用者知道這個時間是系統自動找的，不是他自己指定的。

---

## FR-002 修改行程

### Input

> 今天健身改七點
> 

系統：

- 搜尋今日健身
- 更新時間
- 回覆成功

### 實作備註：撞期檢查

- 跟 FR-001 一樣會先做撞期檢查（排除自己原本的時段），改到的新時間跟其他行程重疊時一樣拒絕修改、請使用者換時間。

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

### 實作備註

- 對應 `ParsedIntent::ACTIONS` 的 `FIND_FREE_TIME`，由 `Schedules::BulkScheduleService` 執行。Gemini 從訊息裡抽出 `title`（活動名稱）、`occurrences`（要排幾次）、`duration_minutes`（每次時長）、`range_start`/`range_end`（搜尋空檔的日期範圍，例如「這週」會轉成今天到本週日）。
- 演算法很單純：從 `range_start` 到 `range_end` 逐天嘗試（重用 FR-001 自動排程用的 `Schedules::SlotAllocator`，同樣吃 `SchedulingPreference` 的可排程時間/排除時段），一天最多排一次，排滿 `occurrences` 或範圍用完就停止。找到空檔後一樣會過一次 `Schedules::ConflictChecker` 才真正建立，跟其他建立行程的路徑用同一套撞期保護。
- 排不滿的部分不會整個失敗，回覆會列出「已排幾次／目標幾次」，剩下排不進去的次數也會明講，讓使用者知道要不要換個範圍或時間再試一次。
- **判斷 CREATE 還是 FIND_FREE_TIME 靠 Gemini**：訊息裡有「幾次」或給的是一個範圍（這週/這個月）而不是單一天，才會走 FIND_FREE_TIME；只排一次的（不管有沒有給明確時間）都還是走 FR-001 的 CREATE。
- **不會排到已經過去的時間點（bug 修正）**：`Schedules::FreeSlotFinder` 找空檔時，如果日期是今天，可排程時間的起點會自動墊高成「現在 + 1 小時」（`MIN_LEAD_TIME`），比這個時間點早的空檔一律不會回傳；如果日期已經整天過去，直接回傳空陣列。這個邏輯放在 `FreeSlotFinder` 這一層，FR-001（單筆自動排程）、FR-005（這裡）、FR-006（每日固定習慣）三個用到「找空檔」的地方都共用，不用各自實作一次。
  - 例如 22:00 才傳「這週找時間安排兩次閱讀1小時」，今天已經沒有 1 小時以上的空檔（22:00+1hr=23:00 超過可排程時間終點 22:00），會直接跳過今天，排到明天/後天。
- **「這週」跟「下週」的區間算法不同**：「這週」這類**包含今天**的範圍，起點固定是今天（今天以前已經過去，不能往前推）；「下週」「下個月」這類**完全在未來**的範圍，起點是那個範圍實際的第一天（例如下週一），不會被拉到今天。prompt 裡另外把「今天是星期幾」也一併告訴 Gemini，方便它算週/月的邊界。

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
  1. `Schedules::FreeSlotFinder` 呼叫 `GoogleCalendarService#find_free_busy`，在 `SchedulingPreference.current` 設定的「可排程時間」（預設 10:00–22:00，已扣掉「排除時段」如午休/晚餐）內找當天的忙碌時段，算出空檔。這份設定跟 FR-001/FR-008 共用，改一次兩邊都會生效。
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

- **觸發方式（v1.0 調整）**：正式的每天 23:00 觸發改由 n8n 負責（見 [docs/n8n_workflows.md](../docs/n8n_workflows.md) 工作流程 B），不再是 Rails 的 `config/recurring.yml`。n8n 讀 `GET /api/v1/schedules?date=...`，自己呼叫 Gemini 整理摘要、自己呼叫 LINE Push Message API 推播，Rails 端完全不參與。
- Rails 這邊原本針對 FR-007 寫的 `DailySummaryJob` / `Schedules::DailySummaryService` 程式碼跟測試都還留著（沒有刪除），可以用 `bin/rails runner 'DailySummaryJob.perform_now'` 手動執行，做為「同一個功能不透過 n8n、純 Rails 也能做到」的對照組，但**不會**再被自動排程觸發（避免跟 n8n 重複推播兩次）。
- 目前資料模型沒有「完成狀態」欄位，因此用 `end_time <= 現在時間` 當作「已完成」的判斷依據，其餘視為「尚未完成」（n8n 版本的摘要邏輯也是採用一樣的判斷方式）。
- Rails 版本的摘要文字交給 Gemini（AI-004）依 `prompts/daily_summary.txt.erb` 產生；若 Gemini 呼叫失敗或回傳空白，會自動退回程式產生的純文字版本，確保推播不會因為 AI 服務問題而整個失敗。

---

## FR-009 每日行程提醒（v1.0 新增，原規格沒有這條）

每天 09:00

系統：

- 讀取今天的行程
- 整理成清單
- LINE 推播

### Output（LINE 推播）

```
☀️ 早安！今天的安排：
⏰ 10:00 📌 閱讀
⏰ 17:00 📌 健身
⏰ 19:00 📌 看中醫
```

### 實作備註

- 完全由 n8n 負責（見 [docs/n8n_workflows.md](../docs/n8n_workflows.md) 工作流程 A），Rails 沒有對應的 Job，只提供 `GET /api/v1/schedules?date=YYYY-MM-DD` 這個唯讀 API 給 n8n 讀取當天行程；格式化訊息、推播 LINE 都在 n8n 的節點裡完成。
- 這條刻意不經過 AI（單純資料轉換），跟 FR-007 一組一起看，展示 n8n 一邊做「純資料流程」、一邊做「串 LLM 的流程」兩種形狀。

---

## FR-010 每週項目時間統計（v1.0 新增，原規格沒有這條，對應 Roadmap v2.0「AI 每週分析」的第一步）

每週一 08:00

系統：

- 直接讀取 Google Calendar（`primary` 日曆）上上週一～上週日的所有事件
- 依事件標題（項目）分組，加總每個項目的時數
- 寫入 Google Sheet 累積統計
- LINE 推播本週統計已更新、附上時數前幾名的項目

### Output（Google Sheet 新增/更新的列）

有行程的一週：

| 週期 | 項目 | 總時數 | 行程數 |
| --- | --- | --- | --- |
| 2026-07-27 ~ 2026-08-02 | 健身 | 3.5 | 3 |
| 2026-07-27 ~ 2026-08-02 | 閱讀 | 2.0 | 4 |

完全沒有行程的一週，固定寫入一列「無」，而不是留空或整週跳過不寫：

| 週期 | 項目 | 總時數 | 行程數 |
| --- | --- | --- | --- |
| 2026-08-03 ~ 2026-08-09 | 無 | 0 | 0 |

### Output（LINE 推播）

有行程：

```
📊 上週（2026-07-27 ~ 2026-08-02）時間統計已更新到 Google Sheet
🏆 健身：3.5 小時（3 筆）
🏆 閱讀：2.0 小時（4 筆）
```

沒有行程：

```
📊 上週（2026-08-03 ~ 2026-08-09）沒有任何行程紀錄，上週無行程。
```

### 實作備註

- 完全由 n8n 負責（見 [docs/n8n_workflows.md](../docs/n8n_workflows.md) 工作流程 C），Rails 完全不參與——沒有對應的 Job，也不提供任何 API 給這個工作流程呼叫。n8n 用內建的 Google Calendar node（`Get Many`，開 `Single Events` 展開重複事件）直接讀 `primary` 日曆上的事件，分組加總、寫 Google Sheet、組 LINE 訊息都在 n8n 節點裡完成。這點跟 FR-007/FR-009 不一樣：那兩個還是會呼叫 Rails 的 `GET /api/v1/schedules?date=...` 拿資料，FR-010 是三個工作流程裡唯一完全繞過 Rails 的。
- **資料來源包含手動加的日曆事件，不只是這個系統建立的行程**：因為讀的是 Google Calendar 本身而不是 Rails 的 `Schedule` 資料表，統計範圍會是「`primary` 日曆上實際發生的所有事件」，使用者自己手動加、不是透過這個系統建立的行程也會被算進去。這是刻意的選擇，為了讓每週時間統計反映真實的時間分配全貌，不只是這個系統管理的那一部分。
- 目前 Google Calendar 事件沒有獨立的「項目／分類」欄位（見十一、資料模型 `Calendar Event` 的 `category`，v1.0 尚未實作），這裡直接把事件的 `summary`（標題）當作項目名稱分組。
- 寫入 Google Sheet 用「Append or Update」，以「週期＋項目」兩欄當比對鍵，同一週重跑不會產生重複列。
- **上週完全沒有事件時，不會整條工作流程跳過不寫**：分組加總的 Code node 一律輸出至少 1 個 item，沒有事件就固定輸出 1 筆 `項目="無"`、`總時數=0`、`行程數=0`，讓 Google Sheet 跟 LINE 都清楚看到「這週有統計過、結果是 0」，後面的 Google Sheets／LINE node 不需要額外判斷要不要執行；同一個 Code node 也會過濾掉沒有 `summary`／明確起訖時間的事件（例如全天事件只有 `date` 沒有 `dateTime`），避免不完整的資料被誤當成一筆有效紀錄混進統計。
- 這個功能原本的第一版是讀 Rails 的 `GET /api/v1/schedules`，為此在 Rails 端加了 `start_date`/`end_date` 區間查詢參數；後來改成直接讀 Google Calendar API 之後，這個區間查詢就沒有任何呼叫端在用了。討論後決定先保留它當作 `Schedule` API 的通用能力（不影響其他功能），沒有回頭刪掉。

---

## FR-007 / FR-009 / FR-010 共通：LINE 主動推播

- 這三個通知都是系統主動發訊息（不是回覆使用者訊息），走的是 LINE Messaging API 的 **Push Message**，跟 FR-001~004 用的 Reply Message（需要 `reply_token`，且有時效限制）不同。
- 推播對象是 LINE 的 `user_id`（跟 `credentials.line.user_id` 同一組），取得方式見 README「首次設定」第 4 步；n8n 那邊要另外把同一組 `channel_access_token` / `user_id` 設定成自己的 credential。
- FR-005/006（每日固定行程）仍由 Rails 的 `config/recurring.yml` + Solid Queue 觸發（`SOLID_QUEUE_IN_PUMA`，見 `config/deploy.yml`），因為那條有撞期檢查、自動排空檔這類業務邏輯，適合留在程式碼裡；FR-007/FR-009/FR-010 這幾個通知/報表則交給 n8n。

---

## FR-008 自動排程設定（v1.0 新增，原規格沒有這條，因應實際使用需求追加）

### 背景

FR-001（建立行程）跟 FR-006（每日固定行程）都有「沒給明確時間，需要系統自動找空檔排入」的情境。這個空檔範圍原本是寫死在程式裡，但不同人生活作息不同（幾點吃午餐、幾點算晚上），所以拉出一份可以透過 LINE 對話調整的設定。

### Input

> 把可排程時間改成9點到21點，午休改成12:30到13:30
> 

系統：

- 讀取目前的自動排程設定
- 依 Gemini 判斷這句話要異動的部分，跟原本設定合併成新的完整設定
- 存檔、回覆新的設定內容

### Output（LINE 回覆）

```
✅ 已更新自動排程設定：
🕐 可排程時間：09:00-21:00
🚫 排除時段：12:30-13:30、18:00-19:00
```

### 實作備註

- 設定存在 `SchedulingPreference` 資料表，單一使用者的個人助理只會有一筆（`SchedulingPreference.current`，沒有就自動用預設值建立：可排程時間 10:00-22:00，排除 12:00-13:00 與 18:00-19:00）。
- 因為使用者一句話可能只想改其中一部分（例如只改午休時間），Gemini 會在 prompt 裡先拿到「目前的設定」當作上下文，回傳**合併後的完整設定**，Rails 端不用自己做欄位層級的差異比對，直接整組覆寫即可（`Schedules::ScheduleSettingsService`）。
- 格式不合法（例如時間不是 `HH:MM`）會擋在 Model 驗證（`SchedulingPreference`），回覆使用者「設定格式不太對」，不會存進一半的髒資料。
- `Schedules::FreeSlotFinder` 統一吃「可排程時間 + 排除時段 + Google Calendar 忙碌時段」三種輸入算空檔，FR-001 的自動排程跟 FR-006 的每日固定行程都共用同一份 `SchedulingPreference`，改一次設定兩邊都會生效。

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

## SchedulingPreference（v1.0 新增，FR-008）

> 單一使用者的個人助理，只會有一筆，透過 `SchedulingPreference.current` 存取（沒有就自動用預設值建立）。

| Field | Type | 說明 |
| --- | --- | --- |
| window_start | String | 可排程時間起點，格式 `HH:MM`，預設 `10:00` |
| window_end | String | 可排程時間終點，格式 `HH:MM`，預設 `22:00` |
| excluded_ranges | jsonb | 要排除的固定時段陣列，例如 `[{"start":"12:00","end":"13:00"},{"start":"18:00","end":"19:00"}]` |

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

## Workflow D

每週項目時間統計

```
Cron（每週一）
↓
直接讀取 Google Calendar 上週事件
↓
依項目分組加總時數
↓
寫入 Google Sheet
↓
LINE 摘要
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
- AI 每週分析（基礎版的每週項目時間統計已在 v1.0 提前實作，見 FR-010；這裡指的是在統計數字之上再加一層 AI 洞察/建議，例如分析時間分配是否失衡）
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
