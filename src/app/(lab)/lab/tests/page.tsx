import { redirect } from "next/navigation";
import { CatalogManager } from "@/components/catalog/CatalogManager";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";
import { requireMembership } from "@/lib/auth/authorization";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

export default async function TestsPage() {
  const membership = await requireMembership([
    "lab_admin", "lab_manager", "receptionist", "billing_staff", "technician",
  ]);
  const supabase = await createSupabaseServerClient();
  const { data: hasPageAccess, error: pageAccessError } = await supabase.rpc(
    "has_lab_page_access",
    { target_lab: membership.labId, target_page: "tests" },
  );
  if (pageAccessError) {
    const message = getDatabaseSetupMessage(pageAccessError);
    if (message) return <DatabaseSetupNotice message={message} />;
    throw new Error(`Could not verify test catalog page access: ${pageAccessError.message}`);
  }
  if (!hasPageAccess) redirect("/lab");
  const [
    { data: canRead, error: readError },
    { data: canManage, error: manageError },
  ] = await Promise.all([
    supabase.rpc("has_lab_permission", {
      target_lab: membership.labId,
      target_permission: "services.read",
    }),
    supabase.rpc("has_lab_permission", {
      target_lab: membership.labId,
      target_permission: "services.manage",
    }),
  ]);

  const permissionError = readError ?? manageError;
  if (permissionError) {
    const message = getDatabaseSetupMessage(permissionError);
    if (message) return <DatabaseSetupNotice message={message} />;
    throw new Error(`Could not verify test catalog access: ${permissionError.message}`);
  }
  if (!canRead) redirect("/lab");

  const [
    { data: departments, error: departmentError },
    { data: tests, error: testError },
  ] = await Promise.all([
    supabase.from("service_categories")
      .select("id, name, sort_order")
      .eq("lab_id", membership.labId)
      .is("deleted_at", null)
      .order("sort_order"),
    supabase.from("services")
      .select("id, category_id, code, name, description, service_type, price, duration_minutes, turnaround_minutes, preparation_instructions, fasting_required, method, normal_range, patient_visible")
      .eq("lab_id", membership.labId)
      .eq("active", true)
      .is("deleted_at", null)
      .order("name"),
  ]);

  const dataError = departmentError ?? testError;
  if (dataError) {
    const message = getDatabaseSetupMessage(dataError);
    if (message) return <DatabaseSetupNotice message={message} />;
    throw new Error(`Could not load the test catalog: ${dataError.message}`);
  }

  return (
    <div className="workspace-page">
      <div className="workspace-page-heading">
        <div>
          <p className="workspace-eyebrow">Laboratory setup</p>
          <h1>Tests catalog</h1>
          <p className="workspace-page-description">Maintain this laboratory’s departments, tests, and service pricing.</p>
        </div>
      </div>
      <CatalogManager
        departments={departments ?? []}
        tests={tests ?? []}
        canManage={canManage === true}
      />
    </div>
  );
}
