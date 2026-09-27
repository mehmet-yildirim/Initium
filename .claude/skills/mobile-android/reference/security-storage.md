# Keystore + Tink + DataStore token store

`EncryptedSharedPreferences` / `EncryptedFile` (`androidx.security:security-crypto`) are
deprecated. Encrypt with Tink AEAD whose keyset is wrapped by an Android Keystore master key, and
persist with DataStore.

Options:

- **Tink directly** (shown below): `com.google.crypto.tink:tink-android` + `androidx.datastore:datastore`.
- **`androidx.datastore:datastore-tink`** provides a ready `AeadSerializer`, but it is still in the
  1.3.0 alpha line — adopt only if your project accepts alpha dependencies.

## Port (domain)

```kotlin
interface TokenStore {
    val session: Flow<Session>
    suspend fun save(session: Session)
    suspend fun clear()
}

@Serializable
data class Session(val accessToken: String? = null, val refreshToken: String? = null)
```

## Adapter (data)

```kotlin
private const val KEYSET_NAME = "session_keyset"
private const val KEYSET_PREFS = "session_keyset_prefs"
private const val MASTER_KEY_URI = "android-keystore://session_master_key"
private const val SESSION_FILE = "session.pb.enc"

private class EncryptedSessionSerializer(private val aead: Aead) : Serializer<Session> {
    private val associatedData = SESSION_FILE.encodeToByteArray()

    override val defaultValue = Session()

    override suspend fun readFrom(input: InputStream): Session {
        val ciphertext = input.readBytes()
        if (ciphertext.isEmpty()) return defaultValue
        return try {
            val plaintext = aead.decrypt(ciphertext, associatedData)
            Json.decodeFromString<Session>(plaintext.decodeToString())
        } catch (e: GeneralSecurityException) {
            throw CorruptionException("Session cannot be decrypted", e)
        } catch (e: SerializationException) {
            throw CorruptionException("Session cannot be parsed", e)
        }
    }

    override suspend fun writeTo(t: Session, output: OutputStream) {
        val plaintext = Json.encodeToString(t).encodeToByteArray()
        output.write(aead.encrypt(plaintext, associatedData))
    }
}

class DataStoreTokenStore(context: Context, scope: CoroutineScope) : TokenStore {
    private val dataStore: DataStore<Session>

    init {
        AeadConfig.register()
        val aead = AndroidKeysetManager.Builder()
            .withSharedPref(context, KEYSET_NAME, KEYSET_PREFS)
            .withKeyTemplate(KeyTemplate.createFrom(PredefinedAeadParameters.AES256_GCM))
            .withMasterKeyUri(MASTER_KEY_URI)
            .build()
            .keysetHandle
            .getPrimitive(RegistryConfiguration.get(), Aead::class.java)
        dataStore = DataStoreFactory.create(
            serializer = EncryptedSessionSerializer(aead),
            corruptionHandler = ReplaceFileCorruptionHandler { Session() },
            scope = scope,
            produceFile = { context.dataStoreFile(SESSION_FILE) },
        )
    }

    override val session: Flow<Session> = dataStore.data

    override suspend fun save(session: Session) {
        dataStore.updateData { session }
    }

    override suspend fun clear() {
        dataStore.updateData { Session() }
    }
}
```

Notes:

- Create exactly one instance per file (Hilt `@Singleton`); multiple DataStores on one file throw.
- The corruption handler resets to an empty session — the user signs in again. Log the event via
  the `Logger` port without the payload.
- The Tink keyset (encrypted by the Keystore key) lives in its own SharedPreferences file; that file
  holds no plaintext secrets.
- Exclude `session.pb.enc` and the keyset prefs from backup and device transfer in
  `res/xml/data_extraction_rules.xml`; the Keystore key never leaves the device.
- For credentials that need user presence, create a separate Keystore key with
  `setUserAuthenticationRequired(true)` and gate it with `BiometricPrompt`.
- Migrating from EncryptedSharedPreferences: read once with the old API, write to the new store,
  then delete the old file; remove `security-crypto` afterwards.
