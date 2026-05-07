import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/inline_markdown_controller.dart';
import 'package:markdown_editor_live/src/block_widgets/block_widget_callbacks.dart'; // ============================================================
// @remind HEADING BLOCK
// ============================================================

class HeadingBlockWidget extends StatefulWidget {
  const HeadingBlockWidget({
    required this.level,
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

  final int level;
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
  State<HeadingBlockWidget> createState() => _HeadingBlockWidgetState();
}

class _HeadingBlockWidgetState extends State<HeadingBlockWidget> {
  late final InlineMarkdownController _controller;
  late final FocusNode _focusNode;
  bool _hasFocus = false;
  bool _isEditing = false;

  static const _fontSizes = [28.0, 24.0, 20.0, 18.0, 16.0, 14.0];

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
  void didUpdateWidget(HeadingBlockWidget oldWidget) {
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
    setState(() {
      _hasFocus = _focusNode.hasFocus;
      _isEditing = _hasFocus;
      _controller.showSyntax = _hasFocus;
    });
    widget.onFocusChanged?.call(_hasFocus);
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

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controller.selection.isCollapsed && _controller.selection.baseOffset == 0) {
        widget.onDelete?.call();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      widget.onNewline?.call(_controller.selection.baseOffset);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onMovePrevious?.call();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onMoveNext?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  TextStyle get _headingStyle {
    final double fontSize = _fontSizes[widget.level.clamp(1, 6) - 1];
    return widget.style.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: fontSize,
      color: Colors.blueAccent,
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
              if (widget.showMarkdownSource)
                TextSpan(text: '${'#' * widget.level} ', style: _headingStyle),
              _controller.buildTextSpan(
                context: context,
                style: _headingStyle,
                withComposing: false,
              ),
              const TextSpan(text: '\n'),
            ]),
          ),
        ),
      );
    }

    final prefix = '${'#' * widget.level} ';

    return SelectionContainer.disabled(
      child: Focus(
        onKeyEvent: _handleKeyEvent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prefix, style: _headingStyle.copyWith(color: Colors.grey.shade500)),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: _headingStyle,
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
          ],
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
