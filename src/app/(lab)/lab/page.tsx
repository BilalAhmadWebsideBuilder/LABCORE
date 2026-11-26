import { ArrowRight, Package, Users } from "lucide-react";
import Link from "next/link";
import { requireMembership } from "@/lib/auth/authorization";
import { LAB_DASHBOARD_ROLES } from "@/lib/auth/roles";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";
import { PageLoadErrorNotice } from "@/components/workspace/PageLoadErrorNotice";

export const instant = false;

export default async function LabDashboard() {
  const membership = await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const { data: hasPageAccess, error: pageAccessError } = await supabase.rpc(
    "has_lab_page_access",
    {
      target_lab: membership.labId,
      target_page: "dashboard",
    },
  );

  if (pageAccessError) {
    const setupMessage = getDatabaseSetupMessage(pageAccessError);
    if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
    return (
      <PageLoadErrorNotice
        title="Dashboard unavailable"
        message="We could not verify access to this workspace. Please try again later or contact your administrator."
      />
    );
  }
  if (!hasPageAccess) {
    return (
      <PageLoadErrorNotice
        title="Dashboard access is restricted"
        message="Your account does not have access to this page. Contact your laboratory administrator."
      />
    );
  }

  const { data: canReadPatients, error: permissionError } = await supabase.rpc(
    "has_lab_permission",
    {
      target_lab: membership.labId,
      target_permission: "patients.read",
    },
  );

  if (permissionError) {
    const setupMessage = getDatabaseSetupMessage(permissionError);
    if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
    return (
      <PageLoadErrorNotice
        title="Dashboard unavailable"
        message="We could not verify your dashboard permissions. Please try again later or contact your administrator."
      />
    );
  }

  let patientCount: number | null = null;
  let lowStockCount: number | null = null;
  if (canReadPatients) {
    const { count, error } = await supabase
      .from("patients")
      .select("id", { count: "exact", head: true })
      .eq("lab_id", membership.labId)
      .is("deleted_at", null);

    if (error) {
      const setupMessage = getDatabaseSetupMessage(error);
      if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
      return (
        <PageLoadErrorNotice
          title="Dashboard unavailable"
          message="We could not load the laboratory summary. Please try again later or contact your administrator."
        />
      );
    }
    patientCount = count ?? 0;
  }

  const { data: canReadInventory, error: inventoryPermissionError } =
    await supabase.rpc("has_lab_permission", {
      target_lab: membership.labId,
      target_permission: "inventory.read",
    });
  if (inventoryPermissionError) {
    const setupMessage = getDatabaseSetupMessage(inventoryPermissionError);
    if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
  } else if (canReadInventory) {
    const { data: inventory, error: inventoryError } = await supabase
      .from("reagent_stock")
      .select("quantity, reorder_level")
      .eq("lab_id", membership.labId)
      .is("deleted_at", null)
      .limit(500);
    if (inventoryError) {
      const setupMessage = getDatabaseSetupMessage(inventoryError);
      if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
    } else {
      lowStockCount = (inventory ?? []).filter(
        (row) => Number(row.quantity) <= Number(row.reorder_level),
      ).length;
    }
  }

  return (
    <div className="workspace-page">
      <div className="workspace-page-heading">
        <div>
          <p className="workspace-eyebrow">Laboratory overview</p>
          <h1>Your workspace</h1>
          <p className="workspace-page-description">
            Manage this laboratory’s patient records and continue setup of its workflows.
          </p>
        </div>
      </div>

      <section className="workspace-stat-grid" aria-label="Laboratory summary">
        <article className="workspace-stat-card">
          <span className="workspace-stat-icon"><Users size={18} /></span>
          <p>Registered patients</p>
          <strong>{patientCount === null ? "Restricted" : patientCount.toLocaleString()}</strong>
          <span>{patientCount === null ? "Not available for your role" : "In this laboratory"}</span>
        </article>
        {lowStockCount !== null && (
          <article className="workspace-stat-card">
            <span className="workspace-stat-icon"><Package size={18} /></span>
            <p>Low-stock reagents</p>
            <strong>{lowStockCount.toLocaleString()}</strong>
            <span>At or below reorder level</span>
          </article>
        )}
      </section>

      <section className="workspace-card workspace-next-step">
        <div className="workspace-next-icon"><Users size={21} /></div>
        <div>
          <h2>Patient records</h2>
          <p>Register a patient or find an existing record in this laboratory.</p>
        </div>
        <Link className="workspace-primary-button" href="/lab/patients">
          Open patients <ArrowRight size={17} />
        </Link>
      </section>
    </div>
  );
}
