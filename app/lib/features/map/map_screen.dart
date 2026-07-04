import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/map_point.dart';
import '../new_report/new_report_flow.dart';
import '../report_detail/report_detail_sheet.dart';
import 'barriers_list_sheet.dart';
import 'cluster.dart';
import 'map_providers.dart';
import 'map_style.dart';
import 'marker_icons.dart';
import 'tier_filter_chips.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _sydney = CameraPosition(
    target: LatLng(-33.8988, 151.2093),
    zoom: 12,
  );

  GoogleMapController? _controller;
  KerbMarkerIcons? _icons;
  Timer? _debounce;
  double _zoom = _sydney.zoom;
  Set<Marker> _markers = const {};
  int _markerBuild = 0;
  bool _myLocationEnabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _icons ??= KerbMarkerIcons(MediaQuery.devicePixelRatioOf(context));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _scheduleViewportFetch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final controller = _controller;
      if (!mounted || controller == null) return;
      final bounds = await controller.getVisibleRegion();
      if (!mounted) return;
      ref.read(mapBboxProvider.notifier).state = bboxOf(bounds);
    });
  }

  /// Re-cluster the current points and paint them as native markers.
  /// Async because bitmaps render lazily; a generation counter drops stale
  /// builds when the camera or data moves on.
  Future<void> _rebuildMarkers() async {
    final icons = _icons;
    if (icons == null) return;
    final points = ref.read(mapPointsProvider).valueOrNull ?? const <MapPoint>[];
    final generation = ++_markerBuild;
    final clusters = clusterMapPoints(points, _zoom);

    final markers = <Marker>{};
    for (final cluster in clusters) {
      if (cluster.count == 1) {
        final point = cluster.points.first;
        markers.add(Marker(
          markerId: MarkerId(point.locationId),
          position: point.position,
          icon: await icons.pin(point.tier),
          anchor: const Offset(0.5, 1),
          consumeTapEvents: true,
          onTap: () => showReportDetailSheet(context, point),
        ));
      } else {
        markers.add(Marker(
          markerId: MarkerId(
            'cluster-${cluster.position.latitude}-${cluster.position.longitude}',
          ),
          position: cluster.position,
          icon: await icons.cluster(cluster.count, cluster.redFraction),
          anchor: const Offset(0.5, 0.5),
          consumeTapEvents: true,
          onTap: () => _controller?.animateCamera(
            CameraUpdate.newLatLngZoom(
              cluster.position,
              math.min(_zoom + 2.5, 19),
            ),
          ),
        ));
      }
    }

    if (!mounted || generation != _markerBuild) return;
    setState(() => _markers = markers);
  }

  Future<void> _goToMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      // Blue dot only after consent, so the first frame never asks.
      setState(() => _myLocationEnabled = true);
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
      );
    } catch (_) {
      // No location plugin on this platform (web/desktop trial) — stay put.
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(mapPointsProvider);
    ref.listen(mapPointsProvider, (_, __) => _rebuildMarkers());

    return Scaffold(
      backgroundColor: KerbColors.paper,
      body: Stack(
        children: [
          if (mapsSupported)
            GoogleMap(
              initialCameraPosition: _sydney,
              style: kerbMapStyle,
              markers: _markers,
              myLocationEnabled: _myLocationEnabled,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              tiltGesturesEnabled: false,
              // Keeps the Google logo clear of the floating nav bar.
              padding: const EdgeInsets.only(bottom: 88),
              onMapCreated: (controller) {
                _controller = controller;
                _scheduleViewportFetch();
              },
              onCameraMove: (position) => _zoom = position.zoom,
              onCameraIdle: () {
                _scheduleViewportFetch();
                _rebuildMarkers();
              },
            )
          else
            const KerbEmptyState(
              icon: Icons.map_rounded,
              title: 'Map preview unavailable',
              caption: 'Google Maps has no desktop runtime — '
                  'run the trial in Chrome (flutter run -d chrome).',
            ),
          // Top chrome: brand chip + tier filters, floating over the map.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _BrandChip(),
                      if (ref.watch(useFakeProvider)) ...[
                        const SizedBox(width: 8),
                        const _DemoDataChip(),
                      ],
                      const Spacer(),
                      IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: points.isLoading ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const KerbFloatingPill(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: KerbColors.brand600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const TierFilterChips(),
                  const SizedBox(height: 10),
                  _InViewPill(
                    points: points.valueOrNull ?? const [],
                    onTap: () => showBarriersListSheet(
                      context,
                      points.valueOrNull ?? const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom-right action stack, kept above the floating nav bar.
          Positioned(
            right: 16,
            bottom: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _RoundIconButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'My location',
                  onTap: _goToMyLocation,
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'report',
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: const Text('Report barrier'),
                  onPressed: () async {
                    final submitted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const NewReportFlow()),
                    );
                    if (submitted == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report submitted — verifying with AI…'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "N barriers in view" — doubles as the entry to the accessible list view
/// of everything the markers show.
class _InViewPill extends StatelessWidget {
  const _InViewPill({required this.points, required this.onTap});

  final List<MapPoint> points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: points.isEmpty
          ? const SizedBox.shrink()
          : Semantics(
              button: true,
              label: '${points.length} barriers in view, open list',
              child: GestureDetector(
                onTap: onTap,
                child: KerbFloatingPill(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.format_list_bulleted_rounded,
                          size: 16, color: KerbColors.brand700),
                      const SizedBox(width: 6),
                      Text(
                        '${points.length} barrier${points.length == 1 ? '' : 's'} in view',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: KerbColors.ink900,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more_rounded,
                          size: 16, color: KerbColors.ink600),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Shown when the app booted on fake data (USE_FAKE or Supabase
/// unconfigured/unreachable) so demo pins aren't mistaken for live reports.
class _DemoDataChip extends StatelessWidget {
  const _DemoDataChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: KerbColors.warnFill,
        borderRadius: BorderRadius.circular(999),
        boxShadow: KerbShadows.subtle,
      ),
      child: const Text(
        'Demo data',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: KerbColors.warn,
        ),
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip();

  @override
  Widget build(BuildContext context) {
    return KerbFloatingPill(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: KerbColors.brand600,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.accessible_forward_rounded,
                size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text('AccessMap', style: kerbDisplay(size: 16)),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x2210222A),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: KerbColors.ink900),
          ),
        ),
      ),
    );
  }
}
