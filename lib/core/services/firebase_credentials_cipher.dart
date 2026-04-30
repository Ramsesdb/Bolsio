import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Symmetric cipher for FlutterSecureStorage credentials that need to be
/// sync'd to Firestore.
///
/// Threat model: this is pseudo-security. If an attacker has access to the
/// user's Firebase account they already have the ciphertext AND the UID;
/// combined with the hardcoded pepper baked into the app binary they can
/// decrypt. The point is to avoid storing API keys as plain strings visible
/// in the Firestore console / backups / server-side logs.
///
/// Scheme:
///   - 256-bit key derived via PBKDF2-HMAC-SHA256 from (uid + pepper).
///     100k iterations chosen as a reasonable middle ground between mobile
///     runtime cost and offline attack cost. Key derivation is cached per
///     uid to avoid re-running PBKDF2 for every field on a sync.
///   - AES-GCM 128-bit nonce, 128-bit auth tag.
///   - On-wire format: base64(nonce || ciphertext || mac).
class FirebaseCredentialsCipher {
  FirebaseCredentialsCipher._();
  static final FirebaseCredentialsCipher instance =
      FirebaseCredentialsCipher._();

  // Long random constant baked into the app. Changing this invalidates every
  // already-synced credential (users would need to re-enter on the other
  // devices). DO NOT rotate casually.
  static const _pepper =
      'bolsio.v1.pepper.3f7a2c91d4e58b6ac0ef1d92a73b4c8e5f6079182a3b4c5d6e7f80912a3b4c5d6';

  static const _iterations = 100000;
  static const _keyLengthBytes = 32; // 256-bit AES key
  static const _nonceLengthBytes = 12; // AES-GCM standard

  final AesGcm _aesGcm = AesGcm.with256bits();
  final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: _keyLengthBytes * 8,
  );

  final Map<String, SecretKey> _keyCache = {};

  Future<SecretKey> _keyForUser(String uid) async {
    final cached = _keyCache[uid];
    if (cached != null) return cached;

    final secret = SecretKey(utf8.encode(uid + _pepper));
    final salt = utf8.encode('bolsio.credentials.salt.v1:$uid');

    final derived = await _pbkdf2.deriveKey(secretKey: secret, nonce: salt);
    _keyCache[uid] = derived;
    return derived;
  }

  /// Encrypt [plaintext] for [uid]. Returns base64 of nonce || ciphertext || tag.
  Future<String> encryptForUser(String plaintext, String uid) async {
    final key = await _keyForUser(uid);
    final nonce = _aesGcm.newNonce(); // 12 bytes, random per message
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );

    final bb = BytesBuilder(copy: false)
      ..add(secretBox.nonce)
      ..add(secretBox.cipherText)
      ..add(secretBox.mac.bytes);
    return base64Encode(bb.toBytes());
  }

  /// Decrypt a payload produced by [encryptForUser]. Throws on tamper or
  /// wrong key.
  Future<String> decryptForUser(String ciphertextB64, String uid) async {
    final raw = base64Decode(ciphertextB64);
    if (raw.length < _nonceLengthBytes + 16) {
      throw const FormatException('ciphertext too short');
    }

    final nonce = raw.sublist(0, _nonceLengthBytes);
    final macStart = raw.length - 16; // GCM tag is 16 bytes
    final cipherText = raw.sublist(_nonceLengthBytes, macStart);
    final mac = Mac(raw.sublist(macStart));

    final key = await _keyForUser(uid);
    final clear = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }
}

