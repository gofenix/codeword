#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECURE_DIR="/Users/bytedance/.secure/codeword"
KEYSTORE_PATH="$SECURE_DIR/codeword-upload.jks"
CERTIFICATE_PATH="$SECURE_DIR/codeword-upload-certificate.pem"
KEY_PROPERTIES_PATH="$REPO_ROOT/apps/codeword/android/key.properties"
KEYCHAIN_SERVICE="codeword-google-play-upload"
KEY_ALIAS="codeword-upload"

umask 077
mkdir -p "$SECURE_DIR"

if [[ -f "$KEYSTORE_PATH" ]]; then
  if ! security find-generic-password \
    -a "$KEY_ALIAS" \
    -s "$KEYCHAIN_SERVICE" \
    -w >/dev/null 2>&1; then
    echo "Existing upload keystore has no matching Keychain password; refusing to overwrite it." >&2
    exit 1
  fi
  UPLOAD_PASSWORD="$(security find-generic-password \
    -a "$KEY_ALIAS" \
    -s "$KEYCHAIN_SERVICE" \
    -w)"
else
  UPLOAD_PASSWORD="$(openssl rand -hex 24)"
  security add-generic-password \
    -U \
    -a "$KEY_ALIAS" \
    -s "$KEYCHAIN_SERVICE" \
    -w "$UPLOAD_PASSWORD" >/dev/null
  keytool -genkeypair \
    -keystore "$KEYSTORE_PATH" \
    -storetype PKCS12 \
    -storepass "$UPLOAD_PASSWORD" \
    -keypass "$UPLOAD_PASSWORD" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=Codeword Upload, OU=Mobile, O=Codeword, L=Shanghai, ST=Shanghai, C=CN" >/dev/null
fi

keytool -list \
  -keystore "$KEYSTORE_PATH" \
  -storepass "$UPLOAD_PASSWORD" \
  -alias "$KEY_ALIAS" >/dev/null

keytool -exportcert \
  -rfc \
  -keystore "$KEYSTORE_PATH" \
  -storepass "$UPLOAD_PASSWORD" \
  -alias "$KEY_ALIAS" \
  -file "$CERTIFICATE_PATH" >/dev/null

PROPERTIES_TMP="$(mktemp "$KEY_PROPERTIES_PATH.tmp.XXXXXX")"
trap 'rm -f "$PROPERTIES_TMP"' EXIT
{
  printf 'storePassword=%s\n' "$UPLOAD_PASSWORD"
  printf 'keyPassword=%s\n' "$UPLOAD_PASSWORD"
  printf 'keyAlias=%s\n' "$KEY_ALIAS"
  printf 'storeFile=%s\n' "$KEYSTORE_PATH"
} >"$PROPERTIES_TMP"
mv "$PROPERTIES_TMP" "$KEY_PROPERTIES_PATH"
chmod 600 "$KEY_PROPERTIES_PATH" "$KEYSTORE_PATH" "$CERTIFICATE_PATH"
trap - EXIT

unset UPLOAD_PASSWORD
echo "Android upload key is configured."
echo "Keystore: $KEYSTORE_PATH"
echo "Certificate for Play Console: $CERTIFICATE_PATH"
