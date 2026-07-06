class CreateUsageRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :usage_records do |t|
      t.string :provider, null: false, default: "anthropic"
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0
      t.string :request_label
      # Polymorphic, optional (adds composite index on [recordable_type, recordable_id])
      t.references :recordable, polymorphic: true, null: true

      t.timestamps
    end

    add_index :usage_records, :created_at
  end
end
