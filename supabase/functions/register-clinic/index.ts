import { createClient } from 'npm:@supabase/supabase-js@2'

// Paste the SAME decimal modulus you put in license_verifier.dart:
const MODULUS_DEC = '20203797802593410663666366605079726360446927517292465263038419473866385984552141653206975007947126635288365632671500157384688728264457913161178253893157020185642329615433788401151707821940917520635932357988845312625187930062869261825677628121135819704504493375734464481970595446094463685971404638191659129129234720907927793258477069629325093169814196586347269275251249049476621222023504951393653382379485127722644266816581298524833794103812038512060073333917814610602502112878171236299217959477204264801178020594411625303937409306315774386458173443441490044507604407663411432931174876301534245877353262712707559573323'
const EXPONENT = 65537n

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

function bytes(b: bigint): Uint8Array {
  let hex = b.toString(16); if (hex.length % 2) hex = '0' + hex
  const out = new Uint8Array(hex.length / 2)
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16)
  return out
}
const b64url = (u: Uint8Array) => btoa(String.fromCharCode(...u)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

async function verify(lic: any): Promise<boolean> {
  try {
    const key = await crypto.subtle.importKey('jwk',
      { kty: 'RSA', n: b64url(bytes(BigInt(MODULUS_DEC))), e: b64url(bytes(EXPONENT)), alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'])
    const canonical = JSON.stringify({
      clinicId: lic.clinicId, clinicName: lic.clinicName, tier: lic.tier, cloudPackage: lic.cloudPackage,
      maxBranches: lic.maxBranches, maxUsers: lic.maxUsers, issuedAt: lic.issuedAt,
      expiresAt: lic.expiresAt, machineFingerprint: lic.machineFingerprint,
    })
    const sig = Uint8Array.from(atob(lic.signature), c => c.charCodeAt(0))
    return await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sig, new TextEncoder().encode(canonical))
  } catch { return false }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { license, email, password } = await req.json()
    if (!license || !email || !password) return json({ ok: false, error: 'Missing fields.' }, 400)
    if (!(await verify(license))) return json({ ok: false, error: 'License signature is not valid.' }, 400)
    if (new Date(license.expiresAt) < new Date()) return json({ ok: false, error: 'This license has expired.' }, 400)

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } })

    const { error: userErr } = await admin.auth.admin.createUser({
  email, password, email_confirm: true, app_metadata: { clinic_id: license.clinicId },
})
const dup = userErr && /already.*(registered|exists)|duplicate/i.test(userErr.message)
if (userErr && !dup) return json({ ok: false, error: userErr.message }, 400)
// dup => a previous attempt already created this account; fall through and finish the clinic row.

const { error: clinicErr } = await admin.from('clinics').upsert({
  id: license.clinicId, name: license.clinicName, tier: license.tier, status: 'active', expires_at: license.expiresAt,
})
if (clinicErr) return json({ ok: false, error: clinicErr.message }, 400)
return json({ ok: true })

  
  } catch (e) { return json({ ok: false, error: String(e) }, 500) }
})