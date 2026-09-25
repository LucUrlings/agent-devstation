#!/usr/bin/env bash
set -euo pipefail

work=$(mktemp -d /tmp/devstation-sdks.XXXXXX)

python3 -m pip --version
python --version
pip3 --version
python3 -c 'import ssl; print(ssl.OPENSSL_VERSION)'
node -e 'if (process.arch !== "x64" && process.arch !== "arm64") process.exit(1)'
npm --version
npx --version
corepack --version

dotnet new console --output "$work/dotnet" --no-restore >/dev/null
dotnet restore "$work/dotnet" --ignore-failed-sources >/dev/null
dotnet run --project "$work/dotnet" --no-restore | grep -qx 'Hello, World!'

printf '%s\n' 'class Smoke { public static void main(String[] args) { System.out.println("java ok"); } }' > "$work/Smoke.java"
javac "$work/Smoke.java"
java -cp "$work" Smoke | grep -qx 'java ok'

printf '%s\n' 'package main' 'import "fmt"' 'func main() { fmt.Println("go ok") }' > "$work/main.go"
gofmt -w "$work/main.go"
go run "$work/main.go" | grep -qx 'go ok'
[[ -z "$(gofmt -l "$work/main.go")" ]]

cargo new --quiet --bin "$work/rust"
cargo run --quiet --offline --manifest-path "$work/rust/Cargo.toml" | grep -qx 'Hello, world!'
rustup show active-toolchain

printf '%s\n' 'All selected SDKs compiled or ran a small program.'
