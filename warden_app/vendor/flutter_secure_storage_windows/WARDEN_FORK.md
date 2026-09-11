# Wcash Warden Windows secure-storage fork

This directory is a source copy of `flutter_secure_storage_windows` 4.2.2.
Its upstream `LICENSE` is retained unchanged.

Warden-specific storage guarantees:

- The upstream asynchronous operation lock remains in place, so each public
  read-modify-write operation is serialized.
- Writes are encrypted into a unique same-directory temporary file, flushed,
  verified, and installed with Windows `ReplaceFileW` or `MoveFileExW`.
  First-file moves use `MOVEFILE_WRITE_THROUGH`; `ReplaceFileW` receives zero
  flags because its documented `REPLACEFILE_WRITE_THROUGH` value is not
  supported.
- A validated `.bak` recovery copy is refreshed after each committed write. An
  `.invalid` marker prevents an older backup from resurrecting a deleted or
  replaced value when a backup refresh is interrupted.
- Partial replacement failures restore the prior validated ciphertext. A
  `.restore` marker makes a transiently failed restoration retryable.
- Read, DPAPI, UTF-8, and JSON failures never delete the only ciphertext.
- Codec details and decoded payloads are excluded from logs and surfaced
  exceptions.

The portable atomic-storage engine and its file/replacement interfaces live in
`lib/src/atomic_file_storage.dart`. Its tests run without Windows or DPAPI;
the DPAPI and Windows replacement bindings still require a Windows test host.

## Integration

Warden selects this fork with the following local dependency override in
`warden_app/pubspec.yaml`:

```yaml
dependency_overrides:
  flutter_secure_storage_windows:
    path: vendor/flutter_secure_storage_windows
```

The committed `warden_app/pubspec.lock` must continue to resolve this package
from that relative path. A Windows release must not be produced if either the
override or lockfile source changes.
