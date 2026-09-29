import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's dialer with [number] ready to call.
///
/// If nothing can open it (a tablet, or no dialer) the number is copied
/// instead and the person is told, so they are never left with a button that
/// does nothing.
Future<void> callNumber(BuildContext context, String number) async {
  final messenger = ScaffoldMessenger.of(context);
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: number));
  } catch (_) {
    opened = false;
  }
  if (opened) return;

  await Clipboard.setData(ClipboardData(text: number));
  messenger.showSnackBar(SnackBar(content: Text('Could not open the dialer. $number copied.')));
}
