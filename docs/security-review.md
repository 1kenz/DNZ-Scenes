# Security review: DNZ-Scenes v0.3.0

Date: 2026-10-28 · Tier 1 · Reviewer: self-review by the author of the code, so not independent
Method: DNZ-Core `secure-code-review` checklist (BLOCKER scan, standards pass), a short STRIDE pass from
`threat-modeling`, and greps over `Sources/`. Not run: gitleaks, dynamic/fuzz testing, a review by a second
person. The fixes below have not been compiled or observed on macOS 27 yet.

## Scope and trust boundaries
Inputs: global hotkeys (Carbon), menu clicks, `config.json` (user-writable), files picked in open panels
(wallpaper image, .app bundles), Accessibility responses from other apps.
Outputs: window moves/hides in other apps, launching apps by bundle id, desktop picture, `config.json`.
Data: app bundle ids, display UUIDs, profile names. No personal data, no credentials, no network.

## BLOCKER scan (DNZ secure-code-review section 1)
| Check | Result |
| --- | --- |
| Hardcoded secrets | None found (grep) |
| Shell/SQL built from strings | No process execution, no SQL (grep: Process, NSTask, system, popen, NSAppleScript, eval: none) |
| Unvalidated input to dangerous sink | Wallpaper name is checked (plain file name, no leading dot) in core and app; no exec/eval sinks |
| TLS / crypto / auth / tokens | Not applicable: no network, no crypto, no auth |
| PII in logs | Logs contain bundle ids and error text only |
| SSRF / XXE | Not applicable (no network, no untrusted XML) |

## Findings
| Severity | Where | Issue | Status |
| --- | --- | --- | --- |
| MAJOR | repo | `.pre-commit-config.yaml` (gitleaks) exists but the project is not a git repository, so the Tier 1 mandatory gitleaks hook never runs | OPEN, owner action below |
| MAJOR | build-app.sh | Ad-hoc signature: Accessibility trust is tied to the binary and is lost on every rebuild, which trains click-through of the permission prompt; no hardened runtime | PARTLY FIXED: hardened runtime and `SIGN_ID` option added. Owner must supply a stable identity |
| MINOR | WindowPlacer.firstWindowFrame | `as!` casts on values returned by other apps could crash the app | FIXED (type id check) |
| MINOR | WindowPlacer.standardWindows | A hung app could block the main thread for the default AX timeout, freezing the menu | FIXED (0.5 s messaging timeout) |
| MINOR | WindowPlacer.place | Delayed placement after launch could act on a recycled pid | FIXED (`isTerminated` check) |
| MINOR | ConfigStore | Directory permission only set at creation; a symlinked config file was followed | FIXED (0700 on every save, symlink refused) |
| MINOR | Wallpaper / Config | Wallpaper name accepted hidden names such as `.x` | FIXED (rejected, covered by a check) |
| INFO | config.json | Anything running as your user can edit it and make a profile launch/hide installed apps. Same trust level as the user account; file is mode 600 | ACCEPTED |
| INFO | Accessibility permission | Lets the app read and control other apps' UI. Mitigated by: no network, no scripting, no remote input path, zero dependencies | ACCEPTED, keep it that way (ADR-0001) |
| INFO | Image decoding | Wallpaper thumbnails are decoded by ImageIO from files you choose | ACCEPTED |
| INFO | assets/ | 77 MB of 4K PNGs would bloat git history | Housekeeping: downscale or use Git LFS before the first commit |

## STRIDE (short)
- Spoofing: another binary posing as this app does not inherit the Accessibility permission (tied to code identity); a stable signature strengthens this.
- Tampering: `config.json` edits are the main local tampering path (see INFO above).
- Repudiation: not applicable for a single-user local tool.
- Information disclosure: nothing leaves the machine; `config.json` lists installed app ids and display UUIDs.
- Denial of service: hung apps are bounded by the AX timeout; nothing waits on external input.
- Elevation of privilege: no privileged helper, no entitlements, no SIP changes (ADR-0001).

## Owner actions
1. Make the project a repo and activate the secret scan:
   `brew install pre-commit gitleaks`, then in the project folder:
   `git init && pre-commit install && pre-commit run --all-files` (decide about the 77 MB assets first).
2. Use a stable signing identity: list yours with `security find-identity -v -p codesigning`
   (Xcode > Settings > Accounts can create a free Apple Development certificate), then
   `SIGN_ID="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh`.
3. Move the built app to `~/Applications` and grant Accessibility to that copy only.
4. Re-run this review after any change that adds a dependency, network access, process execution or AppleScript.
