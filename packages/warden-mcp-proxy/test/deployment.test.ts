import { describe, expect, test } from 'vitest';

import {
  ADMISSION_STATUS,
  DESKTOP_COMMANDER_ID,
  QUALIFICATION_DEPLOYMENT_MANIFEST,
  WARDEN_MCP_PROXY_ID,
  validateWardenMcpDeployment,
  type WardenMcpDeploymentManifest,
} from '../src/index';

describe('WARDEN-MCP-PROXY-001 deployment topology', () => {
  test('accepts the qualification-only proxy entrypoint manifest', () => {
    expect(
      validateWardenMcpDeployment(QUALIFICATION_DEPLOYMENT_MANIFEST),
    ).toMatchObject({
      valid: true,
    });
  });

  test('rejects a publicly exposed Desktop Commander target', () => {
    const manifest: WardenMcpDeploymentManifest = {
      services: QUALIFICATION_DEPLOYMENT_MANIFEST.services.map((service) =>
        service.identity === DESKTOP_COMMANDER_ID
          ? { ...service, exposure: 'public' as const }
          : service,
      ),
    };
    expect(validateWardenMcpDeployment(manifest)).toEqual({
      valid: false,
      reason: 'DIRECT_TARGET_ROUTE_FORBIDDEN',
    });
  });

  test('rejects any caller other than the proxy for Desktop Commander', () => {
    const manifest: WardenMcpDeploymentManifest = {
      services: QUALIFICATION_DEPLOYMENT_MANIFEST.services.map((service) =>
        service.identity === DESKTOP_COMMANDER_ID
          ? {
              ...service,
              callableBy: [WARDEN_MCP_PROXY_ID, 'DEVELOPER-TOOLING-DOOR-001'],
            }
          : service,
      ),
    };
    expect(validateWardenMcpDeployment(manifest)).toEqual({
      valid: false,
      reason: 'DIRECT_TARGET_ROUTE_FORBIDDEN',
    });
  });

  test('rejects attempted promotion in the deployment manifest', () => {
    const manifest = {
      services: QUALIFICATION_DEPLOYMENT_MANIFEST.services.map((service) => ({
        ...service,
        admissionStatus:
          service.identity === DESKTOP_COMMANDER_ID
            ? 'STAGING_QUALIFIED'
            : ADMISSION_STATUS,
      })),
    } as unknown as WardenMcpDeploymentManifest;
    expect(validateWardenMcpDeployment(manifest)).toEqual({
      valid: false,
      reason: 'QUALIFICATION_BOUNDARY_REQUIRED',
    });
  });
});
