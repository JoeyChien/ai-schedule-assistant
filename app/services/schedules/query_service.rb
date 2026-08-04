module Schedules
  # FR-004：讀取指定區間內的行程，整理成清單回覆給使用者
  class QueryService
    def call(parsed_intent)
      Schedule.in_range(parsed_intent.query_range).order(start_time: :asc)
    end
  end
end
