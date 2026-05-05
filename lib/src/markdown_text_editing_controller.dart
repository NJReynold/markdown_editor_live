import 'package:flutter/material.dart';

class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text, this.onLinkTap, this.onImageTap, this.imageHeightLines = 5})
    : assert(imageHeightLines > 0, 'imageHeightLines must be positive') {
    _sourceText = super.text;
    // Add virtual newlines for image spacing on initial text
    _updateTextWithNewlines();
  }

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

  ///Stores table info for cell editing support.
  final List<_TableInfo> _tableInfos = [];

  /// The currently focused line number (0-indexed).
  /// When set, syntax markers are hidden on all other lines.
  int? _focusedLine;

  /// The source text without virtual newlines
  String _sourceText = '';

  /// Flag to prevent recursive text updates
  bool _isUpdatingText = false;

  int? get focusedLine => _focusedLine;

  /// Set the focused line and update text to inject/remove newlines
  set focusedLine(int? value) {
    if (_focusedLine != value) {
      _focusedLine = value;
      _updateTextWithNewlines();
      notifyListeners();
    }
  }

  void updateFocusedLineFromSelection() {
    if (selection.isValid && selection.baseOffset >= 0) {
      // Ensure _sourceText is up-to-date (defensive measure)
      if (_sourceText.isEmpty && super.text.isNotEmpty) {
        _sourceText = _removeVirtualNewlines(super.text);
      }
      // Map display offset to source offset first, then calculate line number from source text
      final int sourceOffset = _displayToSourceOffset(selection.baseOffset, super.text);
      focusedLine = _getLineNumber(sourceOffset, _sourceText);
    }
  }

  /// Looks up the URL at the given character offset.
  /// Returns null if no link exists at that offset.
  String? getLinkUrlAtOffset(int offset) {
    for (final ({int end, int start, String url}) range in _linkRanges) {
      if (offset >= range.start && offset < range.end) {
        return range.url;
      }
    }
    return null;
  }

  /// Maps a source text offset to a display text offset.
  /// The display text may contain virtual newline markers (\u200B\n)
  /// which are 2 display characters that represent 0 source characters.
  int _sourceToDisplayOffset(int sourceOffset, String displayText) {
    int displayOffset = 0;
    int sourcePos = 0;

    for (int i = 0; i < displayText.length && sourcePos < sourceOffset; i++) {
      if (displayText.startsWith(_virtualNewlineMarker, i)) {
        // Virtual newline marker - counts as 0 in source, 2 in display
        displayOffset += _virtualNewlineMarker.length;
        i += _virtualNewlineMarker.length - 1;
      } else {
        sourcePos++;
        displayOffset++;
      }
    }

    return displayOffset;
  }

  /// Maps a display text offset to a source text offset.
  /// Virtual newline markers in display text are skipped when counting source offset.
  int _displayToSourceOffset(int displayOffset, String displayText) {
    int sourceOffset = 0;

    for (int i = 0; i < displayOffset && i < displayText.length; i++) {
      if (displayText.startsWith(_virtualNewlineMarker, i)) {
        // Virtual newline marker - skip in source, advance past both chars
        i += _virtualNewlineMarker.length - 1;
      } else {
        sourceOffset++;
      }
    }

    return sourceOffset;
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
  Widget _buildImageWidget(String url, String altText, TextStyle style) {
    final double fontSize = style.fontSize ?? 16.0;

    return GestureDetector(
      onTap: onImageTap != null ? () => onImageTap!(url) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: SizedBox(height: fontSize * imageHeightLines * (style.height ?? 1.2), child: _buildImageWithSource(url, altText)),
      ),
    );
  }

  /// Builds the appropriate image source based on URL scheme.
  Widget _buildImageWithSource(String url, String altText) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(url, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => _buildImageError(altText));
    } else if (url.startsWith('asset://')) {
      return Image.asset(url.replaceFirst('asset://', ''), fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => _buildImageError(altText));
    } else {
      // Unknown scheme - show error placeholder directly
      return _buildImageError(altText.isNotEmpty ? altText : 'Unsupported URL: $url');
    }
  }

  /// Builds an error placeholder when image fails to load.
  Widget _buildImageError(String altText) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
      child: Text(altText.isNotEmpty ? altText : 'Image not found', style: const TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  // ============================================================
  // TABLE PARSING AND RENDERING
  // ============================================================

  /// Parses a matched table text into structured data.
  _TableData _parseTableStructure(String tableText) {
    final List<String> lines = tableText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length < 2) return _TableData([], [], []);

    final List<String> headers = _parseCells(lines[0]);
    final List<String> separatorCells = _parseCells(lines[1]);

    final List<TextAlign> alignments = separatorCells.map((cell) {
      final String trimmed = cell.trim();
      final bool leftAligned = trimmed.startsWith(':');
      final bool rightAligned = trimmed.endsWith(':');
      if (leftAligned && rightAligned) return TextAlign.center;
      if (rightAligned) return TextAlign.right;
      return TextAlign.left;
    }).toList();

    final rows = <List<String>>[];
    for (int i = 2; i < lines.length; i++) {
      rows.add(_parseCells(lines[i]));
    }

    return _TableData(headers, alignments, rows);
  }

  /// Splits a table row into individual cell texts.
  static List<String> _parseCells(String line) {
    String trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  /// Builds a rendered Table widget from parsed table data.
  Widget _buildTableWidget(_TableData tableData, int tableIndex, TextStyle style, BuildContext context) {
    final int numColumns = tableData.headers.length;

    return Padding(
      padding: const EdgeInsets.symmetric(),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade400),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: List.generate(numColumns, (col) {
              final String cellText = col < tableData.headers.length ? tableData.headers[col] : '';
              final TextAlign align = col < tableData.alignments.length ? tableData.alignments[col] : TextAlign.left;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  cellText,
                  style: style.copyWith(fontWeight: FontWeight.bold),
                  textAlign: align,
                ),
              );
            }),
          ),
          ...tableData.rows.asMap().entries.map((entry) {
            final List<String> row = entry.value;
            return TableRow(
              children: List.generate(numColumns, (col) {
                final String cellText = col < row.length ? row[col] : '';
                final TextAlign align = col < tableData.alignments.length ? tableData.alignments[col] : TextAlign.left;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(cellText, style: style, textAlign: align),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  /// Updates a specific cell in a table and returns the new source text.
  /// [tableIndex] identifies which table, [row] and [col] identify the cell.
  /// Row 0 is the header row.
  String updateTableCell(int tableIndex, int row, int col, String newValue) {
    if (tableIndex >= _tableInfos.length) return _sourceText;

    final _TableInfo info = _tableInfos[tableIndex];
    final int sourceStart = _displayToSourceOffset(info.displayStart, super.text);
    final int sourceEnd = _displayToSourceOffset(info.displayEnd, super.text);
    final String tableSource = _sourceText.substring(sourceStart, sourceEnd);
    final List<String> lines = tableSource.split('\n').where((l) => l.trim().isNotEmpty).toList();

    // row 0 = header (lines[0]), row 1+ = data rows (lines[2+])
    final int lineIdx = row == 0 ? 0 : row + 1; // +1 to skip separator
    if (lineIdx >= lines.length) return _sourceText;

    final List<String> cells = _parseCells(lines[lineIdx]);
    while (cells.length <= col) {
      cells.add('');
    }
    cells[col] = newValue;

    // Reconstruct the line
    final newLine = '| ${cells.join(' | ')} |';
    lines[lineIdx] = newLine;

    // Reconstruct table text, preserving trailing newline if present
    final String originalTableText = _sourceText.substring(sourceStart, sourceEnd);
    final trailingNewline = originalTableText.endsWith('\n') ? '\n' : '';
    final String newTableText = lines.join('\n') + trailingNewline;

    return _sourceText.substring(0, sourceStart) + newTableText + _sourceText.substring(sourceEnd);
  }

  /// Returns the table info list for external use.
  List<_TableInfo> get tableInfos => List.unmodifiable(_tableInfos);

  // ============================================================
  // NEWLINE INJECTION FOR IMAGE SPACING
  // ============================================================

  /// Pattern to match image syntax (with full groups for parsing)
  static final _imagePattern = RegExp(r'(!\[)([^\]]*)(\]\()([^)]+)(\))');

  /// Pattern to match markdown table blocks (header + separator + data rows)
  static final _tablePattern = RegExp(
    r'^(\|[^\n]+\|)[ \t]*\n(\|[ \t:]*-+[ \t:]*(?:\|[ \t:]*-+[ \t:]*)*\|)[ \t]*\n((?:\|[^\n]*\|[ \t]*(?:\n|$))*)',
    multiLine: true,
  );

  /// Pattern to match our virtual newlines (marked with special comment)
  /// We use zero-width space + newline to mark virtual newlines
  static const _virtualNewlineMarker = '\u200B\n';

  /// Update the actual text to include newlines around unfocused images
  void _updateTextWithNewlines() {
    if (_isUpdatingText) return;
    _isUpdatingText = true;

    try {
      _updateTextWithNewlinesInternal();
    } finally {
      _isUpdatingText = false;
    }
  }

  /// Internal method that performs the actual newline update logic.
  /// Must be called within an _isUpdatingText guard to prevent recursion.
  void _updateTextWithNewlinesInternal() {
    // @remind I believe the place where extra lines are added for images

    // First, clean any existing virtual newlines from the current text
    final String cleanText = _removeVirtualNewlines(super.text);

    // Store the clean source text
    _sourceText = cleanText;

    if (cleanText.isEmpty) {
      return;
    }

    // Determine which line range is "focused" (where we show raw syntax)
    // When _focusedLine is null, ALL images should have newlines (all rendered as widgets)
    // When _focusedLine is set, only images NOT on that line should have newlines
    (int, int)? focusedLineRange;
    if (_focusedLine != null) {
      focusedLineRange = _getLineRange(_focusedLine!, cleanText);
    }

    // Colect all image and table matches, then process in order
    final allMatches = <({int start, int end, String text, _PatternType type})>[];

    for (final RegExpMatch match in _imagePattern.allMatches(cleanText)) {
      allMatches.add(
        (
          start: match.start,
          end: match.end,
          text: match.group(0)!,
          type: _PatternType.image,
        ),
      );
    }

    for (final RegExpMatch match in _tablePattern.allMatches(cleanText)) {
      allMatches.add(
        (
          start: match.start,
          end: match.end,
          text: match.group(0)!,
          type: _PatternType.table,
        ),
      );
    }
    // Sort by start position to ensure correct processing order
    allMatches.sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer();
    int lastEnd = 0;

    for (final match in allMatches) {
      if (match.start < lastEnd) continue; // skip overlapping
      buffer.write(cleanText.substring(lastEnd, match.start));

      if (match.type == _PatternType.image) {
        final bool isOnFocusedLine = focusedLineRange != null && match.start >= focusedLineRange.$1 && match.start < focusedLineRange.$2;

        if (!isOnFocusedLine) {
          final int linesAbove = (imageHeightLines - 1) ~/ 2;
          if (linesAbove > 0) {
            buffer.write(_virtualNewlineMarker * linesAbove);
          }
          buffer.write(match.text);
          final int linesBelow = (imageHeightLines - 1) - linesAbove;
          if (linesBelow > 0) {
            buffer.write(_virtualNewlineMarker * linesBelow);
          }
        } else {
          buffer.write(match.text);
        }
      } else if (match.type == _PatternType.table) {
        // Check if focused line is inside the table
        final bool isInFocusedTable = focusedLineRange != null && match.start < focusedLineRange.$2 && match.end > focusedLineRange.$1;

        if (!isInFocusedTable) {
          // Table rendered as widget — add virtual newlines for spacing
          // Estimate height: count data lines in the table
          final int tableLineCount = match.text.split('\n').where((l) => l.trim().isNotEmpty).length;
          // Use roughly 1 virtual newline per table row for spacing
          final int linesAbove = (tableLineCount - 1) ~/ 2;
          final int linesBelow = (tableLineCount - 1) - linesAbove;
          print(linesAbove);
          print(linesBelow);
          if (linesAbove > 0) {
            buffer.write(_virtualNewlineMarker * linesAbove);
          }
          buffer.write(match.text);
          if (linesBelow > 0) {
            buffer.write(_virtualNewlineMarker * linesBelow);
          }
        } else {
          buffer.write(match.text);
        }
      }

      lastEnd = match.end;
    }

    // Add remaining text
    buffer.write(cleanText.substring(lastEnd));

    final newText = buffer.toString();

    if (super.text != newText) {
      // Preserve cursor position relative to source text
      final TextSelection oldSelection = selection;
      // Map selection from display to source offsets before text change
      final int sourceBase = _displayToSourceOffset(oldSelection.baseOffset, super.text);
      final int sourceExtent = _displayToSourceOffset(oldSelection.extentOffset, super.text);
      super.text = newText;
      // Restore selection with offsets mapped from source to display
      if (oldSelection.isValid) {
        final int newBase = _sourceToDisplayOffset(sourceBase, newText);
        final int newExtent = _sourceToDisplayOffset(sourceExtent, newText);
        selection = TextSelection(
          baseOffset: newBase.clamp(0, newText.length),
          extentOffset: newExtent.clamp(0, newText.length),
          affinity: oldSelection.affinity,
        );
      }
    }
  }

  /// Remove virtual newlines from text
  String _removeVirtualNewlines(String text) {
    return text.replaceAll(_virtualNewlineMarker, '');
  }

  /// Override text setter to update source text and add newlines for image spacing
  @override
  set text(String value) {
    if (_isUpdatingText) {
      super.text = value;
      return;
    }

    // Clean any virtual newlines from incoming text
    final String cleanValue = _removeVirtualNewlines(value);
    _sourceText = cleanValue;

    // Always update with newlines for image spacing, regardless of focus state
    _updateTextWithNewlines();
  }

  /// Override value setter to handle paste operations
  /// Flutter's TextField sets controller.value directly when pasting,
  /// bypassing the text setter. This ensures _sourceText stays synchronized.
  @override
  set value(TextEditingValue newValue) {
    if (_isUpdatingText) {
      super.value = newValue;
      return;
    }

    // Check if text has actually changed (selection-only changes should pass through)
    if (newValue.text == super.text) {
      // Selection-only change - pass through without processing
      super.value = newValue;
      return;
    }

    // Text has changed - clean virtual newlines and update source text
    final String cleanText = _removeVirtualNewlines(newValue.text);
    _sourceText = cleanText;

    // Map selection from display coordinates (in newValue.text) to source coordinates
    // This is critical because newValue.selection is relative to newValue.text which
    // contains virtual newlines, but we're about to set cleanText which has none.
    final int mappedSourceBase = _displayToSourceOffset(newValue.selection.baseOffset, newValue.text);
    final int mappedSourceExtent = _displayToSourceOffset(newValue.selection.extentOffset, newValue.text);

    // Update with cleaned text AND mapped selection (source coordinates)
    _isUpdatingText = true;
    try {
      final sourceSelection = TextSelection(
        baseOffset: mappedSourceBase.clamp(0, cleanText.length),
        extentOffset: mappedSourceExtent.clamp(0, cleanText.length),
        affinity: newValue.selection.affinity,
      );
      super.value = newValue.copyWith(text: cleanText, selection: sourceSelection);
      // Always add newlines for image spacing, regardless of focus state
      _updateTextWithNewlinesInternal();
    } finally {
      _isUpdatingText = false;
    }
  }

  /// Get the source text (without virtual newlines)
  String get sourceText => _sourceText;

  @override
  TextSpan buildTextSpan({required BuildContext context, required bool withComposing, TextStyle? style}) {
    // Clear link ranges on each rebuild
    _linkRanges.clear();
    style ??= const TextStyle();
    return _parseMarkdown(text, style, context);
  }

  TextSpan _parseMarkdown(String displayText, TextStyle defaultStyle, BuildContext context) {
    final List<InlineSpan> spans = [];

    // Calculate focused line range in SOURCE text coordinates
    // This is critical because _focusedLine is tracked in source coordinates,
    // and virtual newlines in displayText would cause offset mismatches
    (int start, int end)? focusedLineRangeSource;
    if (_focusedLine != null) {
      focusedLineRangeSource = _getLineRange(_focusedLine!, _sourceText);
    }

    // Pattern definitions
    final patterns = <_MarkdownPattern>[
      // Headers: show # only on focused line
      _MarkdownPattern(RegExp(r'^(#{1,6}\s+)(.*)$', multiLine: true), (match) {
        final int headingLevel = match.group(1)!.trim().length;
        final fontSizes = [28.0, 24.0, 20.0, 18.0, 16.0, 14.0];
        final double fontSize = fontSizes[headingLevel.clamp(1, 6) - 1];
        return TextStyle(fontWeight: FontWeight.bold, fontSize: fontSize, color: Colors.blueAccent);
      }, type: _PatternType.header),
      // Unordered List
      _MarkdownPattern(RegExp(r'^([ \t]*)([*+-])([ \t]+)', multiLine: true), (match) => const TextStyle(fontWeight: FontWeight.w500), type: _PatternType.list),
      // Ordered List
      _MarkdownPattern(RegExp(r'^([ \t]*)(\d+\.)([ \t]+)', multiLine: true), (match) => const TextStyle(fontWeight: FontWeight.w500), type: _PatternType.list),
      // Bold **text**
      _MarkdownPattern(RegExp(r'(\*\*)(.+?)(\*\*)'), (match) => const TextStyle(fontWeight: FontWeight.bold)),
      // Bold __text__
      _MarkdownPattern(RegExp('(__)(.+?)(__)'), (match) => const TextStyle(fontWeight: FontWeight.bold)),
      // Italic *text*
      _MarkdownPattern(RegExp(r'(\*)(.+?)(\*)'), (match) => const TextStyle(fontStyle: FontStyle.italic)),
      // Italic _text_
      _MarkdownPattern(RegExp('(_)(.+?)(_)'), (match) => const TextStyle(fontStyle: FontStyle.italic)),
      // Strikethrough ~~text~~
      _MarkdownPattern(RegExp('(~~)(.+?)(~~)'), (match) => const TextStyle(decoration: TextDecoration.lineThrough)),
      // Inline code `text`
      _MarkdownPattern(
        RegExp('(`)([^`]+)(`)'),
        (match) => TextStyle(fontFamily: 'monospace', backgroundColor: Colors.grey.shade200.withValues(alpha: 0.5)),
      ),
      // Block code ```text```
      _MarkdownPattern(
        RegExp(r'(```[^\n]*\n?)([\s\S]*?)(```)', multiLine: true),
        (match) => TextStyle(fontFamily: 'monospace', backgroundColor: Colors.grey.shade200.withValues(alpha: 0.5)),
        type: _PatternType.blockCode,
        priority: 3,
      ),
      // Links [text](url)
      _MarkdownPattern(
        RegExp(r'(\[)([^\]]+)(\]\()([^\)]+)(\))'),
        (match) => const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
        type: _PatternType.link,
        priority: 3,
      ),
      // Images ![alt text](url)
      _MarkdownPattern(_imagePattern, (match) => const TextStyle(), type: _PatternType.image),
      // Tables |header| ... |
      _MarkdownPattern(_tablePattern, (match) => const TextStyle(), type: _PatternType.table),
      // Thematic break
      _MarkdownPattern(
        RegExp(r'^ {0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})$', multiLine: true),
        (match) => const TextStyle(color: Colors.grey),
        type: _PatternType.thematicBreak,
        priority: 1,
      ),
      // Virtual newline pattern (to hide markers)
      _MarkdownPattern(RegExp(r'\u200B'), (match) => const TextStyle(fontSize: 0, color: Colors.transparent), type: _PatternType.virtualNewline, priority: 10),
    ];

    // Collect all matches
    final List<_MatchRange> ranges = [];

    for (final pattern in patterns) {
      for (final RegExpMatch match in pattern.exp.allMatches(displayText)) {
        // Convert display position to source position for accurate line comparison
        final int matchStartSource = _displayToSourceOffset(match.start, displayText);
        final bool isOnFocusedLine =
            focusedLineRangeSource != null && matchStartSource >= focusedLineRangeSource.$1 && matchStartSource < focusedLineRangeSource.$2;

        final TextStyle rangeStyle = pattern.styleBuilder(match);
        final List<InlineSpan> matchSpans = [];

        // TextStyle to start with (merging default + pattern style)
        final TextStyle combinedStyle = defaultStyle.merge(rangeStyle);
        // Style for hidden syntax (zero size)
        final TextStyle hiddenStyle = combinedStyle.copyWith(fontSize: 0.0);

        if (pattern.type == _PatternType.virtualNewline) {
          // Hide zero-width markers with zero-size text
          matchSpans.add(TextSpan(text: match.group(0), style: hiddenStyle));
        } else if (pattern.type == _PatternType.header) {
          // Group 1: Syntax (e.g. "# "), Group 2: Content
          final String syntax = match.group(1)!;
          final String content = match.group(2)!;

          matchSpans.add(TextSpan(text: syntax, style: isOnFocusedLine ? combinedStyle : hiddenStyle));
          matchSpans.add(TextSpan(text: content, style: combinedStyle));
        } else if (pattern.type == _PatternType.list) {
          // Group 1: Leading indent, Group 2: Bullet/Number, Group 3: Space
          final String indent = match.group(1)!;
          final String bulletOrNumber = match.group(2)!;
          final String space = match.group(3)!;

          matchSpans.add(TextSpan(text: indent, style: defaultStyle));

          if (isOnFocusedLine) {
            matchSpans.add(
              TextSpan(
                text: bulletOrNumber + space,
                style: combinedStyle.copyWith(color: Colors.blueAccent),
              ),
            );
          } else {
            final replacement = RegExp(r'^\d+\.$').hasMatch(bulletOrNumber) ? bulletOrNumber : '•';
            matchSpans.add(
              TextSpan(
                text: replacement + space,
                style: combinedStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            );
          }
        } else if (pattern.type == _PatternType.thematicBreak) {
          if (isOnFocusedLine) {
            matchSpans.add(
              TextSpan(
                text: match.group(0),
                style: combinedStyle.copyWith(color: Colors.grey),
              ),
            );
          } else {
            final int lineLength = match.group(0)!.length;
            final String lineChars = '─' * lineLength;
            matchSpans.add(
              TextSpan(
                text: lineChars,
                style: combinedStyle.copyWith(color: Colors.grey, letterSpacing: 0),
              ),
            );
          }
        } else if (pattern.type == _PatternType.link) {
          // Groups: 1=[, 2=text, 3=](, 4=url, 5=)
          final String bracket = match.group(1)!;
          final String linkText = match.group(2)!;
          final String middle = match.group(3)!;
          final String url = match.group(4)!;
          final String closeParen = match.group(5)!;

          final linkStyle = combinedStyle;

          // Store the link range for offset-based tap detection
          final int linkTextStart = match.start + bracket.length;
          final int linkTextEnd = linkTextStart + linkText.length;
          _linkRanges.add((start: linkTextStart, end: linkTextEnd, url: url));

          if (isOnFocusedLine) {
            matchSpans
              ..add(TextSpan(text: bracket, style: linkStyle))
              ..add(TextSpan(text: linkText, style: linkStyle))
              ..add(TextSpan(text: middle, style: linkStyle))
              ..add(
                TextSpan(
                  text: url,
                  style: linkStyle.copyWith(color: Colors.blue.shade300),
                ),
              )
              ..add(TextSpan(text: closeParen, style: linkStyle));
          } else {
            matchSpans
              ..add(TextSpan(text: bracket, style: hiddenStyle))
              ..add(TextSpan(text: linkText, style: linkStyle))
              ..add(TextSpan(text: middle, style: hiddenStyle))
              ..add(TextSpan(text: url, style: hiddenStyle))
              ..add(TextSpan(text: closeParen, style: hiddenStyle));
          }
        } else if (pattern.type == _PatternType.image) {
          // Groups: 1=![, 2=alt text, 3=](, 4=url, 5=)
          final String openingMarker = match.group(1)!;
          final String altText = match.group(2)!;
          final String bridge = match.group(3)!;
          final String url = match.group(4)!;
          final String closeParen = match.group(5)!;
          final int syntaxLength = match.group(0)!.length;

          if (isOnFocusedLine) {
            // On focused line: show full raw syntax for editing
            matchSpans
              ..add(TextSpan(text: openingMarker, style: combinedStyle))
              ..add(TextSpan(text: altText, style: combinedStyle))
              ..add(TextSpan(text: bridge, style: combinedStyle))
              ..add(
                TextSpan(
                  text: url,
                  style: combinedStyle.copyWith(color: Colors.blue.shade300),
                ),
              )
              ..add(TextSpan(text: closeParen, style: combinedStyle));
          } else {
            // On unfocused line: hide all syntax and show image widget
            // The newlines for spacing are already in the text

            matchSpans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _buildImageWidget(url, altText, combinedStyle)));

            // Fill remaining character positions with zero-width spaces (hidden)
            // WidgetSpan occupies 1 position, so we need (syntaxLength - 1) more
            final int zwspCount = syntaxLength - 1;
            if (zwspCount > 0) {
              matchSpans.add(TextSpan(text: '\u200B' * zwspCount, style: hiddenStyle));
            }
          }
        } else if (pattern.type == _PatternType.table) {
          final String tableText = match.group(0)!;
          // Check if the focused line falls anywhere within this table's range
          final int matchEndSource = _displayToSourceOffset(match.end, displayText);
          final bool isInFocusedTable =
              focusedLineRangeSource != null && matchStartSource < focusedLineRangeSource.$2 && matchEndSource > focusedLineRangeSource.$1;

          if (isInFocusedTable) {
            // Cursor is inside the table — show raw markdown with styled pipes
            // (inspired by markdown-inline-editor-vscode's reveal-on-cursor pattern)
            final TextStyle pipeStyle = combinedStyle.copyWith(color: Colors.grey.shade500);
            final TextStyle separatorStyle = combinedStyle.copyWith(color: Colors.grey.shade400);

            final List<String> lines = tableText.split('\n');
            for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
              if (lineIdx > 0) {
                matchSpans.add(TextSpan(text: '\n', style: combinedStyle));
              }
              final String line = lines[lineIdx];
              // Separator line (e.g. |---|---|)
              final bool isSeparator = RegExp(r'^\|?[\s\-:|]+\|?$').hasMatch(line.trim()) && line.contains('-');
              if (isSeparator) {
                matchSpans.add(TextSpan(text: line, style: separatorStyle));
              } else {
                // Header or data row — color the pipes, leave text as-is
                int pos = 0;
                while (pos < line.length) {
                  if (line[pos] == '|') {
                    matchSpans.add(TextSpan(text: '|', style: pipeStyle));
                    pos++;
                  } else {
                    int nextPipe = line.indexOf('|', pos);
                    if (nextPipe == -1) nextPipe = line.length;
                    final isHeader = lineIdx == 0;
                    final TextStyle cellStyle = isHeader ? combinedStyle.copyWith(fontWeight: FontWeight.bold) : combinedStyle;
                    matchSpans.add(TextSpan(text: line.substring(pos, nextPipe), style: cellStyle));
                    pos = nextPipe;
                  }
                }
              }
            }
          } else {
            // Cursor is outside — render as a pretty WidgetSpan table
            final _TableData tableData = _parseTableStructure(tableText);
            final int tableIndex = _tableInfos.length;
            _tableInfos.add(_TableInfo(displayStart: match.start, displayEnd: match.end, data: tableData));

            matchSpans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _buildTableWidget(tableData, tableIndex, combinedStyle, context)));

            final int tableSyntaxLength = tableText.length;
            final int tableZwspCount = tableSyntaxLength - 1;
            if (tableZwspCount > 0) {
              matchSpans.add(TextSpan(text: '\u200B' * tableZwspCount, style: hiddenStyle));
            }
          }
        } else if (pattern.type == _PatternType.blockCode) {
          // Block code: show ``` markers when cursor is anywhere inside the block
          final int matchEndSource = _displayToSourceOffset(match.end, displayText);
          final bool isInFocusedBlock =
              focusedLineRangeSource != null && matchStartSource < focusedLineRangeSource.$2 && matchEndSource > focusedLineRangeSource.$1;

          final String prefix = match.group(1)!;
          final String content = match.group(2)!;
          final String suffix = match.group(3)!;

          matchSpans.add(
            TextSpan(
              text: prefix,
              style: isInFocusedBlock ? combinedStyle : hiddenStyle,
            ),
          );
          matchSpans.add(TextSpan(text: content, style: combinedStyle));
          matchSpans.add(
            TextSpan(
              text: suffix,
              style: isInFocusedBlock ? combinedStyle : hiddenStyle,
            ),
          );
        } else if (pattern.type == _PatternType.inline) {
          if (match.groupCount >= 3) {
            final String prefix = match.group(1)!;
            final String content = match.group(2)!;
            final String suffix = match.group(3)!;

            matchSpans.add(TextSpan(text: prefix, style: isOnFocusedLine ? combinedStyle : hiddenStyle));
            matchSpans.add(TextSpan(text: content, style: combinedStyle));
            matchSpans.add(TextSpan(text: suffix, style: isOnFocusedLine ? combinedStyle : hiddenStyle));
          } else {
            matchSpans.add(TextSpan(text: match.group(0), style: combinedStyle));
          }
        }

        ranges.add(_MatchRange(match.start, match.end, matchSpans, pattern.priority));
      }
    }

    // Sort by start position, then by priority (higher first), then by length
    ranges.sort((a, b) {
      final int startCompare = a.start.compareTo(b.start);
      if (startCompare != 0) return startCompare;
      final int priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      final int lengthCompare = b.end.compareTo(a.end);
      return lengthCompare;
    });

    // Remove overlapping ranges (keep higher priority)
    final List<_MatchRange> filteredRanges = [];
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
        spans.add(TextSpan(text: displayText.substring(textCursor, range.start), style: defaultStyle));
      }

      spans.addAll(range.spans);
      textCursor = range.end;
    }

    // Add remaining text
    if (textCursor < displayText.length) {
      spans.add(TextSpan(text: displayText.substring(textCursor), style: defaultStyle));
    }

    return TextSpan(style: defaultStyle, children: spans);
  }
}

enum _PatternType { header, list, inline, blockCode, link, thematicBreak, image, table, virtualNewline }

class _MarkdownPattern {
  _MarkdownPattern(this.exp, this.styleBuilder, {this.type = _PatternType.inline, this.priority = 0});
  final RegExp exp;
  final TextStyle Function(Match match) styleBuilder;
  final _PatternType type;
  final int priority;
}

class _MatchRange {
  _MatchRange(this.start, this.end, this.spans, this.priority);
  final int start;
  final int end;
  final List<InlineSpan> spans;
  final int priority;
}

class _TableData {
  _TableData(this.headers, this.alignments, this.rows);
  final List<String> headers;
  final List<TextAlign> alignments;
  final List<List<String>> rows;
}

class _TableInfo {
  _TableInfo({required this.displayStart, required this.displayEnd, required this.data});
  final int displayStart;
  final int displayEnd;
  final _TableData data;
}
