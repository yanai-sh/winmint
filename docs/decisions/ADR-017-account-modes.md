# ADR-017: Bake-in account credentials at ISO build

## Decision

Profile `account.mode` is **`localAutoLogon` only**: username plus password (or `passwordPath`) are required before planning/building an Output ISO. Unattend bakes `LocalAccounts` + AutoLogon; ImageServicing always stamps offline Supervisor Shell; MachineSetup always stamps Autologon.

Portable / no-password ISO (`oobeLocal`, deferred Shell, interactive OOBE owner creation) is **rejected**. Wizard collects username + password; curated emit stays bake-in.

## Why

Hyper-V and current Windows 11 OOBE (HideOnlineAccountScreens, offline NIC, CXH/NRO) could not prove a normal-user path to a local account without console escapes (`ms-cxh:localonly`, etc.). That escape is not product UX, and VM Offline OOBE does not stand in for bare-metal confidence. Credential-bound bake-in is the path Smoke and Primary already use and can verify.

## Rejected

- `oobeLocal` / native OOBE as the shipping owner-identity path.
- Deferred Shell (`FirstLogonCommands` → Supervisor + logoff).
- Curated default flip gated on oobeLocal FirstLogon proof (#164).
- C2 custom identity UI as the portable path (still superseded).
- Password-less shareable ISO as the product story.

## Review trigger

Microsoft ships a documented, durable unattend-only path to interactive local-account OOBE without console tricks **and** Primary proves it — reopen only then.
