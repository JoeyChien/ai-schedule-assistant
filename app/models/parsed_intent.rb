class ParsedIntent
  include ActiveModel::Model

  ACTIONS = %w[CREATE UPDATE DELETE QUERY UPDATE_SCHEDULE_SETTINGS FIND_FREE_TIME].freeze
  DEFAULT_DURATION_MINUTES = 60

  attr_accessor :action,
                :title,
                :start_time,
                :end_time,
                :location,
                :time_specified,
                :duration_minutes,
                :date,
                :preferred_period,
                :window_start,
                :window_end,
                :excluded_ranges,
                :occurrences,
                :range_start,
                :range_end

  def self.from_hash(hash)
    new(
      action: hash["action"],
      title: hash["title"],
      start_time: parse_time(hash["start_time"]),
      end_time: parse_time(hash["end_time"]),
      location: hash["location"].presence,
      time_specified: hash["time_specified"],
      duration_minutes: hash["duration_minutes"].presence&.to_i,
      date: hash["date"].presence,
      preferred_period: hash["preferred_period"].presence,
      window_start: hash["window_start"].presence,
      window_end: hash["window_end"].presence,
      excluded_ranges: hash["excluded_ranges"].presence,
      occurrences: hash["occurrences"].presence&.to_i,
      range_start: hash["range_start"].presence,
      range_end: hash["range_end"].presence
    )
  end

  def self.parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value)
  end
  private_class_method :parse_time

  def create?
    action == "CREATE"
  end

  def update?
    action == "UPDATE"
  end

  def delete?
    action == "DELETE"
  end

  def query?
    action == "QUERY"
  end

  def update_schedule_settings?
    action == "UPDATE_SCHEDULE_SETTINGS"
  end

  def find_free_time?
    action == "FIND_FREE_TIME"
  end

  # 沒收到明確的 false 就當作「有給時間」，避免舊有呼叫方式（沒設定這個欄位）被誤判成要自動排程
  def time_specified?
    time_specified != false
  end

  # CREATE 但使用者沒給明確時間，需要系統自動找空檔排入
  def needs_auto_schedule?
    create? && !time_specified?
  end

  def requested_duration
    (duration_minutes || DEFAULT_DURATION_MINUTES).minutes
  end

  # 自動排程要排在哪一天；優先用 Gemini 給的 date，其次用 start_time，都沒有就用今天
  def target_date
    return Date.parse(date) if date.present?

    (start_time || Time.zone.now).to_date
  end

  # QUERY 的查詢區間；Gemini 沒給時間時預設查今天
  def query_range
    query_begin = (start_time || Time.zone.now).beginning_of_day
    query_end = (end_time || start_time || Time.zone.now).end_of_day

    query_begin..query_end
  end

  # FIND_FREE_TIME 要排幾次；沒給就當作 1 次
  def requested_occurrences
    occurrences || 1
  end

  # FIND_FREE_TIME 搜尋空檔的日期範圍；Gemini 沒給時間時預設只搜今天
  def schedule_range
    range_from = range_start.present? ? Date.parse(range_start) : Date.current
    range_to = range_end.present? ? Date.parse(range_end) : range_from

    range_from..range_to
  end

  def to_schedule_attributes
    {
      title: title,
      start_time: start_time,
      end_time: end_time || start_time&.+(1.hour),
      source: "line",
      status: "confirmed"
    }
  end
end
