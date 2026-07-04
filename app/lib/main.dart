import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'core/ui.dart';
import 'features/map/map_screen.dart';
import 'features/my_reports/my_reports_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.useFake) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    // Anonymous auth: enough for RLS (role `authenticated`); device-scoped.
    if (Supabase.instance.client.auth.currentSession == null) {
      await Supabase.instance.client.auth.signInAnonymously();
    }
  }

  runApp(const ProviderScope(child: AccessMapApp()));
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
      scaffoldMessengerKey: kerbMessengerKey,
      // Desktop trial runs inside a 9:19.5 phone frame so the mobile-first
      // layout is seen as designed.
      builder: !_isDesktop
          ? null
          : (context, child) => ColoredBox(
                color: KerbColors.frame,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 412, maxHeight: 892),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: child!,
                    ),
                  ),
                ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [MapScreen(), MyReportsScreen()],
      ),
      bottomNavigationBar: _KerbNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Floating pill navigation: two destinations, animated brand-tinted
/// selection, hovering above the content so the map runs edge to edge.
class _KerbNavBar extends StatelessWidget {
  const _KerbNavBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: KerbColors.line),
          boxShadow: KerbShadows.soft,
        ),
        child: Row(
          children: [
            _NavItem(
              icon: Icons.map_rounded,
              label: 'Map',
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
            _NavItem(
              icon: Icons.fact_check_rounded,
              label: 'My reports',
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? KerbColors.brand100 : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? KerbColors.brand700 : KerbColors.ink600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      // Weight stays constant so selection doesn't reflow text.
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? KerbColors.brand700 : KerbColors.ink600,
                      ),
                    ),
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
