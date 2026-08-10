<template>
  <div class="devices-view">
    <div class="view-header">
      <h2>Connected Devices</h2>
      <button @click="refreshDevices" :disabled="loading">
        {{ loading ? 'Loading...' : 'Refresh' }}
      </button>
    </div>

    <div v-if="loading" class="loading">
      Loading devices...
    </div>

    <div v-else-if="devices.length === 0" class="empty-state">
      <p>No devices found. Plug in an Akai controller to get started.</p>
    </div>

    <div v-else class="devices-grid">
      <DeviceCard
        v-for="device in devices"
        :key="device.id"
        :device="device"
        @launch="launchEditor"
        @initialize="initDevice"
      />
    </div>
  </div>
</template>

<script>
import { ref } from 'vue'
import DeviceCard from '../components/DeviceCard.vue'
import { fetchDevices, initializeDevice } from '../utils/api.js'

export default {
  name: 'DevicesView',
  components: {
    DeviceCard
  },
  props: {
    devices: Array,
    loading: Boolean
  },
  emits: ['refresh'],
  setup(props, { emit }) {
    const refreshDevices = () => {
      emit('refresh')
    }

    const launchEditor = (deviceId) => {
      console.log('Launch editor for:', deviceId)
      // In real implementation, would call backend or local launcher
    }

    const initDevice = async (deviceId) => {
      try {
        const result = await initializeDevice(deviceId)
        console.log('Device initialized:', result)
      } catch (error) {
        console.error('Failed to initialize device:', error)
      }
    }

    return {
      refreshDevices,
      launchEditor,
      initDevice
    }
  }
}
</script>

<style scoped>
.devices-view {
  padding: 20px;
}

.view-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 30px;
}

.view-header h2 {
  font-size: 24px;
  color: var(--accent);
  margin: 0;
}

.view-header button {
  padding: 8px 16px;
}

.loading {
  text-align: center;
  padding: 40px 20px;
  color: var(--text-secondary);
}

.empty-state {
  text-align: center;
  padding: 60px 20px;
  color: var(--text-secondary);
}

.devices-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 20px;
}

@media (max-width: 768px) {
  .devices-grid {
    grid-template-columns: 1fr;
  }
}
</style>
