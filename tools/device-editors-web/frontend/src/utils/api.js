const API_BASE = 'http://localhost:8000/api'
const WS_BASE = 'ws://localhost:8000'

export async function fetchDevices() {
  try {
    const response = await fetch(`${API_BASE}/devices`)
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return await response.json()
  } catch (error) {
    console.error('fetchDevices error:', error)
    throw error
  }
}

export async function fetchMidiPorts() {
  try {
    const response = await fetch(`${API_BASE}/midi/ports`)
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return await response.json()
  } catch (error) {
    console.error('fetchMidiPorts error:', error)
    throw error
  }
}

export async function initializeDevice(deviceId) {
  try {
    const response = await fetch(`${API_BASE}/devices/${deviceId}/init`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return await response.json()
  } catch (error) {
    console.error('initializeDevice error:', error)
    throw error
  }
}

export async function fetchPresets() {
  try {
    const response = await fetch(`${API_BASE}/presets`)
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return await response.json()
  } catch (error) {
    console.error('fetchPresets error:', error)
    throw error
  }
}

export async function savePreset(presetData) {
  try {
    const response = await fetch(`${API_BASE}/presets`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(presetData)
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return await response.json()
  } catch (error) {
    console.error('savePreset error:', error)
    throw error
  }
}

export function setupWebSocket(onMessage, onDisconnect) {
  const ws = new WebSocket(`${WS_BASE}/ws/monitoring`)

  ws.addEventListener('open', () => {
    console.log('WebSocket connected')
  })

  ws.addEventListener('message', (event) => {
    try {
      const data = JSON.parse(event.data)
      onMessage(data)
    } catch (error) {
      console.error('WebSocket parse error:', error)
    }
  })

  ws.addEventListener('close', () => {
    console.log('WebSocket disconnected')
    if (onDisconnect) onDisconnect()
  })

  ws.addEventListener('error', (error) => {
    console.error('WebSocket error:', error)
    if (onDisconnect) onDisconnect()
  })

  return ws
}
