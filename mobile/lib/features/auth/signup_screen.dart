import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/biometric_service.dart';
import '../../core/theme/kasa_fonts.dart';
import '../../core/theme/kasa_tokens.dart';
import '../../core/utils/api_error.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/kasa_layout.dart';
import '../../core/widgets/kasa_primitives.dart';

const _storage = FlutterSecureStorage();

/// A landlord creating their own account: their number, a code texted to it,
/// then their name. Tenants never come here — their landlord
/// adds them.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _phoneForm = GlobalKey<FormState>();
  final _detailsForm = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_phoneCtrl, _codeCtrl, _firstCtrl, _lastCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(apiError(e)),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
  }

  Future<void> _sendCode() async {
    if (!_phoneForm.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(publicDioProvider)
          .post('/api/v1/auth/signup/request-code/', data: {
        'phone_number': normalizeKenyanPhone(_phoneCtrl.text),
      });
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    if (!_detailsForm.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final phone = normalizeKenyanPhone(_phoneCtrl.text);
      final resp =
          await ref.read(publicDioProvider).post('/api/v1/auth/signup/', data: {
        'phone_number': phone,
        'code': _codeCtrl.text.trim(),
        'first_name': _firstCtrl.text.trim(),
        'last_name': _lastCtrl.text.trim(),
      });

      // The same session a sign-in leaves behind, so the app treats them as
      // signed in from here on.
      await _storage.write(key: 'access_token', value: resp.data['access']);
      await _storage.write(key: 'refresh_token', value: resp.data['refresh']);
      await _storage.write(key: 'user_role', value: resp.data['role']);
      await _storage.write(key: 'user_name', value: resp.data['name']);
      await _storage.write(
          key: 'user_phone', value: resp.data['phone_number'] ?? '');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_phone', phone);
      ref.read(sessionUnlockedProvider.notifier).state = true;

      if (mounted) context.go('/dashboard');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = KasaFont.sans(fontSize: 14, color: cs.kasaTextSub);

    return Scaffold(
      backgroundColor: cs.kasaBg,
      appBar: AppBar(
        backgroundColor: cs.kasaBg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Create an account'),
      ),
      // WHY the action bar inside the body: the body shrinks for the
      // keyboard, so the button stays in reach while typing.
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'For landlords. Your tenants get their accounts from you.',
                style: muted,
              ),
              const SizedBox(height: 24),
              Form(
                key: _phoneForm,
                child: TextFormField(
                  controller: _phoneCtrl,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    prefixText: '+254 ',
                    hintText: '712 345 678',
                  ),
                  validator: validateKenyanPhone,
                ),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed:
                        _busy ? null : () => setState(() => _codeSent = false),
                    child: const Text('Use a different number'),
                  ),
                ),
                const SizedBox(height: 8),
                KasaNotice(
                  icon: Icons.sms_outlined,
                  title: 'Check your messages',
                  body:
                      'We sent a 6-digit code to ${_phoneCtrl.text}. It lasts 5 minutes.',
                ),
                const SizedBox(height: 20),
                Form(
                  key: _detailsForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _codeCtrl,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(labelText: 'Code'),
                        validator: (v) => (v ?? '').length == 6
                            ? null
                            : 'Enter the 6-digit code',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _firstCtrl,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.givenName],
                        decoration:
                            const InputDecoration(labelText: 'First name'),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter your first name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _lastCtrl,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.familyName],
                        decoration:
                            const InputDecoration(labelText: 'Last name'),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter your last name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No password needed. Next time, sign in with a code sent to this number.',
                        style: KasaFont.sans(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.kasaTextSub),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        KasaActionBar(children: [
          KasaButton(
            label: _codeSent ? 'Create account' : 'Send code',
            isLoading: _busy,
            onTap: _busy ? null : (_codeSent ? _createAccount : _sendCode),
          ),
        ]),
      ]),
    );
  }
}
