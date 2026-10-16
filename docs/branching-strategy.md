# Branching and promotion strategy

- `master`: production-ready code; merge only reviewed and validated changes.
- `develop`: integration branch for unreleased work and DEV validation.
- `feature`: starter feature branch. For normal work, prefer short-lived branches such as `feature/ABC-123-add-sales-model`.

## Flow

1. Create a short-lived feature branch from the agreed team baseline.
2. Make a focused change and run local checks.
3. Sync with the latest `develop` before integration.
4. Open a pull request into `develop`; review and validate in DEV.
5. Promote `develop` to `master` through a separate pull request after approval and production validation.
6. Avoid direct commits to `master`; protect it with branch rules where available.

The exact meaning of “MST” should be confirmed if it is a named internal process. This starter interprets it as the requested master/develop/feature promotion flow.
