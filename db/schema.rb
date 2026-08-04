# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_04_083918) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "schedules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_time"
    t.string "google_event_id"
    t.string "source"
    t.datetime "start_time"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["google_event_id"], name: "index_schedules_on_google_event_id"
  end

  create_table "scheduling_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "excluded_ranges", default: [{"end" => "13:00", "start" => "12:00"}, {"end" => "19:00", "start" => "18:00"}], null: false
    t.datetime "updated_at", null: false
    t.string "window_end", default: "22:00", null: false
    t.string "window_start", default: "10:00", null: false
  end
end
