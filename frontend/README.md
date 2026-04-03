# frontend

Flutter frontend for Adams.

## Push To Deploy

Pushes to `main` deploy the web app to Netlify through GitHub Actions in
`/.github/workflows/deploy-web.yml`.

Required GitHub repository secrets:

- `NETLIFY_AUTH_TOKEN`
- `NETLIFY_SITE_ID`

Required GitHub repository variable:

- `PROD_API_BASE_URL`

Deployment flow:

1. GitHub Actions runs on every push to `main`.
2. The workflow installs Flutter dependencies inside `frontend/`.
3. It runs `flutter analyze` and `flutter test`.
4. It builds the production web bundle with:
   `flutter build web --release --dart-define=API_BASE_URL=$PROD_API_BASE_URL`
5. It deploys `frontend/build/web` to Netlify.

Production expectation:

- Netlify serves the frontend on `https://www.<domain>`.
- Render serves the backend on `https://api.<domain>`.
- `PROD_API_BASE_URL` should therefore be set to
  `https://api.<domain>/api/v1`.
