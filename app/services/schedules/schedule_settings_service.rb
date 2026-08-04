module Schedules
  # 修改「自動排程設定」（沒指定明確時間的行程可以排入哪些空檔），可以透過 LINE 對話調整
  class ScheduleSettingsService
    class InvalidSettingsError < StandardError; end

    def update(parsed_intent)
      preference = SchedulingPreference.current
      preference.window_start = parsed_intent.window_start if parsed_intent.window_start.present?
      preference.window_end = parsed_intent.window_end if parsed_intent.window_end.present?
      preference.excluded_ranges = parsed_intent.excluded_ranges if parsed_intent.excluded_ranges.present?

      unless preference.save
        raise InvalidSettingsError, "設定格式不太對：#{preference.errors.full_messages.join('、')}"
      end

      preference
    end
  end
end
