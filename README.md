# Industrial Workforce Client

Cross-platform Flutter worker/technician client for the industrial maintenance platform.

## Current version

Authentication is implemented through Supabase Auth and the shared Maintain.ai FastAPI backend. The backend is authoritative for organization, role, and assigned-machine authorization.

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
Default backend is configurable with `MAINTAIN_API_URL`.

Endpoints currently used:
- `GET /api/machines`
- `GET /api/work-orders`
- `GET /api/alerts`
- `PATCH /api/work-orders/{id}`

The app displays only data authorized by the shared Maintain.ai backend. Technician machine assignment is enforced server-side.

### Backend-authoritative security
- Organization/company isolation
- Role-based permissions
- Machine assignment enforcement
- User-specific notification registration
- Push notifications
- WebSocket live events

These will be added after the main platform authentication model is finalized.
