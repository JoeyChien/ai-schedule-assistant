module Schedules
  # FR-005：使用者在對話中一次要求安排多次、跨天的行程（例如「這週找時間安排兩次閱讀1小時」），
  # 從 range_start 到 range_end 逐天找空檔，一天最多排一次，直到排滿 occurrences 或範圍用完
  class BulkScheduleService
    Result = Struct.new(:scheduled, :skipped, keyword_init: true)

    def initialize(
      calendar: GoogleCalendarService.new,
      free_slot_finder: FreeSlotFinder.new(calendar: calendar),
      slot_allocator: SlotAllocator.new(free_slot_finder: free_slot_finder)
    )
      @calendar = calendar
      @slot_allocator = slot_allocator
    end

    def call(parsed_intent)
      preference = SchedulingPreference.current
      duration = parsed_intent.requested_duration
      occurrences = parsed_intent.requested_occurrences

      scheduled = []

      parsed_intent.schedule_range.each do |date|
        break if scheduled.size >= occurrences

        slot = @slot_allocator.find_slot(
          date: date, duration: duration, preference: preference, preferred_period: parsed_intent.preferred_period
        )
        next unless slot

        begin
          ConflictChecker.check!(slot.begin, slot.begin + duration)
        rescue ConflictChecker::ConflictError
          next
        end

        scheduled << create_schedule(parsed_intent.title, slot.begin, slot.begin + duration, parsed_intent.location)
      end

      Result.new(scheduled: scheduled, skipped: occurrences - scheduled.size)
    end

    private

    def create_schedule(title, start_time, end_time, location)
      google_event_id = @calendar.create_event(summary: title, start_time: start_time, end_time: end_time, location: location)

      Schedule.create!(
        title: title,
        start_time: start_time,
        end_time: end_time,
        source: "line",
        status: "confirmed",
        google_event_id: google_event_id
      )
    end
  end
end
