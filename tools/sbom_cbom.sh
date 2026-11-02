#!/usr/bin/env bash
# sbom_cbom.sh - Generate SBOM + draft CBOM for a Flutter (Android + iOS) project.
# Run from the Flutter project root:  bash tools/sbom_cbom.sh
# Output: build/sbom/
set -uo pipefail

SPEC="1.6"
OUT="build/sbom"
APP_NAME="$(grep -m1 '^name:' pubspec.yaml | awk '{print $2}')"
APP_VERSION="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')"

info() { printf '\033[1;34m[info]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -f pubspec.yaml ] || { echo "Run this from the Flutter project root (pubspec.yaml not found)."; exit 1; }
have flutter || { echo "flutter not found on PATH."; exit 1; }
have cdxgen  || { echo "cdxgen missing. Install: npm install -g @cyclonedx/cdxgen"; exit 1; }

mkdir -p "$OUT"

# ---------------------------------------------------------------- 1. Resolve
info "Resolving Dart dependencies"
flutter pub get || warn "flutter pub get failed"

if [ "$(uname)" = "Darwin" ] && [ -f ios/Podfile ]; then
  info "Resolving CocoaPods"
  (cd ios && pod install --repo-update) || warn "pod install failed"
elif [ ! -f ios/Podfile.lock ]; then
  warn "ios/Podfile.lock not found and this is not macOS: iOS native deps will be missing from the SBOM."
fi

# ---------------------------------------------------------------- 2. SBOM
info "Generating SBOM per layer"
cdxgen -t dart   --spec-version "$SPEC" -o "$OUT/sbom-dart.cdx.json" .       || warn "dart SBOM failed"
[ -d android ] && { cdxgen -t gradle --spec-version "$SPEC" -o "$OUT/sbom-android.cdx.json" android || warn "android SBOM failed"; }
[ -d ios ]     && { cdxgen -t swift  --spec-version "$SPEC" -o "$OUT/sbom-ios.cdx.json" ios         || warn "ios SBOM failed"; }

info "Generating full recursive SBOM (fallback / cross-check)"
cdxgen -r --spec-version "$SPEC" -o "$OUT/sbom-full.cdx.json" . || warn "full SBOM failed"

if have cyclonedx; then
  PARTS=()
  for f in sbom-dart sbom-android sbom-ios; do
    [ -s "$OUT/$f.cdx.json" ] && PARTS+=("$OUT/$f.cdx.json")
  done
  if [ "${#PARTS[@]}" -gt 0 ]; then
    info "Merging layer SBOMs"
    cyclonedx merge --input-files "${PARTS[@]}" --output-file "$OUT/sbom-merged.cdx.json" \
      && cyclonedx validate --input-file "$OUT/sbom-merged.cdx.json" --input-version v1_6 \
      || warn "merge/validate failed"
  fi
else
  warn "cyclonedx CLI not installed; skipping merge. Use sbom-full.cdx.json instead."
fi

if have grype; then
  SRC="$OUT/sbom-merged.cdx.json"; [ -s "$SRC" ] || SRC="$OUT/sbom-full.cdx.json"
  info "Vulnerability scan with grype"
  grype "sbom:$SRC" -o table > "$OUT/vulnerabilities.txt" 2>&1 || warn "grype scan failed"
fi

# ---------------------------------------------------------------- 3. CBOM discovery
info "Crypto library detection from dependencies (cdxgen --include-crypto)"
cdxgen -r --spec-version "$SPEC" --include-crypto -o "$OUT/sbom-crypto.cdx.json" . || warn "crypto scan failed"

info "Searching source for crypto usage"
SCAN="$OUT/crypto-findings.txt"
: > "$SCAN"
scan() { # label, dirs, regex
  echo "=== $1 ===" >> "$SCAN"
  grep -rnE --include='*.dart' --include='*.kt' --include='*.java' --include='*.swift' \
       --include='*.m' --include='*.h' --include='*.xml' --include='*.plist' --include='*.gradle' \
       --exclude-dir=Pods --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=.gradle \
       "$3" $2 2>/dev/null >> "$SCAN" || true
  echo >> "$SCAN"
}
scan "Dart"    "lib" \
  "package:(crypto|encrypt|pointycastle|cryptography|webcrypto|flutter_secure_storage|local_auth|dart_jsonwebtoken)|SecurityContext|badCertificateCallback|sha256|sha1|md5|AES|RSA|HMAC|Pbkdf2"
scan "Android" "android/app/src" \
  "Cipher\.getInstance|MessageDigest|KeyStore|KeyGenerator|SecretKeySpec|Mac\.getInstance|SSLContext|TrustManager|BiometricPrompt|cleartextTrafficPermitted|usesCleartextTraffic|pin-set"
scan "iOS"     "ios/Runner" \
  "CryptoKit|CommonCrypto|CC_SHA|SecKey|SecItem|kSecAttr|LAContext|ServerTrust|NSAppTransportSecurity|NSAllowsArbitraryLoads"
info "Findings written to $SCAN"

# ---------------------------------------------------------------- 4. Draft CBOM
info "Building draft CBOM"
APP_NAME="$APP_NAME" APP_VERSION="$APP_VERSION" SPEC="$SPEC" OUT="$OUT" python3 - <<'PY'
import os, re, json, pathlib

spec, out = os.environ["SPEC"], os.environ["OUT"]
roots = ["lib", "android/app/src", "ios/Runner"]
exts = {".dart", ".kt", ".java", ".swift", ".m", ".h"}

# name -> (regex, primitive, extra algorithmProperties)
ALGOS = {
  "AES":         (r"\bAES\b|aes[-_]?(128|256)|kCCAlgorithmAES|AES\.GCM", "block-cipher", {}),
  "ChaCha20":    (r"chacha20", "stream-cipher", {}),
  "SHA-256":     (r"sha[-_]?256", "hash", {"parameterSetIdentifier": "256"}),
  "SHA-512":     (r"sha[-_]?512", "hash", {"parameterSetIdentifier": "512"}),
  "SHA-1":       (r"\bsha[-_]?1\b|CC_SHA1", "hash", {"parameterSetIdentifier": "160"}),
  "MD5":         (r"\bmd5\b|CC_MD5", "hash", {"parameterSetIdentifier": "128"}),
  "HMAC":        (r"\bhmac\b", "mac", {}),
  "RSA":         (r"\bRSA\b|kSecAttrKeyTypeRSA", "pke", {}),
  "ECDSA/EC":    (r"\bECDSA\b|\bECDH\b|kSecAttrKeyTypeEC|secp256r1|P-256", "signature", {}),
  "PBKDF2":      (r"pbkdf2", "kdf", {}),
  "Argon2":      (r"argon2", "kdf", {}),
}
DEPRECATED = {"MD5", "SHA-1"}

found = {k: [] for k in ALGOS}
for root in roots:
    for p in pathlib.Path(root).rglob("*") if pathlib.Path(root).exists() else []:
        if not p.is_file() or p.suffix not in exts:
            continue
        if any(x in p.parts for x in ("build", "Pods", ".dart_tool")):
            continue
        try:
            lines = p.read_text(errors="ignore").splitlines()
        except Exception:
            continue
        for i, line in enumerate(lines, 1):
            for name, (rx, _, _) in ALGOS.items():
                if re.search(rx, line, re.I if name not in ("RSA", "AES", "ECDSA/EC") else 0):
                    found[name].append({"location": str(p), "line": i})

components = []
for name, occ in found.items():
    if not occ:
        continue
    _, prim, extra = ALGOS[name]
    props = [{"name": "cbom:status", "value": "DRAFT - verify mode, key size, usage"}]
    if name in DEPRECATED:
        props.append({"name": "cbom:risk", "value": "deprecated/weak - review usage"})
    components.append({
        "type": "cryptographic-asset",
        "bom-ref": f"crypto/algorithm/{name.lower().replace('/', '-')}",
        "name": name,
        "cryptoProperties": {
            "assetType": "algorithm",
            "algorithmProperties": {"primitive": prim, **extra},
        },
        "evidence": {"occurrences": occ[:50]},
        "properties": props,
    })

# Platform-provided crypto that source scanning cannot see (edit as needed)
components += [
  {"type": "cryptographic-asset", "bom-ref": "crypto/protocol/tls",
   "name": "TLS (dart:io / BoringSSL, Android Conscrypt, iOS Network.framework)",
   "cryptoProperties": {"assetType": "protocol",
     "protocolProperties": {"type": "tls", "version": "1.3"}},
   "properties": [{"name": "cbom:status", "value": "DRAFT - confirm min TLS version and cipher suites"}]},
  {"type": "cryptographic-asset", "bom-ref": "crypto/material/platform-keystore",
   "name": "Platform key storage (Android Keystore / iOS Keychain)",
   "cryptoProperties": {"assetType": "related-crypto-material",
     "relatedCryptoMaterialProperties": {"type": "secret-key", "state": "active"}},
   "properties": [{"name": "cbom:status", "value": "DRAFT - list actual keys/tokens stored"}]},
]

bom = {
  "bomFormat": "CycloneDX", "specVersion": spec, "version": 1,
  "metadata": {"component": {"type": "application",
      "name": os.environ["APP_NAME"], "version": os.environ["APP_VERSION"]}},
  "components": components,
}
pathlib.Path(out, "cbom-draft.cdx.json").write_text(json.dumps(bom, indent=2))
print(f"Draft CBOM: {len(components)} assets")
PY

if have cyclonedx; then
  cyclonedx validate --input-file "$OUT/cbom-draft.cdx.json" --input-version v1_6 || warn "CBOM validation failed"
  if [ -s "$OUT/sbom-merged.cdx.json" ]; then
    cyclonedx merge --input-files "$OUT/sbom-merged.cdx.json" "$OUT/cbom-draft.cdx.json" \
      --output-file "$OUT/sbom-cbom-combined.cdx.json" || warn "combined merge failed"
  fi
fi

# ---------------------------------------------------------------- 5. Metadata
{
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "App: $APP_NAME $APP_VERSION"
  flutter --version 2>/dev/null | head -3
  echo "cdxgen: $(cdxgen --version 2>/dev/null)"
} > "$OUT/README.txt"

info "Done. Outputs in $OUT/"
ls -1 "$OUT"
warn "cbom-draft.cdx.json is auto-detected and incomplete. Review it manually before using it for compliance."
