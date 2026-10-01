import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import '../repositories/user_repositories.dart';
import '../services/call_service.dart';
import '../services/core_services.dart';
import '../widgets/common.dart';
import 'auth/auth_screens.dart';
import 'home/home_shell.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});
  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.04).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
              child: const BrandLogo(size: 120),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 120,
              child: LinearProgressIndicator(minHeight: 3, color: AppColors.cyan, backgroundColor: Colors.white10),
            ),
          ],
        ),
      ),
    );
  }
}

/// يقرر أي شاشة تظهر: البداية، الصيانة، الحظر، تسجيل الدخول، أو الرئيسية.
class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool _minSplashDone = false;
  bool _adminLogin = false;
  SessionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _minSplashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final status = context.watch<AppStatusProvider>();
    final hub = context.read<ChatHub>();
    CallService.instance.updateMe(name: session.profile?.displayName, avatar: session.profile?.avatarUrl);

    if (_lastStatus != session.status) {
      _lastStatus = session.status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (session.status == SessionStatus.signedIn) {
          hub.start();
          final uid = myId;
          if (uid != null) {
            CallService.instance.start(uid, name: session.profile?.displayName, avatar: session.profile?.avatarUrl);
          }
        } else if (session.status == SessionStatus.signedOut) {
          hub.stop();
          CallService.instance.stop();
        }
      });
    }

    Widget child;
    if (!_minSplashDone || session.status == SessionStatus.loading || !status.loaded) {
      child = const SplashView();
    } else if (session.status == SessionStatus.signedIn && (session.profile?.isBanned ?? false)) {
      child = const _BlockedScreen(
        icon: Icons.gpp_bad_rounded,
        title: 'تم حظر حسابك',
        message: 'تم إيقاف حسابك من قبل الإدارة بسبب مخالفة القواعد.',
      );
    } else if (!status.enabled && !session.isAdmin) {
      if (session.status == SessionStatus.signedOut && _adminLogin) {
        child = LoginScreen(onBack: () => setState(() => _adminLogin = false), adminMode: true);
      } else {
        child = _BlockedScreen(
          icon: Icons.construction_rounded,
          title: 'التطبيق متوقف مؤقتًا',
          message: status.message,
          onAdminLogin: session.status == SessionStatus.signedOut ? () => setState(() => _adminLogin = true) : null,
        );
      }
    } else if (session.status == SessionStatus.signedOut) {
      child = const LoginScreen();
    } else {
      child = const HomeShell();
    }

    return AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: child);
  }
}

class _BlockedScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onAdminLogin;
  const _BlockedScreen({required this.icon, required this.title, required this.message, this.onAdminLogin});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.watch<SessionProvider>().status == SessionStatus.signedIn;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(size: 84),
                const SizedBox(height: 36),
                Icon(icon, size: 56, color: AppColors.cyan),
                const SizedBox(height: 14),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6)),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () => context.read<AppStatusProvider>().load(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
                if (signedIn)
                  TextButton(onPressed: () => AuthRepository().signOut(), child: const Text('تسجيل الخروج')),
                if (onAdminLogin != null)
                  TextButton(onPressed: onAdminLogin, child: const Text('دخول المدير')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
