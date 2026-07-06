import { Controller } from "@hotwired/stimulus"

// Copies the text content of the "source" target to the clipboard.
// <div data-controller="clipboard">
//   <div data-clipboard-target="source">text…</div>
//   <button data-action="clipboard#copy" data-clipboard-target="button">複製</button>
// </div>
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.innerText
    try {
      await navigator.clipboard.writeText(text)
      this.flash("已複製 ✓")
    } catch (e) {
      this.flash("複製失敗")
    }
  }

  flash(label) {
    if (!this.hasButtonTarget) return
    const original = this.buttonTarget.dataset.original || this.buttonTarget.textContent
    this.buttonTarget.dataset.original = original
    this.buttonTarget.textContent = label
    setTimeout(() => { this.buttonTarget.textContent = original }, 1500)
  }
}
