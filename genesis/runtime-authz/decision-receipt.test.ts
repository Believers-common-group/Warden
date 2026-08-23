import { buildWardenDecisionReceipt } from './decision-receipt.js';

function assert(condition: unknown, message: string): asserts condition { if (!condition) throw new Error(message); }
function expectThrow(fn: () => unknown, pattern: RegExp) { try { fn(); } catch (e) { assert(pattern.test(String(e)), `wrong error: ${e}`); return; } throw new Error('expected throw'); }

const base = {
  decisionReceiptId:'WDR-20260823-0001', decisionDigest:'d'.repeat(64), decision:'ALLOW' as const,
  principal:{digitalMeId:'DM-ALPHA-001',authenticatedPrincipalReceiptId:'APR-20260823-0001'},
  action:{actionId:'runtime.event.ingest',capabilityId:'runtime:ingest',resourceId:'SCOTTS-DOD-001',effectClass:'WRITE' as const,requestDigest:'b'.repeat(64)},
  authorityRefs:['AUTH-001'],consentRefs:['CONSENT-001'],policyRefs:['POLICY-001'],grantBinding:{grantId:'GRANT-001',authorizationTokenDigest:'c'.repeat(64)},
  issuedAt:'2026-08-23T05:30:01Z',expiresAt:'2026-08-23T05:35:01Z',correlationId:'corr-001'
};
const allow=buildWardenDecisionReceipt(base);
assert(allow.schema_id==='warden:decision','schema');
assert(allow.profile_id==='runtime-exact-action-authorization/v1','profile');
assert(allow.decision_receipt_id==='WDR-20260823-0001','receipt preserved');
assert(allow.decision_digest==='d'.repeat(64),'digest preserved');
assert(allow.principal_binding.digitalme_id==='DM-ALPHA-001','principal');
assert(allow.action_binding.request_digest==='b'.repeat(64),'request digest');
assert(!('authorizationToken' in allow),'no raw token');
expectThrow(()=>buildWardenDecisionReceipt({...base,authorityRefs:[]}),/authorityRefs/);
expectThrow(()=>buildWardenDecisionReceipt({...base,grantBinding:undefined}),/grantBinding/);
const deny=buildWardenDecisionReceipt({...base,decision:'DENY',authorityRefs:undefined,grantBinding:undefined,reasonCodes:['CONSENT_MISSING']});
assert(deny.decision==='DENY','deny');
assert(!('grant_binding' in deny),'deny no grant');
expectThrow(()=>buildWardenDecisionReceipt({...base,authorizationToken:'secret'} as any),/Raw authorization token/);
console.log('Warden decision receipt tests: 12 assertions PASS');
