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
end
