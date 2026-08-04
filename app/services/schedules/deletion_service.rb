module Schedules
  class DeletionService
    def initialize(calendar: GoogleCalendarService.new)
      @calendar = calendar
    end

    def delete(parsed_intent)
      schedule = Finder.find_today_by_title(parsed_intent.title)

      @calendar.delete_event(schedule.google_event_id)
      schedule.destroy!
      schedule
    end
  end
end
