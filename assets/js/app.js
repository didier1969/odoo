// JSS Scheduler - Phoenix LiveView Application (Simplified)
// assets/js/app.js

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons
import "phoenix_html"

// Establish Phoenix Socket and LiveView configuration
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

// Simple topbar implementation (without external dependency)
let topbar = {
  config: function(opts) { this.opts = opts || {} },
  show: function(delay) {
    this.el = this.el || this.createBar()
    this.el.style.display = 'block'
    this.el.style.opacity = '1'
  },
  hide: function() {
    if (this.el) {
      this.el.style.opacity = '0'
      setTimeout(() => { 
        if (this.el) this.el.style.display = 'none' 
      }, 300)
    }
  },
  createBar: function() {
    let bar = document.createElement('div')
    bar.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      height: 3px;
      background: linear-gradient(90deg, #3b82f6, #1d4ed8);
      z-index: 9999;
      transition: opacity 0.3s ease;
      display: none;
    `
    document.body.appendChild(bar)
    return bar
  }
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// CSRF Token for Phoenix
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// JSS-specific hooks for LiveView interactions
let Hooks = {}

// Hook for Gantt Chart interactions
Hooks.GanttChart = {
  mounted() {
    this.initializeGantt()
    this.handleResize()
  },
  
  updated() {
    this.refreshGantt()
  },
  
  initializeGantt() {
    console.log("Initializing Gantt Chart...")
    this.el.addEventListener("wheel", this.handleZoom.bind(this))
    this.el.addEventListener("click", this.handleTaskClick.bind(this))
  },
  
  refreshGantt() {
    console.log("Refreshing Gantt Chart data...")
  },
  
  handleZoom(event) {
    if (event.ctrlKey) {
      event.preventDefault()
      const zoomDirection = event.deltaY > 0 ? "out" : "in"
      this.pushEvent("zoom", {direction: zoomDirection})
    }
  },
  
  handleTaskClick(event) {
    const taskElement = event.target.closest('[data-task-id]')
    if (taskElement) {
      const taskId = taskElement.dataset.taskId
      this.pushEvent("task_selected", {task_id: taskId})
    }
  },
  
  handleResize() {
    window.addEventListener("resize", () => {
      this.pushEvent("viewport_changed", {
        width: window.innerWidth,
        height: window.innerHeight
      })
    })
  }
}

// Hook for real-time optimization monitoring
Hooks.OptimizationMonitor = {
  mounted() {
    this.startMonitoring()
  },
  
  destroyed() {
    this.stopMonitoring()
  },
  
  startMonitoring() {
    this.interval = setInterval(() => {
      this.pushEvent("refresh_status", {})
    }, 2000) // Refresh every 2 seconds
  },
  
  stopMonitoring() {
    if (this.interval) {
      clearInterval(this.interval)
    }
  }
}

// Hook for parameter management
Hooks.ParameterEditor = {
  mounted() {
    this.setupValidation()
  },
  
  setupValidation() {
    const inputs = this.el.querySelectorAll('input[data-parameter]')
    inputs.forEach(input => {
      input.addEventListener('blur', this.validateParameter.bind(this))
      input.addEventListener('input', this.debounceUpdate.bind(this))
    })
  },
  
  validateParameter(event) {
    const input = event.target
    const dataType = input.dataset.dataType
    const value = input.value
    
    if (this.isValidValue(value, dataType)) {
      input.classList.remove('border-red-500')
      input.classList.add('border-green-500')
    } else {
      input.classList.remove('border-green-500')
      input.classList.add('border-red-500')
    }
  },
  
  isValidValue(value, dataType) {
    switch(dataType) {
      case 'integer':
        return /^-?\d+$/.test(value)
      case 'float':
        return /^-?\d*\.?\d+$/.test(value)
      case 'boolean':
        return ['true', 'false'].includes(value.toLowerCase())
      default:
        return true
    }
  },
  
  debounceUpdate(event) {
    clearTimeout(this.updateTimeout)
    this.updateTimeout = setTimeout(() => {
      const input = event.target
      if (this.isValidValue(input.value, input.dataset.dataType)) {
        this.pushEvent("parameter_updated", {
          category: input.dataset.category,
          name: input.dataset.parameter,
          value: input.value
        })
      }
    }, 1000)
  }
}

// LiveSocket configuration
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Connect if there are any LiveViews on the page
liveSocket.connect()

// Expose liveSocket on window for web console debug logs and latency simulation
liveSocket.enableDebug()
window.liveSocket = liveSocket

// JSS Namespace for global functionality
window.JSS = {
  // Utility functions
  formatDuration: function(seconds) {
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const remainingSeconds = seconds % 60
    
    if (hours > 0) {
      return `${hours}h ${minutes}m ${remainingSeconds}s`
    } else if (minutes > 0) {
      return `${minutes}m ${remainingSeconds}s`
    } else {
      return `${remainingSeconds}s`
    }
  },
  
  formatMemory: function(bytes) {
    const mb = bytes / (1024 * 1024)
    return `${mb.toFixed(1)} MB`
  },
  
  // Test functions for manual debugging
  startOptimizationTest: function() {
    console.log("🚀 Starting JSS optimization test...")
    fetch('/api/optimization/start', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      body: JSON.stringify({
        machine_count: 5,
        order_count: 8,
        algorithm_timeout: 3000
      })
    })
    .then(response => response.json())
    .then(data => {
      console.log("✅ Test started:", data)
    })
    .catch(error => {
      console.error("❌ Test failed:", error)
    })
  },
  
  getSystemStatus: function() {
    fetch('/api/status')
    .then(response => response.json())
    .then(data => {
      console.log("📊 System Status:", data)
    })
    .catch(error => {
      console.error("❌ Status fetch failed:", error)
    })
  },
  
  // Gantt Chart utilities
  Gantt: {
    zoomIn: function() {
      window.dispatchEvent(new CustomEvent('gantt:zoom', {detail: {direction: 'in'}}))
    },
    
    zoomOut: function() {
      window.dispatchEvent(new CustomEvent('gantt:zoom', {detail: {direction: 'out'}}))
    },
    
    refresh: function() {
      window.dispatchEvent(new CustomEvent('gantt:refresh'))
    }
  }
}

// Keyboard shortcuts
document.addEventListener('keydown', function(event) {
  // Ctrl+R: Refresh optimization status
  if (event.ctrlKey && event.key === 'r') {
    event.preventDefault()
    JSS.getSystemStatus()
  }
  
  // Ctrl+T: Start test
  if (event.ctrlKey && event.key === 't') {
    event.preventDefault()
    JSS.startOptimizationTest()
  }
})

// Handle notification display
document.addEventListener('phx:notification', function(event) {
  const {type, message} = event.detail
  showNotification(type, message)
})

function showNotification(type, message) {
  const notification = document.createElement('div')
  notification.className = `notification fixed top-4 right-4 px-4 py-2 rounded shadow-lg z-50 transition-all duration-300 ${
    type === 'error' ? 'bg-red-100 text-red-800 border border-red-200' :
    type === 'success' ? 'bg-green-100 text-green-800 border border-green-200' :
    type === 'warning' ? 'bg-yellow-100 text-yellow-800 border border-yellow-200' :
    'bg-blue-100 text-blue-800 border border-blue-200'
  }`
  
  notification.textContent = message
  document.body.appendChild(notification)
  
  // Auto-remove after 5 seconds
  setTimeout(() => {
    notification.style.opacity = '0'
    notification.style.transform = 'translateX(100%)'
    setTimeout(() => {
      if (document.body.contains(notification)) {
        document.body.removeChild(notification)
      }
    }, 300)
  }, 5000)
}

console.log("🎉 JSS Scheduler application loaded successfully!")