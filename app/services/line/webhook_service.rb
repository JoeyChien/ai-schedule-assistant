module Line
  class WebhookService
    InvalidSignatureError = Bot::V2::WebhookParser::InvalidSignatureError

    def initialize
      @parser = Bot::V2::WebhookParser.new(channel_secret: credential(:channel_secret))
      @client = Bot::V2::MessagingApi::ApiClient.new(
        channel_access_token: credential(:channel_access_token)
      )
    end

    # 驗證簽章並解析 webhook events，簽章不符會拋出 InvalidSignatureError
    def parse_events(body:, signature:)
      @parser.parse(body: body, signature: signature)
    end

    def reply_text(reply_token, text)
      @client.reply_message(
        reply_message_request: Bot::V2::MessagingApi::ReplyMessageRequest.new(
          reply_token: reply_token,
          messages: [ Bot::V2::MessagingApi::TextMessage.new(text: text) ]
        )
      )
    end

    # 主動推播（每日固定行程通知、每日摘要），不受 reply_token 有效期限制
    def push_text(user_id, text)
      @client.push_message(
        push_message_request: Bot::V2::MessagingApi::PushMessageRequest.new(
          to: user_id,
          messages: [ Bot::V2::MessagingApi::TextMessage.new(text: text) ]
        )
      )
    end

    private

    def credential(key)
      Rails.application.credentials.dig(:line, key)
    end
  end
end
