class AddGoogleEventIdToSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :schedules, :google_event_id, :string
    add_index :schedules, :google_event_id
  end
end
