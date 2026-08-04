module Line
  class WebhookService
    InvalidSignatureError = Bot::V2::WebhookParser::InvalidSignatureError

    def initialize
      @parser = Bot::V2::WebhookParser.new(channel_secret: ENV.fetch("LINE_CHANNEL_SECRET"))
      @client = Bot::V2::MessagingApi::ApiClient.new(
        channel_access_token: ENV.fetch("LINE_CHANNEL_ACCESS_TOKEN")
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
  end
end
