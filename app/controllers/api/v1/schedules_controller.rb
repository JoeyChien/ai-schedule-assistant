module Api
  module V1
    class SchedulesController < ApplicationController
      # date 是給 n8n 這類外部排程呼叫用的，例如 ?date=2026-08-05 只回傳當天的行程；
      # 沒帶 date 就維持原本「回傳全部」的行為
      def index
        schedules = Schedule.order(start_time: :asc)
        schedules = schedules.on_date(Date.parse(params[:date])) if params[:date].present?

        render json: schedules
      rescue ArgumentError
        render json: { error: "date 格式錯誤，請用 YYYY-MM-DD" }, status: :bad_request
      end


      def show
        schedule = Schedule.find(params[:id])

        render json: schedule
      end


      def create
        schedule = Schedule.new(schedule_params)

        if schedule.save
          render json: schedule,
                 status: :created
        else
          render json: {
            errors: schedule.errors.full_messages
          },
          status: :unprocessable_entity
        end
      end


      def destroy
        schedule = Schedule.find(params[:id])

        schedule.destroy

        head :no_content
      end

      def parse
        schedule = Schedules::CreationService.new.create_from_message(
          params[:message]
        )

        render json: schedule, status: :created
      rescue Ai::GeminiService::RequestError => e
        render json: { error: e.message }, status: :bad_gateway
      rescue Ai::ResponseParser::ParseError => e
        render json: { error: e.message }, status: :unprocessable_entity
      rescue GoogleCalendarService::Error => e
        render json: { error: e.message }, status: :bad_gateway
      end

      private


      def schedule_params
        params.require(:schedule)
              .permit(
                :title,
                :description,
                :start_time,
                :end_time,
                :source,
                :status
              )
      end
    end
  end
end
