// app/javascript/controllers/reports_controller.js
import { Controller } from "@hotwired/stimulus"
import { showSpinner, hideSpinner } from "../utils/spinner"

export default class extends Controller {
  static targets = ["form", "spinner", "submitButton"]
  static originalButtonText = "Generate Report" // Store original text

  generateReport(event) {
    event.preventDefault()
    
    // Disable button and change text
    this.submitButtonTarget.disabled = true
    this.submitButtonTarget.textContent = "Generating..."
    showSpinner(this.spinnerTarget)

    const formData = new FormData(this.formTarget)
    const url = this.formTarget.action

    fetch(url, {
      method: "POST",
      headers: {
        "Accept": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: formData
    })
    .then(response => {
      if (!response.ok) {
        return response.text().then(text => { throw new Error(text) })
      }
      return response.blob()
    })
    .then(blob => {
      const url = window.URL.createObjectURL(blob)
      const a = document.createElement("a")
      a.href = url
      a.download = `inventory_report_${new Date().toISOString().split("T")[0]}.xlsx`
      document.body.appendChild(a)
      a.click()
      window.URL.revokeObjectURL(url)
      a.remove()
    })
    .catch(error => {
      console.error("Error:", error)
      alert("Error generating report: " + error.message)
    })
    .finally(() => {
      // Re-enable button and restore original text
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.textContent = this.constructor.originalButtonText
      hideSpinner(this.spinnerTarget)
    })
  }
}