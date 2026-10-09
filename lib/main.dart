import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'firebase_options.dart';
import 'screens/main_shell.dart';
import 'screens/phone_login_screen.dart';
import 'theme/app_theme.dart';
import 'utils/user_profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Match the status bar to the app's dark theme — without this it defaults
  // to the OS's light-mode styling, which clashes with the dark background.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Halo',
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

/// Routes straight past the login screen when Firebase Auth already has a
/// persisted, signed-in user — otherwise every app restart re-prompts for
/// phone + OTP even though the session is still valid. Firebase Auth
/// persists sessions on its own; this widget is just what actually reads
/// that state on startup instead of ignoring it.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const _loading = Scaffold(
    body: Center(child: CircularProgressIndicator(color: accentGold)),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _loading;
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const PhoneLoginScreen();
        }

        return FutureBuilder<bool>(
          future: hasUserProfile(user.uid),
          builder: (context, profileSnapshot) {
            if (!profileSnapshot.hasData) {
              return _loading;
            }

            if (profileSnapshot.data == true) {
              return const MainShell(groupId: defaultGroupId);
            }

            // Signed in (e.g. Firebase restored the session) but the
            // "what's your name?" step never finished — that step needs
            // the live OTP flow's state to run, so rather than duplicate
            // it here, sign out and let them go through it cleanly again.
            FirebaseAuth.instance.signOut();
            return const PhoneLoginScreen();
          },
        );
      },
    );
  }
}
