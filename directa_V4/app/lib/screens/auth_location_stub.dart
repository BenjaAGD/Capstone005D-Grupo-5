Uri clearedRecoveryUri(Uri uri) {
  final query = Map<String, String>.from(uri.queryParameters)
    ..remove('flow')
    ..remove('code')
    ..remove('error')
    ..remove('error_code')
    ..remove('error_description');

  return uri.replace(queryParameters: query, fragment: '');
}

void clearRecoveryLocation() {}