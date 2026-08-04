module Schedules
  class UpdateService
    def initialize(calendar: GoogleCalendarService.new)
      @calendar = calendar
    end

    def update(parsed_intent)
      schedule = Finder.find_today_by_title(parsed_intent.title)
      new_start_time = parsed_intent.start_time
      new_end_time = parsed_intent.end_time || new_start_time + 1.hour

      ConflictChecker.check!(new_start_time, new_end_time, exclude_id: schedule.id)

      @calendar.update_event(
        schedule.google_event_id,
        summary: parsed_intent.title,
        start_time: new_start_time,
        end_time: new_end_time,
        location: parsed_intent.location
      )

      schedule.update!(start_time: new_start_time, end_time: new_end_time)
      schedule
    end
  end
end
