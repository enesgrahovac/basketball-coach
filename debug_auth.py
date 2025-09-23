#!/usr/bin/env python3
"""
Quick debug script to test Modal auth
"""
import requests
import json

# Your Modal function URL
MODAL_URL = "https://enesgrahovac--analyze.modal.run"

def test_auth_token(token):
    """Test a specific auth token"""
    test_data = {
        "clip_id": "debug-test",
        "storage_key": "test/debug.mp4", 
        "x_worker_auth": token
    }
    
    print(f"Testing with token: {token}")
    
    try:
        response = requests.post(
            MODAL_URL,
            json=test_data,
            headers={"Content-Type": "application/json"},
            timeout=10
        )
        
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text}")
        return response.status_code
        
    except Exception as e:
        print(f"Error: {e}")
        return None

if __name__ == "__main__":
    # Test the token you're using
    current_token = "8ca4618e1b11c804adc3ea4caf628b6c000054a73bed37f3b0d7c78dc254b6f5"
    status = test_auth_token(current_token)
    
    if status == 401:
        print("\n❌ Token mismatch - check your Modal secrets")
    elif status == 422:
        print("\n✅ Auth passed! (422 is expected for invalid clip_id)")
    else:
        print(f"\n❓ Unexpected status: {status}")
