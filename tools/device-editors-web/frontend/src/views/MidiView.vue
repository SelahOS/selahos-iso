<template>
  <div class="midi-view">
    <div class="view-header">
      <h2>MIDI Ports</h2>
    </div>

    <div class="midi-container">
      <div class="midi-section">
        <h3>Input Ports</h3>
        <div v-if="ports.input_ports.length === 0" class="empty">
          No MIDI input ports available
        </div>
        <div v-else class="ports-list">
          <div v-for="(port, index) in ports.input_ports" :key="`in-${index}`" class="port-item">
            <span class="port-icon">↓</span>
            <span class="port-name">{{ port }}</span>
          </div>
        </div>
      </div>

      <div class="midi-section">
        <h3>Output Ports</h3>
        <div v-if="ports.output_ports.length === 0" class="empty">
          No MIDI output ports available
        </div>
        <div v-else class="ports-list">
          <div v-for="(port, index) in ports.output_ports" :key="`out-${index}`" class="port-item">
            <span class="port-icon">↑</span>
            <span class="port-name">{{ port }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'MidiView',
  props: {
    ports: {
      type: Object,
      default: () => ({ input_ports: [], output_ports: [] })
    }
  }
}
</script>

<style scoped>
.midi-view {
  padding: 20px;
}

.view-header {
  margin-bottom: 30px;
}

.view-header h2 {
  font-size: 24px;
  color: var(--accent);
  margin: 0;
}

.midi-container {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
}

.midi-section {
  background-color: var(--secondary);
  border: 2px solid var(--accent);
  border-radius: 8px;
  padding: 20px;
}

.midi-section h3 {
  color: var(--accent);
  margin: 0 0 15px 0;
  font-size: 16px;
}

.empty {
  color: var(--text-secondary);
  text-align: center;
  padding: 30px 0;
}

.ports-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.port-item {
  display: flex;
  align-items: center;
  padding: 10px 12px;
  background-color: var(--primary);
  border: 1px solid var(--accent);
  border-radius: 4px;
  gap: 12px;
}

.port-icon {
  color: var(--accent);
  font-weight: bold;
  font-size: 16px;
}

.port-name {
  color: var(--text-primary);
  font-size: 13px;
  flex: 1;
  word-break: break-all;
}

@media (max-width: 768px) {
  .midi-container {
    grid-template-columns: 1fr;
  }
}
</style>
