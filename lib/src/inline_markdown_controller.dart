import 'package:flutter/material.dart';

/// A simplified TextEditingController that only handles inline markdown
/// formatting: bold, italic, strikethrough, inline code, and links.
///
/// Unlike the old monolithic controller, this has no virtual newlines,
/// no ZWSP padding, and no block-level element handling (images, tables,
/// headings, code blocks are all separate block widgets now).
class InlineMarkdownController extends TextEditingController {
  InlineMarkdownController({super.text, this.onLinkTap});

  /// Called when a link is tapped.
  final void Function(String url)? onLinkTap;

  /// When true, show raw markdown syntax markers (**, *, ~~, `, [], etc).
  /// When false, hide markers and apply formatting styles.
  bool showSyntax = false;

  /// Link ranges for tap detection.
  final List<({int start, int end, String url})> _linkRanges = [];

  /// Looks up the URL at the given character offset.
  String? getLinkUrlAtOffset(int offset) {
    for (final ({int end, int start, String url}) range in _linkRanges) {
      if (offset >= range.start && offset < range.end) {
        return range.url;
      }
    }
    return null;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing, TextStyle? style,
  }) {
    _linkRanges.clear();
    style ??= const TextStyle();
    return _parseInline(text, style);
  }

  TextSpan _parseInline(String text, TextStyle defaultStyle) {
    final spans = <InlineSpan>[];
    final ranges = <_MatchRange>[];

    final patterns = <_InlinePattern>[
      // Bold **text**
      _InlinePattern(RegExp(r'(\*\*)(.+?)(\*\*)'), (m) => const TextStyle(fontWeight: FontWeight.bold)),
      // Bold __text__
      _InlinePattern(RegExp('(__)(.+?)(__)'), (m) => const TextStyle(fontWeight: FontWeight.bold)),
      // Italic *text*
      _InlinePattern(RegExp(r'(\*)(.+?)(\*)'), (m) => const TextStyle(fontStyle: FontStyle.italic)),
      // Italic _text_
      _InlinePattern(RegExp('(_)(.+?)(_)'), (m) => const TextStyle(fontStyle: FontStyle.italic)),
      // Strikethrough ~~text~~
      _InlinePattern(RegExp('(~~)(.+?)(~~)'), (m) => const TextStyle(decoration: TextDecoration.lineThrough)),
      // Inline code `text`
      _InlinePattern(
        RegExp('(`)([^`]+)(`)'),
        (m) => TextStyle(fontFamily: 'monospace', backgroundColor: Colors.grey.shade200.withValues(alpha: 0.5)),
      ),
      // Links [text](url)
      _InlinePattern(
        RegExp(r'(\[)([^\]]+)(\]\()([^\)]+)(\))'),
        (m) => const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
        isLink: true,
      ),
    ];

    for (final pattern in patterns) {
      for (final RegExpMatch match in pattern.exp.allMatches(text)) {
        final TextStyle rangeStyle = pattern.styleBuilder(match);
        final TextStyle combined = defaultStyle.merge(rangeStyle);
        final TextStyle hidden = combined.copyWith(fontSize: 0.0);
        final matchSpans = <InlineSpan>[];

        if (pattern.isLink) {
          // Groups: 1=[, 2=text, 3=](, 4=url, 5=)
          final String bracket = match.group(1)!;
          final String linkText = match.group(2)!;
          final String middle = match.group(3)!;
          final String url = match.group(4)!;
          final String closeParen = match.group(5)!;

          final int linkStart = match.start + bracket.length;
          final int linkEnd = linkStart + linkText.length;
          _linkRanges.add((start: linkStart, end: linkEnd, url: url));

          if (showSyntax) {
            matchSpans
              ..add(TextSpan(text: bracket, style: combined))
              ..add(TextSpan(text: linkText, style: combined))
              ..add(TextSpan(text: middle, style: combined))
              ..add(
                TextSpan(
                  text: url,
                  style: combined.copyWith(color: Colors.blue.shade300),
                ),
              )
              ..add(TextSpan(text: closeParen, style: combined));
          } else {
            matchSpans
              ..add(TextSpan(text: bracket, style: hidden))
              ..add(TextSpan(text: linkText, style: combined))
              ..add(TextSpan(text: middle, style: hidden))
              ..add(TextSpan(text: url, style: hidden))
              ..add(TextSpan(text: closeParen, style: hidden));
          }
        } else if (match.groupCount >= 3) {
          final String prefix = match.group(1)!;
          final String content = match.group(2)!;
          final String suffix = match.group(3)!;

          matchSpans.add(TextSpan(text: prefix, style: showSyntax ? combined : hidden));
          matchSpans.add(TextSpan(text: content, style: combined));
          matchSpans.add(TextSpan(text: suffix, style: showSyntax ? combined : hidden));
        } else {
          matchSpans.add(TextSpan(text: match.group(0), style: combined));
        }

        ranges.add(_MatchRange(match.start, match.end, matchSpans));
      }
    }

    // Sort by start, then longer match first
    ranges.sort((a, b) {
      final int c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return b.end.compareTo(a.end);
    });

    // Remove overlapping ranges
    final filtered = <_MatchRange>[];
    var lastEnd = 0;
    for (final r in ranges) {
      if (r.start >= lastEnd) {
        filtered.add(r);
        lastEnd = r.end;
      }
    }

    // Build span list
    var cursor = 0;
    for (final r in filtered) {
      if (r.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r.start), style: defaultStyle));
      }
      spans.addAll(r.spans);
      cursor = r.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: defaultStyle));
    }

    return TextSpan(style: defaultStyle, children: spans);
  }
}

class _InlinePattern {
  _InlinePattern(this.exp, this.styleBuilder, {this.isLink = false});
  final RegExp exp;
  final TextStyle Function(Match) styleBuilder;
  final bool isLink;
}

class _MatchRange {
  _MatchRange(this.start, this.end, this.spans);
  final int start;
  final int end;
  final List<InlineSpan> spans;
}
