import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/inline_markdown_controller.dart';
import 'package:markdown_editor_live/src/block_widgets/block_widget_callbacks.dart';
// ============================================================
// @remind TEXT BLOCK (Paragraph)
// ============================================================

class TextBlockWidget extends StatefulWidget {
  const TextBlockWidget({
    required this.text,
    required this.style,
    this.showMarkdownSource = false,
    this.onTextChanged,
    this.onDelete,
    this.onNewline,
    this.onMovePrevious,
    this.onMoveNext,
    this.onFocusChanged,
    this.onLinkTap,
    this.focusNode,
    super.key,
  });

  final String text;
  final TextStyle style;
  final bool showMarkdownSource;
  final BlockTextChangedCallback? onTextChanged;
  final BlockDeleteCallback? onDelete;
  final BlockNewlineCallback? onNewline;
  final BlockNavigateCallback? onMovePrevious;
  final BlockNavigateCallback? onMoveNext;
  final BlockFocusCallback? onFocusChanged;
  final void Function(String url)? onLinkTap;
  final FocusNode? focusNode;

  @override
  State<TextBlockWidget> createState() => _TextBlockWidgetState();
}

class _TextBlockWidgetState extends State<TextBlockWidget> {
  late final InlineMarkdownController _controller;
  late final FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = InlineMarkdownController(
      text: widget.text,
      onLinkTap: widget.onLinkTap,
    );
    _controller.showSyntax = false;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(TextBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text && widget.text != oldWidget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    final bool hasFocus = _focusNode.hasFocus;
    setState(() {
      _isEditing = hasFocus;
      _controller.showSyntax = hasFocus;
    });
    widget.onFocusChanged?.call(hasFocus);
  }

  void _enterEditMode() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Backspace at position 0 → merge with previous block
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controller.selection.isCollapsed && _controller.selection.baseOffset == 0) {
        widget.onDelete?.call();
        return KeyEventResult.handled;
      }
    }

    // Enter → split block
    if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      widget.onNewline?.call(_controller.selection.baseOffset);
      return KeyEventResult.handled;
    }

    // Up arrow at first line → move to previous block
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_isOnFirstLine()) {
        widget.onMovePrevious?.call();
        return KeyEventResult.handled;
      }
    }

    // Down arrow at last line → move to next block
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_isOnLastLine()) {
        widget.onMoveNext?.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  bool _isOnFirstLine() {
    final int offset = _controller.selection.baseOffset;
    return !_controller.text.substring(0, offset).contains('\n');
  }

  bool _isOnLastLine() {
    final int offset = _controller.selection.baseOffset;
    return !_controller.text.substring(offset).contains('\n');
  }

  /// Set cursor position from external navigation.
  void setCursorAtStart() {
    _focusNode.requestFocus();
    _controller.selection = const TextSelection.collapsed(offset: 0);
  }

  void setCursorAtEnd() {
    _focusNode.requestFocus();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      _controller.showSyntax = widget.showMarkdownSource;
      return GestureDetector(
        onTap: _enterEditMode,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(children: [
              _controller.buildTextSpan(
                context: context,
                style: widget.style,
                withComposing: false,
              ),
              const TextSpan(text: '\n'),
            ]),
          ),
        ),
      );
    }

    return SelectionContainer.disabled(
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: widget.style,
          maxLines: null,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
          onChanged: widget.onTextChanged,
          onTap: _handleTap,
        ),
      ),
    );
  }

  void _handleTap() {
    final offset = _controller.selection.baseOffset;
    final url = _controller.getLinkUrlAtOffset(offset);
    if (url != null && widget.onLinkTap != null) {
      widget.onLinkTap!(url);
    }
  }
}
