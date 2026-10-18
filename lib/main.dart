import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'providers/providers.dart';
import 'screens/gate.dart';
import 'services/background_service.dart';
import 'services/call_service.dart';
import 'services/core_services.dart';
import 'services/crash_reporter.dart';
import 'services/integrity_service.dart';
import 'services/local_notifications.dart';
import 'services/notif_router.dart';
import 'services/push_service.dart';
import 'services/rtc_safety.dart';
import 'services/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // كل خطوة قبل فتح الواجهة إلها حد زمني: التطبيق لازم يفتح مهما صار (ما يعلك على شاشة الشعار)
  Future<void> step(Future<void> Function() f, int secs) async {
    try {
      await f().timeout(Duration(seconds: secs));
    } catch (_) {}
  }

  await step(() => initializeDateFormatting('ar'), 3);
  await CacheService.init();
  await step(RtcSafety.init, 3);
  // بالتوازي حتى يفتح التطبيق أسرع
  await Future.wait([
    AppConfig.load().timeout(const Duration(seconds: 4)).catchError((_) => AppConfig.useDefaults()),
    step(PushService.init, 6),
    step(IntegrityService.check, 4),
  ]);
  runApp(const RootApp());
}

class RootApp extends StatefulWidget {
  const RootApp({super.key});
  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  bool _ready = false;
  String? _error;
  final _theme = ThemeProvider();

  @override
  void initState() {
    super.initState();
    AppConfig.useDefaults();
    _init();
  }

  int _retries = 0;

  Future<void> _init() async {
    try {
      await Supabase.initialize(url: AppConfig.url, anonKey: AppConfig.anonKey);
      NotifRouter.install();
      CrashReporter.install();
      CrashReporter.sendPendingNativeCrash();
      // هذني ما لازم يوقفن فتح التطبيق إذا تأخرن
      await LocalNotifications.init().timeout(const Duration(seconds: 5)).catchError((_) {});
      await BackgroundBridge.configure().timeout(const Duration(seconds: 6)).catchError((_) {});
      Future.delayed(const Duration(seconds: 4),
          () => UpdateService.autoCheck(() => CallService.instance.navigatorKey.currentContext));
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (e) {
      // ما نطلع شاشة إعدادات للمستخدم: نبقى على شاشة البداية ونعيد المحاولة وحدنا
      _error = '$e';
      final wait = Duration(seconds: (2 << _retries.clamp(0, 4)).clamp(2, 30));
      _retries++;
      Future.delayed(wait, () {
        if (mounted && !_ready) _init();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _theme,
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: AppConfig.appName,
          navigatorKey: CallService.instance.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // المزوّدات فوق الـ Navigator حتى تصل لكل الشاشات
          builder: (context, child) => _ready ? _Providers(child: child!) : child!,
          home: _ready ? const Gate() : const SplashView(),
        ),
      ),
    );
  }
}

class _Providers extends StatelessWidget {
  final Widget child;
  const _Providers({required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityService()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => AppStatusProvider()),
        ChangeNotifierProvider(create: (c) => ChatHub(c.read<ConnectivityService>())),
      ],
      child: child,
    );
  }
}
