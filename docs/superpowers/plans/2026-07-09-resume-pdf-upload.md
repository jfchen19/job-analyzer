# 履歷 PDF 上傳 → 抽文字 → 分析 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓使用者上傳 PDF 履歷,伺服器端抽成純文字帶入 `resume.content`(不存原檔),再以該內容對職缺分析。

**Architecture:** 新增 `PdfTextExtractor`(pdf-reader 抽文字);新增 `POST /resumes/extract_pdf` endpoint 只抽不存、回 JSON;前端 Stimulus controller(仿現有 `job-fetch`)把抽出的文字填進 content textarea 供檢視後再存。分析器 `JobAnalyzerService` 完全不動。

**Tech Stack:** Rails 7.2、Ruby 3.3.7、pdf-reader(抽文字)、prawn(測試產 fixture PDF)、Stimulus/Hotwire、RSpec + WebMock。

## Global Constraints

- 分支:全程在 `feature/resume-pdf-upload`(已 rebase 到含 RSpec 的最新 main),依進度里程碑 commit(每個 Task 一個 commit)。
- **不存 PDF 原檔、不裝 ActiveStorage**:上傳的 PDF 讀 tempfile 抽文字後即丟。
- **分析器 `app/services/job_analyzer_service.rb` 不改**。
- `resume.content`(文字)永遠是分析唯一來源;PDF 上傳是額外入口,不取代手動貼上。
- extract_pdf endpoint 只抽不存、不建/不更新任何 record。
- 檔案大小上限 10MB;不信任副檔名,實際能否解析由 pdf-reader 決定。
- 錯誤一律回友善中文訊息、不 crash,永遠保留手動貼上退路。
- 測試不碰外部:沿用既有 WebMock `disable_net_connect!`;PdfTextExtractor 純本地解析。
- gem:`pdf-reader` 加在預設群組;`prawn` 加在 `:test` 群組(僅測試產 fixture 用)。

---

### Task 1: PdfTextExtractor service + 單元測試

**Files:**
- Modify: `Gemfile`(加 `pdf-reader`、`prawn`)
- Create: `app/services/pdf_text_extractor.rb`
- Create: `spec/support/pdf_fixtures.rb`(prawn 產 PDF bytes 的測試 helper)
- Create: `spec/services/pdf_text_extractor_spec.rb`

**Interfaces:**
- Produces: `PdfTextExtractor.new(io).call` → `{ success: true, text: String }` 或 `{ success: false, error: String }`。`io` 是可被 `PDF::Reader.new` 讀的 IO(如 `StringIO`、`Tempfile`、`File`)。

- [ ] **Step 1: Gemfile 加 gem**

在 `Gemfile` 頂層(靠近其他 gem)加:

```ruby
gem "pdf-reader", "~> 2.12"
```

在 `group :test do ... end` 內加:

```ruby
  gem "prawn", "~> 2.5"
```

- [ ] **Step 2: bundle**

Run: `bundle install`
Expected: 安裝成功,Gemfile.lock 出現 `pdf-reader`、`prawn`。

- [ ] **Step 3: 確認 pdf-reader 錯誤類別(避免 rescue 寫錯)**

Run: `bin/rails runner 'require "pdf/reader"; p PDF::Reader::MalformedPDFError.ancestors.include?(StandardError); p defined?(PDF::Reader::EncryptedPDFError)'`
Expected: 印出 `true` 與 `"constant"`。若 `EncryptedPDFError` 未定義,於 Step 6 的 rescue 改用 `PDF::Reader::MalformedPDFError` 涵蓋(它是加密/損毀的父類);在 report 註明。

- [ ] **Step 4: 建測試 fixture helper(prawn 產 PDF bytes)**

Create `spec/support/pdf_fixtures.rb`:

```ruby
require "prawn"

# Deterministic in-memory PDF bytes for specs — no committed binaries.
module PdfFixtures
  # A PDF with selectable text.
  # NOTE: keep the text ASCII — Prawn's built-in Helvetica cannot encode CJK
  # (it raises Prawn::Errors::IncompatibleStringEncoding). Language doesn't
  # matter for testing extraction, so ASCII fixtures avoid embedding a CJK font.
  def pdf_with_text(str = "Ruby on Rails backend engineer 5 years")
    Prawn::Document.new do
      text str
    end.render
  end

  # A PDF with no text layer (blank page) — stands in for a scanned/image-only PDF.
  def blank_pdf
    Prawn::Document.new { |_pdf| }.render
  end
end
```

- [ ] **Step 5: 寫 PdfTextExtractor spec**

Create `spec/services/pdf_text_extractor_spec.rb`:

```ruby
require "rails_helper"
require_relative "../support/pdf_fixtures"

RSpec.describe PdfTextExtractor do
  include PdfFixtures

  it "從可選取文字的 PDF 抽出文字" do
    result = described_class.new(StringIO.new(pdf_with_text("RESUME-CONTENT-ABC"))).call
    expect(result[:success]).to be(true)
    expect(result[:text]).to include("RESUME-CONTENT-ABC")
  end

  it "無文字層的 PDF(掃描圖型)回抽不到文字的 error" do
    result = described_class.new(StringIO.new(blank_pdf)).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to include("抽不到文字")
  end

  it "非 PDF 的 bytes 回 error、不 raise" do
    result = described_class.new(StringIO.new("這根本不是 PDF")).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to be_present
  end

  it "加密 PDF(PDF::Reader raise)回 error、不 raise" do
    allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError.new("encrypted"))
    result = described_class.new(StringIO.new(pdf_with_text)).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to be_present
  end

  it "nil io 回友善 error" do
    result = described_class.new(nil).call
    expect(result[:success]).to be(false)
    expect(result[:error]).to be_present
  end
end
```

- [ ] **Step 6: 跑測試,確認 RED(PdfTextExtractor 未定義)**

Run: `bundle exec rspec spec/services/pdf_text_extractor_spec.rb`
Expected: FAIL — `uninitialized constant PdfTextExtractor`。

- [ ] **Step 7: 實作 PdfTextExtractor**

Create `app/services/pdf_text_extractor.rb`:

```ruby
require "pdf/reader"

# Extracts plain text from a PDF, tolerating bad input. Never raises to callers;
# returns a friendly error instead. Knows nothing about HTTP, DB, or Resume.
#
#   PdfTextExtractor.new(io).call
#   => { success: true,  text: "..." }
#   => { success: false, error: "..." }
class PdfTextExtractor
  def initialize(io)
    @io = io
  end

  def call
    return failure("請先選擇 PDF 檔") if @io.nil?

    text = extract_text
    return failure("這份 PDF 抽不到文字(可能是掃描圖),請用可選取文字的 PDF 或直接貼上") if text.blank?

    { success: true, text: text }
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    Rails.logger.warn("[PdfTextExtractor] #{e.class}: #{e.message}")
    failure("無法讀取此 PDF(可能加密、損毀或非 PDF),請改用下方貼上")
  rescue => e
    Rails.logger.warn("[PdfTextExtractor] #{e.class}: #{e.message}")
    failure("無法讀取此 PDF,請改用下方貼上")
  end

  private

  def extract_text
    reader = PDF::Reader.new(@io)
    reader.pages.map(&:text).join("\n").strip
  end

  def failure(message)
    { success: false, error: message }
  end
end
```

- [ ] **Step 8: 跑測試,確認 GREEN**

Run: `bundle exec rspec spec/services/pdf_text_extractor_spec.rb`
Expected: PASS(5 examples, 0 failures)。若「加密」案例的 rescue 類別對不上 Step 3 的結果,調整 rescue 清單後再跑。

- [ ] **Step 9: 跑全套確認沒破壞既有**

Run: `bundle exec rspec`
Expected: 全綠(既有 54 + 新 5 = 59 examples, 0 failures)。

- [ ] **Step 10: Commit**

```bash
git add Gemfile Gemfile.lock app/services/pdf_text_extractor.rb spec/support/pdf_fixtures.rb spec/services/pdf_text_extractor_spec.rb
git commit -m "feat: PdfTextExtractor 從 PDF 抽純文字(pdf-reader),含容錯與單元測試"
```

---

### Task 2: extract_pdf endpoint + request spec

**Files:**
- Modify: `config/routes.rb`(resumes 加 `collection { post :extract_pdf }`)
- Modify: `app/controllers/resumes_controller.rb`(加 `extract_pdf` action)
- Create: `spec/requests/resumes_extract_pdf_spec.rb`

**Interfaces:**
- Consumes: `PdfTextExtractor.new(io).call`(Task 1)。
- Produces: `POST /resumes/extract_pdf`,參數 `pdf`(檔案),回 `{ text: ... }`(200)或 `{ error: ... }`(422)。路徑 helper `extract_pdf_resumes_path`。

- [ ] **Step 1: 加 route**

在 `config/routes.rb` 的 `resources :resumes do` 區塊內加一行(與既有 member/collection 並列):

```ruby
  resources :resumes do
    collection do
      post :extract_pdf
    end
    # ...既有的 member routes(set_default 等)保留不動...
  end
```

(若既有已有 `collection do ... end`,把 `post :extract_pdf` 加進去即可,勿重複開區塊。)

- [ ] **Step 2: 寫 request spec**

Create `spec/requests/resumes_extract_pdf_spec.rb`:

```ruby
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
```

- [ ] **Step 3: 跑,確認 RED(action 未定義 / route 未知)**

Run: `bundle exec rspec spec/requests/resumes_extract_pdf_spec.rb`
Expected: FAIL(route 已加但 action 未定義 → `AbstractController::ActionNotFound` 或 500)。

- [ ] **Step 4: 實作 extract_pdf action**

在 `app/controllers/resumes_controller.rb` 加(放在 public actions 區,`private` 之前):

```ruby
  MAX_PDF_BYTES = 10.megabytes

  # Extract text from an uploaded PDF and return JSON. Creates/stores nothing.
  def extract_pdf
    file = params[:pdf]
    return render_pdf_error("請先選擇 PDF 檔") if file.blank?
    return render_pdf_error("檔案過大,請壓縮或改用貼上") if file.size > MAX_PDF_BYTES

    result = PdfTextExtractor.new(file.tempfile).call
    if result[:success]
      render json: { text: result[:text] }
    else
      render_pdf_error(result[:error])
    end
  end
```

在 `private` 區加:

```ruby
  def render_pdf_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
```

- [ ] **Step 5: 跑,確認 GREEN**

Run: `bundle exec rspec spec/requests/resumes_extract_pdf_spec.rb`
Expected: PASS(4 examples, 0 failures)。

- [ ] **Step 6: 跑全套**

Run: `bundle exec rspec`
Expected: 全綠(59 + 4 = 63 examples, 0 failures)。

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/resumes_controller.rb spec/requests/resumes_extract_pdf_spec.rb
git commit -m "feat: POST /resumes/extract_pdf 抽 PDF 文字回 JSON(含大小/型別把關與 request spec)"
```

---

### Task 3: 前端上傳 UI(Stimulus + 表單)+ NEXT_STEPS

**Files:**
- Create: `app/javascript/controllers/resume_pdf_controller.js`
- Modify: `app/views/resumes/_form.html.erb`
- Modify: `NEXT_STEPS.md`

**Interfaces:**
- Consumes: `POST /resumes/extract_pdf`(Task 2)。
- Produces: 使用者可在 new/edit 履歷頁選 PDF → 按「帶入」→ content textarea 被填入抽出的文字。

- [ ] **Step 1: 建 Stimulus controller(仿 job_fetch,改送 FormData)**

Create `app/javascript/controllers/resume_pdf_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Handles the "上傳 PDF → 帶入" flow on the resume form.
// Posts the file to /resumes/extract_pdf and fills the content textarea.
export default class extends Controller {
  static targets = ["file", "content", "status", "button"]

  async extract(event) {
    event.preventDefault()

    const file = this.fileTarget.files[0]
    if (!file) {
      this.showStatus("請先選擇 PDF 檔", "error")
      return
    }

    const form = new FormData()
    form.append("pdf", file)

    this.setLoading(true)
    this.showStatus("解析中,請稍候…", "loading")

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await window.fetch("/resumes/extract_pdf", {
        method: "POST",
        headers: { "X-CSRF-Token": token, "Accept": "application/json" },
        body: form
      })
      const data = await response.json()

      if (response.ok) {
        if (this.hasContentTarget) this.contentTarget.value = data.text || ""
        this.showStatus("已帶入,請檢視/修改後儲存", "success")
      } else {
        this.showStatus(data.error || "無法解析,請改用下方貼上", "error")
      }
    } catch (e) {
      this.showStatus("連線發生問題,請改用下方貼上", "error")
    } finally {
      this.setLoading(false)
    }
  }

  setLoading(isLoading) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = isLoading
    this.buttonTarget.textContent = isLoading ? "解析中…" : "帶入"
  }

  showStatus(message, kind) {
    if (!this.hasStatusTarget) return
    const colors = { loading: "text-gray-500", success: "text-green-600", error: "text-red-600" }
    this.statusTarget.className = `text-sm mt-2 ${colors[kind] || "text-gray-500"}`
    this.statusTarget.textContent = message
  }
}
```

- [ ] **Step 2: 在表單加上傳區塊,並把 content textarea 掛成 target**

在 `app/views/resumes/_form.html.erb`:

(a) 把 `form_with` 加上 controller — 將

```erb
<%= form_with model: resume, class: "space-y-5" do |f| %>
```

改為

```erb
<%= form_with model: resume, data: { controller: "resume-pdf" }, class: "space-y-5" do |f| %>
```

(b) 在 `content` 那個 `<div>`(label + text_area)的**上方**插入上傳區塊:

```erb
  <div class="bg-gray-50 border border-gray-200 rounded-lg p-4">
    <p class="text-sm font-medium mb-1">從 PDF 帶入(選用)</p>
    <p class="text-xs text-gray-500 mb-2">選一份可選取文字的 PDF 履歷,按「帶入」把內容填進下方,存檔前可再修改。</p>
    <div class="flex items-center gap-2">
      <input type="file" accept="application/pdf"
             data-resume-pdf-target="file"
             class="text-sm file:mr-2 file:rounded file:border-0 file:bg-indigo-600 file:text-white file:px-3 file:py-1.5 file:cursor-pointer">
      <button type="button"
              data-action="resume-pdf#extract"
              data-resume-pdf-target="button"
              class="px-3 py-1.5 rounded-md bg-gray-700 text-white text-sm font-medium hover:bg-gray-800 whitespace-nowrap">
        帶入
      </button>
    </div>
    <div data-resume-pdf-target="status" class="text-sm mt-2"></div>
  </div>
```

(c) 把 `content` 的 `text_area` 加上 target。將

```erb
    <%= f.text_area :content, rows: 18,
          class: "w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm focus:border-indigo-500 focus:ring-indigo-500",
          placeholder: "貼上你的履歷純文字內容(技術技能、工作經歷、專案經歷…)" %>
```

改為(加 `data: { "resume-pdf-target": "content" }`):

```erb
    <%= f.text_area :content, rows: 18,
          data: { "resume-pdf-target": "content" },
          class: "w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm focus:border-indigo-500 focus:ring-indigo-500",
          placeholder: "貼上你的履歷純文字內容,或用上方 PDF 帶入" %>
```

- [ ] **Step 3: 驗證 view 可編譯 + Stimulus controller 語法**

Run: `bin/rails runner 'src = ActionView::Template::Handlers::ERB::Erubi.new(File.read("app/views/resumes/_form.html.erb")).src; RubyVM::InstructionSequence.compile(src); puts "erb OK"'`
Expected: `erb OK`。
Run: `node --check app/javascript/controllers/resume_pdf_controller.js`
Expected: 無輸出(語法正確)。若無 node,略過並在 report 註明改以人工檢視。

- [ ] **Step 4: 跑全套(確認沒動壞後端)**

Run: `bundle exec rspec`
Expected: 全綠(63 examples, 0 failures)。

- [ ] **Step 5: NEXT_STEPS 標記 #1 完成**

在 `NEXT_STEPS.md` 把 #1(履歷 PDF 上傳 backlog)標為已完成:PDF 上傳 → pdf-reader 抽文字 → 帶入 content(不存原檔),含 PdfTextExtractor 單元 spec + extract_pdf request spec。

- [ ] **Step 6: Commit**

```bash
git add app/javascript/controllers/resume_pdf_controller.js app/views/resumes/_form.html.erb NEXT_STEPS.md
git commit -m "feat: 履歷表單加 PDF 上傳帶入(Stimulus + 表單),NEXT_STEPS 標記 #1 完成"
```

---

## 交付後(不在本計畫 step 內,由指揮官處理)

- 派 fresh verifier agent read-back:gem 加對群組、PdfTextExtractor 容錯與 spec、extract_pdf endpoint 大小/型別把關、前端 target 對得上、`bundle exec rspec` 全綠、分析器未被動。
- 手動走一次真實 UI:選一份可選取文字 PDF 履歷 → 帶入 → textarea 出文字 → 存 → 用它分析一個職缺。
- 驗過後 merge `feature/resume-pdf-upload` 回 `main`(`--no-ff`)。
