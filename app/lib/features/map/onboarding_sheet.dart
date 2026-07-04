import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

const _seenKey = 'kerb_onboarded_v1';

/// One-time explainer of the report → verify → tier flow. The red/amber
/// semantics aren't self-evident; this is the 20-second version.
Future<void> maybeShowOnboarding(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_seenKey) ?? false) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _OnboardingSheet(),
  );
  await prefs.setBool(_seenKey, true);
}

class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome to AccessMap', style: kerbDisplay(size: 22)),
            const SizedBox(height: 4),
            Text(
              'Barriers, mapped and verified.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            const _Step(
              icon: Icons.add_a_photo_rounded,
              color: KerbColors.brand600,
              fill: KerbColors.brand100,
              title: 'Report a barrier',
              body:
                  'Stairs with no ramp, broken lift, doorway too narrow — snap '
                  'a photo and pin it.',
            ),
            const _Step(
              icon: Icons.auto_awesome_rounded,
              color: KerbColors.brand600,
              fill: KerbColors.brand100,
              title: 'AI verifies it',
              body:
                  'The photo is checked and the venue\'s public accessibility '
                  'claims are investigated online.',
            ),
            const _Step(
              icon: Icons.report_rounded,
              color: KerbColors.danger,
              fill: KerbColors.dangerFill,
              title: 'Red pin: substantiated',
              body: 'Photo confirms the barrier and nothing online disputes it.',
            ),
            const _Step(
              icon: Icons.warning_rounded,
              color: KerbColors.warn,
              fill: KerbColors.warnFill,
              title: 'Amber pin: contested',
              body:
                  'Photos show a barrier, but the venue claims to be '
                  'accessible. Five amber reports turn it red.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.color,
    required this.fill,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final Color fill;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(KerbRadius.sm),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: kerbDisplay(size: 14.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
