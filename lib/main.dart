import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'providers/providers.dart';
import 'screens/gate.dart';
import 'screens/setup_screen.dart';
import 'services/core_services.dart';
import 'services/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await CacheService.init();
  await AppConfig.load();
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
    if (AppConfig.isConfigured) _init();
  }

  Future<void> _init() async {
    try {
      await Supabase.initialize(url: AppConfig.url, anonKey: AppConfig.anonKey);
      await LocalNotifications.init();
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'تعذّر الاتصال بالخادم: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _theme,
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: AppConfig.appName,
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
          home: _ready
              ? const Gate()
              : (AppConfig.isConfigured && _error == null)
                  ? const SplashView()
                  : SetupScreen(
                  error: _error,
                  onSaved: () async {
                    setState(() => _error = null);
                    await _init();
                  },
                ),
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
