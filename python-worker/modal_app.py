from __future__ import annotations
import json, os, time
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from modal import App, Image, Secret, fastapi_endpoint
from pydantic import BaseModel
from fastapi import HTTPException
import requests
# Import Google AI libraries inside function
from google import genai
from google.genai import types
APP_NAME = "basketball-coach-worker"
FRAMES_PER_SECOND = 24
GEMINI_MODEL = "models/gemini-2.5-flash-lite"
# GEMINI_MODEL = "models/gemini-2.5-pro"

image = (
    Image.debian_slim()
    .pip_install(
        "google-genai==1.34.0",
        "requests==2.32.3",
        "fastapi",
        "pydantic",
        "supabase>=2.7.0",
    )
)
app = App(APP_NAME)



class AnalyzeBody(BaseModel):
    # auth is in the body per your comment
    x_worker_auth: Optional[str] = None
    clip_id: str
    storage_key: str

def _env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        raise RuntimeError(f"Missing environment variable: {name}")
    return v

def _assert_auth(header_val: Optional[str]) -> None:
    token = _env("WORKER_AUTH_TOKEN")
    if not header_val or header_val.strip() != token:
        raise PermissionError("Unauthorized")


def _get_supabase_client():
    """Get Supabase client with service role key"""
    from supabase import create_client
    url = _supabase_url()
    key = _env("SUPABASE_SERVICE_ROLE_KEY")
    return create_client(url, key)


def _supabase_url() -> str:
    return _env("SUPABASE_URL").rstrip("/")


def _bucket() -> str:
    return _env("SUPABASE_STORAGE_BUCKET")


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()


CLASSIFY_AND_COACH_PROMPT = """
You are analyzing a single basketball shot attempt from a short video clip.

Return ONLY a single JSON object per the schema below—no extra text.

TASKS
1) Decide if the shot is a MAKE or MISS.
2) Decide the range category: LAY_UP, IN_PAINT, MID_RANGE, THREE_POINTER, or FREE_THROW.
3) Provide 3 concise coaching tips to improve the same type of shot next time.

DEFINITIONS (strict)
- MAKE: Ball passes completely through the hoop from above during the clip (counts even if there’s an and-1).
- MISS: Any shot that does not go in (including blocked after release, airball, rim-out). If no clear attempt occurs, set "make_miss": null.

Range category is based on shooter position at RELEASE and the context of the play:
- LAY_UP: At/under the rim (layups, finger rolls, scoop shots, tip-ins, putbacks, dunks all count as LAY_UP).
- IN_PAINT: Non-layup two-point attempts with both feet inside the painted lane at release (floaters/runners/hooks/post moves inside paint).
- MID_RANGE: Two-point attempts outside the paint but inside the 3-pt line.
- THREE_POINTER: Both feet clearly behind the 3-pt arc at release. Toe on the line → MID_RANGE.
- FREE_THROW: Stationary, unguarded free-throw context.

TIE-BREAKS / EDGE CASES
- Tip-ins/putbacks: Treat as LAY_UP.
- Floaters/runners: Inside paint → IN_PAINT; outside paint → MID_RANGE.
- Blocked after release → MISS with appropriate range.
- If uncertain between two non–free-throw ranges, choose the closer-in one.

CONSTRAINTS
- Classify the first complete attempt in the clip; ignore later attempts.
- Output must be valid JSON only. Do not include reasoning or extra fields.

OUTPUT SCHEMA (use exactly these keys)
{
  "make_miss": "MAKE | MISS | null",
  "range": "LAY_UP | IN_PAINT | MID_RANGE | THREE_POINTER | FREE_THROW | null",
  "confidence": 0.0,
  "tips": ["string", "string", "string"]
}
"""


def _storage_signed_download_url(storage_key: str, expires_in: int = 600) -> str:
    print(f"Getting signed URL for: {storage_key}")
    supabase = _get_supabase_client()
    bucket = _bucket()
    
    try:
        # Create signed URL using Supabase SDK
        response = supabase.storage.from_(bucket).create_signed_url(storage_key, expires_in)
        print(f"Supabase SDK response: {response}")
        
        if 'signedURL' in response:
            signed_url = response['signedURL']
            print(f"Generated signed URL: {signed_url}")
            return signed_url
        else:
            raise Exception(f"No signedURL in response: {response}")
            
    except Exception as e:
        print(f"Error creating signed URL: {e}")
        print(f"Storage key: {storage_key}")
        print(f"Bucket: {bucket}")
        raise


def _download_video_bytes(signed_url: str) -> bytes:
    r = requests.get(signed_url, timeout=60)
    r.raise_for_status()
    return r.content


def _find_latest_analysis_for_clip(clip_id: str) -> Optional[Dict[str, Any]]:
    supabase = _get_supabase_client()
    
    try:
        response = supabase.table('analysis').select('*').eq('clip_id', clip_id).order('created_at', desc=True).limit(1).execute()
        print(f"Analysis query response: {response}")
        
        if response.data:
            return response.data[0]
        return None
        
    except Exception as e:
        print(f"Error finding analysis: {e}")
        raise


def _update_analysis(analysis_id: str, patch: Dict[str, Any]) -> Dict[str, Any]:
    supabase = _get_supabase_client()
    
    try:
        response = supabase.table('analysis').update(patch).eq('id', analysis_id).execute()
        print(f"Analysis update response: {response}")
        
        if response.data:
            return response.data[0]
        else:
            raise Exception(f"No data returned from update: {response}")
            
    except Exception as e:
        print(f"Error updating analysis: {e}")
        raise


def _normalize_range(rng: Optional[str]) -> Optional[str]:
    if not rng:
        return None
    upper = rng.strip().upper()
    mapping = {
        "LAY_UP": "lay_up",
        "IN_PAINT": "in_paint",
        "MID_RANGE": "mid_range",
        "THREE_POINTER": "three_pointer",
        "FREE_THROW": "free_throw",
    }
    return mapping.get(upper)


def _normalize_result(res: Optional[str]) -> Optional[str]:
    if not res:
        return None
    upper = res.strip().upper()
    if upper == "MAKE":
        return "make"
    if upper == "MISS":
        return "miss"
    return None


@app.function(image=image, secrets=[Secret.from_name("basketball-coach-secrets")])
@fastapi_endpoint(method="POST", label="analyze")
def analyze(payload: AnalyzeBody):  # <-- FastAPI binds JSON body here
    start = time.time()
    print("payload", payload)
    try:
        # Auth via body param (simple, works across clients)
        _assert_auth(payload.x_worker_auth)

        print(f"Parsed - clip_id: {payload.clip_id}, storage_key: {payload.storage_key}")

        if not payload.clip_id or not payload.storage_key:
            return {"error": "clip_id and storage_key are required"}, 422

        analysis = _find_latest_analysis_for_clip(payload.clip_id)
        if not analysis:
            return {"error": "No analysis row found for clip"}, 404
        analysis_id = analysis["id"]
        _update_analysis(analysis_id, {"status": "processing", "started_at": _iso_now()})

        signed = _storage_signed_download_url(payload.storage_key)

        video_bytes = _download_video_bytes(signed)

        
        
        client = genai.Client(api_key=_env("GEMINI_API_KEY"))
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=types.Content(
                parts=[
                    types.Part(
                        inline_data=types.Blob(data=video_bytes, mime_type="video/mp4"),
                        video_metadata=types.VideoMetadata(fps=FRAMES_PER_SECOND),
                    ),
                    types.Part(text=CLASSIFY_AND_COACH_PROMPT),
                ]
            ),
            # config=types.GenerateContentConfig(
            #     media_resolution=types.MediaResolution.MEDIA_RESOLUTION_MEDIUM
            # ),
        )

        # Robust JSON extraction
        raw_text = (
            response.candidates[0].content.parts[0].text if response.candidates else ""
        )
        txt = raw_text.strip()
        if txt.startswith("```"):
            # remove markdown fences
            txt = txt.split("\n", 1)[1] if "\n" in txt else txt
            if txt.endswith("```"):
                txt = txt.rsplit("\n", 1)[0]
        try:
            data = json.loads(txt)
        except Exception:
            # try to find first JSON object
            start_i = txt.find("{")
            end_i = txt.rfind("}")
            if start_i != -1 and end_i != -1:
                data = json.loads(txt[start_i : end_i + 1])
            else:
                raise ValueError("Model did not return valid JSON")

        normalized_result = _normalize_result(data.get("make_miss"))
        normalized_range = _normalize_range(data.get("range"))
        confidence = float(data.get("confidence") or 0.0)
        tips = data.get("tips") or []
        if not isinstance(tips, list):
            tips = [str(tips)]
        tips_text = "\n".join([str(t).strip() for t in tips if str(t).strip()])

        updated = _update_analysis(
            analysis_id,
            {
                "status": "success",
                "result": normalized_result,
                "shot_type": normalized_range,
                "confidence": confidence,
                "tips_text": tips_text,
                "completed_at": _iso_now(),
            },
        )

        elapsed = time.time() - start
        return {
            "clip_id": payload.clip_id,
            "analysis_id": analysis_id,
            "status": updated.get("status"),
            "shot_type": updated.get("shot_type"),
            "result": updated.get("result"),
            "confidence": updated.get("confidence"),
            "tips": tips,
            "elapsed_s": round(elapsed, 3),
        }

    except PermissionError as e:
        print(f"Authentication error: {e}")
        return {"error": str(e)}, 401
    except Exception as e:
        print(f"Unexpected error: {e}")
        print(f"Error type: {type(e)}")
        import traceback
        traceback.print_exc()
        
        try:
            analysis_id = locals().get("analysis_id")
            if analysis_id:
                _update_analysis(
                    analysis_id,
                    {
                        "status": "failed",
                        "error_msg": str(e),
                        "completed_at": _iso_now(),
                    },
                )
        except Exception as update_e:
            print(f"Failed to update analysis: {update_e}")
            pass
        return {"error": str(e)}, 500
