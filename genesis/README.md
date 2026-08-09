# Genesis Warden Integration

This directory contains estate-specific Warden contracts and policies developed on the persistent `genesis` integration branch.

It does not redefine or vendor-modify the upstream agent framework. Genesis-specific authority logic is kept in this isolated namespace and may later be implemented by bounded runtime adapters.

## Role

Warden is the consent, authority, privacy, purpose and policy controller between a DigitalMe Actor and any requested capability.

For LENSEOS the execution boundary is:

```text
Application / Visual Intelligence
        -> semantic optical intent
        -> Warden authorization
        -> deterministic Safety Envelope
        -> LENSEOS Runtime / FrameBus
        -> physical optical state
```

Warden authorizes **intent and context access**. It never directly commands electrodes, chemistry-specific waveforms or safety-critical visibility limits.

## LENSEOS contract files

- `contracts/lenseos-intent-authorization.schema.json`
- `policies/lenseos-policy.yaml`

## Decision model

Warden returns one of:

- `ALLOW`
- `DENY`
- `ALLOW_WITH_LIMITS`

Every positive grant is purpose-scoped, environment-scoped and time-bounded. A later Safety Domain may further constrain an allowed request; Warden authorization is necessary but not sufficient for physical actuation.

## Privacy defaults

- physical-system and ordinary environmental sensing may be authorized by environment policy;
- human-context sensing requires explicit purpose and bounded scope;
- gaze, camera, microphone, recording and equivalent content-sensitive sensing default to deny unless explicitly granted;
- remote control defaults to deny unless explicitly granted;
- no permission is inferred merely because a device technically supports the capability.

## Genesis change lineage

Initial change envelope: `GEN-CHG-20260809-LENSEOS-001`.

Common architectural changes must return to `Believers-common-group/genesis-stack:genesis` before stable release promotion.
