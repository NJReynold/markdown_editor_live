import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/markdown_text_editing_controller.dart';

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

  /// The height of inline images in lines of text.
  /// The actual height is calculated as: fontSize * imageHeightLines.
  /// Defaults to 5 lines to maintain backward compatibility.
  final int imageHeightLines;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late final MarkdownEditingController _controller;
  late final FocusNode _textFieldFocusNode;

  /// Stores the previous focused line before a tap, to restore after link tap.
  int? _prevFocusedLine;

  @override
  void initState() {
    super.initState();
    _controller = MarkdownEditingController(
      text: widget.initialValue,
      onLinkTap: widget.onLinkTap,
      onImageTap: widget.onImageTap,
      imageHeightLines: widget.imageHeightLines,
    );
    _controller.addListener(_onSelectionChanged);
    _textFieldFocusNode = FocusNode();
    _textFieldFocusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!_textFieldFocusNode.hasFocus) {
      // Clear focused line when textfield loses focus to show rendered markdown
      _controller.focusedLine = null;
    }
  }

  @override
  void dispose() {
    _textFieldFocusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onSelectionChanged);
    _controller.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    // Save the current focused line before updating
    _prevFocusedLine = _controller.focusedLine;
    _controller.updateFocusedLineFromSelection();
  }

  /// Handles tap events on the text field.
  /// Checks if the tap landed on a link and calls the callback if so.
  void _onTap() {
    if (widget.onLinkTap == null) return;

    final int offset = _controller.selection.baseOffset;
    if (offset < 0) return;

    final String? url = _controller.getLinkUrlAtOffset(offset);
    if (url != null) {
      widget.onLinkTap!(url);
      // Restore focused line to prevent switching to source mode
      if (_prevFocusedLine != null) {
        _controller.focusedLine = _prevFocusedLine;
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Don't intercept keys while cell editor is active to avoid interfering with table editing
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _insertTab();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (_handleListContinuation()) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Regex patterns for detecting list items
  static final _unorderedListPattern = RegExp(r'^([ \t]*)([*+-])([ \t]+)(.*)$');
  static final _orderedListPattern = RegExp(r'^([ \t]*)(\d+)(\.)([ \t]+)(.*)$');

  /// Handles Enter key press for list continuation.
  bool _handleListContinuation() {
    final String text = _controller.value.text;
    final TextSelection selection = _controller.value.selection;

    if (!selection.isValid || !selection.isCollapsed) return false;

    final int cursorOffset = selection.baseOffset;
    final int lineNumber = _getLineNumber(cursorOffset);
    final (int lineStart, int lineEnd) = _getLineRange(lineNumber);
    final String currentLine = text.substring(lineStart, lineEnd);

    // Check for unordered list
    final RegExpMatch? unorderedMatch = _unorderedListPattern.firstMatch(currentLine);
    if (unorderedMatch != null) {
      final String indent = unorderedMatch.group(1)!;
      final String bullet = unorderedMatch.group(2)!;
      final String space = unorderedMatch.group(3)!;
      final String content = unorderedMatch.group(4)!;

      if (content.isEmpty) {
        _removeListPrefix(lineStart, lineEnd);
      } else {
        _insertNewListItem(cursorOffset, '$indent$bullet$space');
      }
      return true;
    }

    // Check for ordered list
    final RegExpMatch? orderedMatch = _orderedListPattern.firstMatch(currentLine);
    if (orderedMatch != null) {
      final String indent = orderedMatch.group(1)!;
      final int number = int.parse(orderedMatch.group(2)!);
      final String dot = orderedMatch.group(3)!;
      final String space = orderedMatch.group(4)!;
      final String content = orderedMatch.group(5)!;

      if (content.isEmpty) {
        _removeListPrefix(lineStart, lineEnd);
      } else {
        _insertNewListItem(cursorOffset, '$indent${number + 1}$dot$space');
      }
      return true;
    }

    return false;
  }

  /// Inserts a new line with the given list prefix at the cursor position.
  void _insertNewListItem(int cursorOffset, String prefix) {
    final String text = _controller.value.text;
    final newText = '${text.substring(0, cursorOffset)}\n$prefix${text.substring(cursorOffset)}';

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset + 1 + prefix.length),
    );
  }

  /// Removes the list prefix from the current line, leaving just the newline.
  void _removeListPrefix(int lineStart, int lineEnd) {
    final String text = _controller.value.text;

    if (lineStart == 0) {
      final String newText = text.substring(lineEnd);
      _controller.value = TextEditingValue(text: newText, selection: const TextSelection.collapsed(offset: 0));
    } else {
      // Remove the previous newline and the entire line content
      final String newText = text.substring(0, lineStart - 1) + text.substring(lineEnd);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: lineStart - 1),
      );
    }
  }

  (int, int) _getLineRange(int lineNumber) {
    final String text = _controller.value.text;
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

  void _insertTab() {
    final String text = _controller.value.text;
    final TextSelection selection = _controller.value.selection;

    if (!selection.isValid) return;

    final String tabString = widget.useSoftTabs ? ' ' * widget.tabWidth : '\t';

    if (selection.isCollapsed) {
      // Insert tab at cursor position
      final String newText = text.substring(0, selection.baseOffset) + tabString + text.substring(selection.baseOffset);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.baseOffset + tabString.length),
      );
    } else {
      _indentSelectedLines(tabString);
    }
  }

  void _indentSelectedLines(String tabString) {
    final String text = _controller.value.text;
    final TextSelection selection = _controller.value.selection;
    final (int startLine, int endLine) = _getSelectedLineRange(selection);

    final List<String> lines = text.split('\n');
    final newLines = <String>[];

    for (int i = startLine; i <= endLine; i++) {
      if (i < lines.length) {
        newLines.add(tabString + lines[i]);
      }
    }

    final String before = lines.sublist(0, startLine).join('\n');
    final String after = lines.sublist(endLine + 1).join('\n');
    final String middle = newLines.join('\n');

    final separator = startLine > 0 ? '\n' : '';
    final separatorAfter = endLine < lines.length - 1 ? '\n' : '';

    _controller.value = TextEditingValue(text: '$before$separator$middle$separatorAfter$after', selection: selection);
  }

  (int, int) _getSelectedLineRange(TextSelection selection) {
    final int startLine = _getLineNumber(selection.baseOffset);
    final int endLine = _getLineNumber(selection.extentOffset);
    return (startLine, endLine);
  }

  int _getLineNumber(int offset) {
    final String text = _controller.value.text;
    int line = 0;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
      }
    }
    return line;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        focusNode: _textFieldFocusNode,
        controller: _controller,
        onChanged: widget.onChanged,
        onTap: _onTap,
        style: widget.style,
        decoration:
            widget.decoration?.copyWith(contentPadding: widget.decoration?.contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 16)) ??
            const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16)),
        maxLines: null,
        keyboardType: TextInputType.multiline,
        // forceStrutHeight must be false to prevent headers from clipping outside the TextField bounds
        strutStyle: const StrutStyle(forceStrutHeight: false),
      ),
    );
  }
}
