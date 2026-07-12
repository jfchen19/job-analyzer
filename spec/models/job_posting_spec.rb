require "rails_helper"

RSpec.describe JobPosting do
  it { is_expected.to validate_presence_of(:job_title) }
  it { is_expected.to validate_presence_of(:raw_content) }
  it { is_expected.to validate_inclusion_of(:status).in_array(JobPosting::STATUSES) }

  describe "#latest_analysis" do
    it "回傳 created_at 最新的一筆" do
      posting = create(:job_posting)
      create(:analysis, job_posting: posting, created_at: 2.days.ago)
      newest = create(:analysis, job_posting: posting, created_at: 1.hour.ago)
      expect(posting.latest_analysis).to eq(newest)
    end
  end

  describe "#safe_source_url" do
    it "http/https 的網址原樣回傳（scheme 大小寫不拘）" do
      expect(build(:job_posting, source_url: "https://www.104.com.tw/job/abc").safe_source_url)
        .to eq("https://www.104.com.tw/job/abc")
      expect(build(:job_posting, source_url: "http://example.com").safe_source_url)
        .to eq("http://example.com")
      expect(build(:job_posting, source_url: "HTTPS://example.com").safe_source_url)
        .to eq("HTTPS://example.com")
    end

    it "javascript:/data:/protocol-relative/開頭空白 等一律回 nil（擋 XSS）" do
      expect(build(:job_posting, source_url: "javascript:alert(1)").safe_source_url).to be_nil
      expect(build(:job_posting, source_url: "data:text/html,<script>").safe_source_url).to be_nil
      expect(build(:job_posting, source_url: "//evil.com").safe_source_url).to be_nil
      expect(build(:job_posting, source_url: " javascript:alert(1)").safe_source_url).to be_nil
    end

    it "空值回 nil" do
      expect(build(:job_posting, source_url: nil).safe_source_url).to be_nil
      expect(build(:job_posting, source_url: "").safe_source_url).to be_nil
    end
  end
end
