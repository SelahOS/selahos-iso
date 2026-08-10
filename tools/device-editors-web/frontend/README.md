# SelahOS Device Bridge Web Interface

Vue.js 3 frontend for the SelahOS Device Bridge FastAPI backend.

## Features

- **Device Management**: View connected Akai Professional controllers
- **Real-time Status**: Live USB device detection and connection status
- **MIDI Ports**: Browse all available MIDI input/output ports
- **Settings**: Configure API host, refresh intervals, MIDI routing
- **System Logs**: Monitor bridge activity and debug issues
- **WebSocket Monitoring**: Real-time device status updates via WebSocket

## Tech Stack

- **Vue 3** - Progressive JavaScript framework
- **Vite** - Next-generation build tool
- **Axios** - HTTP client (for API requests)
- **Chart.js** - Data visualization (for future analytics)

## Development Setup

### Prerequisites

- Node.js 16+ and npm
- Python 3.8+ with FastAPI backend running on `localhost:8000`

### Installation

```bash
cd frontend
npm install
```

### Development Server

```bash
npm run dev
```

The app will be available at `http://localhost:5173` with hot-reload enabled.

The dev server automatically proxies API requests to `http://localhost:8000/api`.

### Building for Production

```bash
npm run build
```

Build output goes to `dist/` directory. This can be served by the FastAPI backend.

## Project Structure

```
frontend/
├── src/
│   ├── components/          # Reusable Vue components
│   │   └── DeviceCard.vue  # Device display card
│   ├── views/              # Page views
│   │   ├── DevicesView.vue    # Device list
│   │   ├── MidiView.vue       # MIDI ports
│   │   ├── SettingsView.vue   # Configuration
│   │   └── LogsView.vue       # System logs
│   ├── utils/              # Utility functions
│   │   └── api.js         # API & WebSocket communication
│   ├── App.vue            # Root component
│   └── main.js            # Entry point
├── index.html             # HTML template
├── vite.config.js         # Vite configuration
└── package.json           # Dependencies
```

## API Integration

The frontend communicates with the FastAPI backend through:

### REST API Endpoints
- `GET /api/devices` - List connected devices
- `GET /api/midi/ports` - Get MIDI ports
- `POST /api/devices/{id}/init` - Initialize device
- `GET /api/presets` - List presets
- `POST /api/presets` - Save preset

### WebSocket
- `WS /ws/monitoring` - Real-time device status updates

## Configuration

Settings are persisted in browser localStorage:

```javascript
{
  apiHost: "localhost:8000",
  refreshInterval: 5000,
  compactMode: false,
  darkMode: true,
  defaultMidiInput: "",
  defaultMidiOutput: ""
}
```

## Styling

The UI uses CSS custom properties for theming:

```css
--primary: #1e1e1e;       /* Dark background */
--secondary: #2a2a2a;     /* Lighter background */
--accent: #D4AF37;        /* Gold accent */
--success: #44ff44;       /* Connected status */
--danger: #ff4444;        /* Disconnected status */
--text-primary: #ffffff;  /* Main text */
--text-secondary: #888888;/* Secondary text */
```

## Performance Optimization

- Component-level code splitting via Vite
- Lazy loading of views
- WebSocket for efficient real-time updates
- Minimal API polling (5s intervals)

## Browser Support

- Chrome/Chromium 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Deployment

1. Build the frontend:
   ```bash
   npm run build
   ```

2. Copy dist/ to the backend static directory (or use FastAPI to serve it)

3. Backend will serve the frontend at `http://localhost:8000/`

## Development Notes

- Hot reload is enabled in dev mode
- API proxying handles CORS automatically
- WebSocket proxying works in dev mode
- Production build includes source maps for debugging

## Future Enhancements

- [ ] Device presets UI
- [ ] MIDI learning/mapping
- [ ] Analytics dashboard
- [ ] Dark/light theme toggle
- [ ] Mobile responsive improvements
- [ ] Keyboard shortcuts
