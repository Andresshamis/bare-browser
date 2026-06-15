# Security Policy

Bare Browser is an early-stage macOS browser project. Security reports are welcome and should be handled privately before public disclosure.

## Supported Versions

Security fixes target the default development branch until the project publishes versioned releases.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability.

Preferred reporting path:

1. Use GitHub's private vulnerability reporting or security advisory flow for this repository when available.
2. If that is not available, contact the maintainer privately through the repository owner profile and share only enough detail to establish a private channel.

Useful reports include:

- Affected commit or branch.
- Reproduction steps.
- Expected and actual behavior.
- Any privacy, persistence, profile-isolation, download, URL-scheme, or WebKit handoff impact.

The project will prioritize reports that could expose browsing data, private-profile state, local files, credentials, tokens, unsafe downloads, or unintended external app launches.

## Scope

In scope:

- Profile isolation failures.
- Private browsing data persistence.
- Unsafe URL scheme or local file handling.
- Download destination, filename, quarantine, or executable-risk bypasses.
- Accidental storage or logging of sensitive URLs, cookies, credentials, tokens, or private metadata.

Out of scope:

- Vulnerabilities solely in websites loaded by the browser.
- Issues requiring malicious local code execution outside Bare Browser.
- Denial-of-service reports without a security or privacy impact.

## Disclosure

Please allow time for a fix and regression tests before public disclosure. If a report is valid, the fix should include tests or documentation updates where practical.
