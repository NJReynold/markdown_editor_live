import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/src/block_widgets/block_widget_callbacks.dart'; // ============================================================
// @remind IMAGE BLOCK
// ============================================================

class ImageBlockWidget extends StatefulWidget {
  const ImageBlockWidget({
    required this.url,
    required this.altText,
    required this.style,
    this.imageHeightLines = 5,
    this.onImageTap,
    this.onChanged,
    this.onDelete,
    this.onMovePrevious,
    this.onMoveNext,
    this.focusNode,
    super.key,
  });

  final String url;
  final String altText;
  final TextStyle style;
  final int imageHeightLines;
  final void Function(String url)? onImageTap;
  final void Function(String url, String altText)? onChanged;
  final BlockDeleteCallback? onDelete;
  final BlockNavigateCallback? onMovePrevious;
  final BlockNavigateCallback? onMoveNext;
  final FocusNode? focusNode;

  @override
  State<ImageBlockWidget> createState() => _ImageBlockWidgetState();
}

class _ImageBlockWidgetState extends State<ImageBlockWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '![${widget.altText}](${widget.url})',
    );
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(ImageBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && (widget.url != oldWidget.url || widget.altText != oldWidget.altText)) {
      _controller.text = '![${widget.altText}](${widget.url})';
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
    if (_focusNode.hasFocus) {
      setState(() => _isEditing = true);
    } else {
      // Parse the edited text back into url + altText
      _commitEdit();
      setState(() => _isEditing = false);
    }
  }

  void _commitEdit() {
    final String text = _controller.text;
    final RegExpMatch? match = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$').firstMatch(text.trim());
    if (match != null) {
      final String altText = match.group(1) ?? '';
      final String url = match.group(2) ?? '';
      widget.onChanged?.call(url, altText);
    }
  }

  void _enterEditMode() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      //_controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
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
    if (_isEditing) {
      return Focus(
        onKeyEvent: _handleKeyEvent,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: widget.style.copyWith(color: Colors.blue.shade300),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      );
    }

    final double fontSize = widget.style.fontSize ?? 16.0;
    final double height = fontSize * widget.imageHeightLines * (widget.style.height ?? 1.2);

    return GestureDetector(
      onTap: _enterEditMode,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          height: height,
          child: _buildImage(),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.url.startsWith('http://') || widget.url.startsWith('https://')) {
      return Image.network(widget.url, fit: BoxFit.contain, errorBuilder: (_, _, _) => _error());
    } else if (widget.url.startsWith('asset://')) {
      return Image.asset(widget.url.replaceFirst('asset://', ''), fit: BoxFit.contain, errorBuilder: (_, _, _) => _error());
    }
    return _error();
  }

  Widget _error() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
      child: Text(
        widget.altText.isNotEmpty ? widget.altText : 'Image not found',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}
