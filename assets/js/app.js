// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/kewkew"
import topbar from "../vendor/topbar"

document.addEventListener("click", async event => {
  const button = event.target.closest("[data-copy-target]")
  if (!button) return

  const input = document.getElementById(button.dataset.copyTarget)
  const status = document.getElementById("visitor-tracking-link-status")
  if (!input || !status) return

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(input.value)
      status.textContent = "Private link copied."
    } else {
      input.focus()
      input.select()
      status.textContent = "Select and copy your private link."
    }
  } catch (_error) {
    input.focus()
    input.select()
    status.textContent = "Select and copy your private link."
  }
})

document.addEventListener("submit", event => {
  const form = event.target.closest("form[data-confirm]")
  if (form && !window.confirm(form.dataset.confirm)) event.preventDefault()
})

document.addEventListener("click", event => {
  const target = event.target.closest("button[data-confirm], a[data-confirm]")
  if (target && !window.confirm(target.dataset.confirm)) {
    event.preventDefault()
    event.stopImmediatePropagation()
  }
}, true)

const visitorTicket = document.getElementById("visitor-ticket")

if (visitorTicket) {
  const status = document.getElementById("visitor-ticket-status")
  const position = document.getElementById("visitor-ticket-position")
  const cancellationForm = document.getElementById("visitor-cancel-form")
  const statusUrl = visitorTicket.dataset.statusUrl

  const refreshTicketStatus = async () => {
    if (document.hidden) return

    try {
      const response = await fetch(statusUrl, {
        headers: {Accept: "application/json"},
        cache: "no-store",
      })

      if (response.status === 404) {
        window.location.reload()
        return
      }

      if (!response.ok) return

      const ticket = await response.json()
      const positionLabel = ticket.position ? `${ticket.position} in line` : "No longer waiting"

      if (status.textContent !== ticket.status_label) status.textContent = ticket.status_label
      if (position.textContent.trim() !== positionLabel) position.textContent = positionLabel
      if (cancellationForm) cancellationForm.hidden = ticket.status !== "waiting"
    } catch (_error) {
      // Keep the last persisted state on screen and retry on the next interval.
    }
  }

  refreshTicketStatus()
  window.setInterval(refreshTicketStatus, 3000)
  document.addEventListener("visibilitychange", refreshTicketStatus)
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

