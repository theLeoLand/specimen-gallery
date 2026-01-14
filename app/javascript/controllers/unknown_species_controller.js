import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "nameField"]

  toggle() {
    const isUnknown = this.checkboxTarget.checked
    
    if (isUnknown) {
      this.nameFieldTarget.value = "Unknown"
      this.nameFieldTarget.disabled = true
      this.nameFieldTarget.required = false
    } else {
      this.nameFieldTarget.value = ""
      this.nameFieldTarget.disabled = false
    }
  }
}

