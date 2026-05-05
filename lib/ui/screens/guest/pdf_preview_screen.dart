import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../client/file_client.dart';

class PdfPreviewScreen extends StatefulWidget {
  final FileClient client;
  final String alias;
  final String remotePath;
  final String fileName;

  const PdfPreviewScreen({
    super.key,
    required this.client,
    required this.alias,
    required this.remotePath,
    required this.fileName,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  bool _loading = true;
  String? _error;
  PdfControllerPinch? _controller;
  int _currentPage = 1;
  int _totalPages = 0;

  bool _isWidgetTestEnvironment() {
    return WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result =
        await widget.client.downloadFile(widget.alias, widget.remotePath);
    if (!mounted) return;

    if (result.isErr) {
      setState(() {
        _loading = false;
        _error = result.errorMessage;
      });
      return;
    }

    if (_isWidgetTestEnvironment()) {
      setState(() {
        _loading = false;
        _error = 'PDF rendering is unavailable in widget tests.';
      });
      return;
    }

    try {
      final doc = await PdfDocument.openData(result.unwrap);
      _controller?.dispose();
      _controller = PdfControllerPinch(document: Future.value(doc));
      setState(() {
        _loading = false;
        _currentPage = 1;
        _totalPages = doc.pagesCount;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Could not open PDF file.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          if (!_loading && _error == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('$_currentPage / $_totalPages'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return PdfViewPinch(
      controller: _controller!,
      onDocumentLoaded: (document) {
        if (!mounted) return;
        setState(() => _totalPages = document.pagesCount);
      },
      onPageChanged: (page) {
        if (!mounted) return;
        setState(() => _currentPage = page);
      },
    );
  }
}
