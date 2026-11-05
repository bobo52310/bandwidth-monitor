# Security Policy

## Supported versions

Bandwidth ECG is pre-release and has no tagged releases yet. Security fixes are made on the `main` branch.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

1. Preferred: use GitHub's private vulnerability reporting. Go to the repository's **Security** tab and choose **Report a vulnerability** (<https://github.com/bobo52310/bandwidth-monitor/security/advisories/new>).
2. If that is not available to you, email **bobo52310@gmail.com** with the subject "Bandwidth ECG security report".

Please include what you found, the steps or a proof of concept to reproduce it, the affected version or commit, and your macOS version. We aim to acknowledge a report within a few days and to keep you updated until it is resolved. This is a one-person, volunteer-run project, so please be patient.

## Scope

What the app does and does not do, to help you judge a report:

- It runs in the macOS App Sandbox. Entitlements are listed in `Config/BandwidthECG.entitlements`: outgoing network connections and read/write access to files you choose in the save panel.
- Its only outgoing request is the optional latency probe (an HTTPS `HEAD` request to `www.apple.com` every 30 seconds, which can be switched off in Settings).
- It has no accounts, no server and no analytics. Speed data, peaks and daily records stay in the app's sandbox container.
- The landing page in `website/` is static and served by Cloudflare Pages.

Reports about the app, the build scripts or the website are all in scope.
