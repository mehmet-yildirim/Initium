# On-device SQLite: Room, drift, SQLDelight

On-device databases migrate on the user's device at app start, from any older version the user
might still have. Every version step must exist and be tested; data loss is unrecoverable.

## Android — Room

```kotlin
@Database(
    entities = [UserEntity::class, PreferenceEntity::class],
    version = 5,             // bump on every schema change
    exportSchema = true,     // commit the exported JSON schemas; migration tests need them
)
abstract class AppDatabase : RoomDatabase() {
    companion object {
        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS user_preferences (
                        id TEXT NOT NULL PRIMARY KEY,
                        user_id TEXT NOT NULL,
                        key TEXT NOT NULL,
                        value TEXT,
                        created_at INTEGER NOT NULL,
                        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS idx_user_pref_user_key ON user_preferences(user_id, key)")
            }
        }
    }
}
```

```kotlin
Room.databaseBuilder(context, AppDatabase::class.java, "app.db")
    .addMigrations(MIGRATION_4_5)
    .build()
```

- Never use `fallbackToDestructiveMigration()` in release builds.
- Simple additive changes can use `@AutoMigration(from = 4, to = 5)` (needs exported schemas);
  renames and deletes need an `AutoMigrationSpec` (`@RenameColumn`, `@DeleteColumn`).
- SQLite cannot drop constraints or change column types in place: create a new table, copy
  data, drop the old one, rename the new one — inside the migration.

```kotlin
@RunWith(AndroidJUnit4::class)
class MigrationTest {
    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java,
    )

    @Test
    fun migrate4To5() {
        helper.createDatabase(TEST_DB, 4).use { db ->
            db.execSQL("INSERT INTO users (id, name, email, created_at) VALUES ('user-1', 'Alice', 'alice@example.com', 0)")
        }

        val migrated = helper.runMigrationsAndValidate(TEST_DB, 5, true, AppDatabase.MIGRATION_4_5)

        migrated.query("SELECT COUNT(*) FROM users").use { cursor ->
            cursor.moveToFirst()
            assertEquals(1, cursor.getInt(0))
        }
    }

    private companion object {
        const val TEST_DB = "migration-test"
    }
}
```

## Flutter — drift

```dart
@DriftDatabase(tables: [Users, UserPreferences])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(users, users.profileImageUrl);
          }
          if (from < 3) {
            await m.createTable(userPreferences);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
```

- Prefer drift's generated step-by-step migrations (`dart run drift_dev make-migrations`) over
  hand-written `from < n` chains once you have more than a few versions.
- Keep schema snapshots under version control and generate tests from them:

```bash
dart run drift_dev make-migrations   # dumps the current schema, generates steps and tests
```

The generated tests use drift_dev's `SchemaVerifier` to migrate from every stored schema
version and compare the result with the expected schema; run them in CI.

## Kotlin Multiplatform — SQLDelight

```sql
-- src/commonMain/sqldelight/migrations/2.sqm — upgrades version 1 → 2
CREATE TABLE user_preferences (
    id TEXT NOT NULL PRIMARY KEY,
    user_id TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_user_pref_user_key ON user_preferences(user_id, key);
```

```kotlin
// build.gradle.kts
sqldelight {
    databases {
        create("AppDatabase") {
            packageName.set("com.example.app.db")
            srcDirs.setFrom("src/commonMain/sqldelight")
            schemaOutputDirectory.set(file("src/commonMain/sqldelight/databases"))
            verifyMigrations.set(true)   // fails the build if .sqm files don't produce the .sq schema
        }
    }
}
```

- `.sqm` file `N.sqm` migrates from version N to N+1; commit the generated `.db` schema files
  so the generated `verify…Migration` Gradle task can check every step in CI.
