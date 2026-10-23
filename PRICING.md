# Taskly product and pricing plan

**English** · [简体中文](PRICING.zh-CN.md)

## Launch status and implementation boundaries

- Policy version: `2026-10-v2`, 2026-10-23. The owner confirmed that every product is still in development and has no actual users. This document replaces conflicting previous pricing, early-bird and Pro proposals; there is no existing customer cohort to migrate. **Prices are launch targets, not live offers or claims that the listed features are implemented.**
- Entitlements cover delivered platforms only. New commercial plans do not change the LICENSE of released source. Source use, modification and redistribution rights are separate from official products, updates and services.
- Security fixes and reading, backing up or exporting your own data must not require another purchase. BYOK keys, payment-provider secrets and issuer private keys have different owners. Native hosts do not collect payment or issue credentials directly.

## Decision

**Consumer flagship; one purchase for the complete official desktop product**

Launch target: **¥168 / US$24; optional 12-month update renewal: ¥68 / US$10**. CNY and USD are independently set regional targets, not a live exchange-rate conversion.

Daily use, long-lived personal data and native interaction make Taskly a candidate for the first complete consumer product. A single complete purchase avoids maintaining an artificial Free/Pro feature matrix.

## Free and paid scope

Free / evaluation: Development previews remain free; this design does not add payment restrictions to existing previews. The future stable commercial edition has a full 14-day trial. After the trial, reading, searching, backups and standard-format export remain available. Reminders, natural-language entry and the CLI are part of the complete product, not separately priced extras. Source remains under AGPL-3.0.

Paid: One named user, covering the complete official macOS, Windows and Linux desktop product on platforms actually delivered, with 12 months of new-version eligibility. Unreleased mobile editions, hosted sync and model usage are not bundled promises.

## Purchase, trial and updates

A purchase includes 12 months of new-version eligibility. Versions obtained within that update window remain usable afterwards. Optional renewal adds 12 months from `max(payment time, current updates_through)`, with no back-billing for a gap and no automatic charge. Team renewals apply to the purchased number of named seats. There is no lifetime-all-future-updates plan. One named user can use their own computers; no hardware fingerprint is collected. Offline seat limits are contractual, not real-time concurrency enforcement. A team purchase combines seats; it does not imply a collaboration cloud.

A new paid tier has a full 14-day trial, then returns to the free tier. For a complete paid product, trial expiry preserves reading/search/backup/export. Offline trial state is a convenience and an agreement, not advertised as rollback-proof or impossible to reset. Do not presell codes before technical and platform gates pass. After a successful payment, Commerce issues Permit credentials idempotently. Use release time and `updates_through` for update eligibility; the current date must not suddenly invalidate an acquired version. Do not promise prompt offline refund/revocation enforcement that cannot be implemented.

The target price includes no custom development, hardware procurement, certification or response-time SLA. Support is asynchronous issue handling for the purchased version, supported platforms and validated combinations; a solo maintainer must not promise round-the-clock responses. Before sales, publish refund/cancellation rules, currency/tax totals, privacy terms and support scope, and confirm them at checkout. This plan is not a substitute for final checkout terms.

## Next gate before sales

Complete the data recovery, feedback and installation-specific update scenarios in #58 first. Then verify post-trial reading/export, Permit import/recovery, update-window boundaries, offline operation and refund states. This documentation does not change gates in the active reminder, sync or host code.

Execution entry: [issue #58](https://github.com/turinglambdaai/taskly/issues/58). Complete this bounded slice before expanding commercial features.

Portfolio role and shared boundaries: [PORTFOLIO](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/PORTFOLIO.md).
