import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import 'engine.dart';

/// New name with only the changed part in the accent color, the rest dimmed.
/// Port of diffAnnotated() in MainActivity.kt.
InlineSpan diffSpans(
    String oldName, String newName, Color base, Color changed) {
  var pre = 0;
  while (pre < oldName.length &&
      pre < newName.length &&
      oldName[pre] == newName[pre]) {
    pre++;
  }
  var suf = 0;
  while (suf < oldName.length - pre &&
      suf < newName.length - pre &&
      oldName[oldName.length - 1 - suf] == newName[newName.length - 1 - suf]) {
    suf++;
  }
  return TextSpan(children: [
    TextSpan(
      text: newName.substring(0, pre),
      style: TextStyle(color: base),
    ),
    TextSpan(
      text: newName.substring(pre, newName.length - suf),
      style: TextStyle(color: changed, fontWeight: FontWeight.bold),
    ),
    TextSpan(
      text: newName.substring(newName.length - suf),
      style: TextStyle(color: base),
    ),
  ]);
}

/// 56×84 poster thumbnail with disk/memory cache (5s timeouts in native
/// PosterImage; cached_network_image handles it here).
class PosterThumb extends StatelessWidget {
  final String url;
  const PosterThumb(this.url, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 84,
        color: scheme.surfaceContainerHighest,
        child: url.isEmpty
            ? Icon(Icons.movie, color: scheme.onSurfaceVariant)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) =>
                    Icon(Icons.movie, color: scheme.onSurfaceVariant),
              ),
      ),
    );
  }
}

/// TMDB search results as a vertical list (same as the native v3.4 build):
/// thumb + name + year·type + 2-line overview, selected highlighted.
class SearchResultList extends StatelessWidget {
  final List<TmdbResult> results;
  final int? selectedId;
  final bool isMovie;
  final void Function(TmdbResult) onPick;

  const SearchResultList({
    super.key,
    required this.results,
    required this.selectedId,
    required this.isMovie,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: results.map((res) {
        final selected = selectedId == res.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => onPick(res),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    PosterThumb(res.poster),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            res.name,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : null,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${res.year} · ${isMovie ? '电影' : '剧集'}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (res.overview.isNotEmpty)
                            Text(
                              res.overview,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle,
                          color: scheme.primary, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Compact single-line input with a rounded border (port of CompactInput).
class CompactInput extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final bool numeric;
  final double height;
  final VoidCallback? onSearch;

  const CompactInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder = '',
    this.numeric = false,
    this.height = 42,
    this.onSearch,
  });

  @override
  State<CompactInput> createState() => _CompactInputState();
}

class _CompactInputState extends State<CompactInput> {
  late final TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(CompactInput old) {
    super.didUpdateWidget(old);
    if (widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: TextField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          keyboardType:
              widget.numeric ? TextInputType.number : TextInputType.text,
          textInputAction: widget.onSearch != null
              ? TextInputAction.search
              : TextInputAction.done,
          onSubmitted: (_) => widget.onSearch?.call(),
          style: Theme.of(context).textTheme.bodyMedium,
          cursorColor: scheme.primary,
          decoration: InputDecoration(
            hintText: widget.placeholder.isEmpty ? null : widget.placeholder,
            hintStyle: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            filled: true,
            fillColor: scheme.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _focused ? scheme.primary : scheme.outline,
                width: _focused ? 1.5 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _focused ? scheme.primary : scheme.outline,
                width: _focused ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small labeled input (port of LabeledInput).
class LabeledInput extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final bool numeric;

  const LabeledInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        CompactInput(
          value: value,
          onChanged: onChanged,
          numeric: numeric,
        ),
      ],
    );
  }
}

/// shields.io-style badge (port of ShieldBadge).
class ShieldBadge extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const ShieldBadge(this.label, this.value, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: const Color(0xFF2F3B4C),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Colors.white),
                ),
              ),
              Container(
                color: const Color(0xFF0B57D0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
