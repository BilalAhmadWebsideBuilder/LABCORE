import { requireMembership } from "@/lib/auth/authorization";
import { LAB_DASHBOARD_ROLES, STAFF_ROLE_LABELS } from "@/lib/auth/roles";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/components/workspace/WorkspaceShell";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";

export const instant = false;

const fallbackPageGrants: Record<string, string[]> = {
  lab_admin: [
    "dashboard", "test_billing", "tests", "departments", "appointments", "scheduling", "samples", "patients", "reports",
    "invoice_history", "referring_doctors", "reagent_stock", "expenses", "analytics",
    "manage_users", "print_requests", "my_print_requests", "settings", "trash_bin", "help",
  ],
  lab_manager: [
    "dashboard", "tests", "departments", "appointments", "scheduling", "samples", "reports", "referring_doctors",
    "reagent_stock", "analytics", "help",
  ],
  receptionist: [
    "dashboard", "test_billing", "patients", "appointments", "samples", "invoice_history",
    "my_print_requests", "help",
  ],
  technician: ["dashboard", "samples", "reports", "help"],
  billing_staff: ["dashboard", "invoice_history", "patients", "expenses", "analytics", "help"],
  reporting_doctor: ["dashboard", "reports", "patients", "help"],
};

export default async function LabWorkspaceLayout({
  children,
}: LayoutProps<"/lab">) {
  const membership = await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const [
    { data: lab, error: labError },
    { data: profile, error: profileError },
    { data: pageGrantRows, error: pageGrantError },
  ] =
    await Promise.all([
      supabase.from("labs").select("name").eq("id", membership.labId).maybeSingle(),
      supabase.from("profiles").select("full_name").eq("id", membership.userId).maybeSingle(),
      supabase.from("page_grants").select("page_key").eq("lab_id", membership.labId).eq("user_id", membership.userId),
    ]);

  const setupMessage =
    (labError && getDatabaseSetupMessage(labError)) ||
    (profileError && getDatabaseSetupMessage(profileError)) ||
    (pageGrantError && getDatabaseSetupMessage(pageGrantError));

  if (labError && !getDatabaseSetupMessage(labError)) {
    throw new Error(`Could not load laboratory workspace: ${labError.message}`);
  }
  if (profileError && !getDatabaseSetupMessage(profileError)) {
    throw new Error(`Could not load staff profile: ${profileError.message}`);
  }
  if (pageGrantError && !getDatabaseSetupMessage(pageGrantError)) {
    throw new Error(`Could not load workspace permissions: ${pageGrantError.message}`);
  }

  const grantedPages = pageGrantRows?.map((row) => row.page_key) ??
    fallbackPageGrants[membership.role] ?? ["dashboard", "help"];

  return (
    <WorkspaceShell
      labName={lab?.name ?? "Laboratory"}
      userName={profile?.full_name?.trim() || "Lab staff"}
      roleLabel={STAFF_ROLE_LABELS[membership.role] ?? "Laboratory staff"}
      grantedPages={grantedPages}
    >
      {setupMessage && <DatabaseSetupNotice message={setupMessage} />}
      {children}
    </WorkspaceShell>
  );
}
