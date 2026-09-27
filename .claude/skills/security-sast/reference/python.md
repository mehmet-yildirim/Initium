# Python security examples

Assumes Python 3.12+, Pydantic v2. Language rules: `lang-python`.

## Injection

```python
# BAD
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
# GOOD — driver placeholders (psycopg uses %s; sqlite3 uses ?)
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

# BAD
subprocess.run(f"ls {path}", shell=True)
# GOOD — list form, no shell, validated argument
subprocess.run(["ls", "--", path], check=True, timeout=10)
```

- Never `eval()`/`exec()` non-constant strings.

## Deserialization and parsing

```python
# BAD — pickle/marshal/shelve on untrusted bytes is remote code execution
data = pickle.loads(payload)

# GOOD — JSON plus schema validation
from pydantic import BaseModel, ConfigDict

class OrderIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    sku: str
    quantity: int

order = OrderIn.model_validate_json(payload)
```

- YAML: `yaml.safe_load`, never `yaml.load` with the default/unsafe loader.
- XML from untrusted sources: `defusedxml`.

## Password hashing

`passlib` is unmaintained and breaks on Python 3.13 (`crypt` removal). Use `pwdlib` or
`argon2-cffi`.

```python
# pip install "pwdlib[argon2]"
from pwdlib import PasswordHash

password_hash = PasswordHash.recommended()  # Argon2id

hashed = password_hash.hash(plain_password)
is_valid, updated_hash = password_hash.verify_and_update(plain_password, hashed)
if is_valid and updated_hash is not None:
    user_repository.update_password_hash(user_id, updated_hash)
```

```python
# pip install argon2-cffi
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

hasher = PasswordHasher()

def verify_password(stored_hash: str, plain_password: str) -> bool:
    try:
        return hasher.verify(stored_hash, plain_password)
    except VerifyMismatchError:
        return False
```

## Randomness and comparison

```python
import hmac
import secrets

token = secrets.token_urlsafe(32)                # never random.* for security
is_same = hmac.compare_digest(received_sig, expected_sig)
```

## Path traversal

```python
from pathlib import Path

UPLOAD_ROOT = Path("/srv/uploads").resolve()

def resolve_upload(file_name: str) -> Path:
    target = (UPLOAD_ROOT / file_name).resolve()
    if not target.is_relative_to(UPLOAD_ROOT):
        raise PathTraversalError(file_name)
    return target
```

## SSRF (A01)

```python
import ipaddress
import socket
from urllib.parse import urlsplit

ALLOWED_HOSTS = frozenset({"api.partner.example"})

def assert_safe_outbound_url(raw_url: str) -> str:
    parts = urlsplit(raw_url)
    if parts.scheme != "https" or parts.hostname not in ALLOWED_HOSTS:
        raise SsrfBlockedError(parts.hostname)
    for *_, sockaddr in socket.getaddrinfo(parts.hostname, parts.port or 443, proto=socket.IPPROTO_TCP):
        if not ipaddress.ip_address(sockaddr[0]).is_global:
            raise SsrfBlockedError(parts.hostname)
    return raw_url
```

- Call the HTTP client with a timeout and redirects disabled
  (`httpx.Client(timeout=10, follow_redirects=False)`).

## Exceptional conditions (A10)

```python
def can_read_document(actor_id: str, document_id: str) -> bool:
    try:
        return policy_client.is_allowed(actor_id, "document:read", document_id)
    except PolicyUnavailableError:
        logger.exception("policy check failed; denying", extra={"actor_id": actor_id})
        return False  # fail closed
```

- Use context managers (`with`) for files, locks, DB sessions and transactions.
- Never `except Exception: pass`; catch specific exceptions and log or re-raise.

## Tooling

- `pip-audit` (PyPA, OSV/PyPI advisories) and/or `safety scan` (Safety CLI 3; `safety check` is
  deprecated) in CI — fail on high/critical.
- Bandit (`bandit -r src -ll`) plus Semgrep `p/python`.
- Type-check with mypy or pyright in strict mode; validate all external data with Pydantic.
