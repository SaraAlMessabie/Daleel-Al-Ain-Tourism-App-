import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/home_shell.dart';
import 'screens/quiz_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The bundled fonts are open source (SIL Open Font License); list them on
  // the "About Daleel" licences page.
  LicenseRegistry.addLicense(() async* {
    for (final font in ['ReemKufi', 'IBMPlexSansArabic']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });

  // Keep the image cache small so the app does not hold many big photos in RAM.
  PaintingBinding.instance.imageCache
    ..maximumSize = 60
    ..maximumSizeBytes = 60 << 20; // 60 MB

  final state = AppState();
  try {
    await state.load(); // opens the database and reads saved preferences
  } catch (e, st) {
    // Show the real problem on screen instead of a blank crash.
    debugPrint('Startup error: $e\n$st');
    runApp(_StartupError('$e'));
    return;
  }
  runApp(ChangeNotifierProvider.value(value: state, child: const DaleelApp()));
}

class DaleelApp extends StatelessWidget {
  const DaleelApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'Daleel',
      debugShowCheckedModeBanner: false,
      theme: daleelTheme(),
      locale: Locale(s.language), // 'ar' automatically switches the app to right-to-left
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // First launch -> quiz. After the quiz is saved -> the main tabs.
      home: s.quizDone ? const HomeShell() : const QuizScreen(),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Daleel could not start:\n\n$message'),
            ),
          ),
        ),
      );
}
