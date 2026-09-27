# Kotlin / Android security examples

Platform rules: `mobile-android`; language rules: `lang-kotlin`. Follow the OWASP MASVS.

## Secrets

- `BuildConfig` fields, `local.properties`, string resources, and NDK constants are all compiled
  into the APK/AAB and can be extracted. Do **not** put API secrets there.
- Keep third-party secrets on a backend; the app authenticates the user and receives short-lived,
  scoped tokens. Use Play Integrity to raise the bar for abusive clients.

## Local storage

`EncryptedSharedPreferences` / `EncryptedFile` (`androidx.security:security-crypto`) are
deprecated. Store data in DataStore or Room and encrypt sensitive values with Tink using a
Keystore-backed key.

```kotlin
import com.google.crypto.tink.Aead
import com.google.crypto.tink.KeyTemplates
import com.google.crypto.tink.RegistryConfiguration
import com.google.crypto.tink.aead.AeadConfig
import com.google.crypto.tink.integration.android.AndroidKeysetManager

class TokenCipher(context: Context) {
    private val aead: Aead

    init {
        AeadConfig.register()
        val keysetHandle = AndroidKeysetManager.Builder()
            .withSharedPref(context, "token_keyset", "token_keyset_prefs")
            .withKeyTemplate(KeyTemplates.get("AES256_GCM"))
            .withMasterKeyUri("android-keystore://token_master_key")
            .build()
            .keysetHandle
        aead = keysetHandle.getPrimitive(RegistryConfiguration.get(), Aead::class.java)
    }

    fun encrypt(plain: ByteArray, associatedData: ByteArray): ByteArray = aead.encrypt(plain, associatedData)
    fun decrypt(cipher: ByteArray, associatedData: ByteArray): ByteArray = aead.decrypt(cipher, associatedData)
}
```

- Exclude sensitive files from backup (`android:dataExtractionRules` / `fullBackupContent`).

## Components and IPC

```xml
<!-- Exported only when another app must start it, and then protected by a permission -->
<activity android:name=".AdminActivity" android:exported="false" />
```

- Validate every `Intent` extra; use explicit intents; `PendingIntent.FLAG_IMMUTABLE` by default.
- WebView: JavaScript off unless required; no `addJavascriptInterface` on untrusted content.

## Database

```kotlin
// BAD
db.rawQuery("SELECT * FROM users WHERE id = $id", null)
// GOOD
db.rawQuery("SELECT * FROM users WHERE id = ?", arrayOf(id))
// Room: @Query("SELECT * FROM users WHERE id = :id") binds parameters safely
```

## Transport

- Network Security Config with `cleartextTrafficPermitted="false"`; no custom `TrustManager`
  that accepts all certificates; no `HostnameVerifier` returning `true`.

## Tooling

- Android Lint security checks, Semgrep `p/kotlin`, CodeQL `java-kotlin`, MobSF for APK review.
- Gradle dependency verification and OSV-Scanner on Gradle lockfiles.
