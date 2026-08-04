require "test_helper"

class ParsedIntentTest < ActiveSupport::TestCase
  test "from_hash builds a ParsedIntent from Gemini's JSON shape" do
    intent = ParsedIntent.from_hash(
      "action" => "CREATE",
      "title" => "健身",
      "start_time" => "2026-08-05T17:00:00+08:00",
      "end_time" => "2026-08-05T18:00:00+08:00",
      "location" => ""
    )

    assert intent.create?
    assert_equal "健身", intent.title
    assert_equal Time.zone.parse("2026-08-05T17:00:00+08:00"), intent.start_time
    assert_nil intent.location
  end

  test "to_schedule_attributes defaults end_time to start_time + 1 hour when missing" do
    intent = ParsedIntent.new(action: "CREATE", title: "健身", start_time: Time.zone.parse("2026-08-05T17:00:00+08:00"))

    attributes = intent.to_schedule_attributes

    assert_equal Time.zone.parse("2026-08-05T18:00:00+08:00"), attributes[:end_time]
    assert_equal "line", attributes[:source]
  end
end
