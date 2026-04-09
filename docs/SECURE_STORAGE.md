# Secure Local Storage (Bondhu App)

The app now uses a **two-layer secure storage** system so sensitive data is encrypted at rest, similar to the web app’s IndexedDB + E2E approach.

## What’s in place

### 1. **SecureStorageService** (`lib/services/secure_storage_service.dart`)
- Uses **flutter_secure_storage** (Keychain on iOS, EncryptedSharedPreferences / Keystore on Android).
- Stores:
  - **DB encryption key** – 256-bit key used to encrypt the local Hive box.
  - **E2E keys** – Placeholders for future end-to-end encryption (private/public JWK).
- Use this only for **small secrets** (keys, tokens), not for large or high-churn data.

### 2. **EncryptedLocalStore** (`lib/services/encrypted_local_store.dart`)
- **Hive** box encrypted with **AES-256** (HiveAesCipher).
- Encryption key is stored in **SecureStorageService** (so it’s in the platform secure enclave).
- Used for:
  - **Chat list and messages** (same data that was in SharedPreferences, now encrypted at rest).
  - **Local user cache** (fallback user when offline).
- On **web** we skip Hive/secure init; the app keeps using SharedPreferences there.

### 3. **Migration and fallback**
- **Read**: Prefer EncryptedLocalStore when `isReady`; if missing, fall back to SharedPreferences.
- **Write**: When encrypted store is ready, we write to both EncryptedLocalStore and SharedPreferences so:
  - Data is encrypted at rest when the secure stack is available.
  - We don’t lose data if encrypted init fails (e.g. first launch or web).

## Comparison with web

| Web (bondhu-v2)        | App (Flutter)                         |
|------------------------|----------------------------------------|
| IndexedDB (Dexie)      | Hive encrypted box                    |
| E2E: RSA-OAEP + AES-GCM| E2E implemented: RSA-OAEP (SHA-256) + AES-256-GCM; keys in SecureStorage |
| Keys in memory / IDB   | Keys in SecureStorageService          |
| Private messages only on device | Chat + user cache encrypted on device   |

## E2E encryption (implemented)

- **E2EEncryptionService** uses RSA-OAEP (2048, SHA-256) + AES-256-GCM; payload format matches the web (`v`, `iv`, `content`, `key`).
- Private keys are stored in **SecureStorageService**; public key is synced to the profile in Appwrite.
- Private (1:1) text messages are encrypted before send and decrypted on receive; global/group messages remain plain.

**All local chat and user cache data is encrypted at rest** on the app using the secure storage system above. After migration, plaintext copies are removed from SharedPreferences (one-time wipe).
