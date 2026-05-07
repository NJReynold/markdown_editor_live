import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/block_widgets/block_widget_callbacks.dart';
import 'package:markdown_editor_live/src/inline_markdown_controller.dart';

// ============================================================
// @remind LIST ITEM BLOCK
// ============================================================

class ListItemBlockWidget extends StatefulWidget {
  const ListItemBlockWidget({
    required this.indent,
    required this.marker,
    required this.text,
    required this.style,
    this.onTextChanged,
    this.onDelete,
    this.onNewline,
    this.onMovePrevious,
    this.onMoveNext,
    this.onFocusChanged,
    this.onLinkTap,
    this.focusNode,
    this.onIndent,
    this.onUnindent,
    super.key,
  });
  final String indent;
  final String marker;
  final String text;
  final TextStyle style;
  final BlockTextChangedCallback? onTextChanged;
  final BlockDeleteCallback? onDelete;
  final BlockNewlineCallback? onNewline;
  final BlockNavigateCallback? onMovePrevious;
  final BlockNavigateCallback? onMoveNext;
  final BlockFocusCallback? onFocusChanged;
  final void Function(String url)? onLinkTap;
  final FocusNode? focusNode;
  final VoidCallback? onIndent;
  final VoidCallback? onUnindent;
  @override
  State<ListItemBlockWidget> createState() => _ListItemBlockWidgetState();
}

class _ListItemBlockWidgetState extends State<ListItemBlockWidget> {
  late final InlineMarkdownController _controller;
  late final FocusNode _focusNode;
  bool _hasFocus = false;
  @override
  void initState() {
    super.initState();
    _controller = InlineMarkdownController(
      text: widget.text,
      onLinkTap: widget.onLinkTap,
    );
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ListItemBlockWidget oldWidget) {
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
      _controller.showSyntax = _hasFocus;
    });
    widget.onFocusChanged?.call(_hasFocus);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controller.selection.isCollapsed && _controller.selection.baseOffset == 0) {
        if (widget.indent.isNotEmpty) {
          widget.onUnindent?.call();
        } else {
          widget.onDelete?.call();
        }
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.onUnindent?.call();
      } else {
        widget.onIndent?.call();
      }
      return KeyEventResult.handled;
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

  @override
  Widget build(BuildContext context) {
    final bool isOrdered = RegExp(r'^\d+\.$').hasMatch(widget.marker);
    final double indentWidth = widget.indent.length * 6.0;
    final String bulletDisplay = _hasFocus ? widget.marker : (isOrdered ? widget.marker : '•');
    final TextStyle bulletStyle = _hasFocus ? widget.style.copyWith(color: Colors.blueAccent) : widget.style.copyWith(fontWeight: FontWeight.bold);
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: indentWidth),
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text('$bulletDisplay ', style: bulletStyle),
          ),
          Expanded(
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
            ),
          ),
        ],
      ),
    );
  }
}
