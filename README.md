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
bin/rails test          # 12 個 model/service 測試，涵蓋建立/修改/刪除/找不到行程/AI 解析失敗/Google API 錯誤
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
- [ ] FR-004 查詢行程
- [ ] FR-005 / FR-006 每日固定行程自動排空檔
- [ ] FR-007 每日摘要推播
