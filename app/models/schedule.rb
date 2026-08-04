class Schedule < ApplicationRecord
  scope :on_date, ->(date) { where(start_time: date.all_day) }
  scope :in_range, ->(range) { where(start_time: range) }
end
