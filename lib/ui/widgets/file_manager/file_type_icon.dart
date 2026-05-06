import 'package:flutter/material.dart';

typedef FileIconData = ({IconData icon, Color color});

/// Folder icon with a warm amber colour.
const FileIconData folderIconData = (
  icon: Icons.folder,
  color: Color(0xFFFFA000),
);

/// Returns the appropriate icon and colour for a file based on its [name].
FileIconData fileTypeIcon(String name) {
  if (!name.contains('.')) {
    return (icon: Icons.insert_drive_file, color: const Color(0xFF607D8B));
  }
  final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' || 'heic' =>
      (icon: Icons.image, color: const Color(0xFF9C27B0)),
    'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' =>
      (icon: Icons.video_file, color: const Color(0xFFE53935)),
    'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' || 'm4a' =>
      (icon: Icons.audio_file, color: const Color(0xFF43A047)),
    'pdf' =>
      (icon: Icons.picture_as_pdf, color: const Color(0xFFF4511E)),
    'zip' || 'tar' || 'gz' || 'bz2' || 'xz' || '7z' || 'rar' =>
      (icon: Icons.folder_zip, color: const Color(0xFF795548)),
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
      (icon: Icons.code, color: const Color(0xFF00ACC1)),
    'txt' || 'md' || 'rst' =>
      (icon: Icons.description, color: const Color(0xFF1E88E5)),
    'doc' || 'docx' =>
      (icon: Icons.article, color: const Color(0xFF1565C0)),
    'xls' || 'xlsx' || 'csv' =>
      (icon: Icons.table_chart, color: const Color(0xFF2E7D32)),
    'ppt' || 'pptx' =>
      (icon: Icons.slideshow, color: const Color(0xFFE65100)),
    _ => (icon: Icons.insert_drive_file, color: const Color(0xFF607D8B)),
  };
}
