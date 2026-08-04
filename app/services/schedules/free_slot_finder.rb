module Schedules
  # 讀取 Google Calendar 忙碌時段，算出指定日期在活動時段內的空檔
  class FreeSlotFinder
    DEFAULT_WINDOW_START = "08:00".freeze
    DEFAULT_WINDOW_END = "22:00".freeze

    def initialize(calendar: GoogleCalendarService.new)
      @calendar = calendar
    end

    # 回傳空檔陣列，每個元素為排他 Range（start_time...end_time）
    # excluded_ranges：額外要排除的固定時段（例如午休、晚餐），格式為 [{ "start" => "12:00", "end" => "13:00" }, ...]
    def free_slots(date:, window_start: DEFAULT_WINDOW_START, window_end: DEFAULT_WINDOW_END, excluded_ranges: [])
      window_open = time_on(date, window_start)
      window_close = time_on(date, window_end)
      window = window_open...window_close

      busy_from_calendar = @calendar.find_free_busy(window_open, window_close)
                                     .map { |period| period.start.to_time...period.end.to_time }

      busy_from_exclusions = excluded_ranges.map do |range|
        time_on(date, range_value(range, :start))...time_on(date, range_value(range, :end))
      end

      busy_periods = (busy_from_calendar + busy_from_exclusions)
                       .map { |period| clip(period, window) }
                       .compact
                       .sort_by(&:begin)

      subtract(window, busy_periods)
    end

    private

    def range_value(range, key)
      range[key] || range[key.to_s]
    end

    def time_on(date, hhmm)
      hour, minute = hhmm.split(":").map(&:to_i)
      Time.zone.local(date.year, date.month, date.day, hour, minute)
    end

    def clip(period, window)
      clipped_start = [ period.begin, window.begin ].max
      clipped_end = [ period.end, window.end ].min

      return nil if clipped_start >= clipped_end

      clipped_start...clipped_end
    end

    def subtract(window, busy_periods)
      free = []
      cursor = window.begin

      busy_periods.each do |busy|
        free << (cursor...busy.begin) if busy.begin > cursor
        cursor = busy.end if busy.end > cursor
      end

      free << (cursor...window.end) if cursor < window.end
      free
    end
  end
end
