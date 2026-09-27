# Go security examples

Assumes Go 1.26/1.27 (keep patch releases current: `os.Root` symlink escape CVE-2026-39822 is fixed
in 1.25.12 and 1.26.5). Language rules: `lang-go`.

## Injection

```go
// BAD
db.QueryContext(ctx, "SELECT * FROM users WHERE id = " + id)
// GOOD — placeholders ($1 for pgx/lib/pq, ? for MySQL/SQLite)
db.QueryContext(ctx, "SELECT * FROM users WHERE id = $1", id)

// BAD
exec.CommandContext(ctx, "sh", "-c", "ls "+userPath)
// GOOD — separate arguments, no shell
exec.CommandContext(ctx, "ls", "--", userPath)
```

- HTML output: `html/template` (contextual escaping), never `text/template` for HTML.

## Randomness and TLS

```go
import "crypto/rand"

token := rand.Text() // Go 1.24+: 26 base32 chars (130 bits) from the CSPRNG

cfg := &tls.Config{MinVersion: tls.VersionTLS13} // use VersionTLS12 only for legacy clients
```

- Never `InsecureSkipVerify: true` outside tests; never `math/rand` for secrets.
- Compare secrets with `subtle.ConstantTimeCompare` (returns 0 on length mismatch, no panic).

## Path traversal — `os.Root`

```go
root, err := os.OpenRoot("/srv/uploads")
if err != nil {
	return fmt.Errorf("open upload root: %w", err)
}
defer root.Close()

// Rejects "..", absolute paths, and symlinks that escape the root
f, err := root.Open(fileName)
if err != nil {
	return fmt.Errorf("open upload %q: %w", fileName, err)
}
defer f.Close()
```

- `os.OpenInRoot(dir, name)` for one-off opens. The root directory itself must be trusted;
  `os.Root` does not stop access to unintended files *inside* the root.

## SSRF-safe HTTP client (A01)

Checking the IP inside the dialer covers DNS rebinding because the check runs on the address that
is actually dialed.

```go
var ErrSSRFBlocked = errors.New("outbound address not allowed")

func denyNonPublic(_, address string, _ syscall.RawConn) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return err
	}
	ip = ip.Unmap()
	if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
		return ErrSSRFBlocked
	}
	return nil
}

func NewOutboundClient() *http.Client {
	dialer := &net.Dialer{Timeout: 5 * time.Second, Control: denyNonPublic}
	return &http.Client{
		Timeout:   10 * time.Second,
		Transport: &http.Transport{DialContext: dialer.DialContext, Proxy: nil},
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
}
```

- Still allowlist hosts at the application layer; the dialer check is the backstop.

## Exceptional conditions (A10)

- Return wrapped errors (`fmt.Errorf("...: %w", err)`); never discard with `_` on security paths.
- Authorization helpers return `(allowed bool, err error)`; callers deny when `err != nil`.
- `defer` cleanup immediately after acquiring a resource; recover from panics only at the HTTP
  middleware boundary, log, and return a generic 500.

## Tooling

- `govulncheck ./...` (reachability-aware), `gosec ./...`, Semgrep `p/golang`, CodeQL `go`.
- Native fuzzing (`go test -fuzz`) for parsers and decoders.
