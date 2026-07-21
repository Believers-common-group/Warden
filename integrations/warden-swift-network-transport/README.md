# Warden Swift Network Transport v0.6

Swift 6 evidence transport for the Warden → RiverOS → Synnergyze boundary.

## Included

- tenant/device/project-bound schema-v2 events;
- purpose and authority enforcement;
- metadata allowlisting;
- canonical SHA-256 hashing and hash-chain anchors;
- HMAC and Apple Ed25519 device signatures;
- encrypted durable local storage hooks;
- deterministic, idempotent batches;
- acknowledgement-before-removal delivery;
- receipt verification and dead-letter handling;
- Supabase Warden schema and Edge Functions;
- governed Typeform MCP connector-licence intake.

## Live Supabase boundary

Project ref: `ayrivdysmbphhlqjmdtc`

- ingestion: `https://ayrivdysmbphhlqjmdtc.supabase.co/functions/v1/warden-ingest`
- MCP licence intake: `https://ayrivdysmbphhlqjmdtc.supabase.co/functions/v1/typeform-mcp-license-intake`

The existing `vsr-voi-recovery-pilot` tenant remains pending. No tenant, device, allow policy, connector licence, or VSR licence is activated implicitly.

## Build

```bash
swift test
swift build -c release
```

## Typeform rule

A Typeform response creates a reviewable connector application only. Warden must validate the referenced VSR licence and approve a licence binding before activation.
