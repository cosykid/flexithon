import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'features/map/map_providers.dart';
import 'features/map/map_screen.dart';
import 'features/my_reports/my_reports_screen.dart';
import 'features/new_report/new_report_flow.dart';

/// Placeholder or missing Supabase config counts as unconfigured — boot on
/// demo data instead of throwing before the first frame (white screen).
bool get _supabaseConfigured =>
    Env.supabaseUrl.startsWith('https://') &&
    !Env.supabaseUrl.contains('YOUR-REF') &&
    Env.supabaseAnonKey.isNotEmpty &&
    Env.supabaseAnonKey != 'YOUR-ANON-KEY';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var useFake = Env.useFake || !_supabaseConfigured;
  if (!useFake) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
      );
      // Anonymous auth: enough for RLS (role `authenticated`); device-scoped.
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.signInAnonymously();
      }
    } catch (e) {
      // Unreachable backend / anonymous sign-ins disabled — demo data beats
      // a blank page.
      debugPrint('Supabase init failed, falling back to demo data: $e');
      useFake = true;
    }
  }

  runApp(ProviderScope(
    overrides: [useFakeProvider.overrideWithValue(useFake)],
    child: const AccessMapApp(),
  ));
}

class AccessMapApp extends StatelessWidget {
  const AccessMapApp({super.key});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AccessMap',
      theme: buildTheme(),
      // Wide-screen trials (Chrome / desktop) run inside a 9:19.5 phone frame
      // so the mobile-first layout is seen as designed. Narrow windows and
      // real phones get the app edge to edge.
      builder: !_isDesktop && !kIsWeb
          ? null
          : (context, child) => LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 700) return child!;
                  return ColoredBox(
                    color: KerbColors.frame,
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 412, maxHeight: 892),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: child!,
                        ),
                      ),
                    ),
                  );
                },
              ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// "Report" is a nav action, not a tab — it pushes the flow full-screen
  /// (Google Maps "Contribute" pattern) so no FAB covers the map.
  Future<void> _openReportFlow() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewReportFlow()),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted — verifying with AI…'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [MapScreen(), MyReportsScreen()],
      ),
      // Flat, full-width Google Maps-style navigation: white bar, grey
      // hairline on top, blue pill indicator behind the selected icon.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: KerbColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _index == 0 ? 0 : 2,
          onDestinationSelected: (i) {
            if (i == 1) {
              _openReportFlow();
              return;
            }
            setState(() => _index = i == 0 ? 0 : 1);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline_rounded),
              selectedIcon: Icon(Icons.add_circle_rounded),
              label: 'Report',
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check_rounded),
              label: 'My reports',
            ),
          ],
        ),
      ),
    );
  }
}
