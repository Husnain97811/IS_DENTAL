/// Google Drive app identity — from Google Cloud Console → APIs & Services
/// → Credentials → your "Desktop app" OAuth client.
///
/// For a Desktop app Google does not treat the client secret as secret
/// (it ships inside every installed copy), so it is fine here. What keeps
/// a clinic's files safe is the clinic's own Google sign-in plus the
/// DentOS encryption.
class DriveConfig {
  static const clientId = 'PASTE_CLIENT_ID.apps..com';
  static const clientSecret = 'PASTE_CLIENT_SECRET';

  /// Only files DentOS itself creates — never the rest of the clinic's
  /// Drive. Keeps Google's review light ("non-sensitive" scope).
  static const scope = 'https://www.googleapis.com/auth/drive.file';

  static bool get configured =>
      !clientId.startsWith('PASTE') && !clientSecret.startsWith('PASTE');
}
