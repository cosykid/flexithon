import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/report.dart';
import 'map_providers.dart';

final verificationWatcherProvider =
    Provider<VerificationWatcher>((ref) => VerificationWatcher(ref));

/// Polls a just-submitted report until the AI pipeline classifies it, then
/// announces the outcome in a snackbar and refreshes the map + My Reports.
/// Polling (vs realtime) works identically on fake mode, local stack and
/// hosted Supabase — no channel setup, worth it at hackathon scale.
class VerificationWatcher {
  VerificationWatcher(this._ref);

  final Ref _ref;
  static const _interval = Duration(seconds: 3);
  static const _maxPolls = 40; // ~2 minutes, then give up quietly

  void watch(String reportId) {
    unawaited(_poll(reportId));
  }

  Future<void> _poll(String reportId) async {
    final repo = _ref.read(repositoryProvider);
    for (var i = 0; i < _maxPolls; i++) {
      await Future<void>.delayed(_interval);
      final Report? report;
      try {
        report = await repo.fetchReport(reportId);
      } catch (_) {
        continue; // transient network error — keep polling
      }
      if (report == null) return;
      if (report.status == ReportStatus.pending) continue;

      _ref.invalidate(myReportsProvider);
      _ref.invalidate(mapPointsProvider);
      _announce(report);
      return;
    }
  }

  void _announce(Report report) {
    final (icon, text, color) = switch (report.status) {
      ReportStatus.rejected => (
          Icons.block_rounded,
          'Report rejected — the photo didn\'t match the description.',
          KerbColors.ink300,
        ),
      _ => switch (report.tier) {
          ReportTier.substantiated => (
              Icons.report_rounded,
              'Verified: substantiated. It\'s on the map.',
              KerbColors.danger,
            ),
          ReportTier.partiallySubstantiated => (
              Icons.warning_rounded,
              'Verified: partially substantiated — the venue claims '
                  'accessibility, but your photo says otherwise.',
              KerbColors.warnBright,
            ),
          _ => (
              Icons.help_outline_rounded,
              'Report reviewed: unsubstantiated. Add a photo next time to '
                  'get it on the map.',
              KerbColors.ink300,
            ),
        },
    };

    kerbMessengerKey.currentState?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
