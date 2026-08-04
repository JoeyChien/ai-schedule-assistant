module Schedules
  class CreationService
    def initialize(calendar: GoogleCalendarService.new)
      @parser = ParserService.new
      @calendar = calendar
    end

    def create_from_message(message)
      create(@parser.parse(message))
    end

    def create(parsed_intent)
      google_event_id = @calendar.create_event(
        summary: parsed_intent.title,
        start_time: parsed_intent.start_time,
        end_time: parsed_intent.end_time,
        location: parsed_intent.location
      )

      Schedule.create!(
        parsed_intent.to_schedule_attributes.merge(google_event_id: google_event_id)
      )
    end
  end
end
