import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/places_api.dart';
import '../../models/venue.dart';

/// Search Google Places near the report position; pops with the chosen Venue.
/// Live search: results refresh as you type (debounced), sorted by Places'
/// own bias to the GPS position, each with its distance from you.
class VenueSearchPage extends StatefulWidget {
  const VenueSearchPage({super.key, required this.near});

  final LatLng near;

  @override
  State<VenueSearchPage> createState() => _VenueSearchPageState();
}

class _VenueSearchPageState extends State<VenueSearchPage> {
  final _api = PlacesApi();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Venue> _results = [];
  bool _loading = false;
  bool _searched = false;

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
    setState(() {}); // refresh the clear button
  }

  Future<void> _search() async {
    final query = _controller.text;
    setState(() => _loading = true);
    final results = await _api.textSearch(query, near: widget.near);
    // A newer query may have started while this one was in flight.
    if (!mounted || _controller.text != query) return;
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tag a venue')),
      body: Column(
        children: [
          if (Env.googlePlacesKey.isEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KerbColors.warnFill,
                borderRadius: BorderRadius.circular(KerbRadius.sm),
              ),
              child: const Text(
                'Google Places key not configured — venue search is disabled '
                'in this build.',
                style: TextStyle(color: KerbColors.warn, fontSize: 13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search nearby venues…',
                prefixIcon: const Icon(Icons.search, color: KerbColors.ink300),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        tooltip: 'Clear',
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _loading ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: const LinearProgressIndicator(
              color: KerbColors.brand600,
              backgroundColor: KerbColors.line,
              minHeight: 2,
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      if (_searched && !_loading) {
        return const KerbEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No venues found',
          caption: 'Try a shorter name — results are biased to venues '
              'within a few hundred metres of your pin.',
        );
      }
      return const KerbEmptyState(
        icon: Icons.storefront_rounded,
        title: 'Find the venue you\'re at',
        caption: 'Type a name — “cafe”, “library”, “station” — and pick '
            'the right one. Tagging helps the AI check the venue\'s '
            'public accessibility claims.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _VenueTile(
        venue: _results[i],
        distanceMeters: _distanceMeters(widget.near, _results[i].position),
        onTap: () => Navigator.of(context).pop(_results[i]),
      ),
    );
  }
}

class _VenueTile extends StatelessWidget {
  const _VenueTile({
    required this.venue,
    required this.distanceMeters,
    required this.onTap,
  });

  final Venue venue;
  final double distanceMeters;
  final VoidCallback onTap;

  String get _distanceLabel => distanceMeters < 1000
      ? '${distanceMeters.round()} m'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KerbColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KerbRadius.md),
        side: const BorderSide(color: KerbColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KerbRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: KerbColors.brand100,
                  borderRadius: BorderRadius.circular(KerbRadius.sm),
                ),
                child: const Icon(Icons.storefront_rounded,
                    size: 22, color: KerbColors.brand700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (venue.address != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        venue.address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _distanceLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: KerbColors.ink600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Haversine distance in metres — close enough for "how far is this venue".
double _distanceMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.latitude * math.pi / 180) *
          math.cos(b.latitude * math.pi / 180) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}
