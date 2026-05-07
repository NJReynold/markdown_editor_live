import 'package:flutter/material.dart';

// ============================================================
// @remind BLOCK TYPES
// ============================================================

/// Base class for all document blocks.
sealed class Block {
  String toMarkdown();
}

/// A paragraph of text with inline markdown formatting.
class ParagraphBlock extends Block {
  ParagraphBlock(this.text);
  String text;

  @override
  String toMarkdown() => text;
}

/// A heading (H1–H6).
class HeadingBlock extends Block {
  HeadingBlock(this.level, this.text);
  int level;
  String text;

  @override
  String toMarkdown() => '${'#' * level} $text';
}

/// A single list item (ordered or unordered).
class ListItemBlock extends Block {
  ListItemBlock({
    required this.text,
    this.indent = '',
    this.marker = '-',
  });
  String indent;
  String marker; // e.g. "-", "*", "+", "1.", "2."
  String text;

  bool get isOrdered => RegExp(r'^\d+\.$').hasMatch(marker);

  @override
  String toMarkdown() => '$indent$marker $text';
}

/// A fenced code block.
class CodeBlock extends Block {
  CodeBlock({this.language = '', this.code = ''});
  String language;
  String code;

  @override
  String toMarkdown() {
    final String lang = language.isNotEmpty ? language : '';
    return '```$lang\n$code\n```';
  }
}

/// A table with headers, alignment, and data rows.
class TableBlock extends Block {
  TableBlock({
    required this.headers,
    required this.alignments,
    required this.rows,
  });
  List<String> headers;
  List<TextAlign> alignments;
  List<List<String>> rows;

  @override
  String toMarkdown() {
    final buffer = StringBuffer();
    // Header row
    buffer.write('| ${headers.join(' | ')} |');
    buffer.write('\n');
    // Separator row
    final seps = <String>[];
    for (final TextAlign align in alignments) {
      switch (align) {
        case TextAlign.center:
          seps.add(':---:');
        case TextAlign.right:
          seps.add('---:');
        default:
          seps.add('---');
      }
    }
    // Pad separators to match header count
    while (seps.length < headers.length) {
      seps.add('---');
    }
    buffer.write('| ${seps.join(' | ')} |');
    // Data rows
    for (final List<String> row in rows) {
      buffer.write('\n');
      final cells = List<String>.generate(
        headers.length,
        (i) => i < row.length ? row[i] : '',
      );
      buffer.write('| ${cells.join(' | ')} |');
    }
    return buffer.toString();
  }
}

/// An image on its own line.
class ImageBlock extends Block {
  ImageBlock({required this.url, this.altText = ''});
  String url;
  String altText;

  @override
  String toMarkdown() => '![$altText]($url)';
}

/// A thematic break (horizontal rule).
class ThematicBreakBlock extends Block {
  ThematicBreakBlock({this.rawText = '---'});
  final String rawText;

  @override
  String toMarkdown() => rawText;
}

// ============================================================
// @remind MARKDOWN PARSER
// ============================================================

class MarkdownParser {
  static final _headingRegExp = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _unorderedListRegExp = RegExp(r'^([ \t]*)([*+-])\s(.*)$');
  static final _orderedListRegExp = RegExp(r'^([ \t]*)(\d+\.)\s(.*)$');
  static final _thematicBreakRegExp = RegExp(r'^ {0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})$');
  static final _imageOnlyRegExp = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$');
  static final _tableSepRegExp = RegExp(
    r'^\|?[ \t:]*-+[ \t:]*(\|[ \t:]*-+[ \t:]*)*\|?$',
  );

  /// Parses a markdown string into a list of blocks.
  static List<Block> parse(String markdown) {
    final List<String> lines = markdown.split('\n');
    final blocks = <Block>[];
    var i = 0;
    final paragraphLines = <String>[];

    void flushParagraph() {
      if (paragraphLines.isNotEmpty) {
        blocks.add(ParagraphBlock(paragraphLines.join('\n')));
        paragraphLines.clear();
      }
    }

    while (i < lines.length) {
      final String line = lines[i];

      // Fenced code block
      if (line.trimLeft().startsWith('```')) {
        flushParagraph();
        final RegExpMatch? langMatch = RegExp(r'^```(.*)$').firstMatch(line.trimLeft());
        final String language = langMatch?.group(1)?.trim() ?? '';
        final codeLines = <String>[];
        i++;
        while (i < lines.length) {
          if (lines[i].trimLeft().startsWith('```')) {
            i++;
            break;
          }
          codeLines.add(lines[i]);
          i++;
        }
        blocks.add(CodeBlock(language: language, code: codeLines.join('\n')));
        continue;
      }

      // Table: check if this line + next line form a table header + separator
      if (line.trim().startsWith('|') && i + 1 < lines.length && _tableSepRegExp.hasMatch(lines[i + 1].trim())) {
        flushParagraph();
        final headerLine = line;
        final String sepLine = lines[i + 1];
        final dataLines = <String>[];
        i += 2;
        while (i < lines.length && lines[i].trim().startsWith('|') && lines[i].trim().contains('|')) {
          // Don't consume if it looks like a new table separator
          if (_tableSepRegExp.hasMatch(lines[i].trim())) break;
          dataLines.add(lines[i]);
          i++;
        }
        blocks.add(_parseTable(headerLine, sepLine, dataLines));
        continue;
      }

      // Blank line
      if (line.trim().isEmpty) {
        flushParagraph();
        i++;
        continue;
      }

      // Thematic break
      if (_thematicBreakRegExp.hasMatch(line)) {
        flushParagraph();
        blocks.add(ThematicBreakBlock(rawText: line));
        i++;
        continue;
      }

      // Heading
      final RegExpMatch? headingMatch = _headingRegExp.firstMatch(line);
      if (headingMatch != null) {
        flushParagraph();
        final int level = headingMatch.group(1)!.length;
        final String text = headingMatch.group(2)!;
        blocks.add(HeadingBlock(level, text));
        i++;
        continue;
      }

      // Image on its own line
      final RegExpMatch? imageMatch = _imageOnlyRegExp.firstMatch(line.trim());
      if (imageMatch != null) {
        flushParagraph();
        blocks.add(
          ImageBlock(
            altText: imageMatch.group(1)!,
            url: imageMatch.group(2)!,
          ),
        );
        i++;
        continue;
      }

      // Unordered list item
      final RegExpMatch? ulMatch = _unorderedListRegExp.firstMatch(line);
      if (ulMatch != null) {
        flushParagraph();
        blocks.add(
          ListItemBlock(
            indent: ulMatch.group(1)!,
            marker: ulMatch.group(2)!,
            text: ulMatch.group(3)!,
          ),
        );
        i++;
        continue;
      }

      // Ordered list item
      final RegExpMatch? olMatch = _orderedListRegExp.firstMatch(line);
      if (olMatch != null) {
        flushParagraph();
        blocks.add(
          ListItemBlock(
            indent: olMatch.group(1)!,
            marker: olMatch.group(2)!,
            text: olMatch.group(3)!,
          ),
        );
        i++;
        continue;
      }

      // Regular text → accumulate into paragraph
      paragraphLines.add(line);
      i++;
    }

    flushParagraph();
    return blocks;
  }

  static TableBlock _parseTable(
    String headerLine,
    String sepLine,
    List<String> dataLines,
  ) {
    final List<String> headers = _parseCells(headerLine);
    final List<String> sepCells = _parseCells(sepLine);
    final List<TextAlign> alignments = sepCells.map((cell) {
      final String trimmed = cell.trim();
      final bool left = trimmed.startsWith(':');
      final bool right = trimmed.endsWith(':');
      if (left && right) return TextAlign.center;
      if (right) return TextAlign.right;
      return TextAlign.left;
    }).toList();

    final List<List<String>> rows = dataLines.map(_parseCells).toList();
    return TableBlock(
      headers: headers,
      alignments: alignments,
      rows: rows,
    );
  }

  static List<String> _parseCells(String line) {
    String trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.split('|').map((c) => c.trim()).toList();
  }
}

// ============================================================
// @remind MARKDOWN SERIALIZER
// ============================================================

class MarkdownSerializer {
  /// Converts a list of blocks back into a markdown string.
  static String serialize(List<Block> blocks) {
    final buffer = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) {
        final Block prev = blocks[i - 1];
        final Block curr = blocks[i];
        // Consecutive list items use single newline
        if (prev is ListItemBlock && curr is ListItemBlock) {
          buffer.write('\n');
        } else {
          buffer.write('\n\n');
        }
      }
      buffer.write(blocks[i].toMarkdown());
    }
    return buffer.toString();
  }
}
