import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/places_api.dart';
import '../../models/venue.dart';

/// Top-left map search: round button → inline search bar + results dropdown.
class MapLocationSearch extends StatefulWidget {
  const MapLocationSearch({
    super.key,
    required this.near,
    required this.onPlaceSelected,
    required this.rowTrailing,
    this.inViewSlot,
  });

  final LatLng near;
  final ValueChanged<Venue> onPlaceSelected;
  /// Filter / demo chips on the right of the top row.
  final Widget rowTrailing;
  /// Shown beside the search button when search is collapsed (e.g. in-view pill).
  final Widget? inViewSlot;

  @override
  State<MapLocationSearch> createState() => _MapLocationSearchState();
}

class _MapLocationSearchState extends State<MapLocationSearch>
    with SingleTickerProviderStateMixin {
  static const _searchRadiusMeters = 30000.0;
  static const _buttonSize = 48.0;

  final _api = PlacesApi();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  bool _open = false;
  bool _loading = false;
  bool _searched = false;
  List<Venue> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _anim.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    if (open) {
      _anim.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else {
      _anim.reverse();
      _focusNode.unfocus();
      _controller.clear();
      _results = [];
      _searched = false;
      _loading = false;
      _debounce?.cancel();
    }
  }

  void _onQueryChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  Future<void> _runSearch() async {
    final query = _controller.text;
    setState(() => _loading = true);
    final results = await _api.textSearch(
      query,
      near: widget.near,
      radiusMeters: _searchRadiusMeters,
    );
    if (!mounted || _controller.text != query) return;
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  void _pick(Venue venue) {
    widget.onPlaceSelected(venue);
    _setOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value.clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildTopLeft(t)),
                const SizedBox(width: 8),
                widget.rowTrailing,
              ],
            ),
            // Results slide down + fade in as the bar opens; collapse on close.
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: t,
                child: Opacity(
                  opacity: t,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildResultsPanel(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Cross-fades the round button into the search pill, which grows out from
  /// the button's footprint so the open/close reads as one smooth slide.
  Widget _buildTopLeft(double t) {
    return SizedBox(
      height: _buttonSize,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final full = constraints.maxWidth;
          final width = _buttonSize + (full - _buttonSize) * t;
          final buttonOpacity = (1 - t / 0.4).clamp(0.0, 1.0);
          final fieldOpacity = ((t - 0.3) / 0.7).clamp(0.0, 1.0);
          return Stack(
            children: [
              // Collapsed layer: search button + in-view pill, fades out first.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _open,
                  child: Opacity(
                    opacity: buttonOpacity,
                    child: _buildClosedRow(),
                  ),
                ),
              ),
              // Expanded layer: the pill grows left→right; content is laid out
              // at full width and clipped, so no overflow mid-animation.
              if (t > 0)
                IgnorePointer(
                  ignoring: !_open,
                  child: Opacity(
                    opacity: fieldOpacity,
                    child: _buildSearchField(width, full),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildClosedRow() {
    return Row(
      children: [
        _SearchIconButton(onTap: () => _setOpen(true)),
        if (widget.inViewSlot != null) ...[
          const SizedBox(width: 8),
          Expanded(child: widget.inViewSlot!),
        ],
      ],
    );
  }

  Widget _buildSearchField(double width, double contentWidth) {
    const pillRadius = BorderRadius.all(Radius.circular(999));

    return Container(
      width: width,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: pillRadius,
        border: Border.all(color: KerbColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33202124),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: contentWidth,
        maxWidth: contentWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.search_rounded, size: 20, color: KerbColors.ink300),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 34,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: KerbColors.pendingFill,
                  borderRadius: pillRadius,
                ),
                child: ClipRRect(
                  borderRadius: pillRadius,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: const InputDecorationTheme(
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                    child: Container(
                      height: 34,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.search,
                        onChanged: _onQueryChanged,
                        onSubmitted: (_) => _runSearch(),
                        style: const TextStyle(fontSize: 13, height: 1.2),
                        decoration: const InputDecoration(
                          hintText: 'Address, suburb…',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            color: KerbColors.ink600,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: 'Close search',
            onPressed: () => _setOpen(false),
            color: KerbColors.ink600,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsPanel() {
    if (Env.googlePlacesKey.isEmpty) {
      return const _ResultsCard(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Google Places key not configured — search is disabled in this build.',
            style: TextStyle(color: KerbColors.warn, fontSize: 13),
          ),
        ),
      );
    }

    if (_loading) {
      return const _ResultsCard(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: KerbColors.brand600,
              ),
            ),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      if (!_searched) return const SizedBox.shrink();
      return const _ResultsCard(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'No places found — try a street, suburb, or landmark.',
            style: TextStyle(fontSize: 13, color: KerbColors.ink600),
          ),
        ),
      );
    }

    return _ResultsCard(
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: KerbColors.line),
        itemBuilder: (context, i) {
          final venue = _results[i];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined, color: KerbColors.brand700),
            title: Text(
              venue.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: venue.address == null
                ? null
                : Text(
                    venue.address!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () => _pick(venue),
          );
        },
      ),
    );
  }
}

class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Search location',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: const Color(0x33202124),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.search_rounded, size: 22, color: KerbColors.ink600),
          ),
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: const Color(0x33202124),
      color: KerbColors.surface,
      borderRadius: BorderRadius.circular(KerbRadius.md),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.35,
        ),
        child: child,
      ),
    );
  }
}
