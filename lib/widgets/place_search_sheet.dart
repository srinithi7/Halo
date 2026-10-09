import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/place_search_service.dart';
import '../theme/app_theme.dart';

/// Search sheet for jumping the SafeWalk map to a place.
///
/// [localResults] is whatever the app already knows about locally (safe
/// spots, communities); those are ranked instantly and work offline. Free
/// text is additionally sent to OpenStreetMap Nominatim in release builds.
class PlaceSearchSheet extends StatefulWidget {
  const PlaceSearchSheet({
    super.key,
    required this.localResults,
    required this.onSelect,
    this.bias,
    this.title = 'Search for a place',
  });

  final List<PlaceResult> Function() localResults;
  final ValueChanged<PlaceResult> onSelect;
  final PlaceResult? bias;
  final String title;

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _searching = false;
  bool _didSearch = false;

  @override
  void initState() {
    super.initState();
    _results = widget.localResults();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final term = _controller.text.trim();
    if (!mounted) return;
    setState(() {
      _searching = term.isNotEmpty;
      _didSearch = term.isNotEmpty;
    });

    final results = await PlaceSearchService.search(
      term,
      localResults: widget.localResults(),
      bias: widget.bias?.point,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _results = widget.localResults();
      _didSearch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _clear, child: const Text('Clear')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Area, landmark or address',
                  hintStyle: const TextStyle(color: textMuted2, fontSize: 15),
                  prefixIcon: const Icon(LucideIcons.search, color: textMuted),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentGold,
                            ),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: bgSurface3,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(buttonRadius),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _didSearch
                              ? 'No places matched that search.'
                              : 'Start typing to search safe spots, '
                                  'communities and OpenStreetMap places.',
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: spacingPadding,
                        vertical: 4,
                      ),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: spacingSmallGap),
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return _PlaceResultTile(
                          result: result,
                          onTap: () => widget.onSelect(result),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceResultTile extends StatelessWidget {
  const _PlaceResultTile({required this.result, required this.onTap});

  final PlaceResult result;
  final VoidCallback onTap;

  IconData get _icon {
    switch (result.kind) {
      case PlaceResultKind.safeSpot:
        return LucideIcons.shieldCheck;
      case PlaceResultKind.community:
        return LucideIcons.users;
      case PlaceResultKind.place:
        return LucideIcons.mapPin;
    }
  }

  Color get _color {
    switch (result.kind) {
      case PlaceResultKind.safeSpot:
        return colorGreen;
      case PlaceResultKind.community:
        return accentPurple;
      case PlaceResultKind.place:
        return accentGold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: bgSurface2,
      child: ListTile(
        leading: Icon(_icon, color: _color),
        title: Text(
          result.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: result.subtitle.isEmpty
            ? null
            : Text(
                result.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: textMuted, fontSize: 12),
              ),
        trailing: const Icon(
          LucideIcons.arrowUpRight,
          size: 16,
          color: textMuted2,
        ),
        onTap: onTap,
      ),
    );
  }
}
