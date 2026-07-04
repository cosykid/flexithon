import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/places_api.dart';
import '../../models/venue.dart';

/// Search Google Places near a point; pops with the chosen Venue.
/// Used both for tagging a report to a venue and for the map search bar.
class VenueSearchPage extends StatefulWidget {
  const VenueSearchPage({
    super.key,
    required this.near,
    this.title = 'Tag a venue',
  });

  final LatLng near;
  final String title;

  @override
  State<VenueSearchPage> createState() => _VenueSearchPageState();
}

class _VenueSearchPageState extends State<VenueSearchPage> {
  final _api = PlacesApi();
  final _controller = TextEditingController();
  List<Venue> _results = [];
  bool _loading = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    final results = await _api.textSearch(_controller.text, near: widget.near);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search nearby venues…',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final venue = _results[i];
                return ListTile(
                  leading: const Icon(Icons.place),
                  title: Text(venue.name),
                  subtitle: venue.address == null ? null : Text(venue.address!),
                  onTap: () => Navigator.of(context).pop(venue),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
