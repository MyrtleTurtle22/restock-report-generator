// app/javascript/utils/spinner.js
export function showSpinner(element) {
  if (!element) return
  
  element.innerHTML = `
    <div class="spinner">
      <div class="double-bounce1"></div>
      <div class="double-bounce2"></div>
    </div>
  `
  element.style.display = 'block'
}

export function hideSpinner(element) {
  if (!element) return
  element.style.display = 'none'
}