import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';

final serverUrlProvider = StateProvider<String>((ref) => AppConstants.apiBaseUrl);
