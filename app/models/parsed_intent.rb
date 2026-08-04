class ParsedIntent
  include ActiveModel::Model

  ACTIONS = %w[CREATE UPDATE DELETE QUERY FIND_FREE_TIME].freeze

  attr_accessor :action,
                :title,
                :start_time,
                :end_time,
                :location

  def self.from_hash(hash)
    new(
      action: hash["action"],
      title: hash["title"],
      start_time: parse_time(hash["start_time"]),
      end_time: parse_time(hash["end_time"]),
      location: hash["location"].presence
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

  def find_free_time?
    action == "FIND_FREE_TIME"
  end

  # QUERY 的查詢區間；Gemini 沒給時間時預設查今天
  def query_range
    range_start = (start_time || Time.zone.now).beginning_of_day
    range_end = (end_time || start_time || Time.zone.now).end_of_day

    range_start..range_end
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
