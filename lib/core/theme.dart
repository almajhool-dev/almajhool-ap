import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const cyan = Color(0xFF00E5FF);
  static const violet = Color(0xFF7C4DFF);
  static const pink = Color(0xFFFF4D9D);
  static const green = Color(0xFF00E676);
  static const danger = Color(0xFFFF5252);

  static const darkBg = Color(0xFF0A0E17);
  static const darkSurface = Color(0xFF121826);
  static const darkCard = Color(0xFF1A2233);

  static const lightBg = Color(0xFFF4F6FB);
  static const lightSurface = Colors.white;

  /// لون الخلفية الثابت (للحدود والفواصل — الشاشات نفسها شفافة فوق الخلفية المتحركة)
  static Color bgOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkBg : lightBg;

  static const brandGradient = LinearGradient(
    colors: [cyan, violet],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: AppColors.darkBg,
        surface: AppColors.darkSurface,
        card: AppColors.darkCard,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: AppColors.lightBg,
        surface: AppColors.lightSurface,
        card: Colors.white,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color card,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.violet,
      brightness: brightness,
      primary: isDark ? AppColors.cyan : AppColors.violet,
      secondary: isDark ? AppColors.violet : AppColors.cyan,
      surface: surface,
      error: AppColors.danger,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      // الشاشات شفافة حتى تبين الخلفية المتحركة (البطاقات تبقى واضحة)
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: bg,
      splashFactory: InkSparkle.splashFactory,
      dialogTheme: DialogThemeData(
        backgroundColor: (isDark ? AppColors.darkSurface : Colors.white).withValues(alpha: 0.94),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.cyan.withValues(alpha: isDark ? 0.35 : 0.25)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardColor: card,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkCard : const Color(0xFFEFF2F8),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.9),
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white10 : Colors.black12,
        thickness: 0.6,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      // تنقّل أسرع بين الشاشات (انتقال خفيف وسريع بدل التكبير البطيء)
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _FxPageTransition(),
      }),
    );
  }
}

/// انتقال بين الشاشات: الشاشة الجديدة تظهر بتلاشي وتكبير خفيف، والقديمة تتلاشى
/// (لأن الشاشات شفافة فوق الخلفية المتحركة ما تتداخل).
class _FxPageTransition extends PageTransitionsBuilder {
  const _FxPageTransition();
  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inC = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final outC = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic);
    return FadeTransition(
      opacity: ReverseAnimation(outC),
      child: FadeTransition(
        opacity: inC,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(inC), child: child),
      ),
    );
  }
}
