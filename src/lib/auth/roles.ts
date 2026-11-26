const roleDestinations: Record<string, string> = {
  lab_admin: "/lab",
  lab_manager: "/lab",
  receptionist: "/lab",
  technician: "/lab",
  billing_staff: "/lab",
  reporting_doctor: "/doctor",
};

export function getDashboardPath(role: string) {
  return roleDestinations[role] ?? null;
}

export const LAB_DASHBOARD_ROLES = [
  "lab_admin",
  "lab_manager",
  "receptionist",
  "technician",
  "billing_staff",
] as const;

export const STAFF_ROLE_LABELS: Record<string, string> = {
  lab_admin: "Lab Administrator",
  lab_manager: "Lab Manager",
  receptionist: "Receptionist",
  technician: "Lab Technician",
  billing_staff: "Accountant",
  reporting_doctor: "Pathologist",
};
