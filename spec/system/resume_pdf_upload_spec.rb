require "rails_helper"
require_relative "../support/pdf_fixtures"

RSpec.describe "履歷 PDF 上傳帶入", type: :system do
  include PdfFixtures

  # 瀏覽器上傳需要磁碟上的檔案路徑;把 prawn 產生的 PDF bytes 寫到暫存檔。
  # 用 after 清掉(Tempfile.create 的 class-method 形式不會自動刪)。
  after { File.unlink(@pdf_path) if @pdf_path && File.exist?(@pdf_path) }

  def pdf_fixture_path(text)
    file = Tempfile.create([ "resume", ".pdf" ])
    file.binmode
    file.write(pdf_with_text(text))
    file.close
    @pdf_path = file.path
  end

  it "選 PDF → 按帶入 → 文字填進 content → 存檔成功" do
    path = pdf_fixture_path("RESUME-SYSTEM-CHECK Rails engineer")

    visit new_resume_path
    fill_in "resume[title]", with: "系統測試履歷"
    # 檔案 input 沒有 name/id/label(只掛 data-resume-pdf-target="file"),
    # 用 CSS 定位後直接 .set(path)。
    find('input[type=file][data-resume-pdf-target="file"]', visible: :all).set(path)
    click_button "帶入"

    # Stimulus 非同步 fetch extract_pdf 後填入 content;等狀態訊息出現再斷言
    expect(page).to have_content("已帶入")
    expect(find_field("resume[content]").value).to include("RESUME-SYSTEM-CHECK")

    click_button "儲存"

    expect(page).to have_content("履歷已建立")
    expect(Resume.last.content).to include("RESUME-SYSTEM-CHECK")
  end
end
