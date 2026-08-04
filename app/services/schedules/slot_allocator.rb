module Schedules
  # 依「自動排程設定」（可排程時間 + 排除時段 + Google Calendar 忙碌時段）找一個排得下的空檔，
  # 有給模糊時段（早上/中午/下午/晚上）會優先找落在那個時段的位置，該時段排不下才退回整個可排程時間找。
  # 給 Schedules::CreationService（單筆、沒給明確時間）跟 Schedules::BulkScheduleService（多筆、跨天）共用。
  class SlotAllocator
    PREFERRED_PERIOD_RANGES = {
      "morning" => (0..12 * 60),
      "noon" => (11 * 60..13 * 60),
      "afternoon" => (12 * 60..18 * 60),
      "evening" => (18 * 60..24 * 60)
    }.freeze

    def initialize(free_slot_finder:)
      @free_slot_finder = free_slot_finder
    end

    # 回傳排他 Range（start_time...end_time）或 nil（該日期真的排不下）
    def find_slot(date:, duration:, preference:, preferred_period: nil)
      period_range = PREFERRED_PERIOD_RANGES[preferred_period]

      slot = period_range && slot_in_window(date, duration, preference, period_range)
      slot ||= slot_in_window(date, duration, preference, nil)
      slot
    end

    private

    def slot_in_window(date, duration, preference, period_range)
      window_start, window_end = effective_window(preference, period_range)
      return nil unless window_start && window_start < window_end

      @free_slot_finder.free_slots(
        date: date,
        window_start: to_hhmm(window_start),
        window_end: to_hhmm(window_end),
        excluded_ranges: preference.excluded_ranges
      ).find { |slot| (slot.end - slot.begin) >= duration }
    end

    # 把「可排程時間」跟「模糊時段」取交集，交集不存在（例如全部設定都在晚上以前結束）就回傳 nil
    def effective_window(preference, period_range)
      window_start = to_minutes(preference.window_start)
      window_end = to_minutes(preference.window_end)
      return [ window_start, window_end ] unless period_range

      [ [ window_start, period_range.begin ].max, [ window_end, period_range.end ].min ]
    end

    def to_minutes(hhmm)
      hour, minute = hhmm.split(":").map(&:to_i)
      hour * 60 + minute
    end

    def to_hhmm(minutes)
      format("%02d:%02d", minutes / 60, minutes % 60)
    end
  end
end
