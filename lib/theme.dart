import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Daleel palette: the colours of Al Ain.
// Sand and dune from the desert edge, terracotta from the mud-brick forts,
// oasis green from the date palms, falaj teal from the old water channels.
// Every text colour here passes WCAG AA on the surface it is used on.
// ---------------------------------------------------------------------------
const sand = Color(0xFFF5EBDD); // page background
const sandDeep = Color(0xFFEDE0CC); // secondary panels, skeletons
const parchment = Color(0xFFFFFBF5); // cards, sheets, search fields
const dune = Color(0xFFD9B380); // selection, indicator, decoration only
const duneLine = Color(0xFFE2D2BA); // hairlines and outlines
const terracotta = Color(0xFFA4522D); // primary actions (white text 5.5:1)
const terracottaDeep = Color(0xFF7E3B1E); // pressed / text on dune
const oasis = Color(0xFF4F6B4A); // secondary, "for you", success
const falaj = Color(0xFF2F6F73); // buses and water
const darkBrown = Color(0xFF3B2A1E); // body text (11.6:1 on sand)
const mutedBrown = Color(0xFF6E5A49); // secondary text (5.5:1 on sand)
const errorClay = Color(0xFFA3322A);

/// Display face: Reem Kufi, a Kufic design that echoes the geometric
/// lettering on Gulf architecture. Used only for headings and place names.
const displayFont = 'ReemKufi';

/// Text face: IBM Plex Sans Arabic, which carries matching Arabic and Latin.
const textFont = 'PlexArabic';

ThemeData daleelTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: terracotta,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF3D9C7),
    onPrimaryContainer: terracottaDeep,
    secondary: oasis,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFDDE6D3),
    onSecondaryContainer: Color(0xFF2C4229),
    tertiary: falaj,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD3E7E5),
    onTertiaryContainer: Color(0xFF173F42),
    error: errorClay,
    onError: Colors.white,
    errorContainer: Color(0xFFF6D9D3),
    onErrorContainer: Color(0xFF5E1A14),
    surface: sand,
    onSurface: darkBrown,
    onSurfaceVariant: mutedBrown,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: parchment,
    surfaceContainer: parchment,
    surfaceContainerHigh: Color(0xFFF8F0E4),
    surfaceContainerHighest: sandDeep,
    outline: Color(0xFFB9A58C),
    outlineVariant: duneLine,
    inverseSurface: darkBrown,
    onInverseSurface: sand,
    inversePrimary: dune,
    shadow: Color(0xFF3B2A1E),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: textFont,
  );

  TextStyle? display(TextStyle? s) => s?.copyWith(
        fontFamily: displayFont,
        fontWeight: FontWeight.w700,
        color: darkBrown,
        height: 1.25,
      );

  final text = base.textTheme;
  final textTheme = text.copyWith(
    displaySmall: display(text.displaySmall),
    headlineLarge: display(text.headlineLarge),
    headlineMedium: display(text.headlineMedium),
    headlineSmall: display(text.headlineSmall),
    titleLarge: display(text.titleLarge?.copyWith(fontSize: 21)),
    titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: text.bodyLarge?.copyWith(height: 1.55),
    bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
    bodySmall: text.bodySmall?.copyWith(color: mutedBrown, height: 1.45),
    labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );

  const buttonText =
      TextStyle(fontFamily: textFont, fontSize: 15, fontWeight: FontWeight.w600);
  final rounded14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: sand,
    appBarTheme: AppBarTheme(
      backgroundColor: sand,
      foregroundColor: darkBrown,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.headlineSmall?.copyWith(fontSize: 26),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: parchment,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dune.withValues(alpha: 0.55),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) {
          final on = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: textFont,
            fontSize: 12.5,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
            color: on ? darkBrown : mutedBrown,
          );
        },
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? terracottaDeep : mutedBrown,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: parchment,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: duneLine),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: parchment,
      selectedColor: dune.withValues(alpha: 0.6),
      checkmarkColor: terracottaDeep,
      side: const BorderSide(color: duneLine),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        fontFamily: textFont,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: darkBrown,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded14,
        minimumSize: const Size(64, 48),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded14,
        minimumSize: const Size(64, 48),
        foregroundColor: terracottaDeep,
        side: const BorderSide(color: Color(0xFFB9A58C)),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: terracottaDeep,
        minimumSize: const Size(48, 48),
        textStyle: buttonText,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: dune.withValues(alpha: 0.6),
        selectedForegroundColor: darkBrown,
        side: const BorderSide(color: duneLine),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: parchment,
      hintStyle: const TextStyle(color: mutedBrown),
      prefixIconColor: mutedBrown,
      suffixIconColor: mutedBrown,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: field(duneLine),
      enabledBorder: field(duneLine),
      focusedBorder: field(terracotta, 1.6),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: parchment,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0xFFC9B79F),
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: parchment,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: parchment,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(iconColor: terracotta),
    dividerTheme: const DividerThemeData(color: duneLine, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: darkBrown,
      contentTextStyle: const TextStyle(fontFamily: textFont, color: sand),
      actionTextColor: dune,
      shape: rounded14,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: terracotta,
      linearTrackColor: sandDeep,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: parchment,
      foregroundColor: terracottaDeep,
      elevation: 3,
      highlightElevation: 5,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: terracotta,
      selectionColor: dune.withValues(alpha: 0.5),
      selectionHandleColor: terracotta,
    ),
  );
}
