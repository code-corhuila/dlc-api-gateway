# Changelog

All notable changes of `dlc-api-gateway` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/). A release is tagged `v<version>` once it is merged into `main`.

## [Unreleased]

## [3.0.0] - 2026-11-14

The changelog starts at this release.

### Added

- Add nginx foundation with health and not-found envelope.
- Add correlation id and cors limited to the front origin.
- Route owner apis with credential presence filter.
- Add login and general rate limits per client ip.
- Take the client address only from the trusted front proxy.

### Fixed

- Restore codeowners and complete annex i files.
- Route auth to the auth-service compose name.
- Generate correlation ids as version 4 uuids.
- Require trusted Front address at deployment.
- Route the Billing pending-price read.
- Route the Appointments waiting list and appointment types.
