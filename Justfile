# WinMint v2 — host tasks (winget install Casey.Just)

set windows-shell := ["pwsh.exe", "-NoProfile", "-Command"]

default:
    @just --list

restore:
    dotnet restore

build: restore
    dotnet build --no-restore

format-check:
    dotnet format --verify-no-changes

check: format-check build
    dotnet test --no-build

publish-provisioning:
    dotnet publish src/WinMint.Provisioning/WinMint.Provisioning.csproj -c Release -o artifacts/provisioning
