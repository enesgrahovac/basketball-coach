#!/usr/bin/env python3
"""
Test script for Supabase SDK functionality
"""
import os
from supabase import create_client

def test_supabase_connection():
    """Test basic Supabase connection and storage access"""
    
    # Load environment variables
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    bucket_name = os.getenv("SUPABASE_STORAGE_BUCKET", "clips")
    
    if not supabase_url or not supabase_key:
        print("❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables")
        return False
    
    try:
        # Create Supabase client
        supabase = create_client(supabase_url, supabase_key)
        print("✅ Supabase client created successfully")
        
        # Test storage bucket access
        storage_key = "ios/0AD5E34A-34A4-45B3-8783-994212CA24A2.mp4"
        
        print(f"🔍 Testing signed URL generation for: {storage_key}")
        
        # Create signed URL
        response = supabase.storage.from_(bucket_name).create_signed_url(storage_key, 600)
        print(f"📝 SDK Response: {response}")
        
        if 'signedURL' in response:
            signed_url = response['signedURL']
            print(f"✅ Signed URL generated: {signed_url}")
            
            # Test if we can make a HEAD request to verify the file exists
            import requests
            head_response = requests.head(signed_url, timeout=10)
            print(f"📊 HEAD request status: {head_response.status_code}")
            
            if head_response.status_code == 200:
                print("✅ File is accessible via signed URL")
                return True
            else:
                print(f"❌ File not accessible: {head_response.status_code}")
                return False
        else:
            print(f"❌ No signedURL in response: {response}")
            return False
            
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_database_access():
    """Test database access via Supabase SDK"""
    
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    
    if not supabase_url or not supabase_key:
        print("❌ Missing environment variables for database test")
        return False
    
    try:
        supabase = create_client(supabase_url, supabase_key)
        
        # Test querying the analysis table
        print("🔍 Testing database access...")
        
        response = supabase.table('analysis').select('id, clip_id, status').limit(5).execute()
        print(f"📝 Database query response: {response}")
        
        if hasattr(response, 'data'):
            print(f"✅ Database query successful, found {len(response.data)} records")
            return True
        else:
            print("❌ No data attribute in response")
            return False
            
    except Exception as e:
        print(f"❌ Database error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("🚀 Testing Supabase SDK functionality...")
    print()
    
    storage_ok = test_supabase_connection()
    print()
    
    db_ok = test_database_access()
    print()
    
    if storage_ok and db_ok:
        print("✅ All tests passed! Supabase SDK is working correctly.")
    else:
        print("❌ Some tests failed. Check the errors above.")
