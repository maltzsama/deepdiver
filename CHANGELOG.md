# Changelog

All notable changes to LakeDeepDiver will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased](https://github.com/maltzsama/lakedeepdiver/compare/v0.1.0...HEAD)

### Features

- **orchestrator**: skip_reason on ExecutionHistory + table-level run guard
- **queues**: separate engine lifecycle into its own queue and worker
- **s3**: STS AssumeRole and per-catalog S3 storage auth
- **dashboard, freshness**: needs-action feed with errors, per-table SLA affordances
- **catalogs**: Nessie over Iceberg REST with config-driven prefix
- **catalogs**: auth strategies with RFC 8693 token exchange
- **operations**: one block per execution with timeline bar
- **execution_steps**: split skip_reason from error_message, add blocked status
- **error_events**: detail page with assign/acknowledge/resolve workflow and teams

### Bug Fixes

- **retention**: cascade FK on execution_steps/table_locks so prune never halts
- **freshness**: heartbeat on FreshnessRun so sweep is not reaped mid-flight
- **trino**: accumulate rows across pagination pages in poll
- **history, pager**: query id last in step meta; pager active-page bug
- **docs**: read counter.dev data-id from DATA_TRACKING secret
- **catalog endpoint format validation**: add \z anchor (Brakeman ValidationRegex)
- **helpers and broadcasts**: guard from missing request context
- **user role**: add confirmation before changing
- **flash notices**: move all hardcoded to i18n
- **maintenance plan**: add confirmation dialog before pausing

### Refactoring

- **trino**: poll with early-stop limit instead of blind row accumulation
- **catalogs**: drop the path_prefix legacy regime - discovery is the only path
- **history, errors**: step subrows, real filters and a proper pager

### Chores

- ignore dump artifacts
- **error_events**: tighten detail page typography
- **teams**: match project design system on assignment and team forms

## [0.1.0](https://github.com/maltzsama/lakedeepdiver/releases/tag/v0.1.0) - 2026-08-09

### Added

- Initial release: Rails 8 control plane for Iceberg table maintenance.
