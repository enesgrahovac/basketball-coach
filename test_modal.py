#!/usr/bin/env python3
"""
Test script to debug the Modal function directly
"""
import requests
import json

# Your Modal function URL
MODAL_URL = "https://enesgrahovac--analyze.modal.run"

# Test data
test_data = {
    "clip_id": "test-clip-123",
    "storage_key": "clips/ios/test.mp4"
}

# Test auth token (you'll need to set this to match your Modal secrets)
import os
AUTH_TOKEN = os.getenv("WORKER_AUTH_TOKEN", "your-secret-auth-token-123")  # Will use env var if available

def test_modal_endpoint():
    print(f"Testing Modal endpoint: {MODAL_URL}")
    print(f"Request body: {json.dumps(test_data, indent=2)}")
    
    headers = {
        "Content-Type": "application/json",
        "X-Worker-Auth": AUTH_TOKEN
    }
    
    try:
        response = requests.post(
            MODAL_URL,
            json=test_data,
            headers=headers,
            timeout=30
        )
        
        print(f"\nResponse Status: {response.status_code}")
        print(f"Response Headers: {dict(response.headers)}")
        
        try:
            response_json = response.json()
            print(f"Response Body: {json.dumps(response_json, indent=2)}")
        except:
            print(f"Response Text: {response.text}")
            
        if response.status_code == 422:
            print("\n❌ 422 Error - Check the Modal logs for debug output")
        elif response.status_code == 401:
            print("\n❌ 401 Error - Authentication failed")
        elif response.status_code == 200:
            print("\n✅ Success!")
        else:
            print(f"\n❓ Unexpected status: {response.status_code}")
            
    except Exception as e:
        print(f"❌ Request failed: {e}")

if __name__ == "__main__":
    test_modal_endpoint()
