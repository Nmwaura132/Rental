import 'package:flutter/material.dart';

/// Stable root navigator key shared between the router and the auth interceptor.
/// Kept in its own file to avoid circular imports (api_client → router → screens → api_client).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
