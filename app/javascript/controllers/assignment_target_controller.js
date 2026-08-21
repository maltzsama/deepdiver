import { Controller } from "@hotwired/stimulus"

// Toggles between the user and team selects on the error assignment form,
// enabling only the select that matches the chosen target type.
export default class extends Controller {
  static targets = ["select"]

  change(event) {
    const type = event.target.value
    this.selectTargets.forEach((field) => {
      const active = field.dataset.target === type
      field.classList.toggle("hidden", !active)
      const select = field.querySelector("select")
      if (select) select.disabled = !active
    })
  }
}
