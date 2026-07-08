require "rails_helper"

RSpec.describe UsageRecord do
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:model) }

  describe "#cost_dollars" do
    it "把 cents 換算成 dollars（round 4）" do
      record = build(:usage_record, cost_cents: 150)
      expect(record.cost_dollars).to eq(1.5)
    end
  end
end
