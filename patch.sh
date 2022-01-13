#!/bin/bash

set -e

cd "$(dirname "$0")"

WORKING_LOCATION=$(pwd)
cd "$WORKING_LOCATION"
echo "[i] working location: $WORKING_LOCATION"

echo "[*] checking for dependencies..."
REQUIRED_BINARY_LIST=("ldid" "vtool" "otool" "install_name_tool" "unzip" "codesign" "plutil")
BROKEN=false
for BINARY in "${REQUIRED_BINARY_LIST[@]}"; do
    LOCATION="$(which "$BINARY")"
    if [ -z "$LOCATION" ]; then
        echo "ERROR: $BINARY is not installed"
        BROKEN=true
    fi
done
if [ "$BROKEN" = true ]; then
    echo "ERROR: one or more dependencies are not installed"
    exit 1
fi

TARGET_APP=$1

if [ "${TARGET_APP##*.}" = "ipa" ]; then
    echo "[*] extracting application bundle from ipa file"
    unzip -qq "$TARGET_APP"
    cp -r Payload/*.app ./
    rm -rf Payload
    LS_STR=$(ls)
    FOUND=false
    while read -r FILE; do
        if [ "${FILE##*.}" = "app" ]; then
            if [ "$FOUND" = false ]; then
                TARGET_APP=$FILE
                FOUND=true
            else
                echo "ERROR: multiple .app files found in ipa file"
                exit 1
            fi
        fi
    done <<< "$LS_STR"
    
    echo "[*] application bundle extracted"
    echo "[*] app bundle will be set to: $TARGET_APP"
fi

if [ ! -d "$TARGET_APP" ]; then
    echo "[E] please specify a valid application bundle location"
    echo "    usage: <application_bundle_location>/<ipa_file_location>"
    exit 1
fi

echo "[*] preparing environment..."
xattr -r -d com.apple.quarantine "$TARGET_APP"
rm -rf "$TARGET_APP/embedded.mobileprovision" || true
rm -rf "$TARGET_APP/_CodeSignature" || true

cd "$TARGET_APP"
echo "[i] will make patch directly inside $TARGET_APP"

echo "[*] scanning files..."
FILE_LIST=$(find . -type f)
PROCESSED=0
while read -r FILE; do
    FILE_INFO="$(file "$FILE")"
    if [[ $FILE_INFO == *"Mach-O"* ]]; then
        echo "[*] processing $FILE..."
        install_name_tool -change \
            "@rpath/libswiftUIKit.dylib" "/System/iOSSupport/usr/lib/swift/libswiftUIKit.dylib" \
            "$FILE"
        vtool \
            -arch arm64 \
            -set-build-version maccatalyst 10.0 14.0 \
            -replace \
            -output "$FILE" \
            "$FILE"
        codesign --remove "$FILE"
        codesign -s - --force --deep "$FILE"
        chmod 777 "$FILE"
        PROCESSED=$((PROCESSED + 1))
    fi
done <<< "$FILE_LIST"

if [ $PROCESSED -eq 0 ]; then
    echo "[!] no mach object was found nor processed"
    exit 1
fi

echo "[i] patch was made to $PROCESSED files"

cd "$WORKING_LOCATION"

echo "[*] patching bundle items..."
plutil -replace MinimumOSVersion -string 11.0 "$TARGET_APP/Info.plist"

echo "[*] signing bundle..."
SIGN_ENT_BASE64="PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiPz4KPCFET0NUWVBFIHBsaXN0IFBVQkxJQyAiLS8vQXBwbGUvL0RURCBQTElTVCAxLjAvL0VOIiAiaHR0cDovL3d3dy5hcHBsZS5jb20vRFREcy9Qcm9wZXJ0eUxpc3QtMS4wLmR0ZCI+CjxwbGlzdCB2ZXJzaW9uPSIxLjAiPgo8ZGljdD4KCTxrZXk+Y29tLmFwcGxlLnNlY3VyaXR5LmFwcC1zYW5kYm94PC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5hc3NldHMubW92aWVzLnJlYWQtd3JpdGU8L2tleT4KCTx0cnVlLz4KCTxrZXk+Y29tLmFwcGxlLnNlY3VyaXR5LmFzc2V0cy5tdXNpYy5yZWFkLXdyaXRlPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5hc3NldHMucGljdHVyZXMucmVhZC13cml0ZTwva2V5PgoJPHRydWUvPgoJPGtleT5jb20uYXBwbGUuc2VjdXJpdHkuZGV2aWNlLmF1ZGlvLWlucHV0PC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5kZXZpY2UuYmx1ZXRvb3RoPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5kZXZpY2UuY2FtZXJhPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5kZXZpY2UudXNiPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5maWxlcy5kb3dubG9hZHMucmVhZC13cml0ZTwva2V5PgoJPHRydWUvPgoJPGtleT5jb20uYXBwbGUuc2VjdXJpdHkuZmlsZXMudXNlci1zZWxlY3RlZC5yZWFkLXdyaXRlPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5uZXR3b3JrLmNsaWVudDwva2V5PgoJPHRydWUvPgoJPGtleT5jb20uYXBwbGUuc2VjdXJpdHkubmV0d29yay5zZXJ2ZXI8L2tleT4KCTx0cnVlLz4KCTxrZXk+Y29tLmFwcGxlLnNlY3VyaXR5LnBlcnNvbmFsLWluZm9ybWF0aW9uLmFkZHJlc3Nib29rPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5wZXJzb25hbC1pbmZvcm1hdGlvbi5jYWxlbmRhcnM8L2tleT4KCTx0cnVlLz4KCTxrZXk+Y29tLmFwcGxlLnNlY3VyaXR5LnBlcnNvbmFsLWluZm9ybWF0aW9uLmxvY2F0aW9uPC9rZXk+Cgk8dHJ1ZS8+Cgk8a2V5PmNvbS5hcHBsZS5zZWN1cml0eS5wcmludDwva2V5PgoJPHRydWUvPgo8L2RpY3Q+CjwvcGxpc3Q+Cg=="
echo "$SIGN_ENT_BASE64" | base64 -D > ./sign.plist
codesign -s - --force --deep --entitlements sign.plist "$TARGET_APP"
rm ./sign.plist

echo "[*] verify code sign..."
codesign --verify --deep "$TARGET_APP"

echo "[*] done"


