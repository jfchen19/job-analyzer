# job_analyzer

求職用的職缺分析工具。把職缺描述貼進來，它會拿你的履歷跟這則 JD 對照，用 Claude 產出匹配程度、對得上的技能、缺的技能，以及一段可以改寫成自我介紹的草稿。每次呼叫的 token 用量與花費都會記下來。

自己求職時做的。重複讀 JD、反覆判斷「這個職缺我到底合不合」很花時間，而且判斷標準會隨心情飄移，所以把這件事交給一個固定的 prompt。

## 功能

- 貼上 JD 建立職缺，一鍵產生匹配分析（匹配程度 / 關鍵需求 / 符合的技能 / 技能落差 / 自我介紹草稿）
- 履歷可以貼純文字，也可以上傳 PDF 自動抽出文字
- 多份履歷切換，指定其中一份為預設，分析時自動採用
- 首頁顯示職缺總數、已分析數、匹配程度分布、最近五筆分析，以及本月 API 花費
- 每次呼叫的 token 數與換算成本寫進 `usage_records`，之後要做成本報表用

## 技術棧

Rails 8.1 / Ruby 3.3.7 / PostgreSQL / Hotwire（importmap + Stimulus + Turbo）/ Tailwind CSS / RSpec。
LLM 走 Anthropic 官方 `anthropic` gem，預設 model 為 `claude-sonnet-4-6`。

## 環境需求

- Ruby 3.3.7
- PostgreSQL
- **poppler**（提供 `pdftotext`，履歷 PDF 上傳需要）
  macOS：`brew install poppler`　Debian/Ubuntu：`apt install poppler-utils`
- Anthropic API key

## 安裝

```bash
git clone <this-repo>
cd job_analyzer

cp .env.example .env
# 編輯 .env，填入你的 ANTHROPIC_API_KEY

bin/setup
```

先填 `.env` 再跑 `bin/setup`——後者會安裝相依套件、建好資料庫，然後直接把開發伺服器起起來。不想讓它自動啟動就加 `--skip-server`。

`.env` 已被 gitignore，key 不會進版本控制。

之後要再啟動：

```bash
bin/dev
```

用 `bin/dev` 而不是 `rails server`——它會同時起 Rails 與 Tailwind 的 watcher，直接跑 `rails server` 的話改了樣式不會重新編譯。

`bin/setup` 會種一筆佔位用的預設履歷，內容是「請替換成你的實際履歷內容」之類的字樣。開始分析之前先去「履歷」把它編輯成你自己的內容。

## 測試

```bash
bundle exec rspec                                    # 全部
bundle exec rspec spec/services                      # 單一目錄
bundle exec rspec spec/models/resume_spec.rb:20      # 單一 example
```

測試分成 model / service / request / system 四層，system 測試用 Cuprite 跑 headless Chrome。

測試不會真的呼叫 Anthropic API（避免燒掉額度），由三層擋住：WebMock 全域封鎖對外連線、service 層的 client 被 stub、`.env.test` 用假 key。要新增碰到 LLM 的測試時記得確認自己在哪一層底下。

## 靜態檢查

```bash
bin/check
```

一次跑完 RuboCop、Brakeman、bundler-audit，任何一項沒過就以非零狀態結束。

## 環境變數

| 變數 | 必填 | 說明 |
| :--- | :--- | :--- |
| `ANTHROPIC_API_KEY` | 是 | Anthropic API key |
| `ANTHROPIC_MODEL` | 否 | 覆寫分析用的 model，預設 `claude-sonnet-4-6` |

## 已知限制

- **分析是同步的**，一次要等 10～30 秒，期間按鈕會顯示「分析中」。要改善得換成背景工作加 Turbo Stream。
- **104 職缺網址自動帶入幾乎都會失敗**，因為對方有 Cloudflare 擋著，純伺服器端的請求會被回 challenge 頁。所以新增職缺頁把手動貼上列為主要方式，自動帶入只是順手試一下，失敗了不影響流程。
- 成本計算表只登記了 `claude-sonnet-4-6` 與 `claude-haiku-4-5`，換用其他 model 會被記成 0 元，要自己補進 `CostCalculator::PRICING`。
