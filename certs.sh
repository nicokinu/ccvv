#!/bin/sh
# CC&VV（旧名 Copyman）用の自己署名コード署名証明書をKeychainに作成し、build.shが
# それを使うようにするスクリプト。一度実行すれば、以後の再ビルドでは
# アクセシビリティ権限の再許可が不要になる（cdhashが変わっても
# 証明書ベースのコード要件で照合されるため）。
#
# ※ 証明書名は "Copyman Code Signing" のまま。既に Keychain にあるため
#    安易に作り直すと TCC の照合が壊れて権限の再許可が必要になる。
#
# 実行すると Keychain のアクセス許可のダイアログが出ることがあるので
# 「常に許可」を選んでください。
set -eu

CERT_NAME="Copyman Code Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    echo "✅ 証明書「${CERT_NAME}」は既に存在します"
else
    TMPDIR_CRT=$(mktemp -d)
    cat > "$TMPDIR_CRT/copyman.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $CERT_NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$TMPDIR_CRT/key.pem" -out "$TMPDIR_CRT/cert.pem" \
        -days 3650 -config "$TMPDIR_CRT/copyman.cnf" 2>/dev/null
    openssl pkcs12 -export -inkey "$TMPDIR_CRT/key.pem" \
        -in "$TMPDIR_CRT/cert.pem" -out "$TMPDIR_CRT/cert.p12" \
        -passout pass:copyman 2>/dev/null

    security import "$TMPDIR_CRT/cert.p12" -k "$LOGIN_KEYCHAIN" \
        -f pkcs12 -P copyman -T /usr/bin/codesign -A 2>/dev/null || \
    security import "$TMPDIR_CRT/cert.p12" -k "$LOGIN_KEYCHAIN" \
        -f pkcs12 -P copyman -T /usr/bin/codesign

    # 自己署名証書を「コード署名用に信頼」する（これで TCC が再ビルド後も
    # 証明書ベースで照合し、アクセシビリティ権限が外れなくなる）
    security add-trusted-cert -p codeSign -k "$LOGIN_KEYCHAIN" "$TMPDIR_CRT/cert.pem"

    # 秘密鍵のアクセス制御を codesign からでも使えるようにする
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$LOGIN_KEYCHAIN" 2>/dev/null || \
        echo "⚠️  set-key-partition-list は失敗しました。初回 codesign 時にパスワードを聞かれたら入力してください"

    rm -rf "$TMPDIR_CRT"
    echo "✅ 証明書「${CERT_NAME}」を作成し、コード署名用に信頼設定しました（有効期限10年）"
fi

echo "✅ build.sh がこの証明書を使うように更新されています"
