# 建立 RSpec 測試體系 + 補現有核心測試（設計 spec）

- 日期：2026-07-08
- 狀態：設計已與使用者確認，待寫實作計畫（writing-plans）
- 對應 backlog：NEXT_STEPS「D. RSpec」，經使用者決定**提前到 PDF feature 之前先做**
- 分支：另開一條 branch（例：`test/rspec-foundation`），依進度里程碑 commit（非按檔案）

## 目標

專案目前**完全沒有測試框架**（無 `spec/` 無 `test/`，app 以 `--skip-test` 生成）。
本工作先建立 RSpec 測試地基，並補上現有核心程式的測試，之後才回頭做 PDF 上傳 feature。

## 範圍（使用者選定：核心單元 + model 驗證）

- **納入**：三支 service 的核心單元測試、四個 model 的驗證與關鍵方法。
- **不納入**：controller request specs、feature/system specs、CI。（留下一輪）
- **不碰**：PDF 上傳 feature（其 spec 已完成並 park：`2026-07-08-resume-pdf-upload-design.md`）。

## 要裝的 gem（`:development, :test` 群組）

| gem | 用途 | 必要性 |
| :--- | :--- | :--- |
| `rspec-rails` | 測試框架本體 | 必要 |
| `webmock` | 封鎖對外 HTTP + stub `FetchJobContentService` 的 104 請求 | 必要 |
| `factory_bot_rails` | 乾淨產生有效 record（Analysis 有兩個 belongs_to） | 採用 |
| `shoulda-matchers` | validation 測試一行化 | 採用 |

## 測試絕不碰真 Anthropic API（三層防護，避免額度浪費）

已查證：`anthropic` gem 1.55.0 底層走 `Net::HTTP`（`internal/transport/pooled_net_requester.rb`），
WebMock hook 的正是 Net::HTTP，故能攔截。

1. **WebMock `disable_net_connect!(allow_localhost: true)`**（底線）：test 環境全面封鎖對外
   HTTP；任何跑向 `api.anthropic.com` 的請求會 raise，逃不掉。`allow_localhost` 保留給日後可能的
   本地 server。
2. **Client 邊界 stub**（主要）：`allow(LlmUsageTracker).to receive(:client)` 回假 client，
   `messages.create` 回罐頭 response（`.usage` / `.content`）——根本不建立真請求。
3. **測試環境假 key**：`.env.test` 放 `ANTHROPIC_API_KEY=test-dummy`，蓋掉真 key；即使真的
   `Anthropic::Client.new` 也不會動到真額度。

## 地基檔案

- `bundle install`
- `rails generate rspec:install` → 產生 `.rspec`、`spec/spec_helper.rb`、`spec/rails_helper.rb`
- `spec/rails_helper.rb` 加設定：
  - `require "webmock/rspec"`；`WebMock.disable_net_connect!(allow_localhost: true)`
  - factory_bot：`config.include FactoryBot::Syntax::Methods`
  - shoulda-matchers：`Shoulda::Matchers.configure`（rspec + rails）
- `.env.test`：`ANTHROPIC_API_KEY=test-dummy`（並確認 dotenv 在 test 讀得到）
- `spec/factories/`：`resumes`、`job_postings`、`analyses`、`usage_records`

## 要補的測試

### `spec/services/cost_calculator_spec.rb`
- sonnet / haiku 已知 model → 算出正確 cents（含 1M token 邊界值驗算）。
- rounding：產生分數分位時 `.round` 到最近整數。
- `input_tokens`/`output_tokens` 為 nil → `.to_i` 視為 0。
- **未知 provider/model → raise `CostCalculator::UnknownModelError`**。

### `spec/services/llm_usage_tracker_spec.rb`
- `track { canned_response }`：以罐頭 response（`.usage` 回 input/output tokens）→ 建出 UsageRecord
  且欄位（tokens、cost_cents、request_label、recordable）正確；回傳的是同一個 response。
- 未知 model → 吞掉 `UnknownModelError`、`cost_cents` 記 0，仍建 UsageRecord。
- 罐頭 response 用 double，不呼叫真 client。

### `spec/services/job_analyzer_service_spec.rb`
- stub `LlmUsageTracker.client` 回假 client；`messages.create` 回罐頭（`.content` 為含 `.text` 的
  block 陣列、`.usage` 給 tokens）。
- happy path：`analyze` → 建 Analysis（match_level、三個 JSON 欄位、cover_letter、raw_response 正確）、
  `job_posting.status` 轉 `analyzed`、建 UsageRecord、回傳 analysis。
- match_level 非法值 → 收斂為 `low`。
- malformed JSON（罐頭回非 JSON）→ `parse_json` 回 nil → 設 `@error`、不建 Analysis、回 nil。
- `Anthropic::Errors::APIError` 被 raise → 設 `@error`、回 nil。
- `parse_json`（私有，`send` 測）：純 JSON、```json fence 包住、前後夾雜文字抓第一個 `{...}`、
  壞字串 → nil。
- `extract_text`：多個 content block 串接。

### `spec/services/fetch_job_content_service_spec.rb`
- `extract_job_id`（send 測）：`/job/xxxx`、帶 query、`?jobno=` 舊式 → 取到 id；非法 → nil。
- `challenged?`（send 測，用 response double）：status 403 / `Cf-Mitigated` header / `text/html` 且含
  `"Just a moment"` → true；正常 → false。
- webmock stub 端點：
  - JSON 端點回合法罐頭（含 `data.header.jobName` 等）→ `call` 回 `success: true` 與正確欄位。
  - 兩層都回 403 → `call` 回手動貼上的友善錯誤。

### `spec/models/`
- `resume_spec.rb`：`title` / `content` presence；`Resume.default_resume` 回被標記的那份、沒有時回 nil；
  `unset_other_defaults`（存新 default → 其他 default 被清）。
- `job_posting_spec.rb`：`job_title` / `raw_content` presence、`status` inclusion；`latest_analysis` 取最新。
- `analysis_spec.rb`：`match_level` inclusion；`parsed_key_requirements` / `parsed_matched_skills` /
  `parsed_skill_gaps`（合法 JSON→陣列、壞 JSON→`[]`）。
- `usage_record_spec.rb`：`provider` / `model` presence；`cost_dollars`（cents→dollars round 4）。

## 驗收

- `bundle exec rspec` 全綠。
- 明確驗證「測試不碰真 API」：跑測試時無真實對外請求（WebMock 未被觸發 raise 即代表沒有漏網請求；
  可另加一條 spec 斷言對 `api.anthropic.com` 的請求會被 WebMock 擋）。
- 派 fresh verifier agent read-back：gem 群組、三層防護設定、各 spec 存在且涵蓋上述案例、`rspec` 綠燈。

## 明確不做（YAGNI）

- 不寫 controller request specs / feature / system specs。
- 不設 CI。
- 不碰 PDF feature。
- 不追求覆蓋率數字，只補「有邏輯、production 難 debug」的核心單元與 model 驗證。
