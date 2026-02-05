import { Controller } from "@hotwired/stimulus"

// Handles "I'm not sure" checkbox behavior for taxonomy field
export default class extends Controller {
  static targets = ["checkbox", "taxonomyField"]

  toggle() {
    const isUnsure = this.checkboxTarget.checked
    
    if (isUnsure) {
      // Clear and disable the optional taxonomy field
      this.taxonomyFieldTarget.value = ""
      this.taxonomyFieldTarget.disabled = true
    } else {
      // Re-enable taxonomy field
      this.taxonomyFieldTarget.disabled = false
    }
  }
}

