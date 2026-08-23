import { Controller } from "@hotwired/stimulus"

// Toggles between the user and team selects on the error assignment form,
// showing and enabling only the select that matches the chosen target type.
export default class extends Controller {
  static targets = ["select"]

  change(event) {
    const type = event.target.value
    this.selectTargets.forEach((select) => {
      const active = select.dataset.target === type
      select.classList.toggle("hidden", !active)
      select.disabled = !active
    })
  }
}
