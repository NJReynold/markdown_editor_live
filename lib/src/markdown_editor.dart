import 'package:flutter/material.dart';

import 'package:markdown_editor_live/src/block_widgets.dart';
import 'package:markdown_editor_live/src/document_model.dart';

/// A block-level markdown editor that renders each content type as its own
/// editable widget. Tables have per-cell TextFields, headings show/hide `#`
/// markers on focus, code blocks show/hide fences, etc.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    this.initialValue,
    this.onChanged,
    this.onLinkTap,
    this.onImageTap,
    this.style,
    this.decoration,
    this.useSoftTabs = true,
    this.tabWidth = 2,
    this.imageHeightLines = 5,
  });

  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final void Function(String url)? onLinkTap;
  final void Function(String url)? onImageTap;
  final TextStyle? style;
  final InputDecoration? decoration;
  final bool useSoftTabs;
  final int tabWidth;
  final int imageHeightLines;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late List<Block> _blocks;
  late List<FocusNode> _focusNodes;
  late List<GlobalKey> _blockKeys;
  bool _hasSelection = false;

  @override
  void initState() {
    super.initState();
    _blocks = MarkdownParser.parse(widget.initialValue ?? '');
    if (_blocks.isEmpty) {
      _blocks.add(ParagraphBlock(''));
    }
    _focusNodes = List.generate(_blocks.length, (_) => FocusNode());
    _blockKeys = List.generate(_blocks.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    for (final FocusNode fn in _focusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() {
    final String markdown = MarkdownSerializer.serialize(_blocks);
    widget.onChanged?.call(markdown);
  }

  // ----------------------------------------------------------
  // Block text changes
  // ----------------------------------------------------------

  void _onBlockTextChanged(int index, String text) {
    final Block block = _blocks[index];
    switch (block) {
      case ParagraphBlock():
        block.text = text;
      case HeadingBlock():
        block.text = text;
      case ListItemBlock():
        block.text = text;
      case CodeBlock():
        block.code = text;
      default:
        break;
    }
    _notifyChanged();
  }

  void _onTableCellChanged(int blockIndex, int row, int col, String text) {
    final Block block = _blocks[blockIndex];
    if (block is! TableBlock) return;
    if (row == 0) {
      while (block.headers.length <= col) {
        block.headers.add('');
      }
      block.headers[col] = text;
    } else {
      final int dataRow = row - 1;
      while (block.rows.length <= dataRow) {
        block.rows.add(List.filled(block.headers.length, ''));
      }
      while (block.rows[dataRow].length <= col) {
        block.rows[dataRow].add('');
      }
      block.rows[dataRow][col] = text;
    }
    _notifyChanged();
  }

  // ----------------------------------------------------------
  // Block delete (merge with previous)
  // ----------------------------------------------------------

  void _onBlockDelete(int index) {
    if (index <= 0) return;

    setState(() {
      final Block current = _blocks[index];
      final Block previous = _blocks[index - 1];

      final String? currentText = _getBlockText(current);
      final String? previousText = _getBlockText(previous);

      if (currentText != null && previousText != null) {
        // Both text-bearing: merge into previous
        if (previous is HeadingBlock) {
          _blocks[index - 1] = ParagraphBlock(
            previous.toMarkdown() + currentText,
          );
        } else {
          _setBlockText(previous, previousText + currentText);
        }
      } else if (currentText == null || currentText.isEmpty) {
        // Current is non-text or empty: just remove it
      } else {
        // Previous is non-text: move focus only
        _focusNodes[index - 1].requestFocus();
        return;
      }

      _blocks.removeAt(index);
      _focusNodes[index].dispose();
      _focusNodes.removeAt(index);
      _blockKeys.removeAt(index);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (index - 1 < _focusNodes.length) {
          _focusNodes[index - 1].requestFocus();
        }
      });

      _notifyChanged();
    });
  }

  // ----------------------------------------------------------
  // Block split (newline)
  // ----------------------------------------------------------

  void _onBlockNewline(int index, int cursorPosition) {
    setState(() {
      final Block block = _blocks[index];

      if (block is ListItemBlock) {
        if (block.text.isEmpty) {
          _blocks[index] = ParagraphBlock('');
          _notifyChanged();
          return;
        }
        final String before = block.text.substring(0, cursorPosition);
        final String after = block.text.substring(cursorPosition);
        block.text = before;

        String newMarker = block.marker;
        if (block.isOrdered) {
          final int num = int.tryParse(block.marker.replaceAll('.', '')) ?? 1;
          newMarker = '${num + 1}.';
        }

        _insertBlockAfter(
          index,
          ListItemBlock(
            indent: block.indent,
            marker: newMarker,
            text: after,
          ),
        );
        return;
      }

      if (block is ParagraphBlock) {
        final String before = block.text.substring(0, cursorPosition);
        final String after = block.text.substring(cursorPosition);
        block.text = before;
        _insertBlockAfter(index, ParagraphBlock(after));
        return;
      }

      if (block is HeadingBlock) {
        final String before = block.text.substring(0, cursorPosition);
        final String after = block.text.substring(cursorPosition);
        block.text = before;
        _insertBlockAfter(index, ParagraphBlock(after));
        return;
      }

      _insertBlockAfter(index, ParagraphBlock(''));
    });
  }

  void _insertBlockAfter(int index, Block newBlock) {
    final int newIndex = index + 1;
    _blocks.insert(newIndex, newBlock);
    _focusNodes.insert(newIndex, FocusNode());
    _blockKeys.insert(newIndex, GlobalKey());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (newIndex < _focusNodes.length) {
        _focusNodes[newIndex].requestFocus();
      }
    });

    _notifyChanged();
  }

  // ----------------------------------------------------------
  // Block navigation
  // ----------------------------------------------------------

  void _onMoveToPrevious(int index) {
    if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _onMoveToNext(int index) {
    if (index < _blocks.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  // ----------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------

  String? _getBlockText(Block block) {
    return switch (block) {
      ParagraphBlock() => block.text,
      HeadingBlock() => block.text,
      ListItemBlock() => block.text,
      CodeBlock() => block.code,
      _ => null,
    };
  }

  void _setBlockText(Block block, String text) {
    switch (block) {
      case ParagraphBlock():
        block.text = text;
      case HeadingBlock():
        block.text = text;
      case ListItemBlock():
        block.text = text;
      case CodeBlock():
        block.code = text;
      default:
        break;
    }
  }

  // ----------------------------------------------------------
  // List indent / unindent
  // ----------------------------------------------------------

  void _onListIndent(int index) {
    final block = _blocks[index];
    if (block is! ListItemBlock) return;
    setState(() {
      final unit = widget.useSoftTabs ? ' ' * widget.tabWidth : '\t';
      block.indent = block.indent + unit;
      _notifyChanged();
    });
  }

  void _onListUnindent(int index) {
    final block = _blocks[index];
    if (block is! ListItemBlock) return;
    if (block.indent.isEmpty) return;
    setState(() {
      final unit = widget.useSoftTabs ? ' ' * widget.tabWidth : '\t';
      if (block.indent.endsWith(unit)) {
        block.indent = block.indent.substring(0, block.indent.length - unit.length);
      } else if (block.indent.isNotEmpty) {
        // Trim trailing whitespace/tab if it doesn't match exactly
        block.indent = block.indent.trimRight();
      }
      _notifyChanged();
    });
  }

  // ----------------------------------------------------------
  // Build
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final TextStyle effectiveStyle = widget.style ?? const TextStyle(fontSize: 16, height: 1.5);
    final InputDecoration effectiveDecoration =
        widget.decoration ??
        const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        );

    final InputBorder border = effectiveDecoration.border ?? const OutlineInputBorder();
    final EdgeInsetsGeometry padding = effectiveDecoration.contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 16);

    return Container(
      decoration: BoxDecoration(
        border: border is OutlineInputBorder ? Border.fromBorderSide(border.borderSide) : null,
        borderRadius: border is OutlineInputBorder ? border.borderRadius : null,
      ),
      child: SelectionArea(
        onSelectionChanged: (content) {
          final bool hasSelection = content != null && content.plainText.isNotEmpty;
          if (hasSelection != _hasSelection) {
            setState(() => _hasSelection = hasSelection);
          }
        },
        child: ListView.builder(
          padding: padding.resolve(TextDirection.ltr),
          itemCount: _blocks.length,
          itemBuilder: (context, index) =>
              _buildBlock(index, effectiveStyle),
        ),
      ),
    );
  }

  Widget _buildBlock(int index, TextStyle style) {
    final Block block = _blocks[index];

    return switch (block) {
      ParagraphBlock() => TextBlockWidget(
        key: _blockKeys[index],
        text: block.text,
        style: style,
        showMarkdownSource: _hasSelection,
        focusNode: _focusNodes[index],
        onTextChanged: (text) => _onBlockTextChanged(index, text),
        onDelete: () => _onBlockDelete(index),
        onNewline: (pos) => _onBlockNewline(index, pos),
        onMovePrevious: () => _onMoveToPrevious(index),
        onMoveNext: () => _onMoveToNext(index),
        onLinkTap: widget.onLinkTap,
      ),
      HeadingBlock() => HeadingBlockWidget(
        key: _blockKeys[index],
        level: block.level,
        text: block.text,
        style: style,
        showMarkdownSource: _hasSelection,
        focusNode: _focusNodes[index],
        onTextChanged: (text) => _onBlockTextChanged(index, text),
        onDelete: () => _onBlockDelete(index),
        onNewline: (pos) => _onBlockNewline(index, pos),
        onMovePrevious: () => _onMoveToPrevious(index),
        onMoveNext: () => _onMoveToNext(index),
        onLinkTap: widget.onLinkTap,
      ),
      ListItemBlock() => ListItemBlockWidget(
        key: _blockKeys[index],
        indent: block.indent,
        marker: block.marker,
        text: block.text,
        style: style,
        showMarkdownSource: _hasSelection,
        focusNode: _focusNodes[index],
        onTextChanged: (text) => _onBlockTextChanged(index, text),
        onDelete: () => _onBlockDelete(index),
        onNewline: (pos) => _onBlockNewline(index, pos),
        onMovePrevious: () => _onMoveToPrevious(index),
        onMoveNext: () => _onMoveToNext(index),
        onLinkTap: widget.onLinkTap,
        onIndent: () => _onListIndent(index),
        onUnindent: () => _onListUnindent(index),
      ),
      CodeBlock() => CodeBlockWidget(
        key: _blockKeys[index],
        language: block.language,
        code: block.code,
        style: style,
        showMarkdownSource: _hasSelection,
        focusNode: _focusNodes[index],
        onCodeChanged: (text) => _onBlockTextChanged(index, text),
        onDelete: () => _onBlockDelete(index),
        onMovePrevious: () => _onMoveToPrevious(index),
        onMoveNext: () => _onMoveToNext(index),
      ),
      TableBlock() => TableBlockWidget(
        key: _blockKeys[index],
        headers: block.headers,
        alignments: block.alignments,
        rows: block.rows,
        style: style,
        showMarkdownSource: _hasSelection,
        focusNode: _focusNodes[index],
        onCellChanged: (row, col, text) => _onTableCellChanged(index, row, col, text),
        onMovePrevious: () => _onMoveToPrevious(index),
        onMoveNext: () => _onMoveToNext(index),
      ),
      ImageBlock() => ImageBlockWidget(
        key: _blockKeys[index],
        url: block.url,
        altText: block.altText,
        style: style,
        showMarkdownSource: _hasSelection,
        imageHeightLines: widget.imageHeightLines,
        onImageTap: widget.onImageTap,
        focusNode: _focusNodes[index],
        onChanged: (url, altText) {
          block.url = url;
          block.altText = altText;
          _notifyChanged();
        },
        onDelete: () => _onBlockDelete(index),
        onMovePrevious: () => _onMoveToPrevious(index),
        onMoveNext: () => _onMoveToNext(index),
      ),
      ThematicBreakBlock() => ThematicBreakWidget(
        key: _blockKeys[index],
      ),
    };
  }
}
