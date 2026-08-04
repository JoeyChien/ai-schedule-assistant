require "google/apis/calendar_v3"
require "googleauth"

class GoogleCalendarService
  class Error < StandardError; end

  CALENDAR_ID = "primary"
  MAX_ATTEMPTS = 3

  def initialize(client: Google::Apis::CalendarV3::CalendarService.new)
    @calendar = client
    @calendar.authorization = authorize
  end

  # 新增事件，回傳 google_event_id
  def create_event(summary:, start_time:, end_time:, location: nil)
    event = build_event(summary: summary, start_time: start_time, end_time: end_time, location: location)

    with_retries { @calendar.insert_event(CALENDAR_ID, event) }.id
  end

  # 更新既有事件
  def update_event(event_id, summary:, start_time:, end_time:, location: nil)
    event = build_event(summary: summary, start_time: start_time, end_time: end_time, location: location)

    with_retries { @calendar.update_event(CALENDAR_ID, event_id, event) }.id
  end

  # 刪除事件
  def delete_event(event_id)
    with_retries { @calendar.delete_event(CALENDAR_ID, event_id) }
    true
  end

  # 查詢空檔 (User Story 2 & 3 必備)
  def find_free_busy(start_time, end_time)
    request = Google::Apis::CalendarV3::FreeBusyRequest.new(
      time_min: start_time.to_datetime,
      time_max: end_time.to_datetime,
      items: [ { id: CALENDAR_ID } ]
    )

    response = with_retries { @calendar.query_freebusy(request) }
    response.calendars[CALENDAR_ID].busy # 回傳忙碌時段列表
  end

  private

  def build_event(summary:, start_time:, end_time:, location:)
    Google::Apis::CalendarV3::Event.new(
      summary: summary,
      location: location,
      start: Google::Apis::CalendarV3::EventDateTime.new(date_time: start_time.to_datetime),
      end: Google::Apis::CalendarV3::EventDateTime.new(date_time: end_time.to_datetime)
    )
  end

  # NFR: Google API Error 時 Retry 3 次
  def with_retries
    attempts = 0

    begin
      attempts += 1
      yield
    rescue Google::Apis::Error => e
      Rails.logger.error("[GoogleCalendarService] attempt #{attempts} failed: #{e.message}")
      raise Error, "Google Calendar API 呼叫失敗：#{e.message}" if attempts >= MAX_ATTEMPTS

      retry
    end
  end

  def authorize
    Google::Auth::UserRefreshCredentials.new(
      client_id: credential(:client_id),
      client_secret: credential(:client_secret),
      refresh_token: credential(:refresh_token),
      scope: [ Google::Apis::CalendarV3::AUTH_CALENDAR ]
    )
  end

  def credential(key)
    Rails.application.credentials.dig(:google, key)
  end
end
