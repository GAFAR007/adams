# Adams Manual Redeploy

Use this when GitHub Actions is unavailable and you need the latest local
changes live in production.

## Frontend

Current production frontend:

- Netlify site: `whimsical-semolina-ee6bd6`
- Production URL: `https://clfacilitymanagement.gafarstechnologies.com`

Current production API base URL to build against:

- `https://clfacilitymanagement-backend.onrender.com/api/v1`

Manual frontend redeploy:

```bash
cd /Users/gafar/Documents/Documents/myPlayGround/adams/frontend

flutter pub get
flutter analyze
flutter test
flutter build web --release --dart-define=API_BASE_URL=https://clfacilitymanagement-backend.onrender.com/api/v1

netlify deploy --dir=build/web --prod
```

If Netlify says the folder is not linked:

```bash
cd /Users/gafar/Documents/Documents/myPlayGround/adams/frontend
netlify link
netlify deploy --dir=build/web --prod
```

Choose the existing project:

- `whimsical-semolina-ee6bd6`

## Backend

Current production backend:

- Render service: `clfacilitymanagement-backend`
- Temporary live API URL in use by the frontend:
  `https://clfacilitymanagement-backend.onrender.com/api/v1`

To get backend code changes live, Render must deploy a commit that contains the
changes. If your Render service is connected to GitHub auto-deploy on `main`,
push the changes to `main` and let Render redeploy.

Basic publish flow:

```bash
cd /Users/gafar/Documents/Documents/myPlayGround/adams

git add backend/src/services/auth.service.js \
  frontend/lib/app/features/auth/data/auth_repository.dart \
  frontend/lib/app/features/auth/presentation/role_login_screen.dart \
  AGEM.md

git commit -m "Enable email-only quick fill accounts across roles"
git push origin HEAD:main
```

If you do not want to push from terminal, use the Render dashboard after your
changes are on `main`.

## When The Custom API Domain Is Ready

After this works without TLS errors:

- `https://api.clfacilitymanagement.gafarstechnologies.com/health`

switch the frontend build target from the Render default URL to:

- `https://api.clfacilitymanagement.gafarstechnologies.com/api/v1`

Then redeploy the frontend again.
