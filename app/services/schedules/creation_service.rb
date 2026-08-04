module Schedules
  class CreationService
    class NoFreeSlotError < StandardError; end

    # 模糊時段對應的分鐘數區間（從 00:00 起算），用來在自動排程時優先找落在這個時段的空檔
    PREFERRED_PERIOD_RANGES = {
      "morning" => (0..12 * 60),
      "noon" => (11 * 60..13 * 60),
      "afternoon" => (12 * 60..18 * 60),
      "evening" => (18 * 60..24 * 60)
    }.freeze

    def initialize(calendar: GoogleCalendarService.new, free_slot_finder: FreeSlotFinder.new(calendar: calendar))
      @parser = ParserService.new
      @calendar = calendar
      @free_slot_finder = free_slot_finder
    end

    def create_from_message(message)
      create(@parser.parse(message))
    end

    def create(parsed_intent)
      start_time, end_time = resolve_time(parsed_intent)

      ConflictChecker.check!(start_time, end_time)

      google_event_id = @calendar.create_event(
        summary: parsed_intent.title,
        start_time: start_time,
        end_time: end_time,
        location: parsed_intent.location
      )

      Schedule.create!(
        parsed_intent.to_schedule_attributes.merge(start_time: start_time, end_time: end_time, google_event_id: google_event_id)
      )
    end

    private

    def resolve_time(parsed_intent)
      return [ parsed_intent.start_time, parsed_intent.end_time || parsed_intent.start_time + 1.hour ] unless parsed_intent.needs_auto_schedule?

      auto_schedule(parsed_intent)
    end

    # 使用者沒給明確時間（例如「今天晚上做伸展30分」），依「自動排程設定」的空檔範圍找一個位置排入；
    # 有提到模糊時段（早上/中午/下午/晚上）就優先排在那個時段內，真的排不下才退回整個可排程時間找位置
    def auto_schedule(parsed_intent)
      preference = SchedulingPreference.current
      date = parsed_intent.target_date
      duration = parsed_intent.requested_duration
      period_range = PREFERRED_PERIOD_RANGES[parsed_intent.preferred_period]

      slot = period_range && find_slot(date, duration, preference, period_range)
      slot ||= find_slot(date, duration, preference, nil)

      unless slot
        raise NoFreeSlotError,
          "😥 #{date.strftime('%m/%d')} 的可排程時間（#{preference.window_start}-#{preference.window_end}，已扣掉排除時段）已經沒有空檔可以排「#{parsed_intent.title}」了，麻煩指定明確時間。"
      end

      [ slot.begin, slot.begin + duration ]
    end

    def find_slot(date, duration, preference, period_range)
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
