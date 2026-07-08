require "rails_helper"

RSpec.describe Analysis do
  # 有必填 association，給 shoulda 一個有效 subject 以免誤判
  subject { build(:analysis) }

  it { is_expected.to belong_to(:job_posting) }
  it { is_expected.to belong_to(:resume) }
  it { is_expected.to validate_inclusion_of(:match_level).in_array(Analysis::MATCH_LEVELS) }

  describe "#parsed_key_requirements" do
    it "合法 JSON 解析為陣列" do
      analysis = build(:analysis, key_requirements: JSON.generate(["a", "b"]))
      expect(analysis.parsed_key_requirements).to eq(["a", "b"])
    end

    it "壞掉的 JSON 回空陣列" do
      analysis = build(:analysis, key_requirements: "not json")
      expect(analysis.parsed_key_requirements).to eq([])
    end
  end
end
