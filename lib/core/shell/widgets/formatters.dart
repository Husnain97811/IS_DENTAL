import 'package:flutter/services.dart';

class CnicInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Strip everything except digits, cap at 13
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 13 ? digits.substring(0, 13) : digits;

    // Rebuild as XXXXX-XXXXXXX-X
    final buf = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 5 || i == 12) buf.write('-');
      buf.write(capped[i]);
    }
    final formatted = buf.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
