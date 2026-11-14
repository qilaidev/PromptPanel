# Security Policy

## Supported versions

PromptPanel is pre-release software. Security fixes are handled on `main` until the first tagged public release.

## Reporting a vulnerability

Do not open a public issue for a security problem.

Email the maintainer at `hello@qilaidav.com` with:

- A short description of the issue.
- Reproduction steps.
- The affected version or commit.
- Any relevant logs with private prompt content removed.

You should receive an acknowledgement within 7 days. If the issue is confirmed, we will coordinate a fix before public disclosure.

## Data handling expectations

PromptPanel is local-first and makes **zero outbound network requests by default**:

- Prompt content stays on the user's Mac (`~/Library/Application Support/PromptPanel/promptpanel.db`) unless the user explicitly copies/pastes it into another app or opts into user-controlled sync (`设置 → 偏好 → 云端同步`).
- Background update checks are disabled by default (`SUEnableAutomaticChecks = false`, `autoUpdateEnabled = false`). In-place app bundle updates require a valid Apple Developer ID (`TeamIdentifier`) signature and never strip `com.apple.quarantine`; ad-hoc local builds only notify and open the release page.
- Remote sync and update endpoints require `https://` (`NSAppTransportSecurity` enforces HTTPS globally with `NSAllowsLocalNetworking` strictly scoped to local loopback `localhost` / `127.0.0.1` / `::1` for local debugging).
- Optional sync tokens are stored in the macOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) rather than in SQLite backups.

Security reports involving prompt leakage, unexpected network access, unsafe restore behavior, or permission escalation are treated as high priority.
