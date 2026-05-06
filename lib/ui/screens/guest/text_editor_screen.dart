import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../../client/file_client.dart';
import '../../widgets/file_manager/dialogs/conflict_dialog.dart';

// ─── Language descriptor ─────────────────────────────────────────────────────

class _Lang {
  final String name;
  final Mode mode;

  const _Lang(this.name, this.mode);
}

final _kLanguages = [
  _Lang('Plain text', Mode()),
  _Lang('Dart', langDart),
  _Lang('Python', langPython),
  _Lang('JavaScript', langJavascript),
  _Lang('TypeScript', langTypescript),
  _Lang('JSON', langJson),
  _Lang('YAML', langYaml),
  _Lang('Markdown', langMarkdown),
  _Lang('HTML', langXml),
  _Lang('CSS', langCss),
  _Lang('XML', langXml),
  _Lang('Bash', langBash),
  _Lang('Shell', langShell),
  _Lang('C', langC),
  _Lang('C++', langCpp),
  _Lang('Java', langJava),
  _Lang('Go', langGo),
  _Lang('Rust', langRust),
];

/// Detect language from file extension.
_Lang _detectLang(String name) {
  final ext = name.contains('.')
      ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
      : '';
  return switch (ext) {
    'dart' => _kLanguages[1],
    'py' => _kLanguages[2],
    'js' || 'mjs' => _kLanguages[3],
    'ts' => _kLanguages[4],
    'json' => _kLanguages[5],
    'yaml' || 'yml' => _kLanguages[6],
    'md' || 'markdown' => _kLanguages[7],
    'html' || 'htm' => _kLanguages[8],
    'css' => _kLanguages[9],
    'xml' || 'svg' => _kLanguages[10],
    'sh' || 'bash' => _kLanguages[11],
    'c' => _kLanguages[13],
    'cpp' || 'cc' || 'cxx' || 'h' || 'hpp' => _kLanguages[14],
    'java' => _kLanguages[15],
    'go' => _kLanguages[16],
    'rs' => _kLanguages[17],
    _ => _kLanguages[0], // Plain text
  };
}

// ─── Screen ──────────────────────────────────────────────────────────────────

/// Maximum file size allowed for in-editor display (5 MB).
const _kMaxEditorBytes = 5 * 1024 * 1024;

class TextEditorScreen extends StatefulWidget {
  final FileClient client;
  final String alias;
  final String remotePath;
  final String fileName;
  final int fileSize;
  final bool canWrite;

  const TextEditorScreen({
    super.key,
    required this.client,
    required this.alias,
    required this.remotePath,
    required this.fileName,
    required this.fileSize,
    this.canWrite = false,
  });

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  // ── Controllers ──────────────────────────────────────────────────────────
  late CodeLineEditingController _editingController;
  final CodeScrollController _scrollController = CodeScrollController();
  // CodeFindController requires an editing controller — created lazily in initState.
  CodeFindController? _findController;

  // ── State ─────────────────────────────────────────────────────────────────
  bool _loading = true;
  String? _loadError;
  String? _versionToken;
  bool _isDirty = false;
  bool _darkTheme = true;
  bool _themeInitialized = false;
  bool _readOnly = false;
  late _Lang _lang;

  @override
  void initState() {
    super.initState();
    _lang = _detectLang(widget.fileName);
    _readOnly = !widget.canWrite;
    _editingController = CodeLineEditingController.fromText('');
    _findController = CodeFindController(_editingController);
    _loadFile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_themeInitialized) return;
    _darkTheme = Theme.of(context).brightness == Brightness.dark;
    _themeInitialized = true;
  }

  @override
  void dispose() {
    _editingController.dispose();
    _scrollController.dispose();
    _findController?.dispose();
    super.dispose();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _loadFile() async {
    if (widget.fileSize > _kMaxEditorBytes) {
      setState(() {
        _loading = false;
        _loadError =
            'File is too large to edit (${_formatSize(widget.fileSize)}). '
            'Maximum size is ${_formatSize(_kMaxEditorBytes)}.';
      });
      return;
    }

    // Fetch metadata for the version token first.
    final metaResult =
        await widget.client.getMetadata(widget.alias, widget.remotePath);
    if (!mounted) return;
    if (metaResult.isOk) {
      _versionToken = metaResult.unwrap.versionToken;
    }

    final result =
        await widget.client.downloadFile(widget.alias, widget.remotePath);
    if (!mounted) return;
    if (result.isErr) {
      setState(() {
        _loading = false;
        _loadError = result.errorMessage;
      });
      return;
    }

    final bytes = result.unwrap;
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      setState(() {
        _loading = false;
        _loadError =
            'Cannot edit binary file. Use the download option instead.';
      });
      return;
    }

    _editingController.dispose();
    _editingController = CodeLineEditingController.fromText(text);
    _findController?.dispose();
    _findController = CodeFindController(_editingController);
    _editingController.addListener(_onTextChanged);

    setState(() {
      _loading = false;
      _isDirty = false;
    });
  }

  void _onTextChanged() {
    if (!_isDirty && mounted) {
      // Schedule the state update after the current build is complete.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isDirty = true);
      });
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final text = _editingController.text;
    final bytes = Uint8List.fromList(utf8.encode(text));

    final result = await widget.client.uploadFile(
      widget.alias,
      widget.remotePath,
      bytes,
      ifMatch: _versionToken,
    );
    if (!mounted) return;

    if (result.isOk) {
      _versionToken = result.unwrap;
      setState(() => _isDirty = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
      return;
    }

    if (result.errorCode == 'VERSION_CONFLICT') {
      _showSaveConflict(bytes);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Save failed: ${result.errorMessage}'),
          backgroundColor: Colors.red),
    );
  }

  Future<void> _showSaveConflict(Uint8List bytes) async {
    final resolution =
        await showConflictDialog(context, itemName: widget.fileName);
    if (!mounted || resolution == null) return;

    switch (resolution) {
      case ConflictResolution.skip:
        // Discard — reload from server.
        _editingController.removeListener(_onTextChanged);
        setState(() {
          _loading = true;
          _isDirty = false;
        });
        await _loadFile();

      case ConflictResolution.replace:
        // Force overwrite with '*' wildcard If-Match.
        final force = await widget.client.uploadFile(
          widget.alias,
          widget.remotePath,
          bytes,
          ifMatch: '*',
        );        if (!mounted) return;
        if (force.isOk) {
          _versionToken = force.unwrap;
          setState(() => _isDirty = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Saved (overwrite)')));
        }

      case ConflictResolution.keepBoth:
        // Save as a copy.
        final ext = widget.remotePath.contains('.')
            ? widget.remotePath.substring(widget.remotePath.lastIndexOf('.'))
            : '';
        final base = ext.isNotEmpty
            ? widget.remotePath
                .substring(0, widget.remotePath.lastIndexOf('.'))
            : widget.remotePath;
        final copyPath =
            '${base}_copy_${DateTime.now().millisecondsSinceEpoch}$ext';
        await widget.client.uploadFile(widget.alias, copyPath, Uint8List.fromList(bytes));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved as ${copyPath.split('/').last}')),
        );
    }
  }

  // ── Unsaved-changes guard ─────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
            'You have unsaved changes. Leave without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  CodeHighlightTheme _buildHighlightTheme() => CodeHighlightTheme(
        languages: {_lang.name.toLowerCase(): _lang.mode.themeMode},
        theme: _darkTheme ? atomOneDarkTheme : atomOneLightTheme,
      );

  CodeEditorStyle _buildEditorStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = _darkTheme
        ? const Color(0xffabb2bf)
        : const Color(0xff24292e);
    final backgroundColor = _darkTheme
        ? const Color(0xff282c34)
        : const Color(0xfffafafa);
    return CodeEditorStyle(
      codeTheme: _buildHighlightTheme(),
      textColor: textColor,
      hintTextColor: textColor.withValues(alpha: 0.65),
      backgroundColor: backgroundColor,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
      highlightColor: scheme.tertiary.withValues(alpha: 0.22),
      cursorColor: scheme.primary,
      cursorLineColor: scheme.outline.withValues(alpha: 0.35),
      chunkIndicatorColor: scheme.outline.withValues(alpha: 0.6),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final editorStyle = _buildEditorStyle(context);
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _onWillPop();
        if (ok && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: editorStyle.backgroundColor,
        appBar: _buildAppBar(),
        body: _buildBody(editorStyle),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.fileName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isDirty)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('•', style: TextStyle(color: Colors.orange)),
            ),
        ],
      ),
      actions: [
        // Language selector
        PopupMenuButton<_Lang>(
          tooltip: 'Language',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_lang.name,
                    style: Theme.of(context).textTheme.bodyMedium),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
          onSelected: (lang) => setState(() => _lang = lang),
          itemBuilder: (_) => _kLanguages
              .map((l) => PopupMenuItem(value: l, child: Text(l.name)))
              .toList(),
        ),
        // Theme toggle
        IconButton(
          icon: Icon(_darkTheme ? Icons.light_mode : Icons.dark_mode),
          tooltip: _darkTheme ? 'Light theme' : 'Dark theme',
          onPressed: () => setState(() => _darkTheme = !_darkTheme),
        ),
        // Read-only toggle (only for writers)
        if (widget.canWrite)
          IconButton(
            icon: Icon(_readOnly ? Icons.lock : Icons.lock_open),
            tooltip: _readOnly ? 'Read-only (tap to edit)' : 'Editing',
            onPressed: () => setState(() => _readOnly = !_readOnly),
          ),
        // Find
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Find',
          onPressed: () {
            final fc = _findController;
            if (fc == null) return;
            if (fc.value != null) {
              fc.close();
            } else {
              fc.findMode();
              fc.focusOnFindInput();
            }
          },
        ),
        // Save
        if (widget.canWrite && !_readOnly)
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: _isDirty ? 'Save' : 'No changes',
            onPressed: _isDirty ? _save : null,
          ),
      ],
    );
  }

  Widget _buildBody(CodeEditorStyle editorStyle) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    return CodeEditor(
      controller: _editingController,
      scrollController: _scrollController,
      findController: _findController,
      readOnly: _readOnly,
      style: editorStyle,
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
            ),
            DefaultCodeChunkIndicator(
              width: 20,
              controller: chunkController,
              notifier: notifier,
            ),
          ],
        );
      },
    );
  }
}
