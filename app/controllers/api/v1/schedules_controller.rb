module Api
  module V1
    class SchedulesController < ApplicationController
      def index
        schedules = Schedule.order(start_time: :asc)

        render json: schedules
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
