import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  // -- Multi-block selection --
  int _lastFocusedBlock = 0;
  int? _selectionAnchor;
  int? _selectionFocus;
  final FocusNode _editorFocusNode = FocusNode();

  bool get _hasBlockSelection => _selectionAnchor != null && _selectionFocus != null;
  int get _selStart => _hasBlockSelection ? min(_selectionAnchor!, _selectionFocus!) : 0;
  int get _selEnd => _hasBlockSelection ? max(_selectionAnchor!, _selectionFocus!) : 0;
  bool _isBlockSelected(int index) => _hasBlockSelection && index >= _selStart && index <= _selEnd;

  @override
  void initState() {
    super.initState();
    _blocks = MarkdownParser.parse(widget.initialValue ?? '');
    if (_blocks.isEmpty) {
      _blocks.add(ParagraphBlock(''));
    }
    _focusNodes = List.generate(_blocks.length, (_) => FocusNode());
    for (final fn in _focusNodes) {
      fn.addListener(_checkFocusChange);
    }
    _blockKeys = List.generate(_blocks.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    for (final FocusNode fn in _focusNodes) {
      fn.removeListener(_checkFocusChange);
      fn.dispose();
    }
    super.dispose();
  }

  void _notifyChanged() {
    final String markdown = MarkdownSerializer.serialize(_blocks);
    widget.onChanged?.call(markdown);
  }

  // ----------------------------------------------------------
  // Multi-block selection
  // ----------------------------------------------------------

  void _checkFocusChange() {
    for (var i = 0; i < _focusNodes.length; i++) {
      if (_focusNodes[i].hasFocus) {
        _onBlockFocusGained(i);
        return;
      }
    }
  }

  void _onBlockFocusGained(int index) {
    if (HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        _selectionAnchor ??= _lastFocusedBlock;
        _selectionFocus = index;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (index < _focusNodes.length) {
          _focusNodes[index].unfocus();
        }
        _editorFocusNode.requestFocus();
      });
    } else {
      if (_hasBlockSelection) {
        _clearBlockSelection();
      }
      _lastFocusedBlock = index;
    }
  }

  void _clearBlockSelection() {
    setState(() {
      _selectionAnchor = null;
      _selectionFocus = null;
    });
  }

  void _copySelectedBlocks() {
    if (!_hasBlockSelection) return;
    final selected = _blocks.sublist(_selStart, _selEnd + 1);
    final markdown = MarkdownSerializer.serialize(selected);
    Clipboard.setData(ClipboardData(text: markdown));
  }

  void _deleteSelectedBlocks() {
    if (!_hasBlockSelection) return;
    setState(() {
      final start = _selStart;
      final end = _selEnd;
      for (var i = end; i >= start; i--) {
        _blocks.removeAt(i);
        _focusNodes[i].removeListener(_checkFocusChange);
        _focusNodes[i].dispose();
        _focusNodes.removeAt(i);
        _blockKeys.removeAt(i);
      }
      if (_blocks.isEmpty) {
        _blocks.add(ParagraphBlock(''));
        final fn = FocusNode()..addListener(_checkFocusChange);
        _focusNodes.add(fn);
        _blockKeys.add(GlobalKey());
      }
      _selectionAnchor = null;
      _selectionFocus = null;
      _lastFocusedBlock = start.clamp(0, _blocks.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_lastFocusedBlock < _focusNodes.length) {
          _focusNodes[_lastFocusedBlock].requestFocus();
        }
      });
      _notifyChanged();
    });
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (!_hasBlockSelection) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Shift+Down: extend selection
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && HardwareKeyboard.instance.isShiftPressed) {
      if (_selectionFocus! < _blocks.length - 1) {
        setState(() => _selectionFocus = _selectionFocus! + 1);
      }
      return KeyEventResult.handled;
    }

    // Shift+Up: extend selection
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && HardwareKeyboard.instance.isShiftPressed) {
      if (_selectionFocus! > 0) {
        setState(() => _selectionFocus = _selectionFocus! - 1);
      }
      return KeyEventResult.handled;
    }

    // Ctrl+C: copy
    if (event.logicalKey == LogicalKeyboardKey.keyC && (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
      _copySelectedBlocks();
      return KeyEventResult.handled;
    }

    // Ctrl+X: cut
    if (event.logicalKey == LogicalKeyboardKey.keyX && (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
      _copySelectedBlocks();
      _deleteSelectedBlocks();
      return KeyEventResult.handled;
    }

    // Delete/Backspace: delete selection
    if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelectedBlocks();
      return KeyEventResult.handled;
    }

    // Escape: clear selection, focus anchor
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final target = _selectionAnchor ?? _lastFocusedBlock;
      _clearBlockSelection();
      if (target < _focusNodes.length) {
        _focusNodes[target].requestFocus();
      }
      return KeyEventResult.handled;
    }

    // Arrow down without shift: clear, go past selection
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final target = (_selEnd + 1).clamp(0, _blocks.length - 1);
      _clearBlockSelection();
      _focusNodes[target].requestFocus();
      return KeyEventResult.handled;
    }

    // Arrow up without shift: clear, go before selection
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final target = (_selStart - 1).clamp(0, _blocks.length - 1);
      _clearBlockSelection();
      _focusNodes[target].requestFocus();
      return KeyEventResult.handled;
    }

    // Any other key: clear selection, focus anchor
    final target = (_selectionAnchor ?? _lastFocusedBlock).clamp(0, _blocks.length - 1);
    _clearBlockSelection();
    _focusNodes[target].requestFocus();
    return KeyEventResult.handled;
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
      _focusNodes[index].removeListener(_checkFocusChange);
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
    final newFocusNode = FocusNode()..addListener(_checkFocusChange);
    _focusNodes.insert(newIndex, newFocusNode);
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

    return Focus(
      focusNode: _editorFocusNode,
      onKeyEvent: _handleEditorKeyEvent,
      child: Container(
        decoration: BoxDecoration(
          border: border is OutlineInputBorder ? Border.fromBorderSide(border.borderSide) : null,
          borderRadius: border is OutlineInputBorder ? border.borderRadius : null,
        ),
        child: SelectionArea(
          child: ListView.builder(
            padding: padding.resolve(TextDirection.ltr),
            itemCount: _blocks.length,
            itemBuilder: (context, index) =>
                _buildBlock(index, effectiveStyle),
          ),
        ),
      ),
    );
  }

  /* List<Widget> */
  Widget _buildBlock(int index, TextStyle style) {
    final Block block = _blocks[index];

    // When selected: show raw markdown as SelectableText for native copy
    if (_isBlockSelected(index)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 2),
        color: Colors.blue.withValues(alpha: 0.15),
        child: SelectableText(
          block.toMarkdown(),
          style: style.copyWith(
            fontFamily: 'monospace',
            color: Colors.grey.shade800,
          ),
        ),
      );
    }

    // When not selected: render the interactive block widget
    // Wrap in SelectionContainer.disabled so SelectionArea
    // doesn't interfere with TextField editing.
    Widget blockWidget = switch (block) {
      ParagraphBlock() => TextBlockWidget(
        key: _blockKeys[index],
        text: block.text,
        style: style,
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

    return SelectionContainer.disabled(child: blockWidget);
  }
}
