class CreateResumes < ActiveRecord::Migration[7.2]
  def change
    create_table :resumes do |t|
      t.string :title, null: false
      t.text :content, null: false
      t.boolean :is_default, default: false, null: false

      t.timestamps
    end
  end
end
