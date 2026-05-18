import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/ui/services/friendly_error_message.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('maps permission errors to actionable text', () {
      final message = friendlyErrorMessage(
        code: 'PERMISSION_DENIED',
        fallbackMessage: 'permission denied',
        operation: 'rename this item',
      );

      expect(
        message,
        'Permission denied. The host user cannot rename this item here.',
      );
    });

    test('maps unknown HTTP fallback to generic operation message', () {
      final message = friendlyErrorMessage(
        code: 'SERVER_ERROR',
        fallbackMessage: 'HTTP 500',
        operation: 'load this folder',
      );

      expect(
        message,
        'The host failed to load this folder. Please try again.',
      );
    });

    test('keeps custom fallback for unknown codes', () {
      final message = friendlyErrorMessage(
        code: 'CUSTOM_ERROR',
        fallbackMessage: 'Disk quota exceeded',
        operation: 'save this file',
      );

      expect(message, 'Disk quota exceeded');
    });
  });
}
