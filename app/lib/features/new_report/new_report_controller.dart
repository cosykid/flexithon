import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/env.dart';
import '../../data/reports_repository.dart';
import '../../models/venue.dart';
import '../map/map_providers.dart';

class NewReportState {
  final Uint8List? photoBytes;
  final LatLng? position;
  final Venue? venue;
  final String description;
  final bool submitting;
  final String? error;

  const NewReportState({
    this.photoBytes,
    this.position,
    this.venue,
    this.description = '',
    this.submitting = false,
    this.error,
  });

  // Photo is mandatory: verification can't substantiate a report without
  // one, so a photoless submission is a guaranteed dead end.
  bool get canSubmit =>
      photoBytes != null &&
      position != null &&
      description.trim().isNotEmpty &&
      !submitting;

  NewReportState copyWith({
    Uint8List? photoBytes,
    LatLng? position,
    Venue? venue,
    bool clearVenue = false,
    String? description,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) {
    return NewReportState(
      photoBytes: photoBytes ?? this.photoBytes,
      position: position ?? this.position,
      venue: clearVenue ? null : (venue ?? this.venue),
      description: description ?? this.description,
      submitting: submitting ?? this.submitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class NewReportController extends StateNotifier<NewReportState> {
  NewReportController(this._repo) : super(const NewReportState());

  final ReportsRepository _repo;
  final _picker = ImagePicker();

  static const _fallbackPosition = LatLng(-33.8988, 151.2093); // Sydney

  Future<void> pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      var out = bytes;
      try {
        // Downscale before upload: vision endpoints cap request bodies and
        // base64 inflates by a third. ~1024px/q80 lands around 150-300 KB.
        out = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: 1024,
          minHeight: 1024,
          quality: 80,
          format: CompressFormat.jpeg,
        );
      } catch (_) {
        // No compressor on this platform (desktop) — upload the original.
      }
      state = state.copyWith(photoBytes: out, clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'Could not pick a photo: $e');
    }
  }

  Future<void> captureCurrentLocation() async {
    if (Env.useFake) {
      state = state.copyWith(position: _fallbackPosition, clearError: true);
      return;
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(error: 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      state = state.copyWith(
        position: LatLng(pos.latitude, pos.longitude),
        clearError: true,
      );
    } catch (_) {
      // Fix timed out or GPS unavailable — a stale fix still beats the
      // city-centre default for pinning a barrier.
      Position? last;
      try {
        last = await Geolocator.getLastKnownPosition();
      } catch (_) {
        // Not supported on this platform (web).
      }
      if (last != null) {
        state = state.copyWith(
          position: LatLng(last.latitude, last.longitude),
          error: 'GPS is slow — using your last known position, '
              'drag the pin if it looks off.',
        );
        return;
      }
      // Desktop trial, airplane mode. Give the user a pin they can drag
      // rather than a dead end — but say so loudly.
      state = state.copyWith(
        position: _fallbackPosition,
        error: 'Couldn\'t read GPS — pin set to a default location, '
            'move it to the barrier before submitting.',
      );
    }
  }

  void nudgePosition(LatLng position) =>
      state = state.copyWith(position: position);

  void setVenue(Venue? venue) => state = venue == null
      ? state.copyWith(clearVenue: true)
      : state.copyWith(venue: venue);

  void setDescription(String description) =>
      state = state.copyWith(description: description);

  /// Returns the new report id on success, null on failure.
  Future<String?> submit() async {
    if (!state.canSubmit) return null;
    state = state.copyWith(submitting: true, clearError: true);
    try {
      return await _repo.submitReport(ReportDraft(
        photoBytes: state.photoBytes,
        position: state.position!,
        venue: state.venue,
        description: state.description.trim(),
      ));
    } catch (e) {
      state = state.copyWith(submitting: false, error: 'Submit failed: $e');
      return null;
    }
  }
}

final newReportControllerProvider = StateNotifierProvider.autoDispose<
    NewReportController, NewReportState>(
  (ref) => NewReportController(ref.watch(repositoryProvider)),
);
