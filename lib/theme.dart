import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';

/// Палітра застосунку: тепле «паперове» тло, чорнило і один акцент —
/// жовтий, як лампочка. Без градієнтів і зайвих тіней.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.light,
    required this.dark,
    required this.maybe,
    required this.onLight,
  });

  final Color paper;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color line;

  /// Світло є.
  final Color light;

  /// Світла немає.
  final Color dark;

  /// Можливе відключення.
  final Color maybe;

  /// Текст поверх [light].
  final Color onLight;

  static const day = Palette(
    paper: Color(0xFFF3EFE6),
    surface: Color(0xFFFBF9F4),
    ink: Color(0xFF1C1B18),
    muted: Color(0xFF78736A),
    line: Color(0xFFDCD6C9),
    light: Color(0xFFF2B705),
    dark: Color(0xFF2B2A26),
    maybe: Color(0xFFC9BFA8),
    onLight: Color(0xFF1C1B18),
  );

  static const night = Palette(
    paper: Color(0xFF12110F),
    surface: Color(0xFF1B1A17),
    ink: Color(0xFFEFEBE2),
    muted: Color(0xFF8D877C),
    line: Color(0xFF2E2C28),
    light: Color(0xFFF5C02A),
    dark: Color(0xFF57534B),
    maybe: Color(0xFF6B6455),
    onLight: Color(0xFF12110F),
  );

  Color of(Power p) => switch (p) {
        Power.on => light,
        Power.off => dark,
        Power.maybe => maybe,
      };

  static Palette fromContext(BuildContext context) =>
      Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      light: l(light, other.light),
      dark: l(dark, other.dark),
      maybe: l(maybe, other.maybe),
      onLight: l(onLight, other.onLight),
    );
  }
}

extension PaletteX on BuildContext {
  Palette get palette => Palette.fromContext(this);
}

/// Змінні шрифти: вагу задаємо і через fontWeight, і через вісь wght,
/// щоб вона працювала однаково на iOS, Android і в браузері.
TextStyle display(double size,
        {FontWeight weight = FontWeight.w600, Color? color, double? height}) =>
    TextStyle(
      fontFamily: 'Unbounded',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
      height: height ?? 1.1,
      letterSpacing: -0.4,
    );

TextStyle body(double size,
        {FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
    TextStyle(
      fontFamily: 'Golos',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
      height: height ?? 1.35,
    );

/// Цифри однакової ширини — щоб час у списках стояв рівно.
TextStyle numbers(double size,
        {FontWeight weight = FontWeight.w500, Color? color}) =>
    body(size, weight: weight, color: color).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Маленький підпис великими літерами з розрядкою.
TextStyle label(Color color) =>
    body(11.5, weight: FontWeight.w600, color: color)
        .copyWith(letterSpacing: 1.2);

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.light ? Palette.day : Palette.night;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.light,
    brightness: brightness,
  ).copyWith(
    primary: p.ink,
    onPrimary: p.paper,
    surface: p.paper,
    onSurface: p.ink,
    outline: p.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.paper,
    fontFamily: 'Golos',
    extensions: [p],
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.line.withValues(alpha: 0.5),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink),
    // Однакові «айфонні» переходи між екранами на всіх платформах.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    }),
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: p.ink,
      brightness: brightness,
    ),
  );
}
