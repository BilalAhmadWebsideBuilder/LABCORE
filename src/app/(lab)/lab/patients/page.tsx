import { redirect } from "next/navigation";
import { PatientDirectory } from "@/components/patients/PatientDirectory";
import { requireMembership } from "@/lib/auth/authorization";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

export default async function PatientsPage() {
  const membership = await requireMembership(["lab_admin", "receptionist", "billing_staff"]);
  const supabase = await createSupabaseServerClient();
  const [{ data: canRead, error: readPermissionError }, { data: canRegister, error: writePermissionError }] =
    await Promise.all([
      supabase.rpc("has_lab_permission", {
        target_lab: membership.labId,
        target_permission: "patients.read",
      }),
      supabase.rpc("has_lab_permission", {
        target_lab: membership.labId,
        target_permission: "patients.write",
      }),
    ]);

  if (readPermissionError) {
    throw new Error(`Could not verify patient access: ${readPermissionError.message}`);
  }
  if (writePermissionError) {
    throw new Error(`Could not verify patient registration access: ${writePermissionError.message}`);
  }
  if (!canRead) redirect("/lab");

  const { data: patients, error } = await supabase
    .from("patients")
    .select("id, patient_code, full_name, phone, date_of_birth, gender, created_at")
    .eq("lab_id", membership.labId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) {
    throw new Error(`Could not load patient records: ${error.message}`);
  }

  return (
    <div className="workspace-page">
      <div className="workspace-page-heading">
        <div>
          <p className="workspace-eyebrow">Laboratory records</p>
          <h1>Patients</h1>
          <p className="workspace-page-description">
            Search and manage patient records for this laboratory only.
          </p>
        </div>
        <span className="workspace-count-badge">{patients.length} recent records</span>
      </div>
      <PatientDirectory patients={patients ?? []} canRegister={canRegister === true} />
    </div>
  );
}
