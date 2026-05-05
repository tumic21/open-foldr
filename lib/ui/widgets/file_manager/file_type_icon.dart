import 'package:flutter/material.dart';

/// Returns the appropriate [IconData] for a file based on its [name] (extension).
IconData fileTypeIcon(String name) {
  if (!name.contains('.')) return Icons.insert_drive_file;
  final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' || 'heic' =>
      Icons.image,
    'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' => Icons.video_file,
    'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' || 'm4a' => Icons.audio_file,
    'pdf' => Icons.picture_as_pdf,
    'zip' || 'tar' || 'gz' || 'bz2' || 'xz' || '7z' || 'rar' =>
      Icons.folder_zip,
    'dart' ||
    'js' ||
    'ts' ||
    'py' ||
    'java' ||
    'kt' ||
    'c' ||
    'cpp' ||
    'h' ||
    'rs' ||
    'go' ||
    'rb' ||
    'swift' ||
    'json' ||
    'yaml' ||
    'yml' ||
    'xml' ||
    'html' ||
    'css' ||
    'sh' ||
    'bash' =>
      Icons.code,
    'txt' || 'md' || 'rst' => Icons.description,
    'doc' || 'docx' => Icons.article,
    'xls' || 'xlsx' || 'csv' => Icons.table_chart,
    'ppt' || 'pptx' => Icons.slideshow,
    _ => Icons.insert_drive_file,
  };
}
