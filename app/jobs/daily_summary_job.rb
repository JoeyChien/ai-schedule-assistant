class DailySummaryJob < ApplicationJob
  queue_as :default

  def perform(
    date: Date.current,
    daily_summary_service: Schedules::DailySummaryService.new,
    line: Line::WebhookService.new,
    line_user_id: Rails.application.credentials.dig(:line, :user_id)
  )
    text = daily_summary_service.call(date: date)

    if line_user_id.blank?
      Rails.logger.warn("[DailySummaryJob] credentials.line.user_id 未設定，略過推播：\n#{text}")
      return
    end

    line.push_text(line_user_id, text)
  end
end
