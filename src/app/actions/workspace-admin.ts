"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/authorization";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type AdminActionState = {
  error: string | null;
  success: string | null;
};

const emptyState: AdminActionState = { error: null, success: null };
const id = z.uuid();

function message(error: { code?: string; message: string }) {
  return getDatabaseSetupMessage(error) ?? error.message;
}

const workspaceRoles = [
  "lab_admin", "lab_manager", "receptionist", "technician", "billing_staff", "reporting_doctor",
] as const;

export async function archiveLabItem(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    kind: z.enum(["patient", "test", "category", "doctor", "reagent", "expense"]),
    id,
  }).safeParse({ kind: formData.get("kind"), id: formData.get("id") });
  if (!parsed.success) return { ...emptyState, error: "Select a valid record to archive." };
  const membership = await requireMembership(workspaceRoles);
  const supabase = await createSupabaseServerClient();
  const permissionByKind = {
    patient: "patients.write",
    test: "services.manage",
    category: "services.manage",
    doctor: "doctors.manage",
    reagent: "inventory.manage",
    expense: "expenses.manage",
  } as const;
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: permissionByKind[parsed.data.kind],
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot archive this record." };
  const { error } = await supabase.rpc("archive_lab_item", {
    p_lab_id: membership.labId,
    p_kind: parsed.data.kind,
    p_id: parsed.data.id,
  });
  if (error) {
    console.error("Could not archive record:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/trash-bin");
  revalidatePath("/lab/patients");
  revalidatePath("/lab/tests");
  revalidatePath("/lab/referring-doctors");
  revalidatePath("/lab/reagent-stock");
  revalidatePath("/lab/expenses");
  return { ...emptyState, success: "Record moved to the trash bin." };
}

export async function restoreLabItem(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    kind: z.enum(["patient", "test", "category", "doctor", "reagent", "expense"]),
    id,
  }).safeParse({ kind: formData.get("kind"), id: formData.get("id") });
  if (!parsed.success) return { ...emptyState, error: "Select a valid archived record." };
  const membership = await requireMembership(["lab_admin"]);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_page_access", {
    target_lab: membership.labId,
    target_page: "trash_bin",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot restore archived records." };
  const { error } = await supabase.rpc("restore_lab_item", {
    p_lab_id: membership.labId,
    p_kind: parsed.data.kind,
    p_id: parsed.data.id,
  });
  if (error) {
    console.error("Could not restore record:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/trash-bin");
  revalidatePath("/lab/patients");
  revalidatePath("/lab/tests");
  revalidatePath("/lab/referring-doctors");
  revalidatePath("/lab/reagent-stock");
  revalidatePath("/lab/expenses");
  return { ...emptyState, success: "Record restored." };
}

export async function saveLabSettings(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    name: z.string().trim().min(2).max(120),
    city: z.string().trim().max(80),
    phone: z.string().trim().max(32),
    email: z.union([z.literal(""), z.email()]),
    address: z.string().trim().max(240),
    currency: z.string().regex(/^[A-Z]{3}$/),
    timezone: z.string().trim().min(1).max(80),
    receiptFormat: z.enum(["thermal_80mm", "a4_lab_memo"]),
    receiptFooter: z.string().trim().max(500),
  }).safeParse({
    name: formData.get("name"),
    city: formData.get("city") || "",
    phone: formData.get("phone") || "",
    email: formData.get("email") || "",
    address: formData.get("address") || "",
    currency: formData.get("currency"),
    timezone: formData.get("timezone"),
    receiptFormat: formData.get("receiptFormat"),
    receiptFooter: formData.get("receiptFooter") || "",
  });
  if (!parsed.success) return { ...emptyState, error: parsed.error.issues[0]?.message ?? "Check settings." };
  const membership = await requireMembership(["lab_admin"]);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "settings.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot change laboratory settings." };
  const { error } = await supabase.rpc("save_lab_settings", {
    p_lab_id: membership.labId,
    p_name: parsed.data.name,
    p_city: parsed.data.city,
    p_phone: parsed.data.phone,
    p_email: parsed.data.email || null,
    p_address: parsed.data.address,
    p_currency: parsed.data.currency,
    p_timezone: parsed.data.timezone,
    p_receipt_format: parsed.data.receiptFormat,
    p_receipt_footer: parsed.data.receiptFooter,
  });
  if (error) {
    console.error("Could not save laboratory settings:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/settings");
  revalidatePath("/lab");
  return { ...emptyState, success: "Laboratory settings saved." };
}

export async function saveRetentionPolicy(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    retentionDays: z.coerce.number().int().min(365).max(36500),
    legalHoldEnabled: z.enum(["true", "false"]),
  }).safeParse({
    retentionDays: formData.get("retentionDays"),
    legalHoldEnabled: formData.get("legalHoldEnabled"),
  });
  if (!parsed.success) return { ...emptyState, error: "Choose a retention period between 365 and 36500 days." };

  const membership = await requireMembership(workspaceRoles);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "settings.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot change retention settings." };

  const { error } = await supabase.rpc("save_lab_retention_policy", {
    p_lab_id: membership.labId,
    p_retention_days: parsed.data.retentionDays,
    p_legal_hold_enabled: parsed.data.legalHoldEnabled === "true",
  });
  if (error) {
    console.error("Could not save retention policy:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/settings");
  return { ...emptyState, success: "Retention policy saved. Clinical records are not automatically deleted." };
}

export async function updateStaffAccess(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    userId: id,
    role: z.enum(workspaceRoles),
    pageKeys: z.array(z.string()).min(1).max(20),
  }).safeParse({
    userId: formData.get("userId"),
    role: formData.get("role"),
    pageKeys: formData.getAll("pageKeys"),
  });
  if (!parsed.success) return { ...emptyState, error: "Select a role and at least one page." };
  const membership = await requireMembership(["lab_admin"]);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "roles.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot manage staff access." };
  const { error } = await supabase.rpc("set_staff_access", {
    p_lab_id: membership.labId,
    p_user_id: parsed.data.userId,
    p_role: parsed.data.role,
    p_page_keys: parsed.data.pageKeys,
  });
  if (error) {
    console.error("Could not update staff access:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/manage-users");
  return { ...emptyState, success: "Staff role and page access updated." };
}

export async function setStaffActive(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    userId: id,
    active: z.enum(["true", "false"]),
  }).safeParse({ userId: formData.get("userId"), active: formData.get("active") });
  if (!parsed.success) return { ...emptyState, error: "Select a valid staff account." };
  const membership = await requireMembership(["lab_admin"]);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "staff.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot manage staff." };
  const { error } = await supabase.rpc("set_staff_active", {
    p_lab_id: membership.labId,
    p_user_id: parsed.data.userId,
    p_active: parsed.data.active === "true",
  });
  if (error) {
    console.error("Could not update staff status:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/manage-users");
  return { ...emptyState, success: parsed.data.active === "true" ? "Staff account activated." : "Staff account deactivated." };
}

export async function inviteLabStaff(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    email: z.email(),
    fullName: z.string().trim().min(2).max(120),
    phone: z.string().trim().max(32),
    role: z.enum(workspaceRoles),
    pageKeys: z.array(z.string()).min(1).max(20),
  }).safeParse({
    email: formData.get("email"),
    fullName: formData.get("fullName"),
    phone: formData.get("phone") || "",
    role: formData.get("role"),
    pageKeys: formData.getAll("pageKeys"),
  });
  if (!parsed.success) return { ...emptyState, error: parsed.error.issues[0]?.message ?? "Check invitation details." };
  const membership = await requireMembership(["lab_admin"]);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "staff.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot invite staff." };

  const { error } = await supabase.functions.invoke("invite-lab-staff", {
    body: {
      labId: membership.labId,
      email: parsed.data.email,
      fullName: parsed.data.fullName,
      phone: parsed.data.phone || null,
      role: parsed.data.role,
      pageKeys: parsed.data.pageKeys,
    },
  });
  if (error) {
    console.error("Could not invite staff member:", error);
    return {
      ...emptyState,
      error: error.message.includes("not found")
        ? "The staff invitation Edge Function is not deployed."
        : "Invitation failed. Confirm the Edge Function and Auth email settings, then try again.",
    };
  }
  revalidatePath("/lab/manage-users");
  return { ...emptyState, success: "Invitation email sent." };
}

export async function createPrintRequest(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const invoiceId = id.safeParse(formData.get("invoiceId"));
  if (!invoiceId.success) return { ...emptyState, error: "Select a valid invoice." };
  const membership = await requireMembership(workspaceRoles);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "print_requests.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot request invoice printing." };
  const { error } = await supabase.rpc("create_print_request", {
    p_lab_id: membership.labId,
    p_invoice_id: invoiceId.data,
  });
  if (error) {
    console.error("Could not create print request:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/my-print-requests");
  revalidatePath("/lab/print-requests");
  return { ...emptyState, success: "Print request submitted." };
}

export async function reviewPrintRequest(
  _previousState: AdminActionState,
  formData: FormData,
): Promise<AdminActionState> {
  const parsed = z.object({
    requestId: id,
    decision: z.enum(["approved", "rejected", "completed"]),
    reason: z.string().trim().max(240),
  }).safeParse({
    requestId: formData.get("requestId"),
    decision: formData.get("decision"),
    reason: formData.get("reason") || "",
  });
  if (!parsed.success) return { ...emptyState, error: "Select a valid print decision." };
  const membership = await requireMembership(["lab_admin"]);
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "print_requests.manage",
  });
  if (permissionError) return { ...emptyState, error: message(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot review print requests." };
  const { error } = await supabase.rpc("review_print_request", {
    p_lab_id: membership.labId,
    p_request_id: parsed.data.requestId,
    p_decision: parsed.data.decision,
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    console.error("Could not review print request:", error);
    return { ...emptyState, error: message(error) };
  }
  revalidatePath("/lab/print-requests");
  revalidatePath("/lab/my-print-requests");
  return { ...emptyState, success: "Print request updated." };
}
