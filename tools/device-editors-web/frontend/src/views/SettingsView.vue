<template>
  <div class="settings-view">
    <div class="view-header">
      <h2>Settings</h2>
    </div>

    <div class="settings-container">
      <div class="settings-section">
        <h3>API Configuration</h3>
        <div class="setting-item">
          <label>API Host</label>
          <input v-model="settings.apiHost" type="text" placeholder="localhost:8000">
        </div>
        <div class="setting-item">
          <label>Auto-refresh Interval (ms)</label>
          <input v-model.number="settings.refreshInterval" type="number" min="1000" max="60000" step="1000">
        </div>
      </div>

      <div class="settings-section">
        <h3>Display</h3>
        <div class="setting-item">
          <label>
            <input v-model="settings.compactMode" type="checkbox">
            Compact Mode
          </label>
        </div>
        <div class="setting-item">
          <label>
            <input v-model="settings.darkMode" type="checkbox" disabled>
            Dark Mode (Always On)
          </label>
        </div>
      </div>

      <div class="settings-section">
        <h3>Device Bridge</h3>
        <div class="setting-item">
          <label>Default MIDI Input</label>
          <select v-model="settings.defaultMidiInput">
            <option value="">Auto-detect</option>
            <option v-for="port in midiPorts.input_ports" :key="port" :value="port">
              {{ port }}
            </option>
          </select>
        </div>
        <div class="setting-item">
          <label>Default MIDI Output</label>
          <select v-model="settings.defaultMidiOutput">
            <option value="">Auto-detect</option>
            <option v-for="port in midiPorts.output_ports" :key="port" :value="port">
              {{ port }}
            </option>
          </select>
        </div>
      </div>

      <div class="settings-actions">
        <button @click="saveSettings" class="btn-primary">Save Settings</button>
        <button @click="resetSettings" class="btn-secondary">Reset to Defaults</button>
      </div>
    </div>
  </div>
</template>

<script>
import { ref } from 'vue'

const DEFAULT_SETTINGS = {
  apiHost: 'localhost:8000',
  refreshInterval: 5000,
  compactMode: false,
  darkMode: true,
  defaultMidiInput: '',
  defaultMidiOutput: ''
}

export default {
  name: 'SettingsView',
  props: {
    midiPorts: {
      type: Object,
      default: () => ({ input_ports: [], output_ports: [] })
    }
  },
  setup() {
    const settings = ref({ ...DEFAULT_SETTINGS })

    const loadSettings = () => {
      const saved = localStorage.getItem('selahos-settings')
      if (saved) {
        settings.value = { ...DEFAULT_SETTINGS, ...JSON.parse(saved) }
      }
    }

    const saveSettings = () => {
      localStorage.setItem('selahos-settings', JSON.stringify(settings.value))
      alert('Settings saved successfully!')
    }

    const resetSettings = () => {
      if (confirm('Reset all settings to defaults?')) {
        settings.value = { ...DEFAULT_SETTINGS }
        localStorage.removeItem('selahos-settings')
      }
    }

    loadSettings()

    return {
      settings,
      saveSettings,
      resetSettings
    }
  }
}
</script>

<style scoped>
.settings-view {
  padding: 20px;
  max-width: 800px;
}

.view-header {
  margin-bottom: 30px;
}

.view-header h2 {
  font-size: 24px;
  color: var(--accent);
  margin: 0;
}

.settings-container {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.settings-section {
  background-color: var(--secondary);
  border: 2px solid var(--accent);
  border-radius: 8px;
  padding: 20px;
}

.settings-section h3 {
  color: var(--accent);
  margin: 0 0 15px 0;
  font-size: 16px;
}

.setting-item {
  margin-bottom: 15px;
}

.setting-item:last-child {
  margin-bottom: 0;
}

.setting-item label {
  display: block;
  margin-bottom: 6px;
  font-weight: bold;
  color: var(--text-primary);
  font-size: 14px;
}

.setting-item input[type="checkbox"] {
  margin-right: 8px;
  cursor: pointer;
}

.setting-item input[type="text"],
.setting-item input[type="number"],
.setting-item select {
  width: 100%;
  padding: 8px 12px;
  border: 1px solid var(--accent);
}

.settings-actions {
  display: flex;
  gap: 10px;
  margin-top: 20px;
}

.btn-primary,
.btn-secondary {
  padding: 10px 20px;
  border-radius: 4px;
  font-weight: bold;
  border: none;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-primary {
  background-color: var(--accent);
  color: var(--primary);
}

.btn-primary:hover {
  background-color: #e5c158;
}

.btn-secondary {
  background-color: transparent;
  color: var(--accent);
  border: 2px solid var(--accent);
}

.btn-secondary:hover {
  background-color: var(--accent);
  color: var(--primary);
}
</style>
