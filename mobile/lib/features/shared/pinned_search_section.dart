import 'package:flutter/material.dart';
import 'package:sticky_headers/sticky_headers.dart';

/// Keeps a section's search controls at the top while its results scroll.
/// The header stops sticking when this section's content ends.
class PinnedSearchSection extends StatelessWidget {
  const PinnedSearchSection({
    super.key,
    required this.search,
    required this.results,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.backgroundColor,
  });

  final Widget search;
  final Widget results;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final color = backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    return StickyHeaderBuilder(
      builder: (context, stuckAmount) => Material(
        color: color,
        elevation: stuckAmount > 0 ? 2 : 0,
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: search),
        ),
      ),
      content: results,
    );
  }
}
