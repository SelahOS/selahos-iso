<template>
  <div class="app-container">
    <header class="app-header">
      <div class="header-content">
        <div class="logo">
          <h1>SELAH</h1>
          <p>Device Bridge</p>
        </div>
        <div class="header-status">
          <span :class="['status-indicator', apiConnected ? 'connected' : 'disconnected']">
            ● {{ apiConnected ? 'Connected' : 'Offline' }}
          </span>
        </div>
      </div>
    </header>

    <div class="app-content">
      <nav class="sidebar">
        <ul class="nav-menu">
          <li><a href="#" @click.prevent="currentView = 'devices'" :class="{ active: currentView === 'devices' }">Devices</a></li>
          <li><a href="#" @click.prevent="currentView = 'midi'" :class="{ active: currentView === 'midi' }">MIDI Ports</a></li>
          <li><a href="#" @click.prevent="currentView = 'settings'" :class="{ active: currentView === 'settings' }">Settings</a></li>
          <li><a href="#" @click.prevent="currentView = 'logs'" :class="{ active: currentView === 'logs' }">Logs</a></li>
        </ul>
      </nav>

      <main class="main-content">
        <DevicesView v-if="currentView === 'devices'" :devices="devices" :loading="loading" />
        <MidiView v-if="currentView === 'midi'" :ports="midiPorts" />
        <SettingsView v-if="currentView === 'settings'" />
        <LogsView v-if="currentView === 'logs'" />
      </main>
    </div>

    <footer class="app-footer">
      <p>SelahOS Device Bridge v1.0.0</p>
    </footer>
  </div>
</template>

<script>
import { ref, onMounted, onUnmounted } from 'vue'
import DevicesView from './views/DevicesView.vue'
import MidiView from './views/MidiView.vue'
import SettingsView from './views/SettingsView.vue'
import LogsView from './views/LogsView.vue'
import { fetchDevices, fetchMidiPorts, setupWebSocket } from './utils/api.js'

export default {
  name: 'App',
  components: {
    DevicesView,
    MidiView,
    SettingsView,
    LogsView
  },
  setup() {
    const currentView = ref('devices')
    const devices = ref([])
    const midiPorts = ref({ input_ports: [], output_ports: [] })
    const loading = ref(false)
    const apiConnected = ref(false)
    let ws = null

    const loadDevices = async () => {
      loading.value = true
      try {
        const data = await fetchDevices()
        devices.value = data.devices
        apiConnected.value = true
      } catch (error) {
        console.error('Failed to fetch devices:', error)
        apiConnected.value = false
      } finally {
        loading.value = false
      }
    }

    const loadMidiPorts = async () => {
      try {
        midiPorts.value = await fetchMidiPorts()
      } catch (error) {
        console.error('Failed to fetch MIDI ports:', error)
      }
    }

    onMounted(async () => {
      await loadDevices()
      await loadMidiPorts()

      ws = setupWebSocket((data) => {
        if (data.type === 'device_status' && data.devices) {
          devices.value = data.devices.devices
          apiConnected.value = true
        }
      }, () => {
        apiConnected.value = false
      })

      // Refresh data every 5 seconds
      setInterval(() => {
        loadDevices()
        loadMidiPorts()
      }, 5000)
    })

    onUnmounted(() => {
      if (ws) ws.close()
    })

    return {
      currentView,
      devices,
      midiPorts,
      loading,
      apiConnected
    }
  }
}
</script>

<style scoped>
.app-container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background-color: var(--primary);
}

.app-header {
  background-color: var(--primary);
  border-bottom: 2px solid var(--accent);
  padding: 20px;
}

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  max-width: 1400px;
  margin: 0 auto;
}

.logo h1 {
  font-size: 28px;
  font-weight: bold;
  color: var(--accent);
  margin: 0;
}

.logo p {
  font-size: 12px;
  color: var(--text-secondary);
  margin: 2px 0 0 0;
}

.header-status {
  display: flex;
  align-items: center;
}

.status-indicator {
  font-weight: bold;
  padding: 6px 12px;
  border-radius: 4px;
  font-size: 14px;
}

.status-indicator.connected {
  color: var(--success);
}

.status-indicator.disconnected {
  color: var(--danger);
}

.app-content {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.sidebar {
  width: 200px;
  background-color: var(--secondary);
  border-right: 2px solid var(--accent);
  padding: 20px 0;
  overflow-y: auto;
}

.nav-menu {
  list-style: none;
}

.nav-menu li a {
  display: block;
  padding: 12px 20px;
  color: var(--text-primary);
  border-left: 3px solid transparent;
  transition: all 0.2s;
}

.nav-menu li a:hover {
  background-color: var(--primary);
  border-left-color: var(--accent);
  text-decoration: none;
}

.nav-menu li a.active {
  background-color: var(--primary);
  border-left-color: var(--accent);
  color: var(--accent);
  font-weight: bold;
}

.main-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

.app-footer {
  background-color: var(--secondary);
  border-top: 2px solid var(--accent);
  padding: 15px 20px;
  text-align: center;
  font-size: 12px;
  color: var(--text-secondary);
}
</style>
