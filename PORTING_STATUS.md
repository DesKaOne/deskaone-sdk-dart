# Go → Dart SDK parity audit

Source: `github.com/DesKaOne/deskaone-sdk` (Go `main`).
Target: `github.com/DesKaOne/deskaone-sdk-dart` (Dart `feat/go-sdk-parity`).

This file documents actual implemented APIs, not promises of future parity.

| Go package / behavior | Dart equivalent | Status |
| --- | --- | --- |
| `proxy.ProxyType` HTTP, HTTPS, SOCKS4, SOCKS5 | `ProxyType` | Implemented in this branch |
| URL parsing, explicit type / credentials, proxy pickers | `ProxyConfig`, `ProxyPicker` | Implemented; Dart has optional shorthand `host:port` |
| HTTP CONNECT | `network/handler/http.dart` | Implemented |
| HTTPS proxy TLS handshake and HTTP CONNECT | `network/handler/https.dart` | Implemented for plain destination sockets; verified TLS to proxy |
| SOCKS4/SOCKS4a and SOCKS5 | `network/handler/socks4.dart`, `socks5.dart` | Already implemented |
| Direct / proxied TCP | `TCPClient` | Already implemented |
| TLS to ordinary origin, including HTTP CONNECT/SOCKS | `TCPClient(secure: true)` | Already implemented; handlers now pause subscriptions before upgrade |
| TLS-to-HTTPS-proxy plus TLS-to-HTTPS/WSS target | No complete equivalent | **Not supported**: needs nested TLS on an existing SecureSocket |
| Go HTTP client (redirects, response decoding) | `HTTPClient` | Existing Dart implementation; not a byte-for-byte port |
| WebSocket client and reconnect | `WebSocketClient`, `ReconnectWebSocketClient` | Existing Dart implementation |
| Little-endian NetworkStream | `NetworkStream` | Already implemented |
| Typed generic BaseEngine CRUD, batch, upsert, pagination | `EngineSpec`, `BaseEngine`, `SqlDialect` | Ported in this branch (query-based interface) |
| Transactional database migrations and SQL file loader | `DatabaseMigrations`; `Database.migrate` / `migrateFiles` | Ported in this branch |
| SQLite / PostgreSQL database access | `Database`, `SQLiteDatabase`, `PostgresDatabase` | Already implemented; database pooling and Go's SQLite maintenance ticker are not ported |
| Go Storage encrypted key-value / backup | `SecureStorage` | Similar API, **not binary-format compatible**: Go uses legacy CBC, Dart uses authenticated encryption format |
| Debouncer / EventEmitter / Logger / terminal colors | `utils/*` | Already implemented |
| `termcolor` Windows terminal flags | `utils/term_color.dart` | Similar behavior; platform-specific differences |
| Go's CLI examples | `example/*` | Network / DB / storage examples provided; not a one-to-one CLI translation |
| Dart blockchain BIP and secp256k1 utilities | `lib/blockchain` | Dart-only extensions retained |

## Compatibility policies

- `https://` in a **proxy URL** means TLS to proxy; `http://` proxy can
  still tunnel HTTPS destinations.
- Proxy TLS certificate verification remains on by default.
- Certificate trust settings for proxy and target are separate in Dart.
- No fallback from verified TLS proxy to plaintext proxy.
- `ProxyConfig.toString()` redacts passwords. Use `toUrlString()`
  intentionally when serializing credentials.
- Generic SQL engines validate table/column identifiers and bind values.
- Database migration batches execute transactionally, matching Go. There is
  no migration-version table in the Go implementation.
- Storage files cannot be exchanged between Go and Dart directly. Never
  treat Go's unauthenticated legacy CBC format as the current Dart format.

## Validation

Run with Dart SDK >=3.11.4:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

The HTTPS proxy test uses a temporary self-signed certificate generated
with OpenSSL; it skips the local TLS fixture when the `openssl` executable
is unavailable.

The full Dart test suite and CI results must pass before merging or
claiming production parity.
