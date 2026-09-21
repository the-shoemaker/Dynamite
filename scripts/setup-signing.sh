#!/bin/zsh
# Run once, with approval, to create a private, persistent local signing identity.
set -euo pipefail
signing_dir="${HOME}/Library/Application Support/Dynomite/DevelopmentSigning"
keychain="${signing_dir}/signing.keychain-db"
mkdir -p "$signing_dir"
chmod 700 "$signing_dir"
if [[ -f "$signing_dir/identity.sha1" && -f "$keychain" ]]; then
    print 'Dynomite development signing is already configured.'
    exit 0
fi
umask 077
[[ -f "$signing_dir/password" ]] || openssl rand -hex 32 > "$signing_dir/password"
signing_password="$(cat "$signing_dir/password")"
cat > "$signing_dir/certificate.conf" <<'CONFIG'
[req]
distinguished_name = name
x509_extensions = extensions
prompt = no
[name]
CN = Dynomite Local Development
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
openssl req -new -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
    -config "$signing_dir/certificate.conf" -keyout "$signing_dir/key.pem" -out "$signing_dir/certificate.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$signing_dir/key.pem" -in "$signing_dir/certificate.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -name 'Dynomite Local Development' -out "$signing_dir/identity.p12" -passout "file:$signing_dir/password"
[[ -f "$keychain" ]] || security create-keychain -p "$signing_password" "$keychain"
security unlock-keychain -p "$signing_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security import "$signing_dir/identity.p12" -k "$keychain" -P "$signing_password" -x -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$signing_password" "$keychain" >/dev/null
openssl x509 -in "$signing_dir/certificate.pem" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g' > "$signing_dir/identity.sha1"
rm "$signing_dir/key.pem" "$signing_dir/identity.p12"
print 'Created a local signing identity in a dedicated private keychain.'
print 'Next, separately approve code-signing trust for certificate.pem with security add-trusted-cert -r trustRoot -p codeSign.'
