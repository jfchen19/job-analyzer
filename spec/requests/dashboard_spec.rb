require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  it "首頁 200（空資料）" do
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "首頁 200（有分析，會 render _match_badge —— #4 遞迴回歸）" do
    posting = create(:job_posting, status: "analyzed")
    create(:analysis, job_posting: posting, match_level: "medium")
    get root_path
    expect(response).to have_http_status(:ok)
  end
end
