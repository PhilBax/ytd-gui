import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'services/update_service.dart';

class YtdApp extends ConsumerStatefulWidget {
  const YtdApp({super.key});

  @override
  ConsumerState<YtdApp> createState() => _YtdAppState();
}

class _YtdAppState extends ConsumerState<YtdApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    final updateService = ref.read(updateServiceProvider);
    final result = await updateService.checkYtdlpUpdate();
    if (result != null && mounted) {
      _showUpdateDialog(result);
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('yt-dlp Update Available'),
        content: Text(
          'A new version of yt-dlp is available.\n\n'
          'Current: ${info.current}\n'
          'Latest:  ${info.latest}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final updateService = ref.read(updateServiceProvider);
              await updateService.downloadYtdlp(info.latest);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YTD GUI',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    const red = Color(0xFFFF0000);
    const bg = Color(0xFF0F0F0F);
    const surface = Color(0xFF212121);
    const onSurface = Color(0xFFE0E0E0);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: red,
        secondary: red,
        surface: surface,
        onSurface: onSurface,
        error: Color(0xFFCF6679),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF424242)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: red, width: 2),
        ),
        hintStyle: const TextStyle(color: Color(0xFF757575)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: red),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFF303030)),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF303030)),
      iconTheme: const IconThemeData(color: Color(0xFFAAAAAA)),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: onSurface),
        bodySmall: TextStyle(color: Color(0xFFAAAAAA)),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surface),
    );
  }
}
