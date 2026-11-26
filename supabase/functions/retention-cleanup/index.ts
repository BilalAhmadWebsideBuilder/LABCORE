import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

async function constantTimeEqual(left: string, right: string) {
  const [leftHash, rightHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(left)),
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(right)),
  ]);
  const a = new Uint8Array(leftHash);
  const b = new Uint8Array(rightHash);
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  const expectedSecret = Deno.env.get("RETENTION_JOB_SECRET");
  const suppliedSecret = request.headers.get("x-retention-job-secret");
  if (!expectedSecret || !suppliedSecret || !(await constantTimeEqual(expectedSecret, suppliedSecret))) {
    return Response.json({ error: "Authentication required" }, { status: 401 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return Response.json({ error: "Retention service is not configured" }, { status: 503 });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await serviceClient.rpc("run_lab_retention_cleanup");
  if (error) {
    console.error("Could not run retention cleanup:", error.message);
    return Response.json({ error: "Retention cleanup failed" }, { status: 500 });
  }
  return Response.json({ completed: true, result: data }, { status: 200 });
});
