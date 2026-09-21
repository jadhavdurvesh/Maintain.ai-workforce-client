# Maintain.ai Workforce Client Contract

The Workforce client is the technician-facing client for Maintain.ai.

## Authority

The Maintain.ai backend is authoritative for:
- technician identity
- organization membership
- assigned-machine scope
- work-order permissions
- fault/alert visibility
- telemetry visibility
- notifications

The client must never treat its local machine list as an authorization boundary.

## Application context

Authenticated API requests use:

`Authorization: Bearer <Supabase access token>`

and:

`X-Maintain-Application: workforce`

Notification and realtime authorization requests must preserve this application context.

## Authentication flow

1. Authenticate with Supabase.
2. Store the access token.
3. Call `POST /api/auth/supabase/sync`.
4. Call `GET /api/auth/me`.
5. Render the returned workforce identity and assigned scope.
6. Let every backend endpoint enforce the actual permission.

## Realtime

The client requests a backend-issued realtime token from:

`POST /api/auth/realtime-token`

It loads the backend-authorized machine list and joins only machine-scoped telemetry channels (`machine:<id>:telemetry`). Supabase RLS also validates the machine IDs carried in the backend-issued Realtime JWT; Flutter filtering is only a UX optimization.

## Configuration

Use:

- `MAINTAIN_API_URL`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Do not hard-code a deployment hostname in individual services.

## Notifications

Notification registration, listing, read, and device removal requests use the authenticated workforce token and:

`X-Maintain-Application: workforce`

## Do not add

Do not add organization IDs to local authorization logic, bypass assigned-machine checks, use engineering credentials, or create a second permission model in Flutter.
