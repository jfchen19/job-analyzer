require "rails_helper"
require_relative "../support/pdf_fixtures"

RSpec.describe "POST /resumes/extract_pdf" do
  include PdfFixtures

  def upload(bytes, filename:, type:)
    file = Tempfile.new(["u", File.extname(filename)])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, original_filename: filename)
  end

  it "合法 PDF 回 200 與抽出的文字" do
    post extract_pdf_resumes_path,
      params: { pdf: upload(pdf_with_text("RESUME-BODY-XYZ"), filename: "resume.pdf", type: "application/pdf") }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["text"]).to include("RESUME-BODY-XYZ")
  end

  it "非 PDF 檔回 422 與 error" do
    post extract_pdf_resumes_path,
      params: { pdf: upload("not a pdf", filename: "notes.txt", type: "text/plain") }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to be_present
  end

  it "沒帶檔案回 422 與 error" do
    post extract_pdf_resumes_path
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to be_present
  end

  it "超過 10MB 回 422 與 error(不進解析)" do
    big = upload(pdf_with_text, filename: "big.pdf", type: "application/pdf")
    allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(11.megabytes)
    post extract_pdf_resumes_path, params: { pdf: big }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("過大")
  end
end
