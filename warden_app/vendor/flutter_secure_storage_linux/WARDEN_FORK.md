# Wcash Warden Linux secure-storage fork

This directory vendors `flutter_secure_storage_linux` 3.0.3 from pub.dev.
Its upstream BSD 3-Clause license is retained unchanged in `LICENSE`.

The downstream patch keeps `SecretSchema::name` bound to the current owned
label buffer after `SecretStorage::setLabel` changes that label. Upstream 3.0.3
left the schema pointing at the `std::string::c_str()` value captured by the
constructor; replacing the default label with the application's longer label
could invalidate that pointer before the first keyring operation.

`SecretStorageSchemaTest.SchemaNameTracksReallocatedLabelStorage` is a
keyring-independent native regression test for the pointer identity and value
across reallocating label changes.

The downstream parser also converts every malformed decrypted JSON payload to
the fixed `SecretStorageCorruptionError` platform error. It never forwards a
JSON exception or decrypted payload into logs or Dart-visible error details.
`SecretStorageParsingTest.CorruptionErrorNeverContainsDecryptedTokens` guards
that boundary.
