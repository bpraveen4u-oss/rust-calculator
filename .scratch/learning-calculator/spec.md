# Learning Calculator — Product and Technical Specification

Status: ready-for-agent

## Problem Statement

Learners ages 8–11 can get a numerical answer from a calculator, but that alone does not help them understand the arithmetic behind it. Families also need a way to keep separate learner progress available across devices without requiring children to provide personal information or remain online.

## Solution

Build an English-language, accessible, calculator-first learning app for iOS and Android. It supports Common Core-aligned grades 3–5 arithmetic, expressions, fractions, and decimals; provides an immediate answer with optional deterministic hints and worked steps; and works offline. Multiple pseudonymous learner profiles and their calculation history are stored locally. Guardians can optionally pair devices with a short-lived manual code and sync a minimal profile and history through a Rust service. Cloud sync must not launch until U.S. legal/privacy review approves the parental-consent approach.

## User Stories

1. As a learner, I want to choose my grade (3, 4, or 5), so that the explanations use familiar classroom language.
2. As a learner, I want a calculator-first home screen, so that I can enter a calculation without navigating a lesson curriculum.
3. As a learner, I want to enter addition, subtraction, multiplication, and division problems, so that I can check everyday arithmetic.
4. As a learner, I want to enter a multi-step expression, so that I can practice calculations involving more than one operation.
5. As a learner, I want parentheses and standard order of operations to be honored, so that the result matches the intended expression.
6. As a learner, I want to see the answer immediately, so that the calculator remains quick to use.
7. As a learner, I want to reveal a hint only when I ask, so that I can try solving the problem independently first.
8. As a learner, I want to reveal a worked explanation separately from the answer, so that I can learn the reasoning when I need help.
9. As a learner, I want hints and explanations to be deterministic and available on-device, so that they work offline and are consistent.
10. As a learner, I want explanations written and reviewed for my selected grade, so that the vocabulary and examples are age-appropriate.
11. As a learner, I want fraction input and display, including proper and mixed fractions, so that I can work with the forms I see in class.
12. As a learner, I want fraction results simplified and shown exactly, so that I can understand the precise answer.
13. As a learner, I want to reveal a decimal equivalent for a fraction result, so that I can compare representations when useful.
14. As a learner, I want to calculate with decimals, so that I can practice another common grade-level number form.
15. As a learner, I want a contextual visual such as a fraction bar when it clarifies a step, so that I can connect symbols to quantities.
16. As a learner, I want clear feedback for an incomplete or invalid expression, so that I can correct it without being shown a misleading result.
17. As a learner, I want the calculator and explanations to work without internet access, so that I can use them anywhere.
18. As a learner, I want to keep a local history of calculations, so that I can revisit problems I have already worked.
19. As a learner, I want history entries to show the expression, result, time, and topic, so that I can recall what I practiced.
20. As a learner in a household with siblings, I want multiple separate profiles on one device, so that each learner's grade and history stay distinct.
21. As a learner, I want my profile to use a pseudonymous identifier rather than asking for my name or email, so that I can use the app without sharing personal details.
22. As a guardian, I want to manage device linking and cloud-data controls in a separate protected area, so that children do not accidentally change account settings.
23. As a guardian, I want to unlock protected controls with a PIN and platform biometrics when available, so that they are convenient while remaining restricted.
24. As a guardian, I want to opt in to cloud sync only after initiating device pairing, so that local-only use is the default.
25. As a guardian, I want to link devices using a manually entered code, so that I can connect a learner's profile without an email account or QR scanner.
26. As a guardian, I want pairing codes to be single-use, expire after about ten minutes, and have server-side attempt limits, so that a leaked or guessed code has limited value.
27. As a guardian, I want the app to explain the sync choice before pairing, so that I understand that learner history will leave the device.
28. As a guardian, I want to enable sync only after an approved parental-consent flow is completed, so that the service does not collect child progress before consent requirements are met.
29. As a learner with paired devices, I want profile grade and progress to sync automatically when online, so that my learning context is consistent across devices.
30. As a learner, I want sync work to queue while offline and resume after reconnecting, so that temporary connectivity loss does not block learning or discard progress.
31. As a learner, I want to see sync status and the last successful sync time, so that I know whether another device has current progress.
32. As a learner, I want entries from linked devices to merge without replacing one device's history with another's, so that concurrent use does not lose calculations.
33. As a learner, I want duplicate sync submissions to be recognized by entry identity, so that retries do not create duplicate history entries.
34. As a guardian, I want cloud history to contain only the expression, result, timestamp, and topic tag needed for learning review, so that unnecessary activity data is not collected.
35. As a guardian, I want cloud history entries deleted individually 90 days after recording, so that synced calculations are retained only for a defined period.
36. As a guardian, I want local history to remain until it is cleared, so that I can decide when to remove the device's copy.
37. As a guardian, I want to erase a learner's cloud history from the protected area, so that I can remove synced calculations on request.
38. As a guardian, I want cloud-history erasure to leave the pseudonymous profile shell intact, so that the profile can remain linked for future sync if desired.
39. As a guardian, I want an empty cloud profile and its pairing metadata to expire after 90 days without linked-device activity, so that inactive metadata is not retained indefinitely.
40. As a guardian, I want the app to explain that there is no recovery key, so that I understand progress cannot be restored if every linked device is lost.
41. As a learner, I want readable text, screen-reader labels, strong contrast, scalable type, and controls that do not rely on color alone, so that the app is usable with varied access needs.
42. As a learner, I want a calm visual design rather than streaks, leaderboards, or reward loops, so that the experience focuses on understanding.
43. As a family, I want an English-only, free app without ads or in-app purchases in v1, so that the initial learning experience is focused and predictable.

## Implementation Decisions

- Deliver one Flutter application for iOS and Android. The app is calculator-first and supports learners in grades 3–5, with first-party learning content aligned to U.S. Common Core mathematics standards.
- Include addition, subtraction, multiplication, division, multi-step expressions with parentheses and standard order of operations, fractions, and decimals. A calculation shows its answer immediately; optional hints and worked steps are separate user actions.
- Generate explanations deterministically on-device. Review the grade-level wording, hints, examples, and step explanations as first-party content. Do not rely on an online AI service for explanations.
- Fraction results are simplified exact fractions by default, with a user-accessible decimal equivalent. Provide contextual visuals only when they clarify a step.
- Persist local profiles and calculation history in SQLite through a Flutter-compatible persistence layer. Keep sync credentials in iOS Keychain or Android Keystore. Local history remains until a guardian clears it.
- Support multiple pseudonymous learner profiles per installation. Store a selected grade on each profile and synchronize it with the profile. Do not collect a child's name, email, contacts, precise location, or freeform notes.
- Provide protected guardian controls using a guardian PIN and platform biometrics where available. Sync is opt-in and starts only after guardian-initiated device pairing.
- Pair devices with a manually entered, single-use code that expires after approximately ten minutes and is protected by server-side attempt limits. Do not require child email accounts or provide a recovery key.
- Implement the cloud service in Rust with Axum/Tokio, a REST/JSON interface, and SQLx with SQLite. The service is limited to pairing and progress/history synchronization; arithmetic, explanations, and offline behavior remain on-device.
- Sync pseudonymous profile identity, grade, and calculation history fields limited to expression, result, timestamp, and topic tag. History is append-only and de-duplicated by entry ID; merge concurrent updates without replacing history from another device. Queue local changes offline and synchronize automatically when online, with a visible status and last-sync time.
- Cloud history expires per entry 90 days after it is recorded. Guardian-triggered cloud-history deletion erases history but retains the profile shell and pairing metadata; empty profile metadata expires after 90 days without linked-device activity. Local history is not removed by cloud expiration or cloud-history deletion.
- Host the single-instance Rust service on an Azure Linux VM with an encrypted managed disk and automated backups. SQLite's single-instance constraint is intentional for v1.
- U.S. legal/privacy review of the parental-consent method is a launch blocker for cloud sync. The exact consent mechanism is unresolved until that review; a simple guardian toggle must not be assumed sufficient.
- Version one is English-only, free, ad-free, and has no in-app purchases. Do not include a separate practice mode, full lesson curriculum, gamification, or third-party behavioral advertising/analytics SDKs.

## Testing Decisions

- Tests must verify observable behavior and public contracts, not internal implementation details. Prefer the highest practical seams and avoid coupling assertions to widget trees, private helper functions, SQL query structure, or framework internals.
- Flutter user-flow tests will exercise calculator entry and results, operation precedence, fraction simplification and decimal reveal, grade-appropriate optional explanations, profile separation, local history, offline use, and sync status/queue behavior. Use an in-memory local store and a controllable fake sync API so flows are deterministic.
- Rust HTTP API contract tests will exercise pairing-code expiry, single-use and attempt limits, profile authorization, idempotent history merge, guardian cloud-history deletion, and per-entry/profile-metadata expiration against a temporary SQLite database.
- Validate the two seams together with representative client/server contract cases, especially queued offline changes, retry de-duplication, and merged multi-device history.
- There is no existing application or test suite in the repository to extend; these tests establish the initial behavioral testing conventions. No prior-art tests are available.

## Out of Scope

- A separate practice-drill mode, lesson curriculum, assessments, classroom/teacher dashboards, or parent progress-reporting UI.
- Scientific, financial, or non-core arithmetic topics beyond the specified grades 3–5 arithmetic, fractions, decimals, and expressions.
- AI-generated or server-generated explanations, and any requirement for internet access to calculate or learn.
- Child email accounts, named learner profiles, recovery keys, QR-based pairing, and restoration after all paired devices are lost.
- Ads, subscriptions, in-app purchases, streaks, leaderboards, reward loops, and third-party behavioral advertising or analytics SDKs.
- Languages other than English, support for grade levels outside 3–5, and non-U.S. curriculum alignment in v1.
- A multi-instance backend, a managed database, or an Azure hosting design other than the selected single VM with SQLite.
- Enabling cloud sync before the parental-consent approach has passed U.S. legal/privacy review.

## Further Notes

- The product is intended for U.S. children ages 8–11. The consent mechanism and any required verification steps must be decided through qualified legal/privacy review before cloud sync is enabled or launched.
- The user chose to erase cloud history while retaining the profile shell and pairing metadata. The user also chose a 90-day inactivity expiry for empty profile metadata; the exact activity definition should be made explicit during API design and must not extend an individual history entry's 90-day retention period.
- Backup policy and retention for Azure VM backups were not specified. They must be designed so backups do not silently defeat the stated deletion and retention commitments; confirm the operational policy during deployment design.
- The repository was empty when inspected. There are no existing application modules, glossary terms, ADRs, or test conventions to preserve; the proposed testing seams are the first conventions for the implementation.
