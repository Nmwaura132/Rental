# Rental Manager — Flutter Mobile App

## Prerequisites

Install Flutter SDK:
1. Download from https://docs.flutter.dev/get-started/install/windows
2. Extract to `C:\flutter`
3. Add `C:\flutter\bin` to your PATH
4. Run `flutter doctor` and follow any remaining setup steps

## Run the app

```bash
cd mobile
flutter pub get
flutter run
```

The Android emulator defaults to `http://10.0.2.2:8020`. Override endpoints at
build time instead of editing source:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://192.168.1.10:8020 \
  --dart-define=MEDIA_BASE_URL=http://192.168.1.10:9000
```

For a production Android build:

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=MEDIA_BASE_URL=https://files.example.com
```

## Architecture

```
lib/
├── main.dart                  # Entry point, Firebase init
├── core/
│   ├── api/api_client.dart    # Dio + JWT interceptor (auto-refresh)
│   ├── constants.dart         # API URL, app name
│   ├── router.dart            # GoRouter — screens + bottom nav
│   ├── models/                # JSON-serializable models
│   └── utils/currency.dart    # KES formatter
├── features/
│   ├── auth/login_screen.dart
│   ├── dashboard/             # Stats overview
│   ├── properties/            # Property + unit list
│   ├── tenants/               # Lease list
│   ├── payments/              # Invoice list
│   └── notifications/         # SMS / push history
└── shared/
    └── theme/app_theme.dart   # Material 3, Safaricom green palette
```
