import 'dart:convert';

/// A vendor-signed, single-use permission to reset the owner password.
///
/// Signed with the same RSA key as licences, so the app can verify it
/// completely offline. Bound to one clinic, expires, and each nonce is
/// accepted only once.
class ResetToken {
  const ResetToken({
    required this.clinicId,
    required this.nonce,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
  });

  final String clinicId, nonce, signature;
  final DateTime issuedAt, expiresAt;

  /// The exact bytes the vendor signs. Field order is part of the contract.
  String canonicalPayload() => jsonEncode({
        'action': 'ownerReset',
        'clinicId': clinicId,
        'nonce': nonce,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      });

  Map<String, dynamic> toJson() => {
        ...jsonDecode(canonicalPayload()) as Map<String, dynamic>,
        'signature': signature,
      };

  factory ResetToken.fromJson(Map<String, dynamic> j) {
    if (j['action'] != 'ownerReset') {
      throw const FormatException('Not an owner reset token.');
    }
    return ResetToken(
      clinicId: j['clinicId'],
      nonce: j['nonce'],
      issuedAt: DateTime.parse(j['issuedAt']),
      expiresAt: DateTime.parse(j['expiresAt']),
      signature: j['signature'],
    );
  }
}