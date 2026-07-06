import { Controller } from "@hotwired/stimulus"

// Handles the "貼入 104 網址 → 自動帶入" flow on the new job posting form.
// Posts the URL to /job_postings/fetch_content and fills the form fields.
export default class extends Controller {
  static targets = ["url", "jobTitle", "companyName", "rawContent", "status", "button"]

  async fetch(event) {
    event.preventDefault()

    const url = this.urlTarget.value.trim()
    if (!url) {
      this.showStatus("請先貼上 104 職缺網址", "error")
      return
    }

    this.setLoading(true)
    this.showStatus("抓取中,請稍候…", "loading")

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      const response = await window.fetch("/job_postings/fetch_content", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
          "Accept": "application/json"
        },
        body: JSON.stringify({ source_url: url })
      })

      const data = await response.json()

      if (response.ok) {
        if (this.hasJobTitleTarget) this.jobTitleTarget.value = data.job_title || ""
        if (this.hasCompanyNameTarget) this.companyNameTarget.value = data.company_name || ""
        if (this.hasRawContentTarget) this.rawContentTarget.value = data.raw_content || ""
        this.showStatus("已自動帶入,請確認內容後送出", "success")
      } else {
        this.showStatus(data.error || "無法抓取,請手動填寫下方欄位", "error")
      }
    } catch (e) {
      this.showStatus("連線發生問題,請手動填寫下方欄位", "error")
    } finally {
      this.setLoading(false)
    }
  }

  setLoading(isLoading) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = isLoading
    this.buttonTarget.textContent = isLoading ? "抓取中…" : "自動帶入"
  }

  showStatus(message, kind) {
    if (!this.hasStatusTarget) return
    const colors = {
      loading: "text-gray-500",
      success: "text-green-600",
      error: "text-red-600"
    }
    this.statusTarget.className = `text-sm mt-2 ${colors[kind] || "text-gray-500"}`
    this.statusTarget.textContent = message
  }
}
