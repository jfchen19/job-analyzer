require "rails_helper"

RSpec.describe "Resumes", type: :request do
  describe "POST /resumes" do
    it "有效參數建立並導回列表" do
      expect {
        post resumes_path, params: { resume: { title: "後端版本", content: "履歷內容" } }
      }.to change(Resume, :count).by(1)
      expect(response).to redirect_to(resumes_path)
      expect(flash[:notice]).to be_present
    end

    it "缺必填回 422" do
      post resumes_path, params: { resume: { title: "", content: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /resumes/:id" do
    it "更新內容並導回列表" do
      resume = create(:resume, content: "舊內容")
      patch resume_path(resume), params: { resume: { content: "新內容" } }
      expect(resume.reload.content).to eq("新內容")
      expect(response).to redirect_to(resumes_path)
    end
  end

  describe "PUT /resumes/:id/set_default" do
    it "設為預設會取消其他預設" do
      old = create(:resume, is_default: true)
      target = create(:resume, is_default: false)
      put set_default_resume_path(target)
      expect(target.reload.is_default).to be(true)
      expect(old.reload.is_default).to be(false)
      expect(response).to redirect_to(resumes_path)
    end
  end
end
