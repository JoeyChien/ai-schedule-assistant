require "test_helper"

class Api::V1::SchedulesControllerTest < ActionDispatch::IntegrationTest
  test "index without a date param returns every schedule" do
    Schedule.create!(title: "健身", start_time: Time.zone.parse("2026-08-04T17:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T18:00:00+08:00"))
    Schedule.create!(title: "明天的行程", start_time: Time.zone.parse("2026-08-05T09:00:00+08:00"), end_time: Time.zone.parse("2026-08-05T10:00:00+08:00"))

    get api_v1_schedules_path

    assert_response :success
    titles = JSON.parse(response.body).map { |s| s["title"] }
    assert_includes titles, "健身"
    assert_includes titles, "明天的行程"
  end

  test "index with a date param only returns that day's schedules (used by n8n's daily workflows)" do
    today = Schedule.create!(title: "健身", start_time: Time.zone.parse("2026-08-04T17:00:00+08:00"), end_time: Time.zone.parse("2026-08-04T18:00:00+08:00"))
    Schedule.create!(title: "明天的行程", start_time: Time.zone.parse("2026-08-05T09:00:00+08:00"), end_time: Time.zone.parse("2026-08-05T10:00:00+08:00"))

    get api_v1_schedules_path, params: { date: "2026-08-04" }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size
    assert_equal today.id, body.first["id"]
  end

  test "index with an invalid date param replies 400 instead of raising" do
    get api_v1_schedules_path, params: { date: "not-a-date" }

    assert_response :bad_request
    assert_includes JSON.parse(response.body)["error"], "date"
  end
end
