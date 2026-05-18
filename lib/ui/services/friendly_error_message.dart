String friendlyErrorMessage({
  required String code,
  required String fallbackMessage,
  required String operation,
}) {
  switch (code) {
    case 'PERMISSION_DENIED':
    case 'FORBIDDEN':
      return 'Permission denied. The host user cannot $operation here.';
    case 'NETWORK_ERROR':
      return 'Could not reach the host. Check the connection and try again.';
    case 'UNAUTHORIZED':
      return 'Session expired. Reconnect and try again.';
    case 'ALREADY_EXISTS':
      return 'A file or folder with that name already exists.';
    case 'NOT_FOUND':
      return 'This item was not found on the host. Refresh and try again.';
    case 'VERSION_CONFLICT':
      return 'The file changed on the host. Reload or save as a copy.';
    case 'PRECONDITION_REQUIRED':
      return 'This file already exists. Rename or overwrite it.';
    case 'INVALID_ARGUMENT':
      return 'The request was invalid. Please try again.';
    case 'NO_ACTIVE_SECRET':
    case 'SECRET_EXPIRED':
      return 'Pairing code is expired or already used. Ask host for a new code.';
    case 'INVALID_SECRET':
      return 'Pairing code is invalid. Check the code and retry.';
    case 'SERVER_ERROR':
    case 'INTERNAL':
      if (fallbackMessage.toLowerCase().contains('filesystem permission')) {
        return 'The host process is missing filesystem permissions for this action.';
      }
      return 'The host failed to $operation. Please try again.';
    default:
      if (fallbackMessage.startsWith('HTTP ')) {
        return 'The host failed to $operation. Please try again.';
      }
      return fallbackMessage;
  }
}
