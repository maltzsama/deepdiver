import { Controller } from "@hotwired/stimulus"

// Shows only the S3 storage credential fields that apply to the selected
// authentication type (none / static / sts). Field wrappers declare
// data-s3-auth-show="static sts"; the select fires change and every wrapper
// toggles visibility accordingly. Same pattern as catalog-auth-controller.
export default class extends Controller {
  static targets = ["field"]

  change(event) {
    const method = event.target.value
    this.fieldTargets.forEach((wrapper) => {
      const shownFor = (wrapper.dataset.s3AuthShow || "").split(/\s+/)
      wrapper.classList.toggle("hidden", !shownFor.includes(method))
    })
  }

  connect() {
    const select = this.element.querySelector("select[data-s3-auth-select]")
    if (!select) return
    this.change({ target: select })
  }
}
