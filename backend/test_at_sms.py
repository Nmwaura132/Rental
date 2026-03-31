import os
import africastalking
from environ import Env

# Load .env
env = Env()
Env.read_env('.env')

username = env('AT_USERNAME', default='sandbox')
api_key = env('AT_API_KEY', default='')
sender_id = env('AT_SENDER_ID', default=None)

# The test number you provided
test_phone = "+254100368483" 

print(f"--- AT SMS Test ---")
print(f"Username: {username}")
print(f"Target:   {test_phone}")
print(f"Sender:   {sender_id or 'None'}")
print("-------------------")

try:
    africastalking.initialize(username, api_key)
    sms = africastalking.SMS
    
    message = "Rental Manager: This is a test SMS message to verify integration."
    
    # In live mode (not sandbox), sender_id must be valid/approved
    response = sms.send(message, [test_phone], sender_id=sender_id or None)
    print("Response JSON:")
    print(response)
    
    recipients = response['SMSMessageData']['Recipients']
    if recipients and recipients[0]['status'] == 'Success':
        print("\nSUCCESS: The SMS was accepted by Africa's Talking.")
    elif recipients and recipients[0]['status'] == 'Sent':
        print("\nSUCCESS: The SMS was sent (Live mode).")
    else:
        status = recipients[0]['status'] if recipients else 'No recipient data'
        print(f"\nFAILED: Status is '{status}'")

except Exception as e:
    # Check for the common 'The authentication is invalid version!' error
    if "invalid version" in str(e).lower():
        print("\nERROR: Authentication Failed (Invalid Version).")
        print("This usually means the API Key is a Live key being used with 'sandbox' username, or vice-versa.")
    else:
        print(f"\nERROR: {str(e)}")
