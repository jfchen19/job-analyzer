# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Rails 8.1 求職分析工具：貼一則 JD → 呼叫 Anthropic API 對照預設履歷產出匹配分析 → 記錄 token 用量與成本。PostgreSQL + Hotwire（importmap / Stimulus / Turbo）+ Tailwind，無 background job、無 Active Storage。

## 指令

| 用途 | 指令 |
| :--- | :--- |
| 開發 server | `bin/dev` |
| 靜態檢查 | `bin/check`（rubocop + brakeman + bundler-audit，任一失敗即非零退出） |
| 全套測試 | `bundle exec rspec` |
| 單一檔案 | `bundle exec rspec spec/services/job_analyzer_service_spec.rb` |
| 單一 example | `bundle exec rspec spec/services/job_analyzer_service_spec.rb:42` |
| 只跑 system spec | `bundle exec rspec spec/system`（Cuprite headless Chrome） |

**開發一定要用 `bin/dev`，不要用 `rails server`**——後者不會啟動 `Procfile.dev` 裡的 Tailwind watcher，改了 CSS/class 不會生效。

## 架構

### 主資料流（貼 JD → 分析結果）
`JobPostingsController#create`（[app/controllers/job_postings_controller.rb:12](app/controllers/job_postings_controller.rb#L12)）只存 JD 文字，**不分析**。分析是使用者在 show 頁另外觸發的第二步：`#analyze`（[:42](app/controllers/job_postings_controller.rb#L42)）取 `Resume.default_resume` → `JobAnalyzerService#analyze` → 建 `Analysis`、把 `job_posting.status` 設為 `analyzed`（[app/services/job_analyzer_service.rb:71-82](app/services/job_analyzer_service.rb#L71-L82)）→ 導回 show 頁渲染 `latest_analysis`。

`#analyze` 是同步呼叫 LLM（10～30 秒），靠 `data: { turbo_submits_with: }` 給送出回饋（[app/views/job_postings/show.html.erb:17](app/views/job_postings/show.html.erb#L17)）。要改成非同步就得引入 background job + Turbo Stream，目前 `app/jobs/` 只有 scaffold 的 `application_job.rb`。

### Service 層的合約
- **`JobAnalyzerService`** — 唯一做配對分析的地方。`#analyze` 成功回 `Analysis`、失敗回 `nil` 並設 `#error`（呼叫端靠回傳值判斷，不靠例外）。
- **`LlmUsageTracker`** — **所有 Anthropic 呼叫的唯一入口**，包一層記帳。`.client` 在呼叫時才 new（[app/services/llm_usage_tracker.rb:23](app/services/llm_usage_tracker.rb#L23)）；`#track { }` 執行 block、讀 `response.usage`、算成本、建 `UsageRecord`。新增任何 LLM 呼叫都要走這裡，否則不會被記帳。
- **`CostCalculator`** — 純函式，查 `PRICING` 表；未知 model 丟 `UnknownModelError`，由 `LlmUsageTracker` 接住並記 0 元（[app/services/llm_usage_tracker.rb:44-47](app/services/llm_usage_tracker.rb#L44-L47)）。**加新 model 要同步更新 `PRICING`**，否則成本靜默記成 0。
- **`FetchJobContentService`**、**`PdfTextExtractor`** 是獨立分支，不進記帳鏈。後者呼叫系統的 `pdftotext -layout`（外部相依）。

`UsageRecord.recordable` 是多型且 `optional: true`，目前只有 `JobPosting` 掛上去。

### LLM 回應的容錯
模型不保證回乾淨 JSON，所以 `#parse_json` 依序嘗試「直接 parse」→「剝掉 \`\`\`json fence」→「抓第一個 `{...}`」（[app/services/job_analyzer_service.rb:98-112](app/services/job_analyzer_service.rb#L98-L112)）。`match_level` 若不在 `Analysis::MATCH_LEVELS` 允許值內，一律當成 `"low"`。改 prompt 或換 model 時這層要一起顧。

model 名稱走 `ENV.fetch("ANTHROPIC_MODEL", DEFAULT_MODEL)`，API key 由 gem 自己讀 `ENV["ANTHROPIC_API_KEY"]`，沒有 initializer。

### 跨檔案的隱性約定
- `Resume.default_resume` 刻意寫成類別方法而非 scope（[app/models/resume.rb:10](app/models/resume.rb#L10)），避免無資料時回傳 `all`；`before_save :unset_other_defaults` 保證同時只有一筆 default。
- 狀態的合法值定義在 model 常數（`JobPosting::STATUSES`、`Analysis::MATCH_LEVELS`），validation 與 service 的檢查都引用它們，不要另外寫死字串。
- `JobPosting#safe_source_url`（[app/models/job_posting.rb:17](app/models/job_posting.rb#L17)）只放行 `https?://`，擋 `javascript:` XSS；view 端拿到 `nil` 就退化成純文字。**這是修過的真實漏洞，不要繞過它直接用 `source_url` 當 href。**
- 104 職缺抓取必然常態失敗（Cloudflare challenge），設計上就是優雅降級：新增頁把「手動貼上」列為方式一，自動帶入只是 best-effort。

## 測試

**測試不可打真的 Anthropic API**（會燒額度），三層防護缺一不可：
1. WebMock 全域擋網路 — [spec/rails_helper.rb:13-14](spec/rails_helper.rb#L13-L14)
2. stub `LlmUsageTracker.client`（service spec）或更上層的 `JobAnalyzerService#analyze`（request spec）
3. `.env.test` 用 dummy key

新增會碰到 LLM 的測試時，先確認自己落在哪一層防護底下。

## 開發流程

- `main` 隨時保持可跑、測試全部通過；不在 `main` 上直接開發。
- 一個工作單元一條 branch，完成後 `--no-ff` merge 保留合併記錄。
- commit 粒度：一個子任務一個 commit（可跨 model/controller/view/spec），測試跟著它驗的程式碼進同一個 commit。Conventional Commits、英文單行。
- merge 前：`bin/check` 通過 → code review → 實際跑過 `bin/dev` 確認畫面正常（改到 UI 就不能只驗後端）。

Rails 8.1 支援期限：bug fix 到 2026-10-10、安全性到 2027-10-10。
