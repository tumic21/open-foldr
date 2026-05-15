import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

typedef FileIconData = ({IconData icon, Color color});

/// Returns folder icon data with color appropriate for current theme.
FileIconData folderIconData(BuildContext context) {
  final brightness = Theme.of(context).brightness;
  return (
    icon: Icons.folder,
    color: FileTypeColors.getColor(
      FileTypeColors.folderLight,
      FileTypeColors.folderDark,
      brightness,
    ),
  );
}

/// Returns the appropriate icon and colour for a file based on its [name].
FileIconData fileTypeIcon(String name, BuildContext context) {
  final brightness = Theme.of(context).brightness;

  if (!name.contains('.')) {
    return (
      icon: Icons.insert_drive_file,
      color: FileTypeColors.getColor(
        FileTypeColors.genericLight,
        FileTypeColors.genericDark,
        brightness,
      ),
    );
  }

  final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'svg' || 'heic' =>
      (
        icon: Icons.image,
        color: FileTypeColors.getColor(
          FileTypeColors.imageLight,
          FileTypeColors.imageDark,
          brightness,
        ),
      ),
    'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' || 'flv' =>
      (
        icon: Icons.video_file,
        color: FileTypeColors.getColor(
          FileTypeColors.videoLight,
          FileTypeColors.videoDark,
          brightness,
        ),
      ),
    'mp3' || 'wav' || 'flac' || 'ogg' || 'aac' || 'm4a' =>
      (
        icon: Icons.audio_file,
        color: FileTypeColors.getColor(
          FileTypeColors.audioLight,
          FileTypeColors.audioDark,
          brightness,
        ),
      ),
    'pdf' =>
      (
        icon: Icons.picture_as_pdf,
        color: FileTypeColors.getColor(
          FileTypeColors.pdfLight,
          FileTypeColors.pdfDark,
          brightness,
        ),
      ),
    'zip' || 'tar' || 'gz' || 'bz2' || 'xz' || '7z' || 'rar' =>
      (
        icon: Icons.folder_zip,
        color: FileTypeColors.getColor(
          FileTypeColors.archiveLight,
          FileTypeColors.archiveDark,
          brightness,
        ),
      ),
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
      (
        icon: Icons.code,
        color: FileTypeColors.getColor(
          FileTypeColors.codeLight,
          FileTypeColors.codeDark,
          brightness,
        ),
      ),
    'txt' || 'md' || 'rst' =>
      (
        icon: Icons.description,
        color: FileTypeColors.getColor(
          FileTypeColors.textLight,
          FileTypeColors.textDark,
          brightness,
        ),
      ),
    'doc' || 'docx' =>
      (
        icon: Icons.article,
        color: FileTypeColors.getColor(
          FileTypeColors.documentLight,
          FileTypeColors.documentDark,
          brightness,
        ),
      ),
    'xls' || 'xlsx' || 'csv' =>
      (
        icon: Icons.table_chart,
        color: FileTypeColors.getColor(
          FileTypeColors.spreadsheetLight,
          FileTypeColors.spreadsheetDark,
          brightness,
        ),
      ),
    'ppt' || 'pptx' =>
      (
        icon: Icons.slideshow,
        color: FileTypeColors.getColor(
          FileTypeColors.presentationLight,
          FileTypeColors.presentationDark,
          brightness,
        ),
      ),
    _ =>
      (
        icon: Icons.insert_drive_file,
        color: FileTypeColors.getColor(
          FileTypeColors.genericLight,
          FileTypeColors.genericDark,
          brightness,
        ),
      ),
  };
}
