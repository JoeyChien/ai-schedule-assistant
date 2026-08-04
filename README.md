# AI Schedule Assistant

透過 LINE 傳一句話（例如「明天下午五點健身」），由 Gemini 解析意圖後自動操作 Google Calendar 的智慧排程助理。完整規格見 [spec/spec.md](spec/spec.md)。

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
#   user_id: <先存空字串即可，是「每日固定行程通知」「每日摘要推播」(FR-006 / FR-007) 主動推播的對象，
#             等下面第 4 步跟 LINE Bot 對話過一次、從 server log 拿到 user_id 後再回來補上>
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
4. 第一次跟機器人說話後，server log 會印出 `[LineBotController] message from user_id=Uxxxx...`，把這個值存進 `credentials.line.user_id`，才能收到下面第 5 點的主動推播

### 5. 測試每日固定行程 / 每日摘要（FR-005 / FR-006 / FR-007）

這兩個功能設計上是每天由排程自動觸發（`config/recurring.yml`，正式環境用 Solid Queue 於 07:00 / 23:00 執行），本機開發環境預設不會啟動 Solid Queue supervisor，所以要測試的話用 console 手動觸發即可：

```bash
bin/rails runner 'DailyHabitSchedulingJob.perform_now'  # FR-005/006：找空檔排入「閱讀／散步／英文／冥想」
bin/rails runner 'DailySummaryJob.perform_now'          # FR-007：整理今天完成/未完成事項 + 明日建議
```

需要 Google Calendar 憑證（找空檔、建立事件）與 `credentials.line.user_id`（推播用）都設定好才會真的建立行程、送出 LINE 訊息；若 Gemini 呼叫失敗，`DailySummaryJob` 會自動退回純文字版本的摘要，不會整個推播失敗。

## 自動排程設定（沒指定明確時間的行程要排進哪些空檔）

當你說「今天晚上做伸展30分」這種**沒有給明確時間點**的行程，或是每天早上 07:00 自動排的固定習慣（FR-006），系統都是依照同一份「自動排程設定」（`SchedulingPreference`，資料庫裡只會有一筆）決定可以排進哪些空檔：

- **可排程時間**：預設 10:00-22:00
- **排除時段**：預設排除 12:00-13:00（午休）與 18:00-19:00（晚餐）
- 再排除當天已經有的行程（讀 Google Calendar 忙碌時段）

這份設定可以直接用 LINE 對話修改，例如：

- 「把可排程時間改成9點到21點」
- 「午休時間改成12:30到13:30」
- 「晚餐時間改成18:30到19:30，其他不變」

Gemini 會參考目前的設定值，把你這句話要求的異動跟原本沒提到的部分合併後整個更新，不會把沒提到的部分清空。第一次使用（還沒有人設定過）會自動套用上面的預設值，不需要另外初始化。

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
- [x] FR-005 / FR-006 每日固定行程自動排空檔（`DailyHabitSchedulingJob`，每天 07:00）
- [x] FR-007 每日摘要推播（`DailySummaryJob`，每天 23:00）
- [x] FR-008 自動排程設定（v1.0 追加）：沒給明確時間的行程自動找空檔排入，空檔範圍（可排程時間 + 排除時段）可以直接用 LINE 對話修改
