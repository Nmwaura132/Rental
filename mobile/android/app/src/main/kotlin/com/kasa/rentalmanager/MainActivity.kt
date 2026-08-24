package com.kasa.rentalmanager

import io.flutter.embedding.android.FlutterFragmentActivity

// WHY FlutterFragmentActivity and not FlutterActivity: local_auth's Android
// implementation shows the biometric prompt through androidx BiometricPrompt,
// which needs a FragmentActivity host. Using FlutterActivity crashes the
// prompt at call time.
class MainActivity : FlutterFragmentActivity()
