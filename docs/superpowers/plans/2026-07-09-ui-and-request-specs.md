# UI 與 Request/System 測試補強 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把目前只覆蓋邏輯層的測試,延伸到 controller(request specs)與使用者實際操作的 UI/JS 層(system specs),並為曾造成 500 的 `_match_badge` 無限遞迴加回歸測試。

**Architecture:** 三類測試:①`_match_badge` 回歸——GET 會 render 它的頁面斷言 200;②request specs——in-process,分析流程用 stub `JobAnalyzerService`(不碰 API);③system specs——Capybara + cuprite(headless Chrome)實跑「PDF 上傳→帶入」這條有 JS 的流程(走 pdftotext,無外部 API)。

**Tech Stack:** RSpec、Capybara、cuprite(Ferrum/headless Chrome)、WebMock、FactoryBot、既有 pdftotext。

## Global Constraints

- 分支:全程在 `test/ui-and-request-specs`(off main),依進度里程碑 commit(每個 Task 一個 commit)。
- **不改 production 程式**(`app/` 下除非挖到真 bug,先回報)。這是測試補強。
- **測試不得碰真實 Anthropic API**:分析相關流程一律 stub `JobAnalyzerService`(request spec)或不涉及分析(system spec)。沿用既有 WebMock `disable_net_connect!`。
- system spec 只跑「不需 API」的 UI 流程(PDF 上傳帶入);需 API 的分析流程用 request spec + stub。
- 新增 gem 放 `:test` 群組:`capybara`、`cuprite`。
- cuprite 用 headless Chrome(環境已有 `/Applications/Google Chrome.app`)。
- 既有全套為 65 examples;每個 Task 完成後全套仍須全綠。

---

### Task 1: Capybara + cuprite 系統測試基建 + smoke

**Files:**
- Modify: `Gemfile`(加 `capybara`、`cuprite` 到 `:test`)
- Modify: `spec/rails_helper.rb`(system spec 設定)
- Create: `spec/system/smoke_system_spec.rb`

**Interfaces:**
- Produces: system spec 可用(`type: :system` 自動 `driven_by :cuprite`,headless Chrome)。

- [ ] **Step 1: Gemfile 加 gem**

在 `Gemfile` 既有的 `group :test do ... end` 內加:

```ruby
  gem "capybara", "~> 3.40"
  gem "cuprite", "~> 0.15"
```

- [ ] **Step 2: bundle**

Run: `bundle install`
Expected: 安裝成功,Gemfile.lock 出現 `capybara`、`cuprite`、`ferrum`。

- [ ] **Step 3: rails_helper 加 system spec 設定**

在 `spec/rails_helper.rb` 的 `RSpec.configure do |config|` 區塊**之前**加:

```ruby
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 900],
    headless: true,
    browser_options: { "no-sandbox": nil }
  )
end
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
```

在 `RSpec.configure do |config|` 區塊**內**加:

```ruby
  config.before(:each, type: :system) { driven_by :cuprite }
```

- [ ] **Step 4: 寫 smoke system spec(證明 headless Chrome 跑得起來)**

Create `spec/system/smoke_system_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "系統測試基建", type: :system do
  it "能用 headless Chrome 載入首頁" do
    visit "/"
    expect(page).to have_content("職缺")
  end
end
```

（首頁 dashboard 一定含「職缺」字樣;若實際文案不同,改成頁面上確定存在的字。）

- [ ] **Step 5: 跑 smoke,確認 headless Chrome 可用**

Run: `bundle exec rspec spec/system/smoke_system_spec.rb`
Expected: PASS(1 example)。若 Chrome 啟動失敗,report 貼出錯誤(可能需調 browser_path 指到 `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`)。

- [ ] **Step 6: 全套回歸**

Run: `bundle exec rspec`
Expected: 全綠(65 + 1 = 66 examples, 0 failures)。

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock spec/rails_helper.rb spec/system/smoke_system_spec.rb
git commit -m "test: 建立 Capybara + cuprite 系統測試基建(headless Chrome)"
```

---

### Task 2: `_match_badge` 回歸 + job_postings/dashboard request specs

**Files:**
- Create: `spec/requests/job_postings_spec.rb`
- Create: `spec/requests/dashboard_spec.rb`

**Interfaces:**
- Consumes: factories `:job_posting`、`:resume`、`:analysis`;`JobAnalyzerService#analyze`/`#error`(stub);routes `job_posting_path`、`job_postings_path`、`analyze_job_posting_path`、`archive_job_posting_path`、`root_path`。

- [ ] **Step 1: 寫 job_postings request spec**

Create `spec/requests/job_postings_spec.rb`:

```ruby
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
```

- [ ] **Step 2: 寫 dashboard request spec**

Create `spec/requests/dashboard_spec.rb`:

```ruby
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
```

- [ ] **Step 3: 跑,確認全綠**

Run: `bundle exec rspec spec/requests/job_postings_spec.rb spec/requests/dashboard_spec.rb`
Expected: PASS（約 9 examples, 0 failures）。若 #4 回歸紅燈代表遞迴 bug 回來了——回報。

- [ ] **Step 4: 全套回歸**

Run: `bundle exec rspec`
Expected: 全綠。

- [ ] **Step 5: Commit**

```bash
git add spec/requests/job_postings_spec.rb spec/requests/dashboard_spec.rb
git commit -m "test: job_postings/dashboard request specs + _match_badge 遞迴回歸(#4)"
```

---

### Task 3: resumes request specs

**Files:**
- Create: `spec/requests/resumes_spec.rb`

**Interfaces:**
- Consumes: factory `:resume`;routes `resumes_path`、`resume_path`、`set_default_resume_path`。

- [ ] **Step 1: 確認 set_default 路徑名**

Run: `bin/rails routes | grep resumes | grep -i default`
Expected: 顯示 `set_default` 的 path helper（如 `set_default_resume PATCH /resumes/:id/set_default`）。以實際輸出為準寫進 spec。

- [ ] **Step 2: 寫 resumes request spec**

Create `spec/requests/resumes_spec.rb`:

```ruby
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

  describe "PATCH /resumes/:id/set_default" do
    it "設為預設會取消其他預設" do
      old = create(:resume, is_default: true)
      target = create(:resume, is_default: false)
      patch set_default_resume_path(target)
      expect(target.reload.is_default).to be(true)
      expect(old.reload.is_default).to be(false)
      expect(response).to redirect_to(resumes_path)
    end
  end
end
```

- [ ] **Step 3: 跑,確認全綠**

Run: `bundle exec rspec spec/requests/resumes_spec.rb`
Expected: PASS（4 examples, 0 failures）。若 `set_default_resume_path` 名稱與 Step 1 不同,改成實際名稱。

- [ ] **Step 4: 全套回歸**

Run: `bundle exec rspec`
Expected: 全綠。

- [ ] **Step 5: Commit**

```bash
git add spec/requests/resumes_spec.rb
git commit -m "test: resumes request specs(建立/更新/設預設)"
```

---

### Task 4: PDF 上傳帶入的 system spec（守住 JS/UI 這層）

**Files:**
- Create: `spec/system/resume_pdf_upload_spec.rb`

**Interfaces:**
- Consumes: 既有 `spec/support/pdf_fixtures.rb` 的 `pdf_with_text`;`POST /resumes/extract_pdf`(走 pdftotext,無 API);新增履歷表單的 PDF 上傳 UI(`resume-pdf` Stimulus)。

- [ ] **Step 1: 寫 system spec**

Create `spec/system/resume_pdf_upload_spec.rb`:

```ruby
require "rails_helper"
require_relative "../support/pdf_fixtures"

RSpec.describe "履歷 PDF 上傳帶入", type: :system do
  include PdfFixtures

  # attach_file 需要磁碟上的檔案路徑;把 prawn 產生的 PDF bytes 寫到暫存檔。
  def pdf_fixture_path(text)
    file = Tempfile.create(["resume", ".pdf"])
    file.binmode
    file.write(pdf_with_text(text))
    file.close
    file.path
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
```

- [ ] **Step 2: 跑 system spec(headless Chrome 實跑整條 JS 流程)**

Run: `bundle exec rspec spec/system/resume_pdf_upload_spec.rb`
Expected: PASS(1 example)。此測試會實際開 headless Chrome、真的觸發 Stimulus fetch → extract_pdf → pdftotext。需確認執行 rspec 的 shell PATH 有 `pdftotext`(`/opt/homebrew/bin`)。若 `.set(path)` 因 input 被 CSS 隱藏而失敗,加 `make_visible: true` 或改用 `attach_file(find(...)[:id]...)` 前先給 input 一個 id;等不到 content 就拉長 `have_content` 的等待,並在 report 記錄實際調整。

- [ ] **Step 3: 全套回歸**

Run: `bundle exec rspec`
Expected: 全綠(約 66 + 9 + 4 + 1 = 80 examples 上下, 0 failures)。

- [ ] **Step 4: Commit**

```bash
git add spec/system/resume_pdf_upload_spec.rb
git commit -m "test: PDF 上傳帶入 system spec(cuprite 實跑 Stimulus + extract_pdf)"
```

---

## 交付後(不在 step 內,由指揮官處理)

- 派 fresh verifier agent read-back:gem 群組、cuprite 設定、各 spec 存在且涵蓋(#4 回歸、analyze stub 不碰 API、system spec 真跑 JS)、`bundle exec rspec` 全綠。
- **交回使用者實測確認**後,才 merge `test/ui-and-request-specs` 回 main(`--no-ff`)。指揮官不自行 merge。
