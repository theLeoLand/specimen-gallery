import { Controller } from "@hotwired/stimulus"

// Controls the flag modal for reporting specimens
export default class extends Controller {
  static targets = ["modal", "form", "reason", "details", "submitBtn", "message"]
  static values = { url: String }

  open(event) {
    event.preventDefault()
    event.stopPropagation()
    this.modalTarget.classList.remove("hidden")
    this.messageTarget.classList.add("hidden")
    this.formTarget.classList.remove("hidden")
    this.reasonTarget.value = ""
    this.detailsTarget.value = ""
  }

  close(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    this.modalTarget.classList.add("hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  async submit(event) {
    event.preventDefault()

    const reason = this.reasonTarget.value
    if (!reason) {
      alert("Please select a reason")
      return
    }

    this.submitBtnTarget.disabled = true
    this.submitBtnTarget.textContent = "Submitting..."

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          flag: {
            reason: reason,
            details: this.detailsTarget.value
          }
        })
      })

      const data = await response.json()

      if (response.ok) {
        this.formTarget.classList.add("hidden")
        this.messageTarget.textContent = data.message
        this.messageTarget.classList.remove("hidden", "text-red-600")
        this.messageTarget.classList.add("text-emerald-600")

        // Auto-close after 2 seconds
        setTimeout(() => this.close(), 2000)
      } else {
        this.messageTarget.textContent = data.error || "Something went wrong"
        this.messageTarget.classList.remove("hidden", "text-emerald-600")
        this.messageTarget.classList.add("text-red-600")
      }
    } catch (error) {
      this.messageTarget.textContent = "Network error. Please try again."
      this.messageTarget.classList.remove("hidden", "text-emerald-600")
      this.messageTarget.classList.add("text-red-600")
    } finally {
      this.submitBtnTarget.disabled = false
      this.submitBtnTarget.textContent = "Submit Report"
    }
  }
}

