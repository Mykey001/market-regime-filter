"""
Test Google Gemini API Connection
Quick test to verify the API key works before processing EAs
"""

import google.generativeai as genai
import sys

# Your Google Gemini API key
GEMINI_API_KEY = "AIzaSyAb8RN6LOMshdv1w3_YW_pQrbWpafVs2LfRR9Pq9w3nTe7b4l3Q"

def test_api_connection():
    """Test if Google Gemini API is accessible and working"""
    
    print("="*60)
    print("GOOGLE GEMINI API CONNECTION TEST")
    print("="*60)
    print()
    
    try:
        print("1. Configuring Google Gemini API...")
        genai.configure(api_key=GEMINI_API_KEY)
        print("   ✓ API key configured successfully")
        print()
        
        print("2. Initializing Gemini model...")
        model = genai.GenerativeModel('gemini-1.5-pro')
        print("   ✓ Model initialized successfully")
        print()
        
        print("3. Sending test request to API...")
        print("   (This may take 5-10 seconds)")
        
        response = model.generate_content("Say 'API connection successful' in exactly those words.")
        response_text = response.text.strip()
        
        print("   ✓ API response received")
        print()
        
        print("3. Response from AI:")
        print(f"   '{response_text}'")
        print()
        
        print("="*60)
        print("✅ SUCCESS! API is working correctly")
        print("="*60)
        print()
        print("You're ready to use the auto-integration system!")
        print("Run: start_integration.bat")
        print()
        
        return True
        
    except Exception as e:
        print()
        print("="*60)
        print("❌ ERROR! API connection failed")
        print("="*60)
        print()
        print(f"Error type: {type(e).__name__}")
        print(f"Error message: {str(e)}")
        print()
        print("Possible causes:")
        print("1. Invalid API key")
        print("2. No internet connection")
        print("3. API service temporarily unavailable")
        print("4. Missing dependencies (run: pip install google-generativeai)")
        print()
        print("Please check and try again.")
        print()
        
        return False

if __name__ == "__main__":
    success = test_api_connection()
    sys.exit(0 if success else 1)
