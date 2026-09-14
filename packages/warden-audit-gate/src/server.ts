import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from 'node:http';
import {
  admitTarget,
  verifyAdmission,
  type AuditBinding,
  type EvidenceReceipt,
  type TargetConfig,
} from './index.js';
import { uiHtml } from './ui.js';

const receipts: EvidenceReceipt[] = [];
const bindings = new Map<string, AuditBinding>();

async function jsonBody(
  request: IncomingMessage,
): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) chunks.push(Buffer.from(chunk));
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}') as Record<
    string,
    unknown
  >;
}

function send(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  response.end(JSON.stringify(body));
}

export function createGateServer() {
  return createServer(async (request, response) => {
    try {
      if (request.method === 'GET' && request.url === '/') {
        response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
        return response.end(uiHtml);
      }
      if (request.method === 'GET' && request.url === '/readyz')
        return send(response, 200, {
          status: 'ready',
          serviceId: 'warden-audit-gate',
        });
      if (request.method === 'GET' && request.url === '/api/receipts')
        return send(response, 200, receipts);
      if (request.method === 'POST' && request.url === '/api/admit') {
        const body = await jsonBody(request);
        const result = await admitTarget(body as unknown as TargetConfig);
        receipts.unshift(result.receipt);
        if (result.outcome === 'admitted')
          bindings.set(result.binding.id, result.binding);
        return send(
          response,
          result.outcome === 'admitted' ? 200 : 422,
          result,
        );
      }
      if (request.method === 'POST' && request.url === '/api/verify') {
        const body = await jsonBody(request);
        const binding = bindings.get(String(body.bindingId));
        if (!binding) return send(response, 404, { error: 'Unknown binding.' });
        const result = await verifyAdmission(
          binding,
          body.config as TargetConfig,
        );
        receipts.unshift(result.receipt);
        return send(
          response,
          result.outcome === 'admitted' ? 200 : 409,
          result,
        );
      }
      send(response, 404, { error: 'Not found.' });
    } catch (error) {
      send(response, 400, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });
}

const port = Number(process.env.WARDEN_GATE_PORT ?? 4310);
const host = process.env.WARDEN_GATE_HOST ?? '0.0.0.0';
createGateServer().listen(port, host, () =>
  console.log(`Warden Audit Gate ready at http://127.0.0.1:${port}`),
);
