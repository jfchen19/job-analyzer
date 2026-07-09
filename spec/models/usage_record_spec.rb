require "rails_helper"

RSpec.describe UsageRecord do
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:model) }

  describe "#cost_dollars" do
    it "把 cents 換算成 dollars（round 4）" do
      record = build(:usage_record, cost_cents: 150)
      expect(record.cost_dollars).to eq(1.5)
    end

    it "非整除的 cents 也正確換算（不是剛好 .0/.5）" do
      record = build(:usage_record, cost_cents: 12345)
      expect(record.cost_dollars).to eq(123.45)
    end
  end
end
