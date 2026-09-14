import { createServer } from 'node:http';

const serviceId = process.env.WARDEN_TARGET_ID ?? 'alpha-demo';
const port = Number(process.env.WARDEN_TARGET_PORT ?? 4311);
const host = process.env.WARDEN_TARGET_HOST ?? '0.0.0.0';

createServer((request, response) => {
  const headers = {
    'content-type': 'application/json; charset=utf-8',
    'x-warden-service-id': serviceId,
  };
  if (request.url === '/readyz') {
    response.writeHead(200, headers);
    return response.end(
      JSON.stringify({ status: 'ready', serviceId, revision: 'alpha-local-1' }),
    );
  }
  response.writeHead(200, headers);
  response.end(
    JSON.stringify({
      application: 'Alpha',
      serviceId,
      revision: 'alpha-local-1',
    }),
  );
}).listen(port, host, () =>
  console.log(`Alpha demo target ready at http://127.0.0.1:${port}`),
);
