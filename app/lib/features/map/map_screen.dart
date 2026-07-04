import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/map_point.dart';
import '../../models/venue.dart';
import '../new_report/new_report_flow.dart';
import '../new_report/venue_search_page.dart';
import '../report_detail/report_detail_sheet.dart';
import 'map_providers.dart';
import 'onboarding_sheet.dart';
import 'tier_filter_chips.dart';
import 'verification_watcher.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _sydney = LatLng(-33.8988, 151.2093);

  final _mapController = MapController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowOnboarding(context);
    });
  }

  Future<void> _searchPlaces() async {
    final picked = await Navigator.of(context).push<Venue>(
      MaterialPageRoute(
        builder: (_) => VenueSearchPage(
          near: _mapController.camera.center,
          title: 'Search places',
        ),
      ),
    );
    if (picked != null) {
      _mapController.move(picked.position, 16.5);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _scheduleViewportFetch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(mapBboxProvider.notifier).state =
          bboxOf(_mapController.camera.visibleBounds);
    });
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
      _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
    } catch (_) {
      // No location plugin on this platform (desktop trial) — stay put.
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = ref.watch(mapPointsProvider);

    return Scaffold(
      backgroundColor: KerbColors.paper,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _sydney,
              initialZoom: 12,
              onMapReady: _scheduleViewportFetch,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd ||
                    event is MapEventFlingAnimationEnd ||
                    event is MapEventDoubleTapZoomEnd ||
                    event is MapEventScrollWheelZoom) {
                  _scheduleViewportFetch();
                }
              },
            ),
            children: [
              const KerbTileLayer(),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 60,
                  size: const Size(60, 60),
                  // No translate animation on split/merge — pins and
                  // clusters fade in on mount instead (KerbFadeIn).
                  animationsOptions: const AnimationsOptions(
                    zoom: Duration.zero,
                    fitBound: Duration(milliseconds: 400),
                    centerMarker: Duration(milliseconds: 400),
                    spiderfy: Duration(milliseconds: 300),
                  ),
                  markers: [
                    for (final point in points.valueOrNull ?? <MapPoint>[])
                      _buildPin(point),
                  ],
                  builder: (context, markers) => KerbCluster(markers: markers),
                ),
              ),
            ],
          ),
          const Positioned(left: 16, bottom: 96, child: KerbAttributionPill()),
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
                      const Spacer(),
                      _RoundIconButton(
                        icon: Icons.search_rounded,
                        tooltip: 'Search places',
                        onTap: _searchPlaces,
                      ),
                      const SizedBox(width: 8),
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
                    final reportId = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const NewReportFlow()),
                    );
                    if (reportId != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Report submitted — verifying with AI…'),
                        ),
                      );
                      ref.read(verificationWatcherProvider).watch(reportId);
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

  Marker _buildPin(MapPoint point) {
    return TierMarker(
      key: ValueKey(point.locationId),
      point: point.position,
      tier: point.tier,
      child: KerbFadeIn(
        child: Semantics(
          button: true,
          label:
              '${point.name ?? 'Reported barrier'}, ${TierStyle.label(point.tier)}, ${point.reportCount} reports',
          child: GestureDetector(
            onTap: () => showReportDetailSheet(context, point),
            child: KerbPin(tier: point.tier),
          ),
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
