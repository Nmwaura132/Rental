import requests
import json
from environ import Env

# Load .env
env = Env()
Env.read_env('.env')

username = env('AT_USERNAME', default='sandbox')
api_key = env('AT_API_KEY', default='')

test_phone = "+254100368483"
message = "Rental Manager: JSON API test."

def test_endpoint(name, url, user):
    print(f"\n--- Testing {name} Endpoint ---")
    print(f"URL:      {url}")
    print(f"Username: {user}")
    
    headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'apiKey': api_key
    }
    
    # AT JSON API expects 'phoneNumbers' as a string or list
    payload = {
        'username': user,
        'phoneNumbers': [test_phone],
        'message': message
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload)
        print(f"Status Code: {response.status_code}")
        print(f"Response Body: {response.text}")
        
    except Exception as e:
        print(f"RESULT: ERROR - {str(e)}")

# Test 1: Sandbox
test_endpoint("SANDBOX", "https://api.sandbox.africastalking.com/version1/messaging/bulk", "sandbox")

# Test 2: Live (using provided username)
test_endpoint("LIVE", "https://api.africastalking.com/version1/messaging/bulk", username)
