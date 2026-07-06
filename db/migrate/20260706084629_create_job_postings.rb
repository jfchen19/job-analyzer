class CreateJobPostings < ActiveRecord::Migration[7.2]
  def change
    create_table :job_postings do |t|
      t.string :company_name
      t.string :job_title, null: false
      t.text :raw_content, null: false
      t.string :source_url
      t.string :status, default: "pending"

      t.timestamps
    end

    add_index :job_postings, :status
    add_index :job_postings, :created_at
  end
end
