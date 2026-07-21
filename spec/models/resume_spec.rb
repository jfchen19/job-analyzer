require "rails_helper"

RSpec.describe Resume do
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:content) }

  describe ".default_resume" do
    it "回傳被標記為 default 的那份" do
      create(:resume, is_default: false)
      default = create(:resume, is_default: true)
      expect(described_class.default_resume).to eq(default)
    end

    it "沒有 default 時回 nil" do
      create(:resume, is_default: false)
      expect(described_class.default_resume).to be_nil
    end

    it "萬一同時有多筆 is_default（繞過 callback），穩定回傳 id 最小那筆" do
      first = create(:resume, is_default: true)
      second = create(:resume, is_default: false)
      second.update_column(:is_default, true) # 繞過 before_save，模擬異常資料
      expect(described_class.default_resume).to eq(first)
    end
  end

  describe "設為 default 時清掉其他 default" do
    it "舊 default 會被取消" do
      old = create(:resume, is_default: true)
      create(:resume, is_default: true)
      expect(old.reload.is_default).to be(false)
    end
  end
end
