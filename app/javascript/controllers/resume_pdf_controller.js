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
