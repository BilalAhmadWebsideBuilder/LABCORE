import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type InviteBody = {
  labId?: unknown;
  email?: unknown;
  fullName?: unknown;
  phone?: unknown;
  role?: unknown;
  pageKeys?: unknown;
};

const staffRoles = new Set([
  "lab_admin",
  "lab_manager",
  "receptionist",
  "technician",
  "billing_staff",
  "reporting_doctor",
]);
const pageKeys = new Set([
  "dashboard", "test_billing", "tests", "departments", "appointments", "scheduling", "samples", "patients", "reports",
  "invoice_history", "referring_doctors", "reagent_stock", "expenses", "analytics",
  "manage_users", "print_requests", "my_print_requests", "settings", "trash_bin", "help",
]);

function response(body: Record<string, unknown>, status: number, origin: string | null) {
  const headers = new Headers({ "content-type": "application/json" });
  const appOrigin = Deno.env.get("APP_ORIGIN")?.replace(/\/$/, "");
  if (origin && appOrigin && origin === appOrigin) {
    headers.set("access-control-allow-origin", appOrigin);
    headers.set("vary", "Origin");
  }
  return new Response(status === 204 ? null : JSON.stringify(body), { status, headers });
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  const appOrigin = Deno.env.get("APP_ORIGIN")?.replace(/\/$/, "");
  if (origin && appOrigin && origin !== appOrigin) {
    return response({ error: "Origin is not allowed" }, 403, origin);
  }
  if (request.method === "OPTIONS") {
    const result = response({}, 204, origin);
    result.headers.set("access-control-allow-methods", "POST, OPTIONS");
    result.headers.set("access-control-allow-headers", "authorization, apikey, content-type");
    return result;
  }
  if (request.method !== "POST") {
    return response({ error: "Method not allowed" }, 405, origin);
  }

  const authorization = request.headers.get("authorization");
  const bearer = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!bearer) return response({ error: "Authentication required" }, 401, origin);

  let body: InviteBody;
  try {
    body = await request.json() as InviteBody;
  } catch {
    return response({ error: "Invalid request body" }, 400, origin);
  }

  const labId = typeof body.labId === "string" ? body.labId : "";
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const fullName = typeof body.fullName === "string" ? body.fullName.trim() : "";
  const phone = typeof body.phone === "string" ? body.phone.trim() : "";
  const role = typeof body.role === "string" ? body.role : "";
  const requestedPages = Array.isArray(body.pageKeys) ? body.pageKeys : [];
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (
    !uuidPattern.test(labId) ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
    fullName.length < 2 || fullName.length > 120 ||
    phone.length > 32 ||
    !staffRoles.has(role) ||
    requestedPages.length < 1 || requestedPages.length > pageKeys.size ||
    requestedPages.some((page) => typeof page !== "string" || !pageKeys.has(page))
  ) {
    return response({ error: "Invitation details are invalid" }, 400, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const appUrl = Deno.env.get("APP_ORIGIN");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !appUrl) {
    return response({ error: "Invitation service is not configured" }, 503, origin);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${bearer}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: caller, error: callerError } = await callerClient.auth.getUser(bearer);
  if (callerError || !caller.user) {
    return response({ error: "Authentication could not be verified" }, 401, origin);
  }
  const { data: canManage, error: permissionError } = await callerClient.rpc("has_lab_permission", {
    target_lab: labId,
    target_permission: "staff.manage",
  });
  if (permissionError || !canManage) {
    return response({ error: "Staff invitation permission required" }, 403, origin);
  }
  const { data: canManageRoles, error: rolePermissionError } = await callerClient.rpc("has_lab_permission", {
    target_lab: labId,
    target_permission: "roles.manage",
  });
  if (rolePermissionError || !canManageRoles) {
    return response({ error: "Role management permission required" }, 403, origin);
  }
  for (const page of requestedPages as string[]) {
    const { data: hasPage, error: pageError } = await callerClient.rpc("has_lab_page_access", {
      target_lab: labId,
      target_page: page,
    });
    if (pageError || !hasPage) {
      return response({ error: "You can only grant pages already available to your account" }, 403, origin);
    }
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: invited, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName, phone: phone || null },
    redirectTo: `${appUrl.replace(/\/$/, "")}/reset-password`,
  });
  if (inviteError || !invited.user) {
    return response({ error: "Auth could not send the invitation. Check the email and Supabase Auth settings." }, 400, origin);
  }

  const { error: assignmentError } = await callerClient.rpc("assign_invited_member", {
    p_lab_id: labId,
    p_user_id: invited.user.id,
    p_role: role,
    p_page_keys: requestedPages,
    p_full_name: fullName,
    p_phone: phone || null,
  });
  if (assignmentError) {
    await adminClient.auth.admin.deleteUser(invited.user.id);
    return response({ error: "The invite was not assigned to this laboratory. Check your role and page grants." }, 400, origin);
  }

  return response({ invited: true }, 201, origin);
});
