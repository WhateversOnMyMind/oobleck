import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 (RFC 8018), [length] <= 32 bytes is all sync needs.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations, {int length = 32}) {
  final mac = Hmac(sha256, password);
  final out = Uint8List(32);
  // Block 1 only: U1 = HMAC(P, S || INT(1)).
  var u = mac.convert([...salt, 0, 0, 0, 1]).bytes;
  out.setAll(0, u);
  for (var i = 1; i < iterations; i++) {
    u = mac.convert(u).bytes;
    for (var j = 0; j < 32; j++) {
      out[j] ^= u[j];
    }
  }
  return Uint8List.sublistView(out, 0, length);
}

/// Rounds for [deriveLoginKey]. Changing it locks every account out, so don't.
const syncKeyIterations = 100000;

/// The value sent to the server in place of the password: PBKDF2 of the
/// password with the user name as salt, as lower-case hex. The server only
/// stores a salted hash of it, so guessing a password from a leaked database
/// costs a full PBKDF2 per guess. Runs on a background isolate.
Future<String> deriveLoginKey(String username, String password) {
  final user = username.trim().toLowerCase();
  return Isolate.run(() {
    final key = pbkdf2Sha256(utf8.encode(password), utf8.encode('oobleck-sync:$user'), syncKeyIterations);
    return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  });
}
