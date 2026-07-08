# job_analyzer — 下一步

> 狀態(2026-07-08):MVP 已建好,fresh verifier 驗收 7/7 PASS,7 個 staged commits(未 push)。
> 有一個**未 commit** 的改動:`app/services/job_analyzer_service.rb` 的 `parse_json`
> JSON 容錯(剝 ```json code fence / 抓第一個 {...}),已過單元測試,等真實 API 跑過再連同後續一起 commit。

## 真跑後發現的問題(2026-07-08,填 key 首次操作 UI)
- **#2 分析等待無回饋(已修 · commit A)**:`analyze` 是同步呼叫 LLM(10~30 秒),
  送出後瀏覽器乾等、按鈕沒 disable、無 loading,使用者不知跑完沒。
  修法:`show.html.erb` 兩顆分析 button 加 `data-turbo-submits-with`(送出即變「分析中…」並 disable)。
  日後若要更好:改背景 job + Turbo Stream 廣播完成。
- **#3 104 自動帶入基本上必失敗(已修 UI · commit B)**:`FetchJobContentService` 有寫兩層自動抓,
  但 104 在 Cloudflare challenge 後面,純 server 端 HTTP 被回 403「Just a moment」,
  service 註解自己也寫「沒 live-verify 過」。真要通得用 headless browser(見 E)。
  短修:`new.html.erb` 把「手動填寫」升為方式一(推薦)、自動帶入降方式二並加強警語。
- **#1 履歷只能貼純文字,不支援 PDF 上傳(backlog)**:`resumes` 只有 `content:text` 欄位,
  沒接 ActiveStorage。要 PDF 需加附件欄位 + 抽文字(如 `pdf-reader`)。歸到「之後 A」。

## 已完成的里程碑 (2026-07-08)
- **D. RSpec 測試地基與核心單元驗證** ✓ DONE
  - 基建：rspec-rails / webmock / factory_bot / shoulda-matchers 到位
  - 核心單元測試：CostCalculator、LlmUsageTracker、JobAnalyzerService、FetchJobContentService
  - Model 驗證：4 個 model specs（Resume、Job、Analysis、UsageRecord）
  - 三層 API 防護：(1) WebMock disable_net_connect，(2) Anthropic client stub，(3) .env.test 假 key
  - 全套驗收：48 examples, 0 failures
  - 留待後續：feature/request/system specs
  - 後續可補的 4 個測試 nit（final review 判定非阻擋，之後順手）：
    1. `cost_dollars` 目前用 150→1.5 剛好整除，沒真的驗到 `.round(4)`（改用如 12345→123.45）
    2. `parsed_matched_skills` / `parsed_skill_gaps` 未測（是 `parsed_key_requirements` 的雙胞胎）
    3. `extract_text` 未餵非-text block，`.select { type == :text }` 過濾沒驗到
    4. Gemfile 新增 `group :test` 後尾端多一個空行（純美觀）

## 立即(讓基本功能真的能動)
1. 填 key 跑一次真實分析——這是唯一還沒被真跑過的一段(API 呼叫 → JSON parse → 建 Analysis → 記 UsageRecord):
   ```
   cd ~/Documents/job_analyzer
   cp .env.example .env      # 填入真的 ANTHROPIC_API_KEY(ANTHROPIC_MODEL 保持 claude-sonnet-4-6)
   bin/dev                   # http://localhost:3000
   ```
   流程:履歷 → 編輯預設那份貼真履歷(保持 default) → 新增職缺貼真 JD → 分析 → 看四區塊有沒有出來。
   確認記帳:`bin/rails console` → `UsageRecord.last`(要有 model / tokens / cost_cents)。
   出錯就看畫面紅色 flash + `log/development.log` 最後幾行(service 有 log raw 回應/錯誤類別)。
2. 跑通後:commit 那個 parse_json 容錯(併入這輪的修正)。

## 之後(擇一,依你想往哪偏)
- **A. 更好用**:cover letter markdown 匯出 / 投遞狀態追蹤(投遞→面試→結果)/ 多履歷選擇
- **B. cost dashboard 深化**(你原訂目標):成本按 model / 日 / 職缺拆解 + 趨勢
- **C. evals**(最能提升「LLM 專案」成色):用 golden set 量分析準不準
- **D.**(低優先)Ferrum 版 104 抓取、Render 部署

## 工作模式提醒(這個 session 談定的)
- 大任務派 subagent(指揮官不下場),驗收派 fresh agent,不自驗(見 ~/Documents/claude-agent/000_Agent/protocols/model-dispatch.md)。
- 每輪實作前先問「要不要邊做邊 commit、怎麼切」。
- 起手 gate hook 已裝(`~/.claude/hooks/implementation-gate.sh`),會自動提醒上面兩點。
