# 履歷 PDF 上傳 → 抽文字 → 分析（設計 spec）

- 日期：2026-07-08
- 狀態：設計已與使用者確認，待寫實作計畫（writing-plans）
- 對應 backlog：NEXT_STEPS「之後 A」的 PDF 履歷（原問題 #1）

## 目標

讓使用者用**上傳 PDF** 的方式建立 / 更新履歷，並以該履歷內容對職缺做分析。

## 核心原則

PDF 只是「填 `resume.content` 的便利工具」。上傳的 PDF 抽成純文字後**即丟、不保存二進位檔**；
`resume.content`（文字）永遠是分析的唯一來源。分析器 `JobAnalyzerService` **完全不動**
（它照舊讀 `@resume.content` 塞進 prompt）。

## 已確認的三個決策

1. **抽取方式：伺服器端抽文字**（非 PDF 原生送 Claude）。用 `pdf-reader`（純 Ruby、無外部
   binary，Render 也能跑）把 PDF 抽成純文字。分析成本、流程都不變。
2. **不存原檔**：抽完即丟，不裝 ActiveStorage、不做 migration。理由：分析永遠讀已存的
   `resume.content`，一份履歷比對多職缺時不會再碰 PDF；保留原檔對此情境無加分。新版履歷就重新上傳。
3. **上傳流程：先帶入 textarea 可檢視再存**。仿現有 104「自動帶入」的 `job-fetch` 互動：
   選 PDF → 按「帶入」→ 前端拿到抽出的文字填進 `content` textarea → 使用者檢視/修改 → 再按儲存。

## 資料流

```
使用者選 PDF → 按「帶入」
  → POST /resumes/extract_pdf  (multipart，只帶檔案，不帶 resume 其他欄位)
      → PdfTextExtractor.new(io).call 讀 tempfile 抽文字
      → 回 JSON { text: "..." }  或  { error: "..." }
      （此 endpoint 不建立 / 不更新任何 record、不存檔）
  → 前端把 text 填進 content textarea，顯示狀態
  → 使用者檢視/修改 content → 按「儲存」→ 走原本的 resumes#create / #update
分析時：JobAnalyzerService 照舊讀 @resume.content（不變）
```

## 元件與檔案異動（以新增為主）

| 檔 | 動作 |
| :--- | :--- |
| `Gemfile` | 加 `gem "pdf-reader"`，`bundle install` |
| `app/services/pdf_text_extractor.rb` | **新增**。輸入 IO/tempfile，輸出 `{ success:, text: }` 或 `{ success: false, error: }` |
| `config/routes.rb` | `resources :resumes` 內加 `collection { post :extract_pdf }` |
| `app/controllers/resumes_controller.rb` | **新 action** `extract_pdf`：呼叫 extractor，回 JSON；不碰 DB。含檔案大小 / 型別把關 |
| `app/javascript/controllers/resume_pdf_controller.js` | **新增** Stimulus，仿 `job_fetch_controller.js`；差別是送 `FormData`（檔案）而非 JSON |
| `app/views/resumes/_form.html.erb` | `content` 上方加一區塊：檔案欄 +「帶入」鈕 + 狀態列，掛 `data-controller="resume-pdf"`。new/edit 共用此 partial，兩頁自動都有 |
| `NEXT_STEPS.md` | 把 #1 從 backlog 移為已做 |

### PdfTextExtractor 介面

- `PdfTextExtractor.new(io_or_tempfile).call`
  - 成功：`{ success: true, text: "抽出的純文字（各頁以換行接起、strip）" }`
  - 失敗：`{ success: false, error: "友善中文訊息" }`
- 依賴：`pdf-reader`。逐頁 `page.text`，join 後 strip。
- 職責單一：只做「PDF bytes → 純文字或錯誤」，不碰 HTTP、不碰 DB、不知道 Resume 存在。

### resumes#extract_pdf 行為

- 只接受 `params[:pdf]`（`ActionDispatch::Http::UploadedFile`）。
- 把關：無檔 → error；大小 > 10MB → error；其餘交給 extractor（不信任副檔名，靠 pdf-reader 實際解析）。
- 回 `render json: { text: ... }`（200）或 `render json: { error: ... }, status: :unprocessable_entity`。
- 不建立 / 不更新任何 record。CSRF 走同源 form 的 token（同 job-fetch 作法）。

## 錯誤處理（一律回友善訊息、不 crash，永遠保留「手動貼」退路）

| 情境 | 訊息 |
| :--- | :--- |
| 沒選檔 | 請先選擇 PDF 檔 |
| 非 PDF / 損毀 / 加密（PDF::Reader raise） | 無法讀取此 PDF（可能加密或損毀），請改用下方貼上 |
| 抽到空字（掃描圖檔型 PDF） | 這份 PDF 抽不到文字（可能是掃描圖），請用可選取文字的 PDF 或直接貼上 |
| 檔案 > 10MB | 檔案過大，請壓縮或改用貼上 |

## 安全 / 邊界

- endpoint 只抽不存，tempfile 讀完即丟，不落地二進位檔。
- 不信任副檔名或 client 端 content-type，實際能不能解析由 pdf-reader 決定。
- 檔案大小上限（10MB）避免記憶體爆掉。
- content textarea 仍可手動編輯 / 貼上，PDF 上傳是額外入口而非取代。

## 驗證方式（已更新：專案已於 2026-07-08 建立 RSpec 測試體系）

原 spec 寫「專案無測試框架」已過時——RSpec 測試地基（rspec-rails/webmock/factory_bot/
shoulda）已 merge 進 main。本 feature 直接用 RSpec 補測：

- **`spec/services/pdf_text_extractor_spec.rb`（必要）**：用 fixture PDF 驗
  - 正常可選取文字 PDF → 回 `{ success: true, text: ... }` 且含預期文字。
  - 加密 PDF → 回 `{ success: false, error: ... }`、不 raise。
  - 圖檔型（無文字層）PDF → 回空字判定的 error、不 raise。
  - 非 PDF 檔（如純文字/亂數 bytes）→ 回 error、不 raise。
  - fixtures 放 `spec/fixtures/files/`，計畫階段說明如何產生（正常 PDF 可用 Prawn 產；
    加密/圖檔型/非 PDF 各以最小 fixture 提供）。
- **`spec/requests/resumes_extract_pdf_spec.rb`（採用）**：POST `/resumes/extract_pdf`
  - 帶合法 PDF（`fixture_file_upload`）→ 200 且 JSON `text` 有值。
  - 帶非 PDF → 422 且 JSON `error`。
  - 超過大小上限 → 422 且 JSON `error`。
- 沿用測試不碰外部的既有防護（WebMock net-block）；PdfTextExtractor 純本地解析、無外部呼叫。
- 手動走一次 UI：new 履歷頁選 PDF → 帶入 → textarea 出現文字 → 存 → 用它分析一個職缺。
- 最後派 fresh verifier agent 逐條 read-back + `bundle exec rspec` 全綠。

## 明確不做（YAGNI）

- 不存 PDF 原檔、不裝 ActiveStorage。
- 不做 PDF 原生送 Claude。
- 不做多履歷選擇 / cover letter 匯出（NEXT_STEPS 其他項）。
- 不做 controller/feature/system specs 以外的擴張（沿用 RSpec 既有範圍：單元 + request）。
