module Schedules
  class Finder
    class NotFound < StandardError; end

    def self.find_today_by_title(title)
      schedule = Schedule.where(start_time: Date.current.all_day)
                          .where("title LIKE ?", "%#{title}%")
                          .order(start_time: :asc)
                          .first

      schedule || raise(NotFound, "找不到今天的「#{title}」行程")
    end
  end
end
