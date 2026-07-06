class UsageRecord < ApplicationRecord
  belongs_to :recordable, polymorphic: true, optional: true

  validates :provider, presence: true
  validates :model, presence: true

  def cost_dollars
    (cost_cents / 100.0).round(4)
  end
end
