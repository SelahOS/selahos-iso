<template>
  <div class="device-card" :class="{ connected: device.connected, disconnected: !device.connected }">
    <div class="card-header">
      <h3>{{ device.name }}</h3>
      <span :class="['status-badge', device.connected ? 'connected' : 'disconnected']">
        {{ device.connected ? '● Connected' : '● Disconnected' }}
      </span>
    </div>

    <div class="card-content">
      <div class="device-info">
        <p><strong>VID:PID:</strong> {{ device.usb_vid }}:{{ device.usb_pid }}</p>
        <p><strong>Controls:</strong> {{ device.controls }}</p>
      </div>

      <div class="card-actions">
        <button
          @click="$emit('launch', device.id)"
          :disabled="!device.connected"
          class="btn-launch"
        >
          Launch Editor
        </button>
        <button
          @click="$emit('initialize', device.id)"
          :disabled="!device.connected"
          class="btn-init"
        >
          Initialize
        </button>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'DeviceCard',
  props: {
    device: {
      type: Object,
      required: true
    }
  },
  emits: ['launch', 'initialize']
}
</script>

<style scoped>
.device-card {
  background-color: var(--secondary);
  border: 2px solid var(--accent);
  border-radius: 8px;
  overflow: hidden;
  transition: all 0.2s;
  display: flex;
  flex-direction: column;
}

.device-card.connected {
  box-shadow: 0 0 15px rgba(68, 255, 68, 0.2);
}

.device-card.disconnected {
  opacity: 0.6;
  box-shadow: 0 0 15px rgba(255, 68, 68, 0.1);
}

.device-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 20px rgba(212, 175, 55, 0.3);
}

.card-header {
  background-color: var(--primary);
  padding: 15px;
  border-bottom: 1px solid var(--accent);
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.card-header h3 {
  margin: 0;
  font-size: 18px;
  color: var(--accent);
}

.status-badge {
  font-size: 12px;
  font-weight: bold;
  padding: 4px 8px;
  border-radius: 4px;
}

.status-badge.connected {
  color: #44ff44;
}

.status-badge.disconnected {
  color: #ff4444;
}

.card-content {
  padding: 15px;
  flex: 1;
  display: flex;
  flex-direction: column;
}

.device-info {
  flex: 1;
  margin-bottom: 15px;
}

.device-info p {
  margin: 6px 0;
  font-size: 13px;
  color: var(--text-secondary);
}

.device-info strong {
  color: var(--text-primary);
}

.card-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.card-actions button {
  padding: 8px 12px;
  font-size: 12px;
  font-weight: bold;
  border-radius: 4px;
  transition: all 0.2s;
}

.btn-launch {
  background-color: var(--accent);
  color: var(--primary);
  border-color: var(--accent);
}

.btn-launch:hover:not(:disabled) {
  background-color: #e5c158;
}

.btn-init {
  background-color: transparent;
  color: var(--accent);
  border-color: var(--accent);
}

.btn-init:hover:not(:disabled) {
  background-color: var(--accent);
  color: var(--primary);
}

button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
