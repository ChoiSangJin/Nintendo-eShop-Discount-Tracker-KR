import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/datasources/local_store.dart';
import 'presentation/controllers/game_list_controller.dart';
import 'presentation/screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await HiveLocalStore.open();
    runApp(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const TrackerApp(),
      ),
    );
  } on Object {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage_rounded, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      '기기 저장소를 열지 못했습니다. 저장 공간을 확인한 뒤 다시 시도해 주세요.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: main, child: const Text('다시 시도')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Switch 할인 트래커 KR',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko', 'KR'),
    supportedLocales: const [Locale('ko', 'KR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffe60012),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff7f6f2),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff7f6f2),
        foregroundColor: Color(0xff171a22),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const MainScreen(),
  );
}
