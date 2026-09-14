# WARDEN-MCP-PROXY-001 R0.1

Status: `QUALIFICATION_ONLY`

Target: `DESKTOP-COMMANDER-MCP-001`

This package is a qualification harness and mandatory mediation boundary. It does not install, enable, or promote Desktop Commander. Production access and secret access remain false. The source artifact `ALPHA-DESKTOP-COMMANDER-ADMISSION-001 R0.1` was referenced by the requesting conversation but was not present in the inspected checkout, so its registration assertions remain external provenance rather than repository-verified facts.

## Child blocks

- `WARDEN-MCP-PROXY-IDENTITY-001` accepts only explicitly configured caller identities.
- `WARDEN-MCP-REQUEST-NORMALIZER-001` strictly parses supported tools, resolves canonical and real filesystem targets, and creates an allowlisted environment with a synthetic HOME.
- `WARDEN-MCP-BOUNDARY-ENFORCER-001` authorizes the resolved target against configured staging roots and blocks secret-bearing filenames.
- `WARDEN-MCP-EVIDENCE-BRIDGE-001` writes an admission event before execution and a linked execution event afterward. An execution event cannot be written without the exact allow admission event.

The guarded Desktop Commander adapter requires a private, in-memory proxy capability. This makes the package's configured target unreachable through public calls that bypass `WardenMcpProxy.invoke`. `QUALIFICATION_DEPLOYMENT_MANIFEST` supplies the required registration topology: the proxy is the sole public entrypoint, while Desktop Commander is private and callable only by `WARDEN-MCP-PROXY-001`. `validateWardenMcpDeployment` rejects duplicate or missing registrations, public target exposure, additional target callers, and any attempted admission promotion.

## Phase 3

P3.1 through P3.10 live in `packages/warden-mcp-proxy/test/phase3.test.ts`. Promotion is explicitly out of scope: successful tests leave `ADMISSION_STATUS` equal to `QUALIFICATION_ONLY`.
