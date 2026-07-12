# job_analyzer — 專案規則（pointer 檔，保持極短）

Rails 7.2 求職分析工具：貼 JD → Anthropic API 對照預設履歷產出匹配分析，並記錄 token/成本。

## 開發流程
照 `~/Documents/claude-agent/000_Agent/protocols/dev-workflow.md`
（main 乾淨、branch per work、merge 前三道關、**使用者實測拍板才 merge**）。
本專案第 1 關機械檢查入口＝ `bin/check`（rubocop + brakeman + bundler-audit）。

## 專案特有（別處查不到、必須就地講）
- **開發用 `bin/dev`（不是 `rails server`）**——否則 Procfile.dev 的 Tailwind
  watcher 不會跑，改的 CSS/class 不會生效。
- **測試不可打真的 Anthropic API**（避免額度浪費）：WebMock 擋 net
  + stub `LlmUsageTracker.client` + `.env.test` 用 dummy key，三層一起。
- Rails 7.2 官方支援到 **2026-08-09**，之後要規劃升級。
