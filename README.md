# Industrial Workforce Client

Cross-platform Flutter worker/technician client for the industrial maintenance platform.

## Current version

Authentication is intentionally **not implemented yet**. This client is functional without login and is designed to connect to the shared FastAPI backend.

### Worker features
- Dashboard with assigned-machine health overview
- Machine list with health, code, location, department and operating information
- Read-only machine details
- Work-order list
- Acknowledge pending work orders
- Resolve in-progress work orders with required resolution notes
- Work-order priority and status indicators
- Alerts screen
- Backend refresh every 10 seconds
- Manual refresh
- Graceful fallback when the backend is temporarily unavailable
- Android and iOS builds through GitHub Actions

### Current API integration
Default backend: `https://maintain-ai-3.vercel.app`

Endpoints currently used:
- `GET /api/machines`
- `GET /api/work-orders`
- `GET /api/alerts`
- `PATCH /api/work-orders/{id}`

The app currently displays the backend's available data because authentication and worker-specific machine authorization have not yet been added to the main backend.

### Deferred until backend authentication is ready
- Worker login/session
- Organization/company isolation
- Role-based permissions
- Machine assignment enforcement
- User-specific notification registration
- Push notifications
- WebSocket live events

These will be added after the main platform authentication model is finalized.
