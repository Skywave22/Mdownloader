import 'dart:ui';
import 'package:flutter/material.dart';

/// MDownloader design system — a deep "midnight" look with a violet→cyan
/// gradient identity, glass surfaces and soft glows.
class AppColors {
  static const bg = Color(0xFF05070D);
  static const surface = Color(0xFF0D121C);
  static const surface2 = Color(0xFF151C2B);
  static const surface3 = Color(0xFF1D2638);

  static const accent = Color(0xFF8B5CF6); // violet
  static const accent2 = Color(0xFF22D3EE); // cyan
  static const accent3 = Color(0xFF6366F1); // indigo

  static const textHi = Color(0xFFF2F5FA);
  static const textMid = Color(0xFF98A4B8);
  static const textLow = Color(0xFF66718A);

  static const border = Color(0xFF212B40);
  static const danger = Color(0xFFFF5C7A);
  static const ok = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent3, accent2],
  );

  /// Softer, longer gradient for large surfaces (hero, buttons).
  static const gradientSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF06B6D4)],
  );

  static const glow = [
    Color(0x668B5CF6),
    Color(0x0022D3EE),
  ];
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent2,
      tertiary: AppColors.accent3,
      surface: AppColors.surface,
      onSurface: AppColors.textHi,
      error: AppColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textHi,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textHi,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppColors.surface.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: AppColors.accent.withValues(alpha: 0.20),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? AppColors.textHi : AppColors.textLow,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? AppColors.accent2 : AppColors.textLow,
        ),
      ),
    ),
    dividerColor: AppColors.border,
    splashColor: AppColors.accent.withValues(alpha: 0.08),
    highlightColor: AppColors.accent.withValues(alpha: 0.06),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.accent2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textLow),
      prefixIconColor: AppColors.textLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface3,
      contentTextStyle: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// A "‹ Title" section header with an accent bar and optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: AppColors.textHi,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    )),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(color: AppColors.textLow, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Gradient "pill" chip. Optional custom colors.
class GradPill extends StatelessWidget {
  final String text;
  final List<Color>? colors;
  const GradPill({super.key, required this.text, this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors ?? const [AppColors.accent, AppColors.accent2]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

/// A subtle "chip" used for meta / tags.
class MetaPill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  const MetaPill({super.key, required this.text, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        ],
      ),
    );
  }
}

/// Gradient-filled primary button with a soft glow.
class GradButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expanded;
  const GradButton({super.key, required this.label, this.icon, this.onPressed, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 19, color: Colors.white),
          const SizedBox(width: 8),
        ],
        Text(label,
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
    final decorated = Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        gradient: AppColors.gradientSoft,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onPressed == null) {
      return Opacity(opacity: 0.5, child: decorated);
    }
    return GestureDetector(
      onTap: onPressed,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 150),
        builder: (_, v, __) => Transform.scale(scale: 0.985 + 0.015 * v, child: decorated),
      ),
    );
  }
}

/// A glassmorphism surface: translucent card with a blur and hairline border.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Border? border;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        builder: (_, v, __) => Transform.scale(scale: 0.98 + 0.02 * v, child: card),
      ),
    );
  }
}

/// Amber star rating badge, e.g. "★ 8.4".
class RatingBadge extends StatelessWidget {
  final double score;
  const RatingBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: AppColors.amber),
          const SizedBox(width: 3),
          Text(score.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.amber)),
        ],
      ),
    );
  }
}
