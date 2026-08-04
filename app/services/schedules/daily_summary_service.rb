module Schedules
  # FR-007：整理今天完成／未完成的行程，交給 Gemini 產生摘要文字（AI 失敗時退回純文字版本）
  class DailySummaryService
    def initialize(ai: Ai::GeminiService.new)
      @ai = ai
    end

    def call(date: Date.current)
      schedules = Schedule.on_date(date).order(:start_time).to_a
      completed, upcoming = schedules.partition { |s| s.end_time && s.end_time <= Time.current }
      suggestion = suggest_habit(schedules)

      text = generate_with_ai(date: date, completed: completed, upcoming: upcoming, suggestion: suggestion)
      text.presence || fallback_text(date: date, completed: completed, upcoming: upcoming, suggestion: suggestion)
    end

    private

    # 從固定習慣清單中，找出今天還沒排的第一項，作為明天的建議
    def suggest_habit(todays_schedules)
      today_titles = todays_schedules.map(&:title)
      HabitSchedulingService::DAILY_HABITS.find { |habit| today_titles.exclude?(habit[:title]) }
    end

    def generate_with_ai(date:, completed:, upcoming:, suggestion:)
      prompt = Ai::PromptBuilder.render(
        "daily_summary",
        date: date,
        completed: completed.map { |s| schedule_text(s) },
        upcoming: upcoming.map { |s| schedule_text(s) },
        total_count: completed.size + upcoming.size,
        suggestion: suggestion_text(suggestion)
      )

      response = @ai.generate(prompt)
      response.dig("candidates", 0, "content", "parts", 0, "text")&.strip
    rescue Ai::GeminiService::RequestError => e
      Rails.logger.error("[Schedules::DailySummaryService] Gemini 呼叫失敗，改用純文字版本：#{e.message}")
      nil
    end

    def fallback_text(date:, completed:, upcoming:, suggestion:)
      lines = [ "📅 #{date} 每日摘要", "" ]

      if completed.empty?
        lines << "✅ 今天還沒有完成的行程"
      else
        lines << "✅ 已完成："
        completed.each { |s| lines << "・#{schedule_text(s)}" }
      end

      lines << ""

      if upcoming.empty?
        lines << "🕒 都完成囉"
      else
        lines << "🕒 尚未完成："
        upcoming.each { |s| lines << "・#{schedule_text(s)}" }
      end

      total = completed.size + upcoming.size
      rate = total.zero? ? 0 : (completed.size * 100.0 / total).round
      lines << ""
      lines << "📊 今天完成率：#{rate}%"
      lines << ""
      lines << "建議：明天可以安排#{suggestion_text(suggestion)}。"

      lines.join("\n")
    end

    def schedule_text(schedule)
      minutes = duration_minutes(schedule)
      minutes ? "#{schedule.title}（#{minutes} 分鐘）" : schedule.title
    end

    def duration_minutes(schedule)
      return nil unless schedule.start_time && schedule.end_time

      ((schedule.end_time - schedule.start_time) / 60).round
    end

    def suggestion_text(suggestion)
      return "沒有特別建議" unless suggestion

      "#{suggestion[:title]} #{suggestion[:duration_minutes]} 分鐘"
    end
  end
end
