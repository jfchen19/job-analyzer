class CreateAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :analyses do |t|
      t.references :job_posting, null: false, foreign_key: true
      t.references :resume, null: false, foreign_key: true
      t.string :match_level
      t.text :key_requirements
      t.text :matched_skills
      t.text :skill_gaps
      t.text :cover_letter_suggestion
      t.text :raw_response

      t.timestamps
    end
  end
end
