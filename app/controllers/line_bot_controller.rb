class LineBotController < ApplicationController
  def callback
    body = request.body.read
    signature = request.headers["X-Line-Signature"]

    events = webhook_service.parse_events(body: body, signature: signature)

    events.each do |event|
      next unless event.is_a?(Line::Bot::V2::Webhook::MessageEvent)
      next unless event.message.is_a?(Line::Bot::V2::Webhook::TextMessageContent)

      result = Schedules::CommandService.new.call(event.message.text)
      webhook_service.reply_text(event.reply_token, result.reply_text)
    end

    head :ok
  rescue Line::WebhookService::InvalidSignatureError
    head :bad_request
  end

  private

  def webhook_service
    @webhook_service ||= Line::WebhookService.new
  end
end
