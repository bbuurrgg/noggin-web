class GoogleDriveConfig {
  static const apiKey = String.fromEnvironment('GOOGLE_DRIVE_API_KEY');
  static const oauthRedirectUrl = 'noggin://auth-callback';
  static const oauthScopes =
      'openid email profile https://www.googleapis.com/auth/drive.metadata.readonly';
  static const oauthQueryParams = {
    'access_type': 'offline',
    'prompt': 'consent',
    'include_granted_scopes': 'true',
  };

  static bool get hasApiKey => apiKey.trim().isNotEmpty;
}
