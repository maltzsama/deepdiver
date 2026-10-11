import { Controller } from "@hotwired/stimulus"

// Drives the bulk "apply policy" toolbar on the tables index.
//
// The checkboxes live inside the table but belong to the bulk form via the
// HTML5 `form` attribute, so they submit with it even though the form sits
// outside the table. This controller wires the "select all" checkbox and the
// "N selected" counter next to it.
export default class extends Controller {
  static targets = ["all", "item", "count"]

  toggleAll() {
    const checked = this.allTarget.checked
    this.itemTargets.forEach((item) => { item.checked = checked })
    this.refresh()
  }

  refresh() {
    const selected = this.itemTargets.filter((item) => item.checked).length

    this.countTarget.textContent = selected > 0
      ? this.countTarget.dataset.countText.replace("__count__", selected)
      : ""

    this.allTarget.checked = selected > 0 && selected === this.itemTargets.length
    this.allTarget.indeterminate = selected > 0 && selected < this.itemTargets.length
  }
}
