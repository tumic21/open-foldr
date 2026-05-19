library re_editor;

import 'package:flutter/material.dart';

/// Minimal highlight-theme holder for compatibility with the app API.
class CodeHighlightTheme {
  final Map<String, dynamic>? languages;
  final Map<String, TextStyle>? theme;

  const CodeHighlightTheme({this.languages, this.theme});
}

/// Styling options consumed by TextEditorScreen and tests.
class CodeEditorStyle {
  final CodeHighlightTheme? codeTheme;
  final Color? textColor;
  final Color? hintTextColor;
  final Color? backgroundColor;
  final Color? selectionColor;
  final Color? highlightColor;
  final Color? cursorColor;
  final Color? cursorLineColor;
  final Color? chunkIndicatorColor;

  const CodeEditorStyle({
    this.codeTheme,
    this.textColor,
    this.hintTextColor,
    this.backgroundColor,
    this.selectionColor,
    this.highlightColor,
    this.cursorColor,
    this.cursorLineColor,
    this.chunkIndicatorColor,
  });
}

/// Editing controller with a text API similar to the upstream package.
class CodeLineEditingController extends ChangeNotifier {
  final TextEditingController textController;

  CodeLineEditingController.fromText(String text)
      : textController = TextEditingController(text: text) {
    textController.addListener(_onChanged);
  }

  String get text => textController.text;

  set text(String value) {
    if (textController.text == value) return;
    textController.text = value;
    notifyListeners();
  }

  void _onChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    textController.removeListener(_onChanged);
    textController.dispose();
    super.dispose();
  }
}

class CodeScrollController extends ScrollController {}

class CodeChunkController extends ChangeNotifier {}

class CodeFindController extends ChangeNotifier {
  final CodeLineEditingController controller;
  Object? value;

  CodeFindController(this.controller);

  void findMode() {
    value = Object();
    notifyListeners();
  }

  void close() {
    value = null;
    notifyListeners();
  }

  void focusOnFindInput() {}
}

typedef CodeIndicatorBuilder = Widget Function(
  BuildContext context,
  CodeLineEditingController editingController,
  CodeChunkController chunkController,
  ValueNotifier<int> notifier,
);

class CodeEditor extends StatefulWidget {
  final CodeLineEditingController controller;
  final CodeScrollController? scrollController;
  final CodeFindController? findController;
  final bool readOnly;
  final CodeEditorStyle? style;
  final CodeIndicatorBuilder? indicatorBuilder;

  const CodeEditor({
    super.key,
    required this.controller,
    this.scrollController,
    this.findController,
    this.readOnly = false,
    this.style,
    this.indicatorBuilder,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late final ValueNotifier<int> _lineCount;
  final CodeChunkController _chunkController = CodeChunkController();

  @override
  void initState() {
    super.initState();
    _lineCount = ValueNotifier<int>(_countLines(widget.controller.text));
    widget.controller.addListener(_syncLineCount);
  }

  @override
  void didUpdateWidget(covariant CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncLineCount);
      widget.controller.addListener(_syncLineCount);
      _syncLineCount();
    }
  }

  int _countLines(String text) {
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  void _syncLineCount() {
    final next = _countLines(widget.controller.text);
    if (_lineCount.value != next) {
      _lineCount.value = next;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncLineCount);
    _chunkController.dispose();
    _lineCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final textStyle = TextStyle(color: style?.textColor);

    Widget editor = TextField(
      controller: widget.controller.textController,
      readOnly: widget.readOnly,
      maxLines: null,
      expands: true,
      scrollController: widget.scrollController,
      style: textStyle,
      cursorColor: style?.cursorColor,
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.all(12),
        hintStyle: TextStyle(color: style?.hintTextColor),
      ),
    );

    editor = ColoredBox(
      color: style?.backgroundColor ?? Theme.of(context).colorScheme.surface,
      child: editor,
    );

    final indicator = widget.indicatorBuilder
        ?.call(context, widget.controller, _chunkController, _lineCount);
    if (indicator == null) {
      return editor;
    }

    return Row(
      children: [
        indicator,
        Expanded(child: editor),
      ],
    );
  }
}

class DefaultCodeLineNumber extends StatelessWidget {
  final CodeLineEditingController controller;
  final ValueNotifier<int> notifier;

  const DefaultCodeLineNumber({
    super.key,
    required this.controller,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (context, count, _) {
        final lines = List<String>.generate(count, (i) => '${i + 1}').join('\n');
        return SizedBox(
          width: 44,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, right: 6),
              child: Text(
                lines,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        );
      },
    );
  }
}

class DefaultCodeChunkIndicator extends StatelessWidget {
  final double width;
  final CodeChunkController controller;
  final ValueNotifier<int> notifier;

  const DefaultCodeChunkIndicator({
    super.key,
    required this.width,
    required this.controller,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width);
  }
}
