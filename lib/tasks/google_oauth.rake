# 一次性工具：取得 Google Calendar API 所需的 GOOGLE_REFRESH_TOKEN。
#
# 使用方式：
#   bin/rails google:authorize
#
# 前置作業：
#   1. 在 Google Cloud Console 的 OAuth 用戶端（config/google/credentials.json 對應的用戶端）
#      的「已授權的重新導向 URI」中新增：http://localhost:8123/oauth2callback
#      （若要換 port，設定 GOOGLE_OAUTH_PORT 環境變數並同步更新 Console 設定）
#   2. 確保有設定 GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET（.env 或環境變數），
#      沒設定的話會退回讀取 config/google/credentials.json。
#
# 執行後會開啟瀏覽器要求登入 Google 帳號並同意存取 Calendar 權限，
# 完成後終端機會印出 GOOGLE_REFRESH_TOKEN，請手動貼到 .env。

module GoogleOauthSetup
  CREDENTIALS_FILE = Rails.root.join("config", "google", "credentials.json")

  def self.client_id_and_secret
    client_id = ENV["GOOGLE_CLIENT_ID"]
    client_secret = ENV["GOOGLE_CLIENT_SECRET"]

    return [ client_id, client_secret ] if client_id.present? && client_secret.present?

    unless File.exist?(CREDENTIALS_FILE)
      abort "找不到 GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET，也沒有 #{CREDENTIALS_FILE} 可以讀取"
    end

    web = JSON.parse(File.read(CREDENTIALS_FILE))["web"]
    [ web["client_id"], web["client_secret"] ]
  end

  # 啟動一個一次性的本機 HTTP server，等待 Google OAuth callback 帶著 ?code= 導回來
  def self.wait_for_authorization_code(port)
    server = TCPServer.new("127.0.0.1", port)
    session = server.accept
    request_line = session.gets
    path = request_line.to_s.split(" ")[1]
    query = URI.decode_www_form(URI(path).query || "").to_h

    session.print "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n"
    session.print "<html><body>授權完成，請回到終端機查看結果，這個分頁可以關閉了。</body></html>"
    session.close

    abort "授權失敗：#{query['error']}" if query["error"]

    query.fetch("code")
  ensure
    server&.close
  end
end

namespace :google do
  desc "取得 Google Calendar API 的 GOOGLE_REFRESH_TOKEN（一次性 OAuth 授權流程）"
  task authorize: :environment do
    require "socket"
    require "faraday"
    require "json"

    port = (ENV["GOOGLE_OAUTH_PORT"] || 8123).to_i
    redirect_uri = "http://localhost:#{port}/oauth2callback"
    scope = "https://www.googleapis.com/auth/calendar"

    client_id, client_secret = GoogleOauthSetup.client_id_and_secret

    authorize_url = "https://accounts.google.com/o/oauth2/v2/auth?" + URI.encode_www_form(
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scope,
      access_type: "offline",
      prompt: "consent"
    )

    puts "請在瀏覽器開啟以下網址並登入、同意授權："
    puts authorize_url
    puts
    puts "等待授權完成（監聽 #{redirect_uri}）..."

    system("open", authorize_url) if RbConfig::CONFIG["host_os"] =~ /darwin/

    code = GoogleOauthSetup.wait_for_authorization_code(port)

    response = Faraday.post("https://oauth2.googleapis.com/token") do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        code: code,
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      )
    end

    tokens = JSON.parse(response.body)

    if tokens["refresh_token"].blank?
      puts "沒有拿到 refresh_token！請到 https://myaccount.google.com/permissions 移除這個應用程式的授權後重新執行一次"
      puts "（Google 只有在第一次同意授權時才會核發 refresh_token）"
      puts tokens.inspect
      next
    end

    puts
    puts "取得成功！請將以下這行加入 .env："
    puts "GOOGLE_REFRESH_TOKEN=#{tokens['refresh_token']}"
  end
end
