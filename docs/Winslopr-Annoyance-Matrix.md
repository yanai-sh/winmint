# Winslopr Annoyance Matrix

Source: local capture of `https://builtbybel.github.io/Winslopr/annoyances/` provided as `What annoys you about Windows 11 Winslopr.html`.

WinWS is not a granular debloat tool. This list is a source-of-truth audit aid for the two public setup options:

- `Minimal`: remove or disable consumer, web, AI, ad, and shell noise aggressively while preserving Windows platform integrity.
- `CopilotPlus`: preserve useful Copilot+/Edge capabilities, but still remove Recall, OneDrive, ads, telemetry, commerce noise, and unwanted consumer defaults.

## Adopt In Both

| Annoyance | WinWS posture |
| --- | --- |
| Ads in Start Menu | Disable recommendations/promotions. |
| Ads in File Explorer | Disable sync provider notifications; OneDrive is fully removed. |
| Lock Screen ads & tips | Disable Spotlight/tips overlays. |
| Settings app ads | Disable suggested/promotional settings content. |
| "Finish setting up" nag | Disable SCOOBE/account/service upsell nags where practical. |
| Welcome Experience ads | Disable post-update welcome upsell surfaces. |
| Tips and suggestions popups | Disable Windows tips/suggestion notifications. |
| Tailored experiences | Disable tailored experiences from diagnostic data. |
| Personalized ads | Disable advertising ID. |
| Telemetry & diagnostic data | Reduce telemetry policy without disabling Windows Update/servicing. |
| Activity history tracking | Disable activity feed/publish/upload history. |
| Silent app installation | Disable content delivery silent app installs. |
| Spotlight on lock screen | Disable rotating Spotlight ad surface. |
| Recall recording everything | Always remove/disable Recall. |
| Bing search in Start | Disable Bing/web search in Start. |
| Search box suggestions | Disable search highlights/web suggestions. |
| Task View button | Hide by default. |
| Chat/Teams icon on taskbar | Remove consumer Teams/AppX and taskbar pin behavior. |
| OneDrive forced integration | Full remove/block; known folders point to `%USERPROFILE%`. |
| Bloatware pre-installed | Remove obvious consumer/OEM trial AppX prefixes. |
| No restore point created automatically | Create a SetupComplete restore point. |
| File extensions hidden by default | Show extensions. |
| Explorer opens to Quick Access | Candidate default: prefer This PC/Home cleanup if stable across 25H2+. |
| Start layout cluttered | Candidate: ship a clean Start layout once profile generation owns it. |
| Edge first-run experience | Disable in both setup options. |
| Edge shopping assistant | Disable in both setup options. |
| Edge startup boost | Disable in both setup options. |
| Edge imports other browser data | Candidate: disable import-on-launch prompts/policies if reliable. |

## Minimal Only

| Annoyance | WinWS posture |
| --- | --- |
| Copilot forced everywhere | Remove Copilot/WebExperience surfaces. |
| Click to Do suggestions | Disable/remove AI action surfaces where serviceable. |
| Windows AI features cannot be removed | Apply AI removal policy except protected platform components. |
| Edge sidebar & hub | Disable sidebar/hubs. |
| Edge Copilot icon | Disable through sidebar/hubs policy. |
| Edge web widgets | Disable. |
| Edge image enhancement | Disable. |
| Widgets panel | Remove/disable WebExperience/widgets. |
| News and Interests widget | Disable. |

## CopilotPlus-Safe

| Annoyance | WinWS posture |
| --- | --- |
| Copilot forced everywhere | Keep Copilot capability, but avoid forced pins/promos where separable. |
| Click to Do suggestions | Keep unless it proves independently suppressible without harming Copilot+ value. |
| Edge sidebar & hub | Keep because it carries Edge Copilot and useful sidebar apps. |
| Edge Copilot icon | Keep. |
| Edge web widgets | Keep. |
| Edge image enhancement | Keep. |
| Widgets panel | Prefer hide taskbar entry/no news noise; keep WebExperience package. |

## Reject Or Defer

| Annoyance | Reason |
| --- | --- |
| Microsoft account required | Already an account-mode choice: `Local` or `MicrosoftOobe`. |
| Truncated right-click menu | Reject as default; Windows 11 context menu is the platform default and touch-friendly. |
| Forced centered taskbar | User preference; avoid hardcoding unless a shell layer owns it. |
| Snap Assist flyout | User preference; not ISO-builder core. |
| Lock screen before desktop | Avoid weakening lock/session UX by default. |
| Can't move taskbar / can't ungroup icons | Requires ExplorerPatcher-style shell replacement; not core WinWS. |
| Forced Windows Updates | Reject disabling updates; preserve servicing. |
| Defender hard to manage | Reject Defender weakening. |
| Power plan locked to Balanced | Reject global high-performance defaults for laptops. |
| Gaming throttled by default | Keep GameDVR off; reject broad power throttling/performance hacks. |
| Visual effects waste resources | Reject by default on modern hardware. |
| Slow shutdown/restart | Defer; timeout hacks can lose app state. |
| System breaks after updates | Report/audit only; do not ship repair scripts as boot policy. |
| Disk cleanup is buried | Defer to optional maintenance/manual tool. |
| Icon cache corruption | Repair tool, not image default. |
| No easy way to install apps in bulk | Agent/profile owns selected apps; no public bulk picker. |
| No detailed BSOD info | Candidate for developer profile, but low value for ISO default. |
| Location tracking | Exposed as privacy intent; default remains off for privacy, but keep option to preserve location services. |
| Online speech recognition | Do not disable by default; can affect dictation/accessibility/Copilot+ use. |
| App launch tracking | Candidate privacy key, but validate impact on Start recommendations/search first. |
