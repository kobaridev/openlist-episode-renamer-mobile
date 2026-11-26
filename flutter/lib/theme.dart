import 'package:material_ui/material_ui.dart';

/// Refined white-blue design: soft vertical gradient background, frosted
/// glass cards, 16–20dp radii, compact spacing. Mirrors the native
/// light/dark schemes (BlueLight / BlueDark in MainActivity.kt).

final ColorScheme blueLight = const ColorScheme.light(
  primary: Color(0xFF0B57D0),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFD3E3FD),
  onPrimaryContainer: Color(0xFF041E49),
  secondary: Color(0xFF00639B),
  surface: Colors.white,
  onSurface: Color(0xFF1F1F1F),
  surfaceContainerHighest: Color(0xFFEAF1FB),
  onSurfaceVariant: Color(0xFF444746),
  outline: Color(0xFFC4C7C5),
  outlineVariant: Color(0xFFE1E7EF),
  error: Color(0xFFB3261E),
);

final ColorScheme blueDark = const ColorScheme.dark(
  primary: Color(0xFF8AB8FF),
  onPrimary: Color(0xFF08295C),
  primaryContainer: Color(0xFF1E4470),
  onPrimaryContainer: Color(0xFFD3E3FD),
  secondary: Color(0xFF7FCFFF),
  surface: Color(0xFF132239),
  onSurface: Color(0xFFE6EEF9),
  surfaceContainerHighest: Color(0xFF1D3252),
  onSurfaceVariant: Color(0xFFB9C9DE),
  outline: Color(0xFF3D5A85),
  outlineVariant: Color(0xFF243A5C),
  error: Color(0xFFF2B8B5),
);

ThemeData renamerTheme(bool dark) {
  final scheme = dark ? blueDark : blueLight;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.3),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleSmall: TextStyle(fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontWeight: FontWeight.w500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface.withValues(alpha: 0.85),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(50),
      ),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}

/// Page background: soft vertical gradient (light: #D9E9FF→#F2F7FF→white;
/// dark: deep navy), same as the native Box background brush.
class GradientBackground extends StatelessWidget {
  final Widget child;
  final bool dark;
  const GradientBackground({super.key, required this.child, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [
                  Color(0xFF16305A),
                  Color(0xFF0C1A30),
                  Color(0xFF0A1526),
                ]
              : const [
                  Color(0xFFD9E9FF),
                  Color(0xFFF2F7FF),
                  Colors.white,
                ],
        ),
      ),
      child: child,
    );
  }
}

/// Frosted-glass card: translucent surface + subtle border + soft shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding,
    this.color,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      decoration: BoxDecoration(
        color: color ?? scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(radius),
        border: border ??
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}
