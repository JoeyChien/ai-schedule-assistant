class SchedulingPreference < ApplicationRecord
  DEFAULT_WINDOW_START = "10:00".freeze
  DEFAULT_WINDOW_END = "22:00".freeze
  DEFAULT_EXCLUDED_RANGES = [
    { "start" => "12:00", "end" => "13:00" },
    { "start" => "18:00", "end" => "19:00" }
  ].freeze

  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  validates :window_start, :window_end, format: { with: TIME_FORMAT, message: "格式需為 HH:MM" }
  validate :excluded_ranges_are_valid

  # 單一使用者的個人助理，設定只會有一筆，沒有就用預設值建立
  def self.current
    first_or_create! do |preference|
      preference.window_start = DEFAULT_WINDOW_START
      preference.window_end = DEFAULT_WINDOW_END
      preference.excluded_ranges = DEFAULT_EXCLUDED_RANGES
    end
  end

  private

  def excluded_ranges_are_valid
    return if excluded_ranges.blank?

    unless excluded_ranges.is_a?(Array) && excluded_ranges.all? { |range| valid_range?(range) }
      errors.add(:excluded_ranges, "格式需為 [{ start: 'HH:MM', end: 'HH:MM' }, ...]")
    end
  end

  def valid_range?(range)
    range.is_a?(Hash) &&
      range["start"].to_s.match?(TIME_FORMAT) &&
      range["end"].to_s.match?(TIME_FORMAT)
  end
end
