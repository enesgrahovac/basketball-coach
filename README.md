# Basketball Coach – MVP (Option A: Supabase + Modal)

Minimal system to upload ≤30s clips from iOS, analyze with a Python worker (Modal + Gemini), and store results in Supabase (Postgres + Storage).

## Components
- Supabase: Postgres, Storage, Auth (later).
- Modal: Python worker with a web endpoint to run analysis.
- iOS app: Native SwiftUI app.

## Folder Structure
- `python-worker/`: Modal worker app and dependencies.
- `supabase/`: Database schema, Edge Function (`functions/analyze`).
- `ios/`: SwiftUI app.
- `.env.example`: Required environment variables (copy to `.env` and fill in).

## Setup

### 1) Supabase (DB + Storage)
1. Create a new Supabase project.
2. In the SQL editor, run `supabase/schema.sql` to create tables.
3. Create a Storage bucket named `clips` (private).

### 2) Modal (Python worker)
1. Install Modal CLI: `pip install modal` and `modal setup`
2. Copy `.env.example` to `.env` and fill values.
3. Set secrets in Modal (one-time):
   ```bash
   modal secret create basketball-coach-secrets \
     SUPABASE_URL=$(grep ^SUPABASE_URL .env | cut -d= -f2-) \
     SUPABASE_SERVICE_ROLE_KEY=$(grep ^SUPABASE_SERVICE_ROLE_KEY .env | cut -d= -f2-) \
     SUPABASE_STORAGE_BUCKET=$(grep ^SUPABASE_STORAGE_BUCKET .env | cut -d= -f2-) \
     GEMINI_API_KEY=$(grep ^GEMINI_API_KEY .env | cut -d= -f2-) \
     WORKER_AUTH_TOKEN=$(grep ^WORKER_AUTH_TOKEN .env | cut -d= -f2-)
   ```
4. Deploy the worker:
   ```bash
   uvx -p 3.11 --with-requirements python-worker/requirements.txt modal deploy python-worker/modal_app.py
   ```
   Copy the URL printed for the `analyze` endpoint as `MODAL_ANALYZE_URL`.

### 3) Supabase Edge Function (proxy to worker)
Set secrets and deploy:
```bash
supabase functions secrets set MODAL_ANALYZE_URL="<your modal analyze url>"
supabase functions secrets set WORKER_AUTH_TOKEN="$(grep ^WORKER_AUTH_TOKEN .env | cut -d= -f2-)"
# deploy
supabase functions deploy analyze
# find URL
supabase functions list | grep analyze
```
Use the `analyze` function URL as `EDGE_ANALYZE_URL` in iOS.

### 4) iOS App Configuration
Before opening the iOS project, you need to set up your API keys securely:

1. **Copy the configuration template:**
   ```bash
   cd ios
   cp Config-Development.xcconfig.example Config-Development.xcconfig
   ```

2. **Fill in your actual API keys in `Config-Development.xcconfig`:**
   ```
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your_actual_supabase_anon_key
   EDGE_ANALYZE_URL=https://your-project-id.supabase.co/functions/v1/analyze
   ```

3. **Open and build the project:**
   - Open Xcode → Open `ios/` as a project folder
   - Ensure `Info.plist` contains the camera and photo permission strings
   - Run on a device/simulator. Tap "Upload a video", pick a short mp4, and follow on-screen statuses

**Security Note:** The `Config-Development.xcconfig` file contains sensitive API keys and is excluded from version control. Never commit this file to git.

To run it from CLI:
xcodegen generate
open BasketballCoach.xcodeproj

## Modal Endpoint Contract
- URL: `<modal-url>/analyze` (called by the Edge Function)
- Method: POST
- Body (JSON): `{ "clip_id": "<uuid>", "storage_key": "clips/<path>.mp4" }`

## Notes
- The app uses a hybrid polling flow (1s for ~10s, then 2s) to detect completion.
- For production, you can switch to Realtime subscriptions or keep the hybrid approach.
