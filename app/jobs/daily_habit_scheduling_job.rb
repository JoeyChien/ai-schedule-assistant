class DailyHabitSchedulingJob < ApplicationJob
  queue_as :default

  def perform(
    date: Date.current,
    habit_scheduling_service: Schedules::HabitSchedulingService.new,
    line: Line::WebhookService.new,
    line_user_id: Rails.application.credentials.dig(:line, :user_id)
  )
    result = habit_scheduling_service.call(date: date)

    return if result.scheduled.empty? && result.skipped.empty?

    push_notification(line, line_user_id, summary_text(result))
  end

  private

  def summary_text(result)
    lines = [ "🌤️ 今日固定行程安排" ]

    result.scheduled.each do |schedule|
      lines << "✅ #{schedule.title}（#{schedule.start_time.strftime('%H:%M')}-#{schedule.end_time.strftime('%H:%M')}）"
    end

    result.skipped.each do |skip|
      lines << "⚠️ #{skip[:title]}：#{skip[:reason]}"
    end

    lines.join("\n")
  end

  def push_notification(line, user_id, text)
    if user_id.blank?
      Rails.logger.warn("[DailyHabitSchedulingJob] credentials.line.user_id 未設定，略過推播：\n#{text}")
      return
    end

    line.push_text(user_id, text)
  end
end
