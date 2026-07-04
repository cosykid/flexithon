import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/venue.dart';
import '../map/map_providers.dart';
import 'new_report_controller.dart';
import 'venue_search_page.dart';

class NewReportFlow extends ConsumerStatefulWidget {
  const NewReportFlow({super.key});

  @override
  ConsumerState<NewReportFlow> createState() => _NewReportFlowState();
}

class _NewReportFlowState extends ConsumerState<NewReportFlow> {
  @override
  void initState() {
    super.initState();
    // Grab GPS immediately so the pin is ready by the time they scroll down.
    Future.microtask(
      () => ref.read(newReportControllerProvider.notifier).captureCurrentLocation(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newReportControllerProvider);
    final controller = ref.read(newReportControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Report a barrier')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _StepCard(
            number: 1,
            title: 'Photo of the barrier',
            done: state.photoBytes != null,
            child: _PhotoPicker(state: state, controller: controller),
          ),
          const SizedBox(height: 12),
          _StepCard(
            number: 2,
            title: 'Location',
            done: state.position != null,
            child: _LocationPicker(state: state, controller: controller),
          ),
          const SizedBox(height: 12),
          _StepCard(
            number: 3,
            title: 'Venue',
            optional: true,
            done: state.venue != null,
            child: _VenuePicker(state: state, controller: controller),
          ),
          const SizedBox(height: 12),
          _StepCard(
            number: 4,
            title: 'What makes it inaccessible?',
            done: state.description.trim().isNotEmpty,
            child: TextField(
              minLines: 3,
              maxLines: 6,
              onChanged: controller.setDescription,
              decoration: const InputDecoration(
                hintText:
                    'e.g. Entrance has three steps and no ramp; door is too narrow for a wheelchair…',
              ),
            ),
          ),
        ],
      ),
      // Sticky submit bar in the thumb zone.
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: KerbColors.surface,
            border: Border(top: BorderSide(color: KerbColors.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.error != null) ...[
                Text(
                  state.error!,
                  style: const TextStyle(
                    color: KerbColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                icon: state.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(state.submitting ? 'Submitting…' : 'Submit report'),
                onPressed: !state.canSubmit
                    ? null
                    : () async {
                        final reportId = await controller.submit();
                        if (reportId != null) {
                          // New report should show up in My Reports and (once
                          // classified) on the map without a manual refresh.
                          ref.invalidate(myReportsProvider);
                          ref.invalidate(mapPointsProvider);
                          if (context.mounted) {
                            Navigator.of(context).pop(reportId);
                          }
                        }
                      },
              ),
              const SizedBox(height: 8),
              Text(
                'Verified by AI before it appears on the map: your photo is '
                'checked and the venue\'s public accessibility claims are '
                'investigated.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numbered section card; the number flips to a check when the step is done.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.child,
    this.done = false,
    this.optional = false,
  });

  final int number;
  final String title;
  final Widget child;
  final bool done;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KerbColors.surface,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        border: Border.all(color: KerbColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? KerbColors.brand600 : KerbColors.brand100,
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white)
                    : Text(
                        '$number',
                        style: kerbDisplay(
                          size: 13,
                          color: KerbColors.brand700,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: kerbDisplay(size: 15.5, weight: FontWeight.w600)),
              ),
              if (optional)
                Text('Optional', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.state, required this.controller});

  final NewReportState state;
  final NewReportController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.photoBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(KerbRadius.sm),
            child: Image.memory(
              state.photoBytes!,
              height: 190,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera_rounded, size: 19),
                label: const Text('Camera'),
                onPressed: () => controller.pickPhoto(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_rounded, size: 19),
                label: const Text('Gallery'),
                onPressed: () => controller.pickPhoto(ImageSource.gallery),
              ),
            ),
          ],
        ),
        if (state.photoBytes == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'A photo lets the AI substantiate your report — reports without '
              'one stay unverified and off the map.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _LocationPicker extends StatelessWidget {
  const _LocationPicker({required this.state, required this.controller});

  final NewReportState state;
  final NewReportController controller;

  @override
  Widget build(BuildContext context) {
    final position = state.position;
    if (position == null) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.my_location_rounded, size: 19),
        label: const Text('Use my location'),
        onPressed: controller.captureCurrentLocation,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 170,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KerbRadius.sm),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: position,
                initialZoom: 17,
                onTap: (_, latLng) => controller.nudgePosition(latLng),
              ),
              children: [
                const KerbTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: position,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: KerbColors.brand600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Tap the map to fine-tune the pin.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _VenuePicker extends StatelessWidget {
  const _VenuePicker({required this.state, required this.controller});

  final NewReportState state;
  final NewReportController controller;

  @override
  Widget build(BuildContext context) {
    final venue = state.venue;
    if (venue != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: KerbColors.paper,
          borderRadius: BorderRadius.circular(KerbRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront_rounded,
                size: 20, color: KerbColors.brand700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (venue.address != null)
                    Text(
                      venue.address!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: 'Remove venue',
              onPressed: () => controller.setVenue(null),
            ),
          ],
        ),
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(Icons.storefront_rounded, size: 19),
      label: const Text('Tag a venue'),
      onPressed: state.position == null
          ? null
          : () async {
              final picked = await Navigator.of(context).push<Venue>(
                MaterialPageRoute(
                  builder: (_) => VenueSearchPage(near: state.position!),
                ),
              );
              if (picked != null) controller.setVenue(picked);
            },
    );
  }
}
