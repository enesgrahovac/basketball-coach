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
open ShotIQ.xcodeproj

## Modal Endpoint Contract
- URL: `<modal-url>/analyze` (called by the Edge Function)
- Method: POST
- Body (JSON): `{ "clip_id": "<uuid>", "storage_key": "clips/<path>.mp4" }`

## AI Evaluation Framework

The `ai-evaluation/` directory contains a comprehensive evaluation framework for testing and comparing different models and prompts for basketball shot analysis.

### Framework Features

- **Data Synchronization**: Automatically syncs clips and analysis from Supabase
- **Ground Truth Management**: Uses user corrections as the gold standard for evaluation
- **Model Comparison**: Tests different Gemini models and prompt variations
- **Performance Metrics**: Measures accuracy, latency, cost, and reliability
- **Visualization**: Interactive charts and detailed error analysis

### Quick Start

1. **Setup Environment**:
   ```bash
   cd ai-evaluation
   pip install -r requirements.txt
   ```

2. **Configure Credentials**: Ensure your `.env` file contains:
   ```
   SUPABASE_URL=your_supabase_url
   SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
   GEMINI_API_KEY=your_gemini_api_key
   ```

3. **Sync Data** (run once or when you have new data):
   ```bash
   jupyter notebook notebooks/1_data_sync.ipynb
   ```

4. **Run Evaluations**:
   ```bash
   jupyter notebook notebooks/2_model_comparison.ipynb
   ```

### Evaluation Metrics

- **Accuracy**: Shot type and make/miss classification accuracy
- **Latency**: Average inference time per video
- **Cost**: Estimated API costs per sample
- **Reliability**: JSON parsing success rate and error analysis
- **Ground Truth**: Uses user-corrected analysis from `analysis_overrides` table

### Directory Structure

```
ai-evaluation/
├── data/                    # Excluded from git
│   ├── videos/             # Downloaded video files
│   ├── ground_truth.json  # Processed ground truth dataset
│   └── model_outputs/      # Evaluation results by model
├── notebooks/
│   ├── 1_data_sync.ipynb          # Data synchronization
│   └── 2_model_comparison.ipynb   # Model evaluation & comparison
├── src/
│   ├── data_manager.py     # Supabase integration
│   ├── evaluator.py        # Model evaluation logic
│   └── metrics.py          # Performance metrics & visualization
├── configs/
│   ├── models.yaml         # Model configurations
│   └── prompts.yaml        # Prompt variations
└── requirements.txt        # Python dependencies
```

### Adding New Models

1. Add model configuration to `configs/models.yaml`
2. Update the evaluator if needed for new API endpoints
3. Run evaluation notebook to test performance

### Adding New Prompts

1. Add prompt variation to `configs/prompts.yaml`
2. Run evaluation notebook to compare performance
3. Analyze results for accuracy and reliability improvements

## Notes
- The app uses a hybrid polling flow (1s for ~10s, then 2s) to detect completion.
- For production, you can switch to Realtime subscriptions or keep the hybrid approach.
- The evaluation framework helps optimize model selection and prompt engineering for better accuracy and cost-effectiveness.
