# RSpec 測試體系 + 核心測試回填 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為既有 Rails 專案建立 RSpec 測試地基，並回填三支 service 與四個 model 的核心測試，過程中保證測試絕不呼叫真實 Anthropic API。

**Architecture:** 用 rspec-rails 建地基；webmock 全面封鎖對外 HTTP、並 stub 104 請求；factory_bot 產生有效 record；shoulda-matchers 簡化驗證測試。因程式已存在，這是**回填**：每支 spec 寫完應**立即通過**（green）；若紅燈代表 spec 寫錯或挖到真 bug，需回報而非硬改測試遷就。

**Tech Stack:** Ruby 3.3.7、Rails 7.2、RSpec、WebMock、FactoryBot、shoulda-matchers、anthropic gem 1.55（底層 Net::HTTP）。

## Global Constraints

- 分支：全程在 `test/rspec-foundation` 上作業，依進度里程碑 commit（每個 Task 一個 commit）。
- 測試**不得**碰真實 Anthropic API：三層防護（WebMock `disable_net_connect!` + `LlmUsageTracker.client` stub + `.env.test` 假 key）。
- 外部 HTTP 一律 stub；不新增 controller/request/feature/system spec；不設 CI。
- 被測程式**不改**（除非挖到真 bug，先回報再議）。
- gem 加在 `:development, :test` 群組。
- 測試預期行為以現有實作為準：`DEFAULT_MODEL = "claude-sonnet-4-6"`、sonnet 定價 input 300 / output 1500（cents per 1M tokens）。

---

### Task 1: RSpec 地基 + 三層 API 防護 + factories

**Files:**
- Modify: `Gemfile`
- Create: `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`（`rails g rspec:install` 產生後修改 rails_helper）
- Create: `.env.test`
- Create: `spec/factories/resumes.rb`, `spec/factories/job_postings.rb`, `spec/factories/analyses.rb`, `spec/factories/usage_records.rb`
- Create: `spec/smoke_spec.rb`（證明地基與 net-block 生效，之後可保留）

**Interfaces:**
- Produces: factories `:resume`, `:job_posting`, `:analysis`, `:usage_record`（後續所有 Task 依賴）；rails_helper 全域設定（webmock net-block、factory_bot syntax、shoulda-matchers）。

- [ ] **Step 1: Gemfile 加測試 gem**

在 `Gemfile` 既有的 `group :development, :test do ... end` 內（若沒有就新增此群組）加入：

```ruby
group :development, :test do
  gem "rspec-rails", "~> 7.1"
  gem "factory_bot_rails", "~> 6.4"
end

group :test do
  gem "webmock", "~> 3.24"
  gem "shoulda-matchers", "~> 6.4"
end
```

- [ ] **Step 2: bundle**

Run: `bundle install`
Expected: 安裝成功，Gemfile.lock 出現 rspec-rails / webmock / factory_bot_rails / shoulda-matchers。

- [ ] **Step 3: 產生 RSpec 地基**

Run: `bin/rails generate rspec:install`
Expected: 建立 `.rspec`、`spec/spec_helper.rb`、`spec/rails_helper.rb`。

- [ ] **Step 4: 設定 rails_helper（三層防護第 1 層 + factory_bot + shoulda）**

在 `spec/rails_helper.rb` 的 `require 'rspec/rails'` 之後、`RSpec.configure` 之前加：

```ruby
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

require "shoulda/matchers"
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
```

在 `RSpec.configure do |config|` 區塊內加：

```ruby
  config.include FactoryBot::Syntax::Methods
```

- [ ] **Step 5: 建 .env.test 假 key（三層防護第 3 層）**

Create `.env.test`：

```
ANTHROPIC_API_KEY=test-dummy-key-not-real
ANTHROPIC_MODEL=claude-sonnet-4-6
```

（dotenv-rails 在 test 環境先讀 `.env.test` 再讀 `.env`，先到先贏，故此假 key 蓋過真 key。）

- [ ] **Step 6: 建 factories**

Create `spec/factories/resumes.rb`：

```ruby
FactoryBot.define do
  factory :resume do
    sequence(:title) { |n| "履歷版本 #{n}" }
    content { "Ruby on Rails 後端工程師，5 年經驗，熟 PostgreSQL、Sidekiq、RSpec。" }
    is_default { false }
  end
end
```

Create `spec/factories/job_postings.rb`：

```ruby
FactoryBot.define do
  factory :job_posting do
    job_title { "Senior Rails Engineer" }
    company_name { "Acme Inc." }
    raw_content { "我們正在尋找資深 Rails 工程師，需熟悉 API 設計與測試。" }
    status { "pending" }
  end
end
```

Create `spec/factories/analyses.rb`：

```ruby
FactoryBot.define do
  factory :analysis do
    association :job_posting
    association :resume
    match_level { "high" }
    key_requirements { JSON.generate(["Rails", "PostgreSQL"]) }
    matched_skills { JSON.generate(["Rails"]) }
    skill_gaps { JSON.generate(["Kubernetes"]) }
    cover_letter_suggestion { "建議強調 Rails 與測試經驗。" }
    raw_response { "{}" }
  end
end
```

Create `spec/factories/usage_records.rb`：

```ruby
FactoryBot.define do
  factory :usage_record do
    provider { "anthropic" }
    model { "claude-sonnet-4-6" }
    input_tokens { 1000 }
    output_tokens { 500 }
    cost_cents { 1 }
    request_label { "analyze_job_posting" }
  end
end
```

- [ ] **Step 7: 寫 smoke spec（證明地基 + net-block）**

Create `spec/smoke_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe "測試地基" do
  it "RSpec 與 factory_bot 可用" do
    resume = create(:resume)
    expect(resume).to be_persisted
  end

  it "WebMock 封鎖對外真實請求（保證不碰真 API）" do
    expect {
      Net::HTTP.get(URI("https://api.anthropic.com/v1/messages"))
    }.to raise_error(WebMock::NetConnectNotAllowedError)
  end
end
```

- [ ] **Step 8: 跑 smoke，確認地基與防護生效**

Run: `bundle exec rspec spec/smoke_spec.rb`
Expected: PASS（2 examples, 0 failures）。第二條證明真請求會被 WebMock 擋下。

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock .rspec .env.test spec/
git commit -m "test: RSpec 地基 + webmock/factory_bot/shoulda + 三層 API 防護"
```

---

### Task 2: CostCalculator spec

**Files:**
- Create: `spec/services/cost_calculator_spec.rb`

**Interfaces:**
- Consumes: `CostCalculator.calculate_cents(provider:, model:, input_tokens:, output_tokens:)` → Integer cents；未知 model raise `CostCalculator::UnknownModelError`。

- [ ] **Step 1: 寫 spec**

Create `spec/services/cost_calculator_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe CostCalculator do
  describe ".calculate_cents" do
    it "以 sonnet 定價算 1M/1M tokens = 1800 cents" do
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-sonnet-4-6",
        input_tokens: 1_000_000, output_tokens: 1_000_000
      )
      expect(cents).to eq(1800)
    end

    it "小額用量四捨五入到最近的 cent" do
      # 1500*300 + 1000*1500 = 450000 + 1500000 = 1950000 / 1e6 = 1.95 -> 2
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-sonnet-4-6",
        input_tokens: 1500, output_tokens: 1000
      )
      expect(cents).to eq(2)
    end

    it "haiku 定價 (input 100 / output 500)" do
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-haiku-4-5",
        input_tokens: 1_000_000, output_tokens: 1_000_000
      )
      expect(cents).to eq(600)
    end

    it "nil tokens 視為 0" do
      cents = described_class.calculate_cents(
        provider: "anthropic", model: "claude-sonnet-4-6",
        input_tokens: nil, output_tokens: nil
      )
      expect(cents).to eq(0)
    end

    it "未知 provider/model 會 raise UnknownModelError" do
      expect {
        described_class.calculate_cents(
          provider: "openai", model: "gpt-4o",
          input_tokens: 100, output_tokens: 100
        )
      }.to raise_error(CostCalculator::UnknownModelError)
    end
  end
end
```

- [ ] **Step 2: 跑，預期全綠（回填既有程式）**

Run: `bundle exec rspec spec/services/cost_calculator_spec.rb`
Expected: PASS（5 examples, 0 failures）。若紅燈，先核對是否算式理解錯或挖到真 bug，回報後再處理。

- [ ] **Step 3: Commit**

```bash
git add spec/services/cost_calculator_spec.rb
git commit -m "test: CostCalculator 單元測試（含未知 model raise）"
```

---

### Task 3: LlmUsageTracker spec

**Files:**
- Create: `spec/services/llm_usage_tracker_spec.rb`

**Interfaces:**
- Consumes: `LlmUsageTracker.new(provider:, model:, request_label:, recordable:).track { response }`；response 需回應 `.usage.input_tokens` / `.usage.output_tokens`；track 建 `UsageRecord` 並回傳原 response。

- [ ] **Step 1: 寫 spec**

Create `spec/services/llm_usage_tracker_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe LlmUsageTracker do
  let(:job_posting) { create(:job_posting) }
  let(:usage) { double("usage", input_tokens: 1000, output_tokens: 500) }
  let(:response) { double("response", usage: usage) }

  def build_tracker(model:)
    described_class.new(
      provider: "anthropic", model: model,
      request_label: "analyze_job_posting", recordable: job_posting
    )
  end

  it "建立 UsageRecord 並記錄正確 tokens 與 cost" do
    tracker = build_tracker(model: "claude-sonnet-4-6")
    expect { tracker.track { response } }.to change(UsageRecord, :count).by(1)

    record = UsageRecord.last
    expect(record.input_tokens).to eq(1000)
    expect(record.output_tokens).to eq(500)
    expect(record.cost_cents).to eq(1) # 1000*300 + 500*1500 = 1050000 /1e6 = 1.05 -> 1
    expect(record.request_label).to eq("analyze_job_posting")
    expect(record.recordable).to eq(job_posting)
  end

  it "回傳原本的 response 物件不變" do
    tracker = build_tracker(model: "claude-sonnet-4-6")
    expect(tracker.track { response }).to eq(response)
  end

  it "未知 model 時吞掉錯誤、cost 記 0，仍建 record" do
    tracker = build_tracker(model: "unknown-model")
    expect { tracker.track { response } }.to change(UsageRecord, :count).by(1)
    expect(UsageRecord.last.cost_cents).to eq(0)
  end
end
```

- [ ] **Step 2: 跑，預期全綠**

Run: `bundle exec rspec spec/services/llm_usage_tracker_spec.rb`
Expected: PASS（3 examples, 0 failures）。

- [ ] **Step 3: Commit**

```bash
git add spec/services/llm_usage_tracker_spec.rb
git commit -m "test: LlmUsageTracker 記帳與未知 model 容錯"
```

---

### Task 4: JobAnalyzerService spec（stub client，絕不碰真 API）

**Files:**
- Create: `spec/services/job_analyzer_service_spec.rb`

**Interfaces:**
- Consumes: `JobAnalyzerService.new(job_posting:, resume:).analyze` → 成功回 Analysis、失敗回 nil 且 `#error` 有值；內部呼叫 `LlmUsageTracker.client.messages.create(...)` 與 `tracker.track`。
- Stub 邊界：`allow(LlmUsageTracker).to receive(:client)` 回假 client。假 response 需回應 `.usage`（給 tokens）與 `.content`（block 陣列，每個 block 有 `.type == :text` 與 `.text`）。

- [ ] **Step 1: 寫 spec**

Create `spec/services/job_analyzer_service_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe JobAnalyzerService do
  let(:job_posting) { create(:job_posting) }
  let(:resume) { create(:resume, is_default: true) }
  let(:service) { described_class.new(job_posting: job_posting, resume: resume) }

  # 假 usage / content block，讓 tracker 與 extract_text 都能運作
  def fake_response(text)
    usage = double("usage", input_tokens: 1000, output_tokens: 500)
    block = double("block", type: :text, text: text)
    double("response", usage: usage, content: [block])
  end

  # 把 LlmUsageTracker.client 換成回傳指定 response 的假 client
  def stub_client_returning(text)
    messages = double("messages")
    allow(messages).to receive(:create).and_return(fake_response(text))
    allow(LlmUsageTracker).to receive(:client).and_return(double("client", messages: messages))
  end

  let(:valid_json) do
    JSON.generate(
      "match_level" => "high",
      "key_requirements" => ["Rails", "SQL"],
      "matched_skills" => ["Rails"],
      "skill_gaps" => ["K8s"],
      "cover_letter_suggestion" => "強調 Rails 經驗"
    )
  end

  describe "#analyze 成功" do
    before { stub_client_returning(valid_json) }

    it "建立 Analysis 並把 job_posting 轉為 analyzed" do
      analysis = service.analyze
      expect(analysis).to be_a(Analysis)
      expect(analysis.match_level).to eq("high")
      expect(analysis.parsed_key_requirements).to eq(["Rails", "SQL"])
      expect(job_posting.reload.status).to eq("analyzed")
    end

    it "同時建立一筆 UsageRecord（記帳）" do
      expect { service.analyze }.to change(UsageRecord, :count).by(1)
    end
  end

  it "非法 match_level 收斂為 low" do
    stub_client_returning(JSON.generate("match_level" => "excellent",
      "key_requirements" => [], "matched_skills" => [], "skill_gaps" => [],
      "cover_letter_suggestion" => ""))
    expect(service.analyze.match_level).to eq("low")
  end

  it "回應非 JSON 時不建 Analysis、設 error、回 nil" do
    stub_client_returning("這不是 JSON")
    expect {
      expect(service.analyze).to be_nil
    }.not_to change(Analysis, :count)
    expect(service.error).to be_present
  end

  it "APIError 被攔截：設 error、回 nil" do
    messages = double("messages")
    allow(messages).to receive(:create).and_raise(
      Anthropic::Errors::APIError.new(url: "https://api.anthropic.com/v1/messages", message: "boom")
    )
    allow(LlmUsageTracker).to receive(:client).and_return(double("client", messages: messages))

    expect(service.analyze).to be_nil
    expect(service.error).to be_present
  end

  describe "#parse_json 容錯（私有，send 測）" do
    it "純 JSON" do
      expect(service.send(:parse_json, '{"a":1}')).to eq("a" => 1)
    end

    it "剝去 ```json code fence" do
      expect(service.send(:parse_json, "```json\n{\"a\":1}\n```")).to eq("a" => 1)
    end

    it "前後夾雜文字時抓第一個 {...}" do
      expect(service.send(:parse_json, "說明：\n{\"a\":1}\n以上")).to eq("a" => 1)
    end

    it "無法解析回 nil" do
      expect(service.send(:parse_json, "完全不是 json")).to be_nil
    end

    it "空字串回 nil" do
      expect(service.send(:parse_json, "")).to be_nil
    end
  end

  describe "#extract_text（私有，send 測）" do
    it "串接所有 type == :text 的 block" do
      blocks = [double(type: :text, text: "前段"), double(type: :text, text: "後段")]
      response = double("response", content: blocks)
      expect(service.send(:extract_text, response)).to eq("前段後段")
    end
  end
end
```

- [ ] **Step 2: 跑，預期全綠**

Run: `bundle exec rspec spec/services/job_analyzer_service_spec.rb`
Expected: PASS（約 9 examples, 0 failures）。若 `Anthropic::Errors::APIError.new` 參數報錯，代表 gem 版本簽章有異動——回報，勿硬改。

- [ ] **Step 3: Commit**

```bash
git add spec/services/job_analyzer_service_spec.rb
git commit -m "test: JobAnalyzerService（happy/錯誤路徑/parse_json 容錯，全程 stub client）"
```

---

### Task 5: FetchJobContentService spec（webmock stub 104）

**Files:**
- Create: `spec/services/fetch_job_content_service_spec.rb`

**Interfaces:**
- Consumes: `FetchJobContentService.new(url).call` → `{ success: true, job_title:, company_name:, raw_content: }` 或 `{ success: false, error: }`；私有 `extract_job_id`、`challenged?`。
- 104 JSON 端點：`https://www.104.com.tw/job/ajax/content/<id>`；HTML 頁：`https://www.104.com.tw/job/<id>`。

- [ ] **Step 1: 寫 spec**

Create `spec/services/fetch_job_content_service_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe FetchJobContentService do
  describe "#extract_job_id（send）" do
    {
      "https://www.104.com.tw/job/8wjw0" => "8wjw0",
      "https://www.104.com.tw/job/8wjw0?jobsource=joblist" => "8wjw0",
      "https://www.104.com.tw/jobs/main/?jobno=1234567" => "1234567"
    }.each do |url, expected|
      it "從 #{url} 取出 #{expected}" do
        expect(described_class.new(url).send(:extract_job_id, url)).to eq(expected)
      end
    end

    it "非 104 網址回 nil" do
      expect(described_class.new("https://google.com").send(:extract_job_id, "https://google.com")).to be_nil
    end
  end

  describe "#challenged?（send）" do
    let(:service) { described_class.new("https://www.104.com.tw/job/8wjw0") }

    it "403 視為被擋" do
      resp = double(status: double(code: 403), headers: {}, to_s: "")
      expect(service.send(:challenged?, resp)).to be(true)
    end

    it "有 Cf-Mitigated header 視為被擋" do
      resp = double(status: double(code: 200), headers: { "Cf-Mitigated" => "challenge" }, to_s: "")
      expect(service.send(:challenged?, resp)).to be(true)
    end

    it "html 內含 Just a moment 視為被擋" do
      resp = double(status: double(code: 200),
                    headers: { "Content-Type" => "text/html" },
                    to_s: "<html>Just a moment...</html>")
      expect(service.send(:challenged?, resp)).to be(true)
    end

    it "正常 JSON 回應不算被擋" do
      resp = double(status: double(code: 200),
                    headers: { "Content-Type" => "application/json" }, to_s: "{}")
      expect(service.send(:challenged?, resp)).to be(false)
    end
  end

  describe "#call" do
    let(:job_id) { "8wjw0" }
    let(:url) { "https://www.104.com.tw/job/#{job_id}" }
    let(:json_endpoint) { "https://www.104.com.tw/job/ajax/content/#{job_id}" }

    it "JSON 端點成功時回傳解析欄位" do
      body = JSON.generate(
        "data" => {
          "header" => { "jobName" => "Rails Engineer", "custName" => "Acme" },
          "jobDetail" => { "jobDescription" => "我們正在找 Rails 工程師" }
        }
      )
      stub_request(:get, json_endpoint)
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      result = described_class.new(url).call
      expect(result[:success]).to be(true)
      expect(result[:job_title]).to eq("Rails Engineer")
      expect(result[:company_name]).to eq("Acme")
      expect(result[:raw_content]).to include("我們正在找 Rails 工程師")
    end

    it "兩層都被 403 擋時回手動貼上的友善錯誤" do
      stub_request(:get, json_endpoint).to_return(status: 403, body: "Just a moment...")
      stub_request(:get, url).to_return(status: 403, body: "Just a moment...")

      result = described_class.new(url).call
      expect(result[:success]).to be(false)
      expect(result[:error]).to include("手動貼上")
    end
  end
end
```

- [ ] **Step 2: 跑，預期全綠**

Run: `bundle exec rspec spec/services/fetch_job_content_service_spec.rb`
Expected: PASS（約 9 examples, 0 failures）。

- [ ] **Step 3: Commit**

```bash
git add spec/services/fetch_job_content_service_spec.rb
git commit -m "test: FetchJobContentService（id 解析/challenge 偵測/webmock 成功與被擋）"
```

---

### Task 6: Model specs（四個 model 驗證與關鍵方法）

**Files:**
- Create: `spec/models/resume_spec.rb`, `spec/models/job_posting_spec.rb`, `spec/models/analysis_spec.rb`, `spec/models/usage_record_spec.rb`

**Interfaces:**
- Consumes: 四個 model 的驗證與方法（`Resume.default_resume`、`Resume#unset_other_defaults`（before_save）、`JobPosting#latest_analysis`、`Analysis#parsed_*`、`UsageRecord#cost_dollars`）。

- [ ] **Step 1: 寫 Resume spec**

Create `spec/models/resume_spec.rb`：

```ruby
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
  end

  describe "設為 default 時清掉其他 default" do
    it "舊 default 會被取消" do
      old = create(:resume, is_default: true)
      create(:resume, is_default: true)
      expect(old.reload.is_default).to be(false)
    end
  end
end
```

- [ ] **Step 2: 寫 JobPosting spec**

Create `spec/models/job_posting_spec.rb`：

```ruby
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
```

- [ ] **Step 3: 寫 Analysis spec**

Create `spec/models/analysis_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe Analysis do
  # 有必填 association，給 shoulda 一個有效 subject 以免誤判
  subject { build(:analysis) }

  it { is_expected.to belong_to(:job_posting) }
  it { is_expected.to belong_to(:resume) }
  it { is_expected.to validate_inclusion_of(:match_level).in_array(Analysis::MATCH_LEVELS) }

  describe "#parsed_key_requirements" do
    it "合法 JSON 解析為陣列" do
      analysis = build(:analysis, key_requirements: JSON.generate(["a", "b"]))
      expect(analysis.parsed_key_requirements).to eq(["a", "b"])
    end

    it "壞掉的 JSON 回空陣列" do
      analysis = build(:analysis, key_requirements: "not json")
      expect(analysis.parsed_key_requirements).to eq([])
    end
  end
end
```

- [ ] **Step 4: 寫 UsageRecord spec**

Create `spec/models/usage_record_spec.rb`：

```ruby
require "rails_helper"

RSpec.describe UsageRecord do
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:model) }

  describe "#cost_dollars" do
    it "把 cents 換算成 dollars（round 4）" do
      record = build(:usage_record, cost_cents: 150)
      expect(record.cost_dollars).to eq(1.5)
    end
  end
end
```

- [ ] **Step 5: 跑全部 model spec，預期全綠**

Run: `bundle exec rspec spec/models`
Expected: PASS（約 12 examples, 0 failures）。

- [ ] **Step 6: Commit**

```bash
git add spec/models
git commit -m "test: 四個 model 驗證與關鍵方法（default_resume/latest_analysis/parsed_*/cost_dollars）"
```

---

### Task 7: 全綠總驗 + NEXT_STEPS 更新

**Files:**
- Modify: `NEXT_STEPS.md`

**Interfaces:**
- Consumes: 前六個 Task 的所有 spec。

- [ ] **Step 1: 跑整套測試，全綠**

Run: `bundle exec rspec`
Expected: PASS（全部 examples, 0 failures）。有任何紅燈先回報。

- [ ] **Step 2: 更新 NEXT_STEPS**

在 `NEXT_STEPS.md` 把「D. RSpec」那條標為已完成（測試地基已建、核心單元 + model 已補、feature/request specs 留待後續），並記下三層 API 防護已就位。

- [ ] **Step 3: Commit**

```bash
git add NEXT_STEPS.md
git commit -m "docs: NEXT_STEPS 標記 RSpec 測試地基與核心測試完成"
```

---

## 交付後（不在本計畫的 step 內，由指揮官處理）

- 派 fresh verifier agent read-back：gem 群組正確、三層防護設定到位、各 spec 存在且涵蓋 spec 列的案例、`bundle exec rspec` 全綠、測試過程無真實對外請求。
- 驗過後 merge `test/rspec-foundation` 回 `main`（`--no-ff`）。
- 之後接回 `feature/resume-pdf-upload`。
