import 'package:web/web.dart' as web;
import 'auth_location_stub.dart' show clearedRecoveryUri;

void clearRecoveryLocation() {
  web.window.history.replaceState(
    null,
    '',
    clearedRecoveryUri(Uri.base).toString(),
  );
}