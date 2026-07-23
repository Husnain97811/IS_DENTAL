import 'dart:convert';

/// QR payload version. v1 = unsigned (P1). Bump to 2 when HMAC signing lands (P2).
const int kQrPayloadVersion = 1;

/// Patient login QR: {"c":"FAST-ISL-482913","p":"<patient-uuid>","v":1}
String buildPatientQrPayload({
  required String clinicId,
  required String patientUuid,
}) => jsonEncode({'c': clinicId, 'p': patientUuid, 'v': kQrPayloadVersion});

/// Clinic link QR (no patient): {"c":"FAST-ISL-482913","v":1}
String buildClinicQrPayload({required String clinicId}) =>
    jsonEncode({'c': clinicId, 'v': kQrPayloadVersion});
