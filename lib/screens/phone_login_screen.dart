import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../constants.dart';
import '../theme/app_theme.dart';
import '../utils/firebase_auth_errors.dart';
import '../utils/user_profile.dart';
import '../widgets/logo_widget.dart';
import 'main_shell.dart';

enum _AuthStep { phone, otp, name }

/// Phone + OTP sign-in via Firebase Auth's native phone provider — no
/// third-party SMS service. First-time users provide a name after OTP
/// verification; returning users land straight on the main shell.
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  _AuthStep _step = _AuthStep.phone;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _nameController = TextEditingController();
  String _selectedCircle = 'PSG Campus';

  String? _verificationId;
  String? _fullPhoneNumber;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendOtp() async {
    final digits = _phoneController.text.trim();
    if (digits.length < 10) {
      _showSnack('Enter a valid 10-digit phone number.');
      return;
    }
    final phoneNumber = '+91$digits';
    setState(() => _isSubmitting = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      // Some Android devices auto-retrieve the SMS and verify without the
      // user typing anything — sign in directly when that happens.
      verificationCompleted: (credential) => _completeSignIn(credential),
      verificationFailed: (e) {
        setState(() => _isSubmitting = false);
        _showSnack(friendlyAuthErrorMessage(e));
      },
      codeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _fullPhoneNumber = phoneNumber;
          _step = _AuthStep.otp;
          _isSubmitting = false;
        });
      },
      codeAutoRetrievalTimeout: (verificationId) =>
          _verificationId = verificationId,
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6 || _verificationId == null) {
      _showSnack('Enter the 6-digit code.');
      return;
    }

    setState(() => _isSubmitting = true);
    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    );
    await _completeSignIn(credential);
  }

  Future<void> _completeSignIn(PhoneAuthCredential credential) async {
    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return;

      final hasProfile = await hasUserProfile(user.uid);
      if (!mounted) return;

      if (hasProfile) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => const MainShell(groupId: defaultGroupId)),
        );
      } else {
        setState(() {
          _fullPhoneNumber ??= user.phoneNumber;
          _step = _AuthStep.name;
          _isSubmitting = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isSubmitting = false);
      _showSnack(friendlyAuthErrorMessage(e));
    }
  }

  Future<void> _submitName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please enter your name.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    await createUserProfile(
      uid: user.uid,
      phoneNumber: _fullPhoneNumber ?? user.phoneNumber ?? '',
      name: name,
      circleName: _selectedCircle,
      signature: 'Helping quietly, noticing clearly.',
      haloScore: 120,
      streak: 1,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => const MainShell(groupId: defaultGroupId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HaloLogo(size: 72),
                  const SizedBox(height: 8),
                  const Text(
                    'Anonymous recognition, real gratitude.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 40),
                  if (_step == _AuthStep.phone) _buildPhoneStep(),
                  if (_step == _AuthStep.otp) _buildOtpStep(),
                  if (_step == _AuthStep.name) _buildNameStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            prefixText: '+91  ',
            prefixIcon: Icon(LucideIcons.phone, size: 18, color: accentGold),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _sendOtp,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: bgPrimary),
                )
              : const Text('Send OTP'),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the code sent to $_fullPhoneNumber',
          textAlign: TextAlign.center,
          style: const TextStyle(color: textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: '6-digit code',
            counterText: '',
            prefixIcon:
                Icon(LucideIcons.shieldCheck, size: 18, color: accentGold),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _verifyOtp,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: bgPrimary),
                )
              : const Text('Verify'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => setState(() {
                    _step = _AuthStep.phone;
                    _otpController.clear();
                  }),
          child: const Text('Use a different number'),
        ),
      ],
    );
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "What's your name?",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Your name',
            prefixIcon: Icon(LucideIcons.user, size: 18, color: accentGold),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _selectedCircle,
          decoration: const InputDecoration(
            labelText: 'Join a nearby circle',
            prefixIcon: Icon(LucideIcons.mapPin, size: 18, color: accentGold),
          ),
          items: const [
            DropdownMenuItem(value: 'PSG Campus', child: Text('PSG Campus')),
            DropdownMenuItem(value: 'RS Puram', child: Text('RS Puram')),
            DropdownMenuItem(
                value: 'Local Circle', child: Text('Local Circle')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _selectedCircle = value);
          },
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitName,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: bgPrimary),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}
