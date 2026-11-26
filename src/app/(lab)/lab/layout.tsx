import { requireMembership } from "@/lib/auth/authorization";
import { LAB_DASHBOARD_ROLES, STAFF_ROLE_LABELS } from "@/lib/auth/roles";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { WorkspaceShell } from "@/components/workspace/WorkspaceShell";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";
import { connection } from "next/server";

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
  await connection();
  const membership = await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const [
    { data: lab, error: labError },
    { data: profile, error: profileError },
    { data: pageGrantRows, error: pageGrantError },
    { data: stockRows, error: stockError },
  ] =
    await Promise.all([
      supabase.from("labs").select("name").eq("id", membership.labId).maybeSingle(),
      supabase.from("profiles").select("full_name").eq("id", membership.userId).maybeSingle(),
      supabase.from("page_grants").select("page_key").eq("lab_id", membership.labId).eq("user_id", membership.userId),
      supabase.from("reagent_stock").select("name, quantity, reorder_level").eq("lab_id", membership.labId).is("deleted_at", null).limit(100),
    ]);

  const setupMessage =
    (labError && getDatabaseSetupMessage(labError)) ||
    (profileError && getDatabaseSetupMessage(profileError)) ||
    (pageGrantError && getDatabaseSetupMessage(pageGrantError)) ||
    (stockError && getDatabaseSetupMessage(stockError));

  if (labError && !getDatabaseSetupMessage(labError)) {
    throw new Error(`Could not load laboratory workspace: ${labError.message}`);
  }
  if (profileError && !getDatabaseSetupMessage(profileError)) {
    throw new Error(`Could not load staff profile: ${profileError.message}`);
  }
  if (pageGrantError && !getDatabaseSetupMessage(pageGrantError)) {
    throw new Error(`Could not load workspace permissions: ${pageGrantError.message}`);
  }
  if (stockError && !getDatabaseSetupMessage(stockError)) {
    throw new Error(`Could not load stock alerts: ${stockError.message}`);
  }

  const grantedPages = pageGrantRows?.map((row) => row.page_key) ??
    fallbackPageGrants[membership.role] ?? ["dashboard", "help"];
  const stockAlerts = (stockRows ?? [])
    .filter((row) => Number(row.quantity) <= Number(row.reorder_level))
    .map((row) => ({
      name: row.name,
      quantity: Number(row.quantity),
      reorderLevel: Number(row.reorder_level),
    }))
    .slice(0, 5);

  return (
    <WorkspaceShell
      labName={lab?.name ?? "Laboratory"}
      userName={profile?.full_name?.trim() || "Lab staff"}
      roleLabel={STAFF_ROLE_LABELS[membership.role] ?? "Laboratory staff"}
      grantedPages={grantedPages}
      stockAlerts={grantedPages.includes("reagent_stock") ? stockAlerts : []}
    >
      {setupMessage && <DatabaseSetupNotice message={setupMessage} />}
      {children}
    </WorkspaceShell>
  );
}
