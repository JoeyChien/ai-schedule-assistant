ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# 測試替身：代替 GoogleCalendarService，避免測試打到真正的 Google API
class FakeGoogleCalendarService
  attr_reader :calls

  def initialize
    @calls = []
    @sequence = 0
  end

  def create_event(**attrs)
    @calls << [ :create_event, attrs ]
    @sequence += 1
    "fake-event-#{@sequence}"
  end

  def update_event(event_id, **attrs)
    @calls << [ :update_event, event_id, attrs ]
    event_id
  end

  def delete_event(event_id)
    @calls << [ :delete_event, event_id ]
    true
  end
end
