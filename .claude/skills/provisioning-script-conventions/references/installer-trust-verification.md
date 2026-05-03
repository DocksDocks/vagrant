# Installer Trust Verification (SHA-384 Pattern)

<constraint>
Never run a curl-fetched installer as root without verifying its integrity against the publisher's canonical hash endpoint. Exit 1 on mismatch — do NOT fall back silently to a hardcoded hash or continue anyway.
</constraint>

## The Composer Pattern

The only curl-installer in this repo (Composer) uses SHA-384 verification:

```bash
COMPOSER_INSTALLER=/tmp/composer-installer.php
curl -fsSL --retry 4 --retry-delay 2 https://getcomposer.org/installer -o "$COMPOSER_INSTALLER"
EXPECTED_SIG=$(curl -fsSL --retry 4 --retry-delay 2 https://composer.github.io/installer.sig)
ACTUAL_SIG=$(sha384sum "$COMPOSER_INSTALLER" | awk '{print $1}')
if [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
  echo "✗ Composer installer SHA-384 mismatch — refusing to run." >&2
  echo "   expected: $EXPECTED_SIG" >&2
  echo "   actual:   $ACTUAL_SIG" >&2
  rm -f "$COMPOSER_INSTALLER"
  exit 1
fi
php "$COMPOSER_INSTALLER" --install-dir=/usr/local/bin --filename=composer
rm -f "$COMPOSER_INSTALLER"
```

Source: `scripts/20-packages.sh:31-42`

## Why apt Does Not Need This

`apt-get install` verifies package signatures against GPG-signed Release files. The package manager chain (apt → dpkg → installed binary) is already integrity-protected. Only curl-fetched installers executed directly as root need additional verification.

## Why the Hash Cannot Be Hardcoded

`composer.github.io/installer.sig` publishes a new SHA-384 hash with every Composer release. Hardcoding the hash means:
- The check fails on every new Composer release
- Provisioning aborts at `20-packages.sh` before any packages are installed
- The only fix is to update the hardcoded hash in the script

Source: `scripts/20-packages.sh:32` — hash is always fetched at runtime.

## Failure Modes

| Failure | Observable symptom | Fix |
|---|---|---|
| CDN delivers wrong installer | `sha384sum` mismatch → `exit 1` | Provisioning aborts at 20-packages.sh with "SHA-384 mismatch" |
| `composer.github.io/installer.sig` unreachable | `curl -f` fails → `set -e` aborts | Network error before even reaching the check |
| Hardcoded hash after Composer release | Hash mismatch every time | Always fetch hash at runtime, never hardcode |
| New installer downloaded but `rm -f` skipped on failure | Stale installer left at `/tmp/` | The `exit 1` path includes `rm -f "$COMPOSER_INSTALLER"` |

## Applying the Pattern to a New Installer

For any future installer fetched via curl and run as root:

1. Download installer to a `/tmp/` path.
2. Fetch the canonical hash from the publisher's documented endpoint.
3. Compute local hash with the appropriate `sha384sum`/`sha256sum` tool.
4. Compare; exit 1 with cleanup on mismatch.
5. Run installer; remove the temp file.

## Gotchas

**Hash algorithm mismatch**: Composer uses SHA-384; other publishers may use SHA-256 or SHA-512. Always match the algorithm to what the publisher specifies in their installation docs. Using SHA-256 against a SHA-384 signature always fails.

**`EXPECTED_SIG` contains whitespace or newline**: `curl -fsSL` fetching `installer.sig` typically returns a bare hash with a trailing newline. Using `$(...)` command substitution strips it automatically; avoid `read` with a pipe which may leave the newline.

**Skipping cleanup on success**: the installer PHP file is deleted after `php "$COMPOSER_INSTALLER" ...` succeeds (`rm -f "$COMPOSER_INSTALLER"` at line 42). If the `php` invocation itself fails under `set -e`, the file is left at `/tmp/`. This is acceptable — the provision aborted anyway and `/tmp/` is cleared on reboot.
