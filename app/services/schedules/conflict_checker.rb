module Schedules
  # 建立/修改行程前檢查時間是否撞期，撞到就拒絕、請使用者自己換時間
  class ConflictChecker
    class ConflictError < StandardError; end

    def self.check!(start_time, end_time, exclude_id: nil)
      scope = Schedule.where("start_time < ? AND end_time > ?", end_time, start_time)
      scope = scope.where.not(id: exclude_id) if exclude_id

      conflict = scope.order(start_time: :asc).first
      return unless conflict

      raise ConflictError, "⚠️ 這個時間跟「#{conflict.title}」（#{format_range(conflict)}）撞期了，麻煩換個時間再說一次。"
    end

    def self.format_range(schedule)
      start_text = schedule.start_time&.strftime("%m/%d %H:%M")
      end_text = schedule.end_time&.strftime("%H:%M")

      [ start_text, end_text ].compact.join("-")
    end
    private_class_method :format_range
  end
end
