import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "attribution"]

  connect() {
    this.toggle()
  }

  toggle() {
    const isCcBy = this.selectTarget.value === "CC_BY"

    if (isCcBy) {
      this.attributionTarget.classList.remove("hidden")
    } else {
      this.attributionTarget.classList.add("hidden")
      this.#clearFields()
    }
  }

  #clearFields() {
    this.attributionTarget.querySelectorAll("input").forEach(input => {
      input.value = ""
    })
  }
}

