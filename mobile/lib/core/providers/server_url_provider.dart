import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';

final serverUrlProvider = Provider<String>((ref) => AppConstants.apiBaseUrl);
