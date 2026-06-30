<template>
  <div class="logs-view">
    <div class="view-header">
      <h2>System Logs</h2>
      <div class="log-controls">
        <select v-model="selectedLevel" class="level-filter">
          <option value="">All Levels</option>
          <option value="ERROR">Errors</option>
          <option value="WARNING">Warnings</option>
          <option value="INFO">Info</option>
          <option value="DEBUG">Debug</option>
        </select>
        <button @click="clearLogs">Clear Logs</button>
      </div>
    </div>

    <div class="logs-container">
      <div v-if="filteredLogs.length === 0" class="empty">
        No logs available
      </div>
      <div v-else class="logs-list">
        <div v-for="(log, index) in filteredLogs" :key="index" :class="['log-entry', log.level.toLowerCase()]">
          <span class="log-timestamp">{{ formatTime(log.timestamp) }}</span>
          <span class="log-level">{{ log.level }}</span>
          <span class="log-message">{{ log.message }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import { ref, computed, onMounted } from 'vue'

export default {
  name: 'LogsView',
  setup() {
    const logs = ref([
      { timestamp: new Date(), level: 'INFO', message: 'SelahOS Device Bridge started' },
      { timestamp: new Date(Date.now() - 5000), level: 'INFO', message: 'API server listening on 0.0.0.0:8000' },
      { timestamp: new Date(Date.now() - 10000), level: 'INFO', message: 'WebSocket monitoring endpoint ready' }
    ])
    const selectedLevel = ref('')

    const filteredLogs = computed(() => {
      if (!selectedLevel.value) return logs.value
      return logs.value.filter(log => log.level === selectedLevel.value)
    })

    const formatTime = (date) => {
      return date.toLocaleTimeString()
    }

    const clearLogs = () => {
      if (confirm('Clear all logs?')) {
        logs.value = []
      }
    }

    return {
      logs,
      selectedLevel,
      filteredLogs,
      formatTime,
      clearLogs
    }
  }
}
</script>

<style scoped>
.logs-view {
  padding: 20px;
}

.view-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

.view-header h2 {
  font-size: 24px;
  color: var(--accent);
  margin: 0;
}

.log-controls {
  display: flex;
  gap: 10px;
}

.level-filter {
  padding: 6px 12px;
  border-radius: 4px;
  border: 1px solid var(--accent);
  background-color: var(--secondary);
  color: var(--text-primary);
}

.log-controls button {
  padding: 6px 12px;
  font-size: 12px;
}

.logs-container {
  background-color: var(--secondary);
  border: 2px solid var(--accent);
  border-radius: 8px;
  height: 500px;
  overflow-y: auto;
  font-family: 'Monaco', 'Courier New', monospace;
  font-size: 12px;
}

.empty {
  color: var(--text-secondary);
  text-align: center;
  padding: 200px 20px;
}

.logs-list {
  padding: 10px;
}

.log-entry {
  padding: 6px 8px;
  margin: 2px 0;
  border-radius: 3px;
  display: flex;
  gap: 10px;
  align-items: center;
}

.log-timestamp {
  color: var(--text-secondary);
  min-width: 80px;
}

.log-level {
  font-weight: bold;
  min-width: 60px;
  text-align: center;
  padding: 2px 6px;
  border-radius: 3px;
}

.log-message {
  flex: 1;
  color: var(--text-primary);
}

.log-entry.error {
  background-color: rgba(255, 68, 68, 0.1);
  color: #ff4444;
}

.log-entry.error .log-level {
  background-color: #ff4444;
  color: white;
}

.log-entry.warning {
  background-color: rgba(255, 200, 0, 0.1);
  color: #ffc800;
}

.log-entry.warning .log-level {
  background-color: #ffc800;
  color: var(--primary);
}

.log-entry.info {
  background-color: rgba(68, 255, 68, 0.05);
  color: var(--text-primary);
}

.log-entry.info .log-level {
  background-color: #44ff44;
  color: var(--primary);
}

.log-entry.debug {
  background-color: rgba(212, 175, 55, 0.05);
  color: var(--text-secondary);
}

.log-entry.debug .log-level {
  background-color: var(--accent);
  color: var(--primary);
}
</style>
