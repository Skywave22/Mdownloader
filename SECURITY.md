# Security Policy

MDownloader takes security seriously. This document explains how to report
security issues and what to expect.

## Supported Versions

Only the **latest release** is supported with security fixes. Older releases
are provided as-is.

| Version | Supported          |
| ------- | ------------------ |
| 0.3.x   | :white_check_mark: |
| 0.2.x   | :x:                |
| 0.1.x   | :x:                |

## What MDownloader does (and does not do)

- MDownloader runs **entirely on your device**. There is no server, no account
  system, and no telemetry. Nothing you search for or download is sent to us.
- The TMDB catalog is fetched directly from TMDB's public API using an API key
  compiled into the app.
- Site "plugins" are small JavaScript programs (QuickJS) that the app runs in a
  sandbox to locate publicly available download links. Plugins can only use the
  helpers the app exposes (`http_get`, `http_post`, `http_request`, `sha256`,
  `md5`, base64, and a small per-plugin key-value store). They **cannot** access
  your files, contacts, location, or other apps.
- Downloaded media is saved to a folder of your choosing (default: your
  Downloads folder).

## Reporting a Vulnerability

If you find a security issue — for example a sandbox escape in the plugin
engine, a path-traversal bug in the downloader, or an unsafe handling of
untrusted input — please report it **privately** instead of opening a public
issue.

- **Preferred:** use GitHub's private vulnerability reporting
  (Security → Report a vulnerability) on
  <https://github.com/Skywave22/Mdownloader/security>.
- **Alternative:** email `security@mdownloader.app` with the details.

Please include:

1. A short description of the issue.
2. Steps to reproduce it.
3. The affected version.
4. Any proof-of-concept code or screenshots (if available).

## What to expect

- You will receive an acknowledgement within **5 business days**.
- We will keep you informed of progress and coordinate a disclosure timeline.
- Please do not disclose the issue publicly until we have shipped a fix.

## Security best practices for users

- Only install plugins from sources you trust. A plugin is code that runs in
  the app's sandbox; review its `plugin.js` before enabling it.
- Download only content you have the right to download.
- Keep the app updated to receive security fixes.

## Responsible use

MDownloader is a personal download manager. Use it only with content you are
legally allowed to download in your jurisdiction. The authors are not
responsible for how the software is used.
