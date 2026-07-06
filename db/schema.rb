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

ActiveRecord::Schema[7.2].define(version: 2026_07_06_084631) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "analyses", force: :cascade do |t|
    t.bigint "job_posting_id", null: false
    t.bigint "resume_id", null: false
    t.string "match_level"
    t.text "key_requirements"
    t.text "matched_skills"
    t.text "skill_gaps"
    t.text "cover_letter_suggestion"
    t.text "raw_response"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_posting_id"], name: "index_analyses_on_job_posting_id"
    t.index ["resume_id"], name: "index_analyses_on_resume_id"
  end

  create_table "job_postings", force: :cascade do |t|
    t.string "company_name"
    t.string "job_title", null: false
    t.text "raw_content", null: false
    t.string "source_url"
    t.string "status", default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_job_postings_on_created_at"
    t.index ["status"], name: "index_job_postings_on_status"
  end

  create_table "resumes", force: :cascade do |t|
    t.string "title", null: false
    t.text "content", null: false
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "usage_records", force: :cascade do |t|
    t.string "provider", default: "anthropic", null: false
    t.string "model", null: false
    t.integer "input_tokens", default: 0, null: false
    t.integer "output_tokens", default: 0, null: false
    t.integer "cost_cents", default: 0, null: false
    t.string "request_label"
    t.string "recordable_type"
    t.bigint "recordable_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_usage_records_on_created_at"
    t.index ["recordable_type", "recordable_id"], name: "index_usage_records_on_recordable"
  end

  add_foreign_key "analyses", "job_postings"
  add_foreign_key "analyses", "resumes"
end
