module Schedules
  class CreationService
    class NoFreeSlotError < StandardError; end

    def initialize(
      calendar: GoogleCalendarService.new,
      free_slot_finder: FreeSlotFinder.new(calendar: calendar),
      slot_allocator: SlotAllocator.new(free_slot_finder: free_slot_finder)
    )
      @parser = ParserService.new
      @calendar = calendar
      @slot_allocator = slot_allocator
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

    # 使用者沒給明確時間（例如「今天晚上做伸展30分」），依「自動排程設定」的空檔範圍找一個位置排入
    def auto_schedule(parsed_intent)
      preference = SchedulingPreference.current
      date = parsed_intent.target_date
      duration = parsed_intent.requested_duration

      slot = @slot_allocator.find_slot(date: date, duration: duration, preference: preference, preferred_period: parsed_intent.preferred_period)

      unless slot
        raise NoFreeSlotError,
          "😥 #{date.strftime('%m/%d')} 的可排程時間（#{preference.window_start}-#{preference.window_end}，已扣掉排除時段）已經沒有空檔可以排「#{parsed_intent.title}」了，麻煩指定明確時間。"
      end

      [ slot.begin, slot.begin + duration ]
    end
  end
end
