# Adams Deployment

This repository now includes the in-repo deployment scaffolding for the planned
production split:

- frontend on Netlify at `https://www.<domain>`
- backend on Render at `https://api.<domain>`
- GoDaddy DNS pointing `www` to Netlify and `api` to Render

## Backend on Render

Use the root-level `render.yaml` blueprint.

Backend service shape:

- root directory: `backend/`
- build command: `npm install`
- start command: `npm start`
- health check path: `/health`

Required production env vars in Render:

- `NODE_ENV=production`
- `HOST=0.0.0.0`
- `MONGODB_URI`
- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `JWT_INVITE_SECRET`
- `JWT_CUSTOMER_REGISTRATION_SECRET`
- `CORS_ORIGIN=https://www.<domain>,https://<netlify-site>.netlify.app` during cutover
- `FRONTEND_APP_URL=https://www.<domain>`
- provider credentials for Brevo, Cloudinary, Google Address, AI, and Stripe

Recommended rollout:

1. Create the Render web service from this repository.
2. Confirm the service boots on the default `onrender.com` URL.
3. Verify `GET /health` and `GET /api/v1`.
4. Attach `api.<domain>` as the custom domain in Render.
5. Add the DNS record Render gives you in GoDaddy.
6. After TLS is active, treat `https://api.<domain>/api/v1` as the canonical production API base URL.

## Frontend on Netlify

GitHub Actions deploys the Flutter web app through
`/.github/workflows/deploy-web.yml`.

Required GitHub repository secrets:

- `NETLIFY_AUTH_TOKEN`
- `NETLIFY_SITE_ID`

Required GitHub repository variable:

- `PROD_API_BASE_URL=https://api.<domain>/api/v1`

Workflow behavior:

1. Runs on every push to `main` and on manual dispatch.
2. Installs Flutter dependencies in `frontend/`.
3. Runs `flutter analyze`.
4. Runs `flutter test`.
5. Builds the production bundle with `API_BASE_URL` injected at compile time.
6. Deploys `frontend/build/web` to Netlify.

Netlify steps:

1. Create the site in Netlify.
2. Store `NETLIFY_SITE_ID` and `NETLIFY_AUTH_TOKEN` in GitHub secrets.
3. Attach `www.<domain>` as the Netlify custom domain.
4. Keep the frontend as the canonical browser origin.

## GoDaddy DNS

Use this domain layout:

- `www` CNAME to the Netlify target
- `api` CNAME to the Render target
- apex `@` redirected to `https://www.<domain>`

Recommended order:

1. Point `www` first.
2. Point `api` second.
3. Trim `CORS_ORIGIN` down to `https://www.<domain>` after the cutover window ends.

## Smoke Tests

Backend:

- `GET /health` returns `200`
- `GET /api/v1` responds successfully
- MongoDB connects on cold boot
- Cloudinary-backed uploads work

Frontend:

- homepage loads on `https://www.<domain>`
- admin, staff, and customer login succeed
- browser refresh preserves the authenticated session
- staff invite links resolve with the current hash-route flow
- request creation, uploads, and dashboards work against `https://api.<domain>/api/v1`

## Known Limitation

Generated PDF receipts are still written to local disk under `backend/uploads`,
so Render restarts do not provide durable long-term receipt storage yet. This is
not solved by the current deployment work.
