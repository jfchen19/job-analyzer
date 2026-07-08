require "rails_helper"

RSpec.describe CostCalculator do
  describe ".calculate_cents" do
    it "以 sonnet 定價算 1M/1M tokens = 1800 cents" do
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-sonnet-4-6",
        input_tokens: 1_000_000, output_tokens: 1_000_000
      )
      expect(cents).to eq(1800)
    end

    it "小額用量四捨五入到最近的 cent" do
      # 1500*300 + 1000*1500 = 450000 + 1500000 = 1950000 / 1e6 = 1.95 -> 2
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-sonnet-4-6",
        input_tokens: 1500, output_tokens: 1000
      )
      expect(cents).to eq(2)
    end

    it "haiku 定價 (input 100 / output 500)" do
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-haiku-4-5",
        input_tokens: 1_000_000, output_tokens: 1_000_000
      )
      expect(cents).to eq(600)
    end

    it "nil tokens 視為 0" do
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-sonnet-4-6",
        input_tokens: nil, output_tokens: nil
      )
      expect(cents).to eq(0)
    end

    it "未知 provider/model 會 raise UnknownModelError" do
      expect {
        described_class.calculate_cents(
          provider: "openai", model: "gpt-4o",
          input_tokens: 100, output_tokens: 100
        )
      }.to raise_error(CostCalculator::UnknownModelError)
    end
  end
end
