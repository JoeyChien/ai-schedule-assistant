module Schedules
  # FR-005 / FR-006：每天固定要養成的習慣，若當天還有空檔就自動排進 Google Calendar
  class HabitSchedulingService
    Result = Struct.new(:scheduled, :skipped, keyword_init: true)

    DAILY_HABITS = [
      { title: "閱讀", duration_minutes: 30 },
      { title: "散步", duration_minutes: 30 },
      { title: "英文", duration_minutes: 30 },
      { title: "冥想", duration_minutes: 15 }
    ].freeze

    def initialize(calendar: GoogleCalendarService.new, free_slot_finder: FreeSlotFinder.new(calendar: calendar))
      @calendar = calendar
      @free_slot_finder = free_slot_finder
    end

    def call(date: Date.current)
      already_scheduled_titles = Schedule.on_date(date).pluck(:title)
      pending_habits = DAILY_HABITS.reject { |habit| already_scheduled_titles.include?(habit[:title]) }

      scheduled = []
      skipped = (DAILY_HABITS - pending_habits).map { |habit| skip(habit[:title], "今天已經安排過了") }

      return Result.new(scheduled: scheduled, skipped: skipped) if pending_habits.empty?

      slots = @free_slot_finder.free_slots(date: date)

      pending_habits.each do |habit|
        slot_index = slots.find_index { |slot| (slot.end - slot.begin) >= habit[:duration_minutes].minutes }

        if slot_index.nil?
          skipped << skip(habit[:title], "找不到空檔")
          next
        end

        slot = slots[slot_index]
        start_time = slot.begin
        end_time = start_time + habit[:duration_minutes].minutes

        begin
          scheduled << create_habit_schedule(title: habit[:title], start_time: start_time, end_time: end_time)
          slots[slot_index] = (end_time...slot.end)
        rescue GoogleCalendarService::Error => e
          Rails.logger.error("[Schedules::HabitSchedulingService] #{e.message}")
          skipped << skip(habit[:title], "建立行程時發生錯誤")
        end
      end

      Result.new(scheduled: scheduled, skipped: skipped)
    end

    private

    def skip(title, reason)
      { title: title, reason: reason }
    end

    def create_habit_schedule(title:, start_time:, end_time:)
      google_event_id = @calendar.create_event(summary: title, start_time: start_time, end_time: end_time, location: nil)

      Schedule.create!(
        title: title,
        start_time: start_time,
        end_time: end_time,
        source: "habit_auto",
        status: "confirmed",
        google_event_id: google_event_id
      )
    end
  end
end
