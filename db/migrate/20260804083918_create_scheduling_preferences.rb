class CreateSchedulingPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduling_preferences do |t|
      t.string :window_start, null: false, default: "10:00"
      t.string :window_end, null: false, default: "22:00"
      t.jsonb :excluded_ranges, null: false, default: [
        { start: "12:00", end: "13:00" },
        { start: "18:00", end: "19:00" }
      ]

      t.timestamps
    end
  end
end
