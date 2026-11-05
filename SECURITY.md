# Security Policy

## Supported versions

Only the latest release of CivicBuddy receives security fixes. The app
offers updates automatically, so please make sure you are on the newest
version from [Releases](https://github.com/Saku2025/civicBuddy/releases/latest)
before reporting.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

**Please do not report security problems in public issues, discussions or
pull requests.**

Report them privately through GitHub instead:

1. Open the [Security tab](https://github.com/Saku2025/civicBuddy/security)
   of this repository.
2. Click **Report a vulnerability**
   ([direct link](https://github.com/Saku2025/civicBuddy/security/advisories/new)).
3. Describe the problem, the app version, the steps to reproduce it and
   what an attacker could do with it.

Only the maintainers can see the report.

## What to expect

- We acknowledge new reports within **7 days**.
- We keep you updated while we investigate and fix the problem.
- Once a fix is released, we can credit you in the release notes if you
  wish.

## Scope

In scope:

- The CivicBuddy Android app (this repository).
- How the app stores survey data and photos on the phone and sends them
  to the backend.
- Access to other users' surveys or photos.

Out of scope:

- The Supabase publishable key and Firebase configuration inside the app.
  They are public by design; data is protected by the backend's access
  rules.
- Problems that need a rooted phone or physical access to an unlocked
  phone.
