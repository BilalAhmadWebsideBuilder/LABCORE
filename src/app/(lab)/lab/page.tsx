import { ArrowRight, Users } from "lucide-react";
import Link from "next/link";
import { requireMembership } from "@/lib/auth/authorization";
import { LAB_DASHBOARD_ROLES } from "@/lib/auth/roles";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

export default async function LabDashboard() {
  const membership = await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const { data: canReadPatients, error: permissionError } = await supabase.rpc(
    "has_lab_permission",
    {
      target_lab: membership.labId,
      target_permission: "patients.read",
    },
  );

  if (permissionError) {
    throw new Error(`Could not verify dashboard permissions: ${permissionError.message}`);
  }

  let patientCount: number | null = null;
  if (canReadPatients) {
    const { count, error } = await supabase
      .from("patients")
      .select("id", { count: "exact", head: true })
      .eq("lab_id", membership.labId)
      .is("deleted_at", null);

    if (error) {
      throw new Error(`Could not load patient count: ${error.message}`);
    }
    patientCount = count ?? 0;
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
