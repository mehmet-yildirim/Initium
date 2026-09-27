---
name: security-sast
description: Security SAST patterns — language-specific vulnerability detection, OWASP Top 10, CVE scanning, secret detection. Apply when writing security-sensitive code or reviewing changes. Use when writing security-sensitive code (auth, input handling, crypto, file access) or reviewing changes for vulnerabilities.
paths:
  - "**/*.ts"
  - "**/*.js"
  - "**/*.py"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.cs"
  - "**/*.go"
  - "**/*.swift"
  - "**/*.dart"
  - "**/*.rb"
  - "**/*.php"
---

# Security SAST — Vulnerability Detection Patterns

This rule provides language-specific security patterns to detect and prevent common vulnerabilities.
Always apply when writing code that handles authentication, authorization, user input, data persistence,
or external service communication.

## Universal Rules (All Languages)

### Input Validation — Required at Every System Boundary
```
BOUNDARY: HTTP request body, query params, path params
BOUNDARY: Message queue message body
BOUNDARY: File uploads (name, size, type, content)
BOUNDARY: External API responses
BOUNDARY: Database records read then used in further operations
BOUNDARY: CLI arguments

Rule: Validate schema + type + business rules BEFORE processing.
Never trust data that crosses a trust boundary.
```

### SQL / NoSQL / Command Injection — Zero Tolerance
```
FORBIDDEN (all languages):
  SQL: "SELECT * FROM users WHERE id = '" + userId + "'"
  SQL: f"DELETE FROM orders WHERE id = {order_id}"
  CMD: exec("git clone " + repoUrl)
  CMD: subprocess.run(f"ls {path}", shell=True)

REQUIRED: Parameterized queries, prepared statements, ORM query builders.
REQUIRED: Allowlist validation before any shell execution.
NEVER: shell=True / exec() / system() with any non-constant string.
```

### Secret / Credential Anti-Patterns
```
FORBIDDEN: Hardcoded passwords, API keys, tokens in any source file
FORBIDDEN: Secrets in environment variable defaults in code
FORBIDDEN: Logging of credentials, tokens, PII, or session data
FORBIDDEN: Secrets in URLs (query params, path segments)
FORBIDDEN: Secrets committed to git (including test fixtures)

REQUIRED: Load secrets from environment variables or secrets manager at runtime
REQUIRED: .env files with real values in .gitignore
REQUIRED: rotate any accidentally committed secret immediately
```

---

## JavaScript / TypeScript

### Injection
```typescript
// CRITICAL — SQL injection
// BAD:
const user = await db.query(`SELECT * FROM users WHERE email = '${email}'`);
// GOOD:
const user = await db.query('SELECT * FROM users WHERE email = $1', [email]);

// CRITICAL — Command injection
// BAD:
exec(`git clone ${repoUrl}`);
// GOOD:
execFile('git', ['clone', repoUrl]);  // args as array, never shell=true

// HIGH — Prototype pollution
// BAD:
Object.assign(target, userInput);  // if userInput has __proto__
// GOOD:
const clean = JSON.parse(JSON.stringify(userInput));  // or use lodash.merge with guard
```

### XSS
```typescript
// CRITICAL — DOM XSS
// BAD:
element.innerHTML = userInput;
document.write(userInput);
// GOOD:
element.textContent = userInput;

// CRITICAL — React XSS
// BAD:
<div dangerouslySetInnerHTML={{ __html: userInput }} />
// GOOD — only with sanitized content:
import DOMPurify from 'dompurify';
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(trustedMarkdown) }} />
```

### Authentication
```typescript
// HIGH — Weak random for tokens
// BAD:
const token = Math.random().toString(36);
// GOOD:
import { randomBytes } from 'node:crypto';
const token = randomBytes(32).toString('hex');

// HIGH — JWT: never trust without verification
// BAD:
const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
// GOOD:
const payload = jwt.verify(token, process.env.JWT_SECRET, { algorithms: ['HS256'] });

// HIGH — Timing attack on token comparison
// BAD:
if (userToken === storedToken)
// GOOD:
import { timingSafeEqual } from 'node:crypto';
timingSafeEqual(Buffer.from(userToken), Buffer.from(storedToken))
```

### Path Traversal
```typescript
// HIGH — Path traversal
// BAD:
const file = fs.readFileSync(`./uploads/${req.params.filename}`);
// GOOD:
import { resolve, join } from 'node:path';
const UPLOAD_DIR = resolve('./uploads');
const filePath = join(UPLOAD_DIR, req.params.filename);
if (!filePath.startsWith(UPLOAD_DIR + path.sep)) throw new Error('Path traversal detected');
const file = fs.readFileSync(filePath);
```

### npm-specific
```
RULE: Run `npm audit --audit-level=high` in CI — fail on HIGH+
RULE: No `--ignore-scripts` suppression without justification
RULE: `package-lock.json` or `yarn.lock` committed and verified
RULE: `npm ci` in CI — not `npm install` (respects lockfile)
```

---

## Python

### Injection
```python
# CRITICAL — SQL injection
# BAD:
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
cursor.execute("SELECT * FROM users WHERE id = " + user_id)
# GOOD:
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# CRITICAL — Command injection
# BAD:
subprocess.run(f"ls {path}", shell=True)
os.system(f"rm {filename}")
# GOOD:
subprocess.run(["ls", path])  # List form, no shell
```

### Deserialization
```python
# CRITICAL — Pickle deserialization of untrusted data
# BAD:
data = pickle.loads(user_data)  # RCE if user_data is malicious
# GOOD:
import json
data = json.loads(user_data)  # JSON only; validate schema with Pydantic
```

### Cryptography
```python
# HIGH — Weak hashing for passwords
# BAD:
import hashlib
hashed = hashlib.md5(password.encode()).hexdigest()
# GOOD:
from passlib.hash import argon2
hashed = argon2.hash(password)

# HIGH — Insecure random
# BAD:
import random
token = random.randbytes(16)  # NOT cryptographically secure
# GOOD:
import secrets
token = secrets.token_hex(32)
```

### File Operations
```python
# HIGH — Path traversal
# BAD:
with open(f"/uploads/{filename}") as f: ...
# GOOD:
import pathlib
base = pathlib.Path("/uploads").resolve()
target = (base / filename).resolve()
if not target.is_relative_to(base):
    raise ValueError("Path traversal detected")
```

### Python-specific
```
RULE: `safety check` or `pip-audit` in CI — fail on CRITICAL/HIGH CVEs
RULE: Type annotations + mypy strict — catches None dereferences
RULE: Pydantic or marshmallow for ALL external data validation
RULE: Never `eval()` or `exec()` on any non-constant string
```

---

## Java

### Injection
```java
// CRITICAL — SQL injection
// BAD:
stmt.execute("SELECT * FROM users WHERE id = " + userId);
// GOOD:
PreparedStatement ps = conn.prepareStatement("SELECT * FROM users WHERE id = ?");
ps.setString(1, userId);

// CRITICAL — JNDI injection (Log4Shell class)
// BAD:
logger.error("User: " + userInput);  // if Log4j 2.x < 2.17.1
// GOOD: upgrade Log4j; disable JNDI lookups: log4j2.formatMsgNoLookups=true

// HIGH — XML External Entity (XXE)
// BAD:
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
DocumentBuilder db = dbf.newDocumentBuilder();
// GOOD: disable external entities:
dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
dbf.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
```

### Deserialization
```java
// CRITICAL — Java deserialization of untrusted data
// BAD:
ObjectInputStream ois = new ObjectInputStream(untrustedStream);
Object obj = ois.readObject();
// GOOD: Use JSON (Jackson/Gson) or validate input before deserialization
// OR: use a deserialization filter (Java 17+): ObjectInputFilter
```

### Cryptography
```java
// HIGH — Weak algorithm
// BAD:
MessageDigest md = MessageDigest.getInstance("MD5");
Cipher c = Cipher.getInstance("DES");
// GOOD:
MessageDigest md = MessageDigest.getInstance("SHA-256");
Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
// Passwords: BCryptPasswordEncoder (Spring) or Argon2
```

### Spring Security
```java
// CRITICAL — CSRF disabled
// BAD:
http.csrf().disable()  // Never in production for stateful sessions
// GOOD: enable CSRF, or use stateless JWT

// HIGH — Actuator endpoints exposed
// BAD (application.properties):
management.endpoints.web.exposure.include=*
// GOOD:
management.endpoints.web.exposure.include=health,info
management.endpoints.web.base-path=/internal/actuator
```

---

## Go

### Injection
```go
// CRITICAL — SQL injection
// BAD:
db.Query("SELECT * FROM users WHERE id = " + id)
// GOOD:
db.Query("SELECT * FROM users WHERE id = $1", id)

// HIGH — Command injection
// BAD:
exec.Command("sh", "-c", "ls " + userPath).Run()
// GOOD:
exec.Command("ls", userPath).Run()  // args as separate strings
```

### Cryptography
```go
// HIGH — Weak random
// BAD:
import "math/rand"
token := rand.Int()
// GOOD:
import "crypto/rand"
b := make([]byte, 32)
rand.Read(b)

// HIGH — Weak TLS config
// BAD:
tls.Config{InsecureSkipVerify: true}  // Never in production
// GOOD:
tls.Config{MinVersion: tls.VersionTLS12}
```

### Path Traversal
```go
// HIGH — Path traversal
// BAD:
filepath.Join("/uploads", r.URL.Query().Get("file"))
// GOOD:
base := filepath.Clean("/uploads")
target := filepath.Join(base, filepath.Clean(r.URL.Query().Get("file")))
if !strings.HasPrefix(target, base + string(os.PathSeparator)) {
    http.Error(w, "forbidden", http.StatusForbidden); return
}
```

---

## Mobile — iOS (Swift)

```swift
// HIGH — Sensitive data in UserDefaults (not encrypted)
// BAD:
UserDefaults.standard.set(authToken, forKey: "token")
// GOOD:
// Use Keychain via KeychainSwift library or Security framework

// HIGH — Logging sensitive data
// BAD:
print("User token: \(token)")
// GOOD: Remove ALL print/NSLog of sensitive data; use os.Logger with privacy labels
// os.Logger().debug("Auth: \(token, privacy: .private)")

// HIGH — Insecure random
// BAD:
let n = Int.random(in: 0..<100)  // OK for non-security; BAD for token generation
// GOOD:
import CryptoKit
let bytes = SymmetricKey(size: .bits256)  // or SecRandomCopyBytes

// HIGH — Certificate pinning bypass indicators
// NEVER: URLSession(configuration: .default) with custom delegate that ignores errors
// NEVER: challenge.sender?.continueWithoutCredential(for: challenge)
```

---

## Mobile — Android (Kotlin)

```kotlin
// HIGH — Hardcoded credentials
// BAD:
val apiKey = "sk-prod-1234567890"
// GOOD: Load from BuildConfig (injected at build time, not in source)

// HIGH — Sensitive data in SharedPreferences (unencrypted)
// BAD:
prefs.edit().putString("token", token).apply()
// GOOD:
EncryptedSharedPreferences.create("secure_prefs", masterKey, context,
    AES256_SIV, AES256_GCM)

// HIGH — Exported components without permission
// BAD (AndroidManifest.xml):
<activity android:name=".AdminActivity" android:exported="true" />
// GOOD:
<activity android:name=".AdminActivity" android:exported="false" />
// Or: android:permission="com.example.ADMIN"

// CRITICAL — SQL injection in SQLiteDatabase
// BAD:
db.rawQuery("SELECT * FROM users WHERE id = " + id, null)
// GOOD:
db.query("users", null, "id = ?", arrayOf(id), null, null, null)
```

---

## OWASP Top 10 — Quick Reference Checklist

When reviewing any code change, mentally check:

| # | Category | Quick Check |
|---|----------|------------|
| A01 | Broken Access Control | Is ownership verified before data access? |
| A02 | Cryptographic Failures | Using strong algorithms? TLS everywhere? No PII in logs? |
| A03 | Injection | All queries parameterized? No shell=True with user data? |
| A04 | Insecure Design | Rate limiting? Account lockout? Business logic validated? |
| A05 | Misconfiguration | No debug mode in prod? Security headers set? |
| A06 | Vulnerable Components | Dependencies audited? No known CVEs in use? |
| A07 | Auth Failures | Tokens cryptographically random? Sessions invalidated on logout? |
| A08 | Data Integrity | No unsafe deserialization? Dependency lockfiles committed? |
| A09 | Logging Failures | Auth failures logged? No PII in logs? Correlation IDs present? |
| A10 | SSRF | User-supplied URLs allowlisted before fetch? Internal IPs blocked? |
