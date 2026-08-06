# AI Schedule Assistant

透過 LINE 傳一句話（例如「明天下午五點健身」），由 Gemini 解析意圖後自動操作 Google Calendar 的智慧排程助理。核心 CRUD/撞期檢查/自動排空檔都是 Rails 本身處理，兩個每日通知（早上行程提醒、晚上摘要）跟一個每週項目時間統計，則是用 n8n 排程串接 Rails API + Gemini + LINE + Google Sheets，見 [docs/n8n_workflows.md](docs/n8n_workflows.md)。完整規格見 [spec/spec.md](spec/spec.md)。

## 環境需求

- Ruby 3.4.10（本專案用 [mise](https://mise.jdx.dev/) 管理版本，`.ruby-version` 已指定）
- PostgreSQL（本機需有 `psql`/`pg_isready` 可連線的 Postgres server）

## 首次設定

```bash
# 1. 安裝 mise 管理的工具版本（Ruby 等）
mise install

# 2. 安裝 gem
bundle install

# 3. 準備環境變數（目前只有 Supabase 這類非機密設定會用到 .env）
cp .env.example .env

# 4. 設定 API 金鑰（Gemini / LINE / Google 全部存放於 Rails encrypted credentials）
bin/rails credentials:edit
# 編輯器打開後，加入：
# gemini:
#   api_key: <你的 Gemini API Key>
# line:
#   channel_secret: <LINE Channel Secret>
#   channel_access_token: <LINE Channel Access Token>
#   user_id: <先存空字串即可，是 FR-006（每日固定行程通知）跟手動測試 FR-007（DailySummaryJob）主動推播的對象，
#             等下面第 4 步跟 LINE Bot 對話過一次、從 server log 拿到 user_id 後再回來補上。
#             n8n 的每日行程提醒/每日摘要(FR-007/FR-009)要另外把同一組 user_id 設定進 n8n，跟這裡無關>
# google:
#   client_id: <config/google/credentials.json 裡的 client_id>
#   client_secret: <config/google/credentials.json 裡的 client_secret>
#   refresh_token: <先存空字串即可，下一步會產生>

# 5. 取得 Google Calendar 的 refresh_token（一次性 OAuth 授權）
# 前置：先到 Google Cloud Console，替 config/google/credentials.json 對應的 OAuth Client
# 新增「已授權的重新導向 URI」：http://localhost:8123/oauth2callback
bin/rails google:authorize
# 完成後照終端機印出的內容，回到 `bin/rails credentials:edit` 把 google.refresh_token 補上

# 6. 建立資料庫
bin/rails db:prepare
```

以上步驟也可以用 `bin/setup` 一次跑完（會另外自動清 log/tmp 並啟動 server）。

## 啟動 Server

```bash
bin/dev
# 等同於 bin/rails server，預設監聽 http://localhost:3000
```

## 測試目前已完成的功能

### 1. 跑自動化測試（不需要任何金鑰）

```bash
bin/rails test          # model/service/job 測試，涵蓋建立/修改/刪除/查詢/撞期檢查/自動排空檔/排程設定/每日排程/每日摘要/找不到行程/AI 解析失敗/Google API 錯誤
bin/rubocop              # 風格檢查
bin/brakeman --no-pager  # 資安掃描
bin/rails zeitwerk:check # 確認所有 class/module 都能正確 autoload
```

### 2. 用 REST API 測試資料庫 CRUD（不需要任何金鑰）

`bin/dev` 啟動後，另開一個終端機：

```bash
# 查詢所有行程
curl http://localhost:3000/api/v1/schedules

# 直接建立一筆行程（純 DB，不會呼叫 Gemini / Google Calendar）
curl -X POST http://localhost:3000/api/v1/schedules \
  -H "Content-Type: application/json" \
  -d '{"schedule":{"title":"重訓","start_time":"2026-08-05T17:00:00+08:00","end_time":"2026-08-05T18:00:00+08:00","source":"manual","status":"confirmed"}}'

# 查詢單筆 / 刪除（把 :id 換成上面回傳的 id）
curl http://localhost:3000/api/v1/schedules/:id
curl -X DELETE http://localhost:3000/api/v1/schedules/:id

# 只查某一天的行程（給 n8n 的每日工作流程用，見下方「n8n 工作流程」）
curl "http://localhost:3000/api/v1/schedules?date=2026-08-05"

# 查某個日期區間的行程（通用區間查詢，目前沒有任何 n8n 工作流程在用，見下方「n8n 工作流程」）
curl "http://localhost:3000/api/v1/schedules?start_date=2026-07-27&end_date=2026-08-02"
```

### 3. 測試 AI 解析 + Google Calendar 建立行程（需要 Gemini + Google 憑證都設定好）

```bash
curl -X POST http://localhost:3000/api/v1/schedules/parse \
  -d "message=明天下午五點健身"
```

這會走完整流程：Gemini 解析意圖 → 寫入 Google Calendar → 存進資料庫。若 Rails credentials 裡的 `google.refresh_token` 還沒設定，這一步會在呼叫 Google Calendar 時失敗（預期行為，代表前面步驟都正確、只差 Google 授權）。

### 4. 測試 LINE Bot（需要真實 LINE 官方帳號 + ngrok）

1. `ngrok http 3000` 取得公開網址
2. 到 LINE Developers Console 把 Webhook URL 設成 `https://<ngrok-domain>/line/callback`
3. 用 LINE 傳訊息給機器人測試，例如：
   - 「明天下午五點健身」→ 建立行程
   - 「今天健身改七點」→ 修改行程（需先有「今天」的同名行程）
   - 「取消今天健身」→ 刪除行程
   - 「今天有什麼安排？」→ 查詢行程（FR-004），會列出當天（或指定日期）的所有行程
   - 如果新增/修改的時間跟既有行程撞期（時間區間有重疊），系統會拒絕建立/修改，回覆哪個行程撞到、請你換個時間，不會直接把兩個行程疊在同一個時段
   - 「今天晚上做伸展30分」→ 沒有給明確時間點，系統會自動在「自動排程設定」的空檔範圍內找位置安排（優先排在你講的時段，例如「晚上」；找不到空檔會直接告訴你，不會硬塞）
   - 「把可排程時間改成9點到21點，午休改成12:30到13:30」→ 修改自動排程設定（見下方「自動排程設定」說明）
   - 「這週找時間安排兩次閱讀1小時」→ FR-005：一次排多個、跨天找空檔（判斷依據是有沒有提到「幾次」或一個範圍如「這週」，只排一次的還是走上面的自動排空檔）；如果整個範圍都排不滿，回覆會明講排了幾次、還差幾次。也支援「下週」（下週一到下週日整週）
   - 找空檔一律不會排到已經過去的時間；如果是排今天，也會自動避開「現在往後 1 小時內」，避免排一個來不及準備、甚至已經過去的時間點
4. 第一次跟機器人說話後，server log 會印出 `[LineBotController] message from user_id=Uxxxx...`，把這個值存進 `credentials.line.user_id`，才能收到下面第 5 點的主動推播

### 5. 測試每日固定行程（FR-006，Rails 自己的排程）

這個功能設計上是每天 07:00 由排程自動觸發（`config/recurring.yml`），本機開發環境預設不會啟動 Solid Queue supervisor，所以要測試的話用 console 手動觸發即可：

```bash
bin/rails runner 'DailyHabitSchedulingJob.perform_now'  # FR-006：找空檔排入「閱讀／散步／英文／冥想」
```

需要 Google Calendar 憑證（找空檔、建立事件）與 `credentials.line.user_id`（推播用）都設定好才會真的建立行程、送出 LINE 訊息。

> FR-007（每日摘要）原本也是 Rails 排程觸發，v1.0 改成用 n8n 在 23:00 觸發（見下方「n8n 工作流程」）。`DailySummaryJob` 程式碼跟測試都還在，可以照樣手動跑 `bin/rails runner 'DailySummaryJob.perform_now'` 測試，只是不會再被自動排程觸發，避免跟 n8n 重複推播。

## 自動排程設定（沒指定明確時間的行程要排進哪些空檔）

當你說「今天晚上做伸展30分」這種**沒有給明確時間點**的行程、「這週找時間安排兩次閱讀1小時」這種**一次排多次**的行程（FR-005），或是每天早上 07:00 自動排的固定習慣（FR-006），系統都是依照同一份「自動排程設定」（`SchedulingPreference`，資料庫裡只會有一筆）決定可以排進哪些空檔：

- **可排程時間**：預設 10:00-22:00
- **排除時段**：預設排除 12:00-13:00（午休）與 18:00-19:00（晚餐）
- 再排除當天已經有的行程（讀 Google Calendar 忙碌時段）

這份設定可以直接用 LINE 對話修改，例如：

- 「把可排程時間改成9點到21點」
- 「午休時間改成12:30到13:30」
- 「晚餐時間改成18:30到19:30，其他不變」

Gemini 會參考目前的設定值，把你這句話要求的異動跟原本沒提到的部分合併後整個更新，不會把沒提到的部分清空。第一次使用（還沒有人設定過）會自動套用上面的預設值，不需要另外初始化。

## n8n 工作流程（每日行程提醒 / 每日摘要 / 每週項目時間統計，FR-007 / FR-009 / FR-010）

每天 09:00 的「今日行程提醒」跟 23:00 的「每日摘要」這兩個通知，是用 n8n 排程觸發、呼叫 Rails 的 `GET /api/v1/schedules?date=...` 拿資料，摘要的部分再呼叫 Gemini，最後直接呼叫 LINE Push Message API 推播；每週一 08:00 的「每週項目時間統計」則**不經過 Rails**，是 n8n 直接呼叫 Google Calendar API 讀上週（`primary` 日曆上）的所有事件，依事件標題分組加總時數後寫進 Google Sheet，再推播一則摘要到 LINE。

完整的節點設定（HTTP Request / Code / Google Calendar / Google Sheets node 的程式碼）見 [docs/n8n_workflows.md](docs/n8n_workflows.md)。之所以這樣分工：

- FR-005/006（找空檔自動排行程）留在 Rails，因為需要撞期檢查、空檔演算法這類「有狀態的業務邏輯」，比較適合寫程式碼、也比較好寫測試。
- FR-007/FR-009 這兩個「排程 → 讀 Rails API → （呼叫 AI）→ 推播」的通知，交給 n8n 編排，展示用 workflow 工具串接既有 API + LLM + 通訊軟體的能力。
- FR-010 這個週報表更進一步，連 Rails 都不經過，直接串 Google Calendar + Google Sheets 兩個外部服務，展示 n8n 也能完全獨立於自家後端、單純用「既有服務 A → 既有服務 B」的方式做資料整合。

## 常用維運指令

```bash
bin/rails google:authorize   # 重新取得 Google Calendar 的 refresh_token
bin/rails db:migrate         # 套用新的 migration
RAILS_ENV=test bin/rails db:migrate  # 測試資料庫也要套用
```

## 開發進度

對照 [spec/spec.md](spec/spec.md) 的 v1.0 MVP：

- [x] FR-001 建立行程（LINE + REST API）
- [x] FR-002 修改行程
- [x] FR-003 刪除行程
- [x] FR-004 查詢行程（LINE，`/api/v1/schedules/parse` 目前只走建立流程，未接 QUERY）
- [x] FR-005 AI 安排固定習慣（LINE 對話一次要求排多次、跨天找空檔，例如「這週找時間安排兩次閱讀1小時」）
- [x] FR-006 每日固定行程自動排空檔（`DailyHabitSchedulingJob`，每天 07:00，Rails 排程）
- [x] FR-007 每日摘要推播（每天 23:00，v1.0 改由 n8n 觸發，見 [docs/n8n_workflows.md](docs/n8n_workflows.md)；Rails 版 `DailySummaryJob` 仍保留供手動測試）
- [x] FR-008 自動排程設定（v1.0 追加）：沒給明確時間的行程自動找空檔排入，空檔範圍（可排程時間 + 排除時段）可以直接用 LINE 對話修改
- [x] FR-009 每日行程提醒（v1.0 追加）：每天 09:00 由 n8n 觸發，列出當天行程並推播到 LINE
- [x] FR-010 每週項目時間統計（v1.0 追加）：每週一 08:00 由 n8n 觸發，讀上週行程依標題分組加總時數，寫入 Google Sheet 並推播摘要到 LINE
