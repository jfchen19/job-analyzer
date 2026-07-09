require "rails_helper"

RSpec.describe "JobPostings", type: :request do
  describe "GET /job_postings/:id（含 _match_badge，#4 遞迴回歸）" do
    it "有分析結果時正常渲染 200（不因 _match_badge 遞迴 500）" do
      posting = create(:job_posting, status: "analyzed")
      create(:analysis, job_posting: posting, match_level: "high")
      get job_posting_path(posting)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /job_postings（列表含 _match_badge）" do
    it "有分析結果時列表 200" do
      posting = create(:job_posting, status: "analyzed")
      create(:analysis, job_posting: posting)
      get job_postings_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /job_postings" do
    it "有效參數建立職缺並轉到 show" do
      expect {
        post job_postings_path, params: { job_posting: { job_title: "Rails Engineer", raw_content: "JD 內容" } }
      }.to change(JobPosting, :count).by(1)
      expect(response).to redirect_to(job_posting_path(JobPosting.last))
    end

    it "缺必填時回 422 重渲染" do
      post job_postings_path, params: { job_posting: { job_title: "", raw_content: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /job_postings/:id/analyze（stub 服務，不碰 API）" do
    let(:posting) { create(:job_posting, status: "pending") }

    it "沒有預設履歷時導回履歷頁並提示" do
      # 確保沒有 default resume
      Resume.update_all(is_default: false)
      post analyze_job_posting_path(posting)
      expect(response).to redirect_to(resumes_path)
      expect(flash[:alert]).to be_present
    end

    it "分析成功導回 show 並提示完成" do
      create(:resume, is_default: true)
      allow_any_instance_of(JobAnalyzerService).to receive(:analyze).and_return(true)
      post analyze_job_posting_path(posting)
      expect(response).to redirect_to(job_posting_path(posting))
      expect(flash[:notice]).to eq("分析完成")
    end

    it "分析失敗導回 show 並帶錯誤" do
      create(:resume, is_default: true)
      allow_any_instance_of(JobAnalyzerService).to receive_messages(analyze: false, error: "分析失敗訊息")
      post analyze_job_posting_path(posting)
      expect(response).to redirect_to(job_posting_path(posting))
      expect(flash[:alert]).to eq("分析失敗訊息")
    end
  end

  describe "PATCH /job_postings/:id/archive" do
    it "封存職缺並導回列表" do
      posting = create(:job_posting, status: "pending")
      patch archive_job_posting_path(posting)
      expect(posting.reload.status).to eq("archived")
      expect(response).to redirect_to(job_postings_path)
    end
  end
end
