import 'package:flutter/material.dart';

class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({
    super.text,
    this.onLinkTap,
    this.onImageTap,
    this.imageHeightLines = 5,
  });

  /// Called when a link is tapped. Receives the URL as a string.
  final void Function(String url)? onLinkTap;

  /// Called when an image is tapped. Receives the URL as a string.
  final void Function(String url)? onImageTap;

  /// The height of inline images in lines of text.
  /// The actual height is calculated as: fontSize * imageHeightLines.
  /// Defaults to 5 lines.
  final int imageHeightLines;

  /// Stores link ranges for offset-based tap detection.
  /// Each entry contains (start, end, url).
  final List<({int start, int end, String url})> _linkRanges = [];

  /// The currently focused line number (0-indexed).
  /// When set, syntax markers are hidden on all other lines.
  int? _focusedLine;

  int? get focusedLine => _focusedLine;

  set focusedLine(int? value) {
    if (_focusedLine != value) {
      _focusedLine = value;
      notifyListeners();
    }
  }

  void updateFocusedLineFromSelection() {
    if (selection.isValid && selection.baseOffset >= 0) {
      focusedLine = _getLineNumber(selection.baseOffset, text);
    }
  }

  /// Looks up the URL at the given character offset.
  /// Returns null if no link exists at that offset.
  String? getLinkUrlAtOffset(int offset) {
    for (final range in _linkRanges) {
      if (offset >= range.start && offset < range.end) {
        return range.url;
      }
    }
    return null;
  }

  int _getLineNumber(int offset, String text) {
    int line = 0;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
      }
    }
    return line;
  }

  (int start, int end) _getLineRange(int lineNumber, String text) {
    int currentLine = 0;
    int lineStart = 0;

    for (int i = 0; i < text.length; i++) {
      if (currentLine == lineNumber) {
        int lineEnd = i;
        while (lineEnd < text.length && text[lineEnd] != '\n') {
          lineEnd++;
        }
        return (lineStart, lineEnd);
      }
      if (text[i] == '\n') {
        currentLine++;
        lineStart = i + 1;
      }
    }

    if (currentLine == lineNumber) {
      return (lineStart, text.length);
    }

    return (0, 0);
  }

  /// Builds an image widget for rendering inline images.
  /// Includes vertical padding for visual spacing without affecting line layout.
  Widget _buildImageWidget(String url, String altText, TextStyle style) {
    final fontSize = style.fontSize?.toDouble() ?? 16.0;
    final verticalPadding = fontSize * (imageHeightLines - 1) / 2;
    
    return GestureDetector(
      onTap: onImageTap != null ? () => onImageTap!(url) : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 4.0,
          vertical: verticalPadding,
        ),
        child: SizedBox(
          height: fontSize,
          child: _buildImageWithSource(url, altText),
        ),
      ),
    );
  }

  /// Builds the appropriate image source based on URL scheme.
  Widget _buildImageWithSource(String url, String altText) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildImageError(altText),
      );
    } else if (url.startsWith('asset://')) {
      return Image.asset(
        url.replaceFirst('asset://', ''),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildImageError(altText),
      );
    } else {
      // For file paths or other sources, try network as fallback
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildImageError(altText),
      );
    }
  }

  /// Builds an error placeholder when image fails to load.
  Widget _buildImageError(String altText) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        altText.isNotEmpty ? altText : 'Image not found',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Clear link ranges on each rebuild
    _linkRanges.clear();
    style ??= const TextStyle();
    return _parseMarkdown(text, style, context);
  }

  TextSpan _parseMarkdown(
    String text,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    final List<InlineSpan> spans = [];

    // Calculate focused line range in SOURCE text
    (int start, int end)? focusedLineRange;
    if (_focusedLine != null) {
      focusedLineRange = _getLineRange(_focusedLine!, text);
    }

    // Pattern definitions
    final patterns = <_MarkdownPattern>[
      // Headers: show # only on focused line
      _MarkdownPattern(RegExp(r'^(#{1,6}\s+)(.*)$', multiLine: true), (match) {
        final headingLevel = match.group(1)!.trim().length;
        final fontSizes = [28.0, 24.0, 20.0, 18.0, 16.0, 14.0];
        final fontSize = fontSizes[headingLevel.clamp(1, 6) - 1];
        return TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          color: Colors.blueAccent,
        );
      }, type: _PatternType.header),
      // Unordered List
      _MarkdownPattern(
        RegExp(r'^([ \t]*)([*+-])([ \t]+)', multiLine: true),
        (match) => const TextStyle(fontWeight: FontWeight.w500),
        type: _PatternType.list,
      ),
      // Ordered List
      _MarkdownPattern(
        RegExp(r'^([ \t]*)(\d+\.)([ \t]+)', multiLine: true),
        (match) => const TextStyle(fontWeight: FontWeight.w500),
        type: _PatternType.list,
      ),
      // Bold **text**
      _MarkdownPattern(
        RegExp(r'(\*\*)(.+?)(\*\*)'),
        (match) => const TextStyle(fontWeight: FontWeight.bold),
        type: _PatternType.inline,
      ),
      // Bold __text__
      _MarkdownPattern(
        RegExp(r'(__)(.+?)(__)'),
        (match) => const TextStyle(fontWeight: FontWeight.bold),
        type: _PatternType.inline,
      ),
      // Italic *text*
      _MarkdownPattern(
        RegExp(r'(\*)(.+?)(\*)'),
        (match) => const TextStyle(fontStyle: FontStyle.italic),
        type: _PatternType.inline,
      ),
      // Italic _text_
      _MarkdownPattern(
        RegExp(r'(_)(.+?)(_)'),
        (match) => const TextStyle(fontStyle: FontStyle.italic),
        type: _PatternType.inline,
      ),
      // Strikethrough ~~text~~
      _MarkdownPattern(
        RegExp(r'(~~)(.+?)(~~)'),
        (match) => const TextStyle(decoration: TextDecoration.lineThrough),
        type: _PatternType.inline,
      ),
      // Inline code `text`
      _MarkdownPattern(
        RegExp(r'(`)([^`]+)(`)'),
        (match) => TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey.shade200.withValues(alpha: 0.5),
        ),
        type: _PatternType.inline,
      ),
      // Block code ```text```
      _MarkdownPattern(
        RegExp(r'(```)([\s\S]*?)(```)'),
        (match) => TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey.shade200.withValues(alpha: 0.5),
        ),
        type: _PatternType.inline,
      ),
      // Links [text](url)
      _MarkdownPattern(
        RegExp(r'(\[)([^\]]+)(\]\()([^\)]+)(\))'),
        (match) => const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        type: _PatternType.link,
      ),
      // Images ![alt text](url)
      _MarkdownPattern(
        RegExp(r'(!\[)([^\]]*)(\]\()([^\)]+)(\))'),
        (match) => const TextStyle(),
        type: _PatternType.image,
      ),
      // Thematic break
      _MarkdownPattern(
        RegExp(
          r'^ {0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})$',
          multiLine: true,
        ),
        (match) => const TextStyle(color: Colors.grey),
        type: _PatternType.thematicBreak,
        priority: 1,
      ),
    ];

    // Collect all matches
    List<_MatchRange> ranges = [];

    for (final pattern in patterns) {
      for (final match in pattern.exp.allMatches(text)) {
        final isOnFocusedLine =
            focusedLineRange != null &&
            match.start >= focusedLineRange.$1 &&
            match.start < focusedLineRange.$2;

        final rangeStyle = pattern.styleBuilder(match);
        final List<InlineSpan> matchSpans = [];

        // TextStyle to start with (merging default + pattern style)
        final combinedStyle = defaultStyle.merge(rangeStyle);
        // Style for hidden syntax (zero size)
        final hiddenStyle = combinedStyle.copyWith(fontSize: 0.0);

        if (pattern.type == _PatternType.header) {
          // Group 1: Syntax (e.g. "# "), Group 2: Content
          final syntax = match.group(1)!;
          final content = match.group(2)!;

          matchSpans.add(
            TextSpan(
              text: syntax,
              style: isOnFocusedLine || _focusedLine == null
                  ? combinedStyle
                  : hiddenStyle,
            ),
          );
          matchSpans.add(TextSpan(text: content, style: combinedStyle));
        } else if (pattern.type == _PatternType.list) {
          // Group 1: Leading indent, Group 2: Bullet/Number, Group 3: Space
          final indent = match.group(1)!;
          final bulletOrNumber = match.group(2)!;
          final space = match.group(3)!;

          matchSpans.add(TextSpan(text: indent, style: defaultStyle));

          if (isOnFocusedLine || _focusedLine == null) {
            matchSpans.add(
              TextSpan(
                text: bulletOrNumber + space,
                style: combinedStyle.copyWith(color: Colors.blueAccent),
              ),
            );
          } else {
            final replacement = RegExp(r'^\d+\.$').hasMatch(bulletOrNumber)
                ? bulletOrNumber
                : '•';
            matchSpans.add(
              TextSpan(
                text: replacement + space,
                style: combinedStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            );
          }
        } else if (pattern.type == _PatternType.thematicBreak) {
          if (isOnFocusedLine || _focusedLine == null) {
            matchSpans.add(
              TextSpan(
                text: match.group(0),
                style: combinedStyle.copyWith(color: Colors.grey),
              ),
            );
          } else {
            final lineLength = match.group(0)!.length;
            final lineChars = '─' * lineLength;
            matchSpans.add(
              TextSpan(
                text: lineChars,
                style: combinedStyle.copyWith(
                  color: Colors.grey,
                  letterSpacing: 0,
                ),
              ),
            );
          }
        } else if (pattern.type == _PatternType.link) {
          // Groups: 1=[, 2=text, 3=](, 4=url, 5=)
          final bracket = match.group(1)!;
          final linkText = match.group(2)!;
          final middle = match.group(3)!;
          final url = match.group(4)!;
          final closeParen = match.group(5)!;

          final linkStyle = combinedStyle;

          // Store the link range for offset-based tap detection
          // The link text starts after '[' and ends before ']('
          final linkTextStart = match.start + bracket.length;
          final linkTextEnd = linkTextStart + linkText.length;
          _linkRanges.add((start: linkTextStart, end: linkTextEnd, url: url));

          if (isOnFocusedLine || _focusedLine == null) {
            matchSpans.add(TextSpan(text: bracket, style: linkStyle));
            matchSpans.add(TextSpan(text: linkText, style: linkStyle));
            matchSpans.add(TextSpan(text: middle, style: linkStyle));
            matchSpans.add(
              TextSpan(
                text: url,
                style: linkStyle.copyWith(color: Colors.blue.shade300),
              ),
            );
            matchSpans.add(TextSpan(text: closeParen, style: linkStyle));
          } else {
            matchSpans.add(TextSpan(text: bracket, style: hiddenStyle));
            matchSpans.add(TextSpan(text: linkText, style: linkStyle));
            matchSpans.add(TextSpan(text: middle, style: hiddenStyle));
            matchSpans.add(TextSpan(text: url, style: hiddenStyle));
            matchSpans.add(TextSpan(text: closeParen, style: hiddenStyle));
          }
        } else if (pattern.type == _PatternType.image) {
          // Groups: 1=![, 2=alt text, 3=](, 4=url, 5=)
          final openingMarker = match.group(1)!;
          final altText = match.group(2)!;
          final bridge = match.group(3)!;
          final url = match.group(4)!;
          final closeParen = match.group(5)!;
          final int syntaxLength = match.group(0)!.length;

          if (isOnFocusedLine || _focusedLine == null) {
            // On focused line: show raw syntax (hide markers with fontSize: 0, show alt text normally)
            matchSpans.add(TextSpan(text: openingMarker, style: hiddenStyle));
            matchSpans.add(TextSpan(text: altText, style: combinedStyle));
            matchSpans.add(TextSpan(text: bridge, style: hiddenStyle));
            matchSpans.add(
              TextSpan(
                text: url,
                style: combinedStyle.copyWith(color: Colors.blue.shade300),
              ),
            );
            matchSpans.add(TextSpan(text: closeParen, style: hiddenStyle));
          } else {
            // On unfocused line: hide all syntax and show image widget
            // Strategy: WidgetSpan occupies 1 text position, so we need (syntaxLength - 1)
            // zero-width spaces to maintain correct cursor positioning.
            
            // Add the image widget with built-in vertical padding
            matchSpans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _buildImageWidget(url, altText, combinedStyle),
              ),
            );
            
            // Fill remaining character positions with zero-width spaces (hidden)
            // WidgetSpan occupies 1 position, so we need (syntaxLength - 1) more
            // to match the source text length exactly.
            final int zwspCount = syntaxLength - 1;
            if (zwspCount > 0) {
              matchSpans.add(TextSpan(text: '\u200B' * zwspCount, style: hiddenStyle));
            }
          }
        } else if (pattern.type == _PatternType.inline) {
          if (match.groupCount >= 3) {
            final prefix = match.group(1)!;
            final content = match.group(2)!;
            final suffix = match.group(3)!;

            matchSpans.add(
              TextSpan(
                text: prefix,
                style: isOnFocusedLine || _focusedLine == null
                    ? combinedStyle
                    : hiddenStyle,
              ),
            );
            matchSpans.add(TextSpan(text: content, style: combinedStyle));
            matchSpans.add(
              TextSpan(
                text: suffix,
                style: isOnFocusedLine || _focusedLine == null
                    ? combinedStyle
                    : hiddenStyle,
              ),
            );
          } else {
            matchSpans.add(
              TextSpan(text: match.group(0), style: combinedStyle),
            );
          }
        }

        ranges.add(
          _MatchRange(match.start, match.end, matchSpans, pattern.priority),
        );
      }
    }

    // Sort by start position, then by length (longer matches first)
    ranges.sort((a, b) {
      final startCompare = a.start.compareTo(b.start);
      if (startCompare != 0) return startCompare;
      final lengthCompare = b.end.compareTo(a.end);
      if (lengthCompare != 0) return lengthCompare;
      return b.priority.compareTo(a.priority);
    });

    // Remove overlapping ranges
    List<_MatchRange> filteredRanges = [];
    int lastEnd = 0;
    for (final range in ranges) {
      if (range.start >= lastEnd) {
        filteredRanges.add(range);
        lastEnd = range.end;
      }
    }

    // Build final spans
    int textCursor = 0;

    for (final range in filteredRanges) {
      if (range.start > textCursor) {
        spans.add(
          TextSpan(
            text: text.substring(textCursor, range.start),
            style: defaultStyle,
          ),
        );
      }

      spans.addAll(range.spans);
      textCursor = range.end;
    }

    // Add remaining text
    if (textCursor < text.length) {
      spans.add(
        TextSpan(text: text.substring(textCursor), style: defaultStyle),
      );
    }

    return TextSpan(style: defaultStyle, children: spans);
  }
}

enum _PatternType { header, list, inline, link, thematicBreak, image }

class _MarkdownPattern {
  final RegExp exp;
  final TextStyle Function(Match match) styleBuilder;
  final _PatternType type;
  final int priority;

  _MarkdownPattern(
    this.exp,
    this.styleBuilder, {
    this.type = _PatternType.inline,
    this.priority = 0,
  });
}

class _MatchRange {
  final int start;
  final int end;
  final List<InlineSpan> spans;
  final int priority;

  _MatchRange(this.start, this.end, this.spans, this.priority);
}
