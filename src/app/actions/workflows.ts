"use server";

import { createHash, randomBytes } from "node:crypto";
import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { fromZonedTime } from "date-fns-tz";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/authorization";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type WorkflowActionState = {
  error: string | null;
  success: string | null;
  link?: string | null;
};

const emptyState: WorkflowActionState = { error: null, success: null };
const idSchema = z.uuid();

function getErrorMessage(error: { code?: string; message: string }) {
  return getDatabaseSetupMessage(error) ?? error.message;
}

async function getMembership() {
  return requireMembership([
    "lab_admin", "lab_manager", "receptionist", "technician", "billing_staff", "reporting_doctor",
  ]);
}

export async function createLabInvoice(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    patientId: idSchema,
    discount: z.coerce.number().finite().min(0).max(100000000),
    discountReason: z.string().trim().max(240),
    initialPayment: z.coerce.number().finite().min(0).max(100000000),
    paymentMethod: z.enum(["cash", "card", "bank_transfer", "mobile_wallet", "other"]),
  }).safeParse({
    patientId: formData.get("patientId"),
    discount: formData.get("discount") || "0",
    discountReason: formData.get("discountReason") || "",
    initialPayment: formData.get("initialPayment") || "0",
    paymentMethod: formData.get("paymentMethod") || "cash",
  });
  const serviceIds = formData.getAll("serviceIds").filter((value): value is string => typeof value === "string");
  if (!parsed.success || serviceIds.length === 0 || serviceIds.some((id) => !idSchema.safeParse(id).success)) {
    return { ...emptyState, error: "Select a patient and at least one valid test." };
  }
  if (new Set(serviceIds).size !== serviceIds.length) {
    return { ...emptyState, error: "A test can only be selected once per invoice." };
  }

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: canBill, error: permissionError } = await supabase.rpc(
    "has_lab_permission",
    { target_lab: membership.labId, target_permission: "billing.manage" },
  );
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!canBill) return { ...emptyState, error: "Your role cannot create invoices." };

  const { data, error } = await supabase.rpc("create_lab_invoice", {
    p_lab_id: membership.labId,
    p_patient_id: parsed.data.patientId,
    p_service_ids: serviceIds,
    p_discount: parsed.data.discount,
    p_discount_reason: parsed.data.discountReason || null,
    p_initial_payment: parsed.data.initialPayment,
    p_payment_method: parsed.data.paymentMethod,
  });
  if (error) {
    console.error("Could not create invoice:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }

  revalidatePath("/lab");
  revalidatePath("/lab/test-billing");
  revalidatePath("/lab/samples");
  revalidatePath("/lab/invoice-history");
  return {
    ...emptyState,
    success: `Invoice ${data?.[0]?.invoice_number ?? ""} created.`,
  };
}

export async function createLabAppointment(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    patientId: idSchema,
    startsAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),
    endsAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),
    reason: z.string().trim().max(240),
  }).safeParse({
    patientId: formData.get("patientId"),
    startsAt: formData.get("startsAt"),
    endsAt: formData.get("endsAt"),
    reason: formData.get("reason") || "",
  });
  if (!parsed.success) return { ...emptyState, error: "Enter a patient and valid appointment times." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const [{ data: allowed, error: permissionError }, { data: settings, error: settingsError }] =
    await Promise.all([
      supabase.rpc("has_lab_permission", {
        target_lab: membership.labId,
        target_permission: "appointments.manage",
      }),
      supabase.from("lab_settings").select("timezone").eq("lab_id", membership.labId).maybeSingle(),
    ]);
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (settingsError) return { ...emptyState, error: getErrorMessage(settingsError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot schedule appointments." };
  const timezone = settings?.timezone ?? "UTC";
  const startsAt = fromZonedTime(parsed.data.startsAt, timezone);
  const endsAt = fromZonedTime(parsed.data.endsAt, timezone);
  if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime())) {
    return { ...emptyState, error: "The selected time is invalid for the laboratory timezone." };
  }

  const { error } = await supabase.rpc("create_lab_appointment", {
    p_lab_id: membership.labId,
    p_patient_id: parsed.data.patientId,
    p_starts_at: startsAt.toISOString(),
    p_ends_at: endsAt.toISOString(),
    p_reason: parsed.data.reason || null,
  });
  if (error) {
    console.error("Could not create appointment:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/appointments");
  return { ...emptyState, success: "Appointment scheduled." };
}

export async function cancelLabAppointment(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    appointmentId: idSchema,
    reason: z.string().trim().min(2).max(240),
  }).safeParse({
    appointmentId: formData.get("appointmentId"),
    reason: formData.get("reason"),
  });
  if (!parsed.success) return { ...emptyState, error: "A cancellation reason is required." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "appointments.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot cancel appointments." };
  const { error } = await supabase.rpc("cancel_lab_appointment", {
    p_lab_id: membership.labId,
    p_appointment_id: parsed.data.appointmentId,
    p_reason: parsed.data.reason,
  });
  if (error) {
    console.error("Could not cancel appointment:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/appointments");
  return { ...emptyState, success: "Appointment cancelled." };
}

export async function saveWorkingHour(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    weekday: z.coerce.number().int().min(0).max(6),
    opensAt: z.string().regex(/^\d{2}:\d{2}$/),
    closesAt: z.string().regex(/^\d{2}:\d{2}$/),
    closed: z.enum(["true", "false"]),
  }).safeParse({
    weekday: formData.get("weekday"),
    opensAt: formData.get("opensAt"),
    closesAt: formData.get("closesAt"),
    closed: formData.get("closed"),
  });
  if (!parsed.success) return { ...emptyState, error: "Enter valid working hours." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot change working hours." };
  const { error } = await supabase.rpc("save_lab_working_hour", {
    p_lab_id: membership.labId,
    p_weekday: parsed.data.weekday,
    p_opens_at: parsed.data.opensAt,
    p_closes_at: parsed.data.closesAt,
    p_closed: parsed.data.closed === "true",
  });
  if (error) {
    console.error("Could not save working hours:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  revalidatePath("/lab/appointments");
  return { ...emptyState, success: "Working hours saved." };
}

export async function createLabResource(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    name: z.string().trim().min(1).max(80),
    resourceType: z.string().trim().min(1).max(60),
  }).safeParse({
    name: formData.get("name"),
    resourceType: formData.get("resourceType"),
  });
  if (!parsed.success) return { ...emptyState, error: "Enter a resource name and type." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot manage resources." };

  const { error } = await supabase.rpc("create_lab_resource", {
    p_lab_id: membership.labId,
    p_name: parsed.data.name,
    p_resource_type: parsed.data.resourceType,
  });
  if (error) {
    console.error("Could not create scheduling resource:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  return { ...emptyState, success: "Resource added." };
}

export async function setLabResourceActive(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    resourceId: idSchema,
    active: z.enum(["true", "false"]),
  }).safeParse({
    resourceId: formData.get("resourceId"),
    active: formData.get("active"),
  });
  if (!parsed.success) return { ...emptyState, error: "Select a valid resource status." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot manage resources." };

  const { error } = await supabase.rpc("set_lab_resource_active", {
    p_lab_id: membership.labId,
    p_resource_id: parsed.data.resourceId,
    p_active: parsed.data.active === "true",
  });
  if (error) {
    console.error("Could not update scheduling resource:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  return { ...emptyState, success: "Resource status updated." };
}

export async function createLabResourceBooking(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    resourceId: idSchema,
    startsAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),
    endsAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),
  }).safeParse({
    resourceId: formData.get("resourceId"),
    startsAt: formData.get("startsAt"),
    endsAt: formData.get("endsAt"),
  });
  if (!parsed.success) return { ...emptyState, error: "Enter a resource and valid booking times." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot manage resource bookings." };

  const { data: settings, error: settingsError } = await supabase.from("lab_settings")
    .select("timezone").eq("lab_id", membership.labId).maybeSingle();
  if (settingsError) return { ...emptyState, error: getErrorMessage(settingsError) };
  const timezone = settings?.timezone ?? "UTC";
  const startsAt = fromZonedTime(parsed.data.startsAt, timezone);
  const endsAt = fromZonedTime(parsed.data.endsAt, timezone);
  if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime()) || endsAt <= startsAt) {
    return { ...emptyState, error: "The selected resource booking time is invalid." };
  }

  const { error } = await supabase.rpc("create_lab_resource_booking", {
    p_lab_id: membership.labId,
    p_resource_id: parsed.data.resourceId,
    p_starts_at: startsAt.toISOString(),
    p_ends_at: endsAt.toISOString(),
    p_appointment_id: null,
  });
  if (error) {
    console.error("Could not book scheduling resource:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  return { ...emptyState, success: "Resource booked." };
}

export async function cancelLabResourceBooking(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({ bookingId: idSchema }).safeParse({
    bookingId: formData.get("bookingId"),
  });
  if (!parsed.success) return { ...emptyState, error: "Select a valid resource booking." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot cancel resource bookings." };

  const { error } = await supabase.rpc("cancel_lab_resource_booking", {
    p_lab_id: membership.labId,
    p_booking_id: parsed.data.bookingId,
  });
  if (error) {
    console.error("Could not cancel resource booking:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  return { ...emptyState, success: "Resource booking cancelled." };
}

export async function createLabStaffShift(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    staffId: idSchema,
    startsAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),
    endsAt: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/),
    status: z.enum(["scheduled", "leave"]),
  }).safeParse({
    staffId: formData.get("staffId"),
    startsAt: formData.get("startsAt"),
    endsAt: formData.get("endsAt"),
    status: formData.get("status"),
  });
  if (!parsed.success) return { ...emptyState, error: "Enter a staff member and valid shift times." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot manage staff shifts." };

  const { data: settings, error: settingsError } = await supabase.from("lab_settings")
    .select("timezone").eq("lab_id", membership.labId).maybeSingle();
  if (settingsError) return { ...emptyState, error: getErrorMessage(settingsError) };
  const timezone = settings?.timezone ?? "UTC";
  const startsAt = fromZonedTime(parsed.data.startsAt, timezone);
  const endsAt = fromZonedTime(parsed.data.endsAt, timezone);
  if (!Number.isFinite(startsAt.getTime()) || !Number.isFinite(endsAt.getTime()) || endsAt <= startsAt) {
    return { ...emptyState, error: "The selected staff shift time is invalid." };
  }

  const { error } = await supabase.rpc("create_lab_staff_shift", {
    p_lab_id: membership.labId,
    p_staff_id: parsed.data.staffId,
    p_starts_at: startsAt.toISOString(),
    p_ends_at: endsAt.toISOString(),
    p_status: parsed.data.status,
  });
  if (error) {
    console.error("Could not create staff shift:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  return { ...emptyState, success: "Staff shift added." };
}

export async function cancelLabStaffShift(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({ shiftId: idSchema }).safeParse({
    shiftId: formData.get("shiftId"),
  });
  if (!parsed.success) return { ...emptyState, error: "Select a valid staff shift." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "scheduling.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot cancel staff shifts." };

  const { error } = await supabase.rpc("cancel_lab_staff_shift", {
    p_lab_id: membership.labId,
    p_shift_id: parsed.data.shiftId,
  });
  if (error) {
    console.error("Could not cancel staff shift:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/scheduling");
  return { ...emptyState, success: "Staff shift cancelled." };
}

export async function recordInvoicePayment(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    invoiceId: idSchema,
    amount: z.coerce.number().finite().positive().max(100000000),
    method: z.enum(["cash", "card", "bank_transfer", "mobile_wallet", "other"]),
    reference: z.string().trim().max(120),
  }).safeParse({
    invoiceId: formData.get("invoiceId"),
    amount: formData.get("amount"),
    method: formData.get("method"),
    reference: formData.get("reference") || "",
  });
  if (!parsed.success) return { ...emptyState, error: "Enter a valid payment amount and method." };

  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: canPay, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "billing.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!canPay) return { ...emptyState, error: "Your role cannot record invoice payments." };

  const { data: receiptNumber, error } = await supabase.rpc("record_invoice_payment", {
    p_lab_id: membership.labId,
    p_invoice_id: parsed.data.invoiceId,
    p_amount: parsed.data.amount,
    p_method: parsed.data.method,
    p_reference: parsed.data.reference || null,
  });
  if (error) {
    console.error("Could not record invoice payment:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }

  revalidatePath("/lab/invoice-history");
  revalidatePath("/lab/test-billing");
  return { ...emptyState, success: `Payment recorded. Receipt ${receiptNumber}.` };
}

export async function transitionSample(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    sampleId: idSchema,
    status: z.enum(["collected", "rejected", "recollected"]),
    reason: z.string().trim().max(240),
  }).safeParse({
    sampleId: formData.get("sampleId"),
    status: formData.get("status"),
    reason: formData.get("reason") || "",
  });
  if (!parsed.success || (parsed.data.status === "rejected" && parsed.data.reason.length < 2)) {
    return { ...emptyState, error: "Provide a valid sample status and rejection reason if needed." };
  }
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "orders.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot update sample status." };

  const { error } = await supabase.rpc("update_sample_status", {
    p_lab_id: membership.labId,
    p_sample_id: parsed.data.sampleId,
    p_status: parsed.data.status,
    p_rejection_reason: parsed.data.reason || null,
  });
  if (error) {
    console.error("Could not update sample status:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/samples");
  revalidatePath("/lab/reports");
  return { ...emptyState, success: "Sample status updated." };
}

export async function transitionOrder(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    orderItemId: idSchema,
    status: z.enum(["in_progress", "additional_information_required", "cancelled"]),
  }).safeParse({
    orderItemId: formData.get("orderItemId"),
    status: formData.get("status"),
  });
  if (!parsed.success) return { ...emptyState, error: "Select a valid order status." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "orders.manage",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot update order status." };

  const { error } = await supabase.rpc("update_order_item_status", {
    p_lab_id: membership.labId,
    p_order_item_id: parsed.data.orderItemId,
    p_status: parsed.data.status,
  });
  if (error) {
    console.error("Could not update order status:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/samples");
  revalidatePath("/lab/reports");
  return { ...emptyState, success: "Order status updated." };
}

export async function assignOrder(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    orderItemId: idSchema,
    technicianId: z.union([z.literal(""), idSchema]),
    doctorId: z.union([z.literal(""), idSchema]),
  }).safeParse({
    orderItemId: formData.get("orderItemId"),
    technicianId: formData.get("technicianId") || "",
    doctorId: formData.get("doctorId") || "",
  });
  if (!parsed.success) return { ...emptyState, error: "Select valid staff assignments." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "orders.assign",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot assign this order." };

  const { error } = await supabase.rpc("assign_order_item", {
    p_lab_id: membership.labId,
    p_order_item_id: parsed.data.orderItemId,
    p_technician_id: parsed.data.technicianId || null,
    p_doctor_id: parsed.data.doctorId || null,
  });
  if (error) {
    console.error("Could not assign order:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/samples");
  revalidatePath("/lab/reports");
  return { ...emptyState, success: "Order assignments saved." };
}

export async function saveReportResult(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    orderItemId: idSchema,
    resultText: z.string().trim().min(1).max(10000),
  }).safeParse({
    orderItemId: formData.get("orderItemId"),
    resultText: formData.get("resultText"),
  });
  if (!parsed.success) return { ...emptyState, error: "Enter a result of up to 10,000 characters." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "reports.upload",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot enter results." };

  const { error } = await supabase.rpc("save_report_result", {
    p_lab_id: membership.labId,
    p_order_item_id: parsed.data.orderItemId,
    p_result_text: parsed.data.resultText,
  });
  if (error) {
    console.error("Could not save report result:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/reports");
  revalidatePath("/lab/samples");
  return { ...emptyState, success: "Result sent for review." };
}

export async function reviewReportResult(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const parsed = z.object({
    reportResultId: idSchema,
    decision: z.enum(["approved", "changes_required"]),
  }).safeParse({
    reportResultId: formData.get("reportResultId"),
    decision: formData.get("decision"),
  });
  if (!parsed.success) return { ...emptyState, error: "Select a valid review decision." };
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "reports.review",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot review reports." };

  const { error } = await supabase.rpc("review_report_result", {
    p_lab_id: membership.labId,
    p_report_result_id: parsed.data.reportResultId,
    p_decision: parsed.data.decision,
  });
  if (error) {
    console.error("Could not review report:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }
  revalidatePath("/lab/reports");
  return { ...emptyState, success: "Review decision saved." };
}

export async function publishReportResult(
  _previousState: WorkflowActionState,
  formData: FormData,
): Promise<WorkflowActionState> {
  const reportResultId = idSchema.safeParse(formData.get("reportResultId"));
  if (!reportResultId.success) return { ...emptyState, error: "Select a valid report." };
  const originHeader = (await headers()).get("origin");
  const configuredOrigin = process.env.NEXT_PUBLIC_SITE_URL;
  const origin = originHeader ?? configuredOrigin;
  if (!origin) return { ...emptyState, error: "The public site URL is not configured." };

  let baseUrl: URL;
  try {
    baseUrl = new URL(origin);
  } catch {
    return { ...emptyState, error: "The public site URL is invalid." };
  }
  if (baseUrl.protocol !== "https:" && baseUrl.hostname !== "localhost") {
    return { ...emptyState, error: "Report links require HTTPS outside localhost." };
  }

  const token = randomBytes(32).toString("hex");
  const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
  const membership = await getMembership();
  const supabase = await createSupabaseServerClient();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "reports.publish",
  });
  if (permissionError) return { ...emptyState, error: getErrorMessage(permissionError) };
  if (!allowed) return { ...emptyState, error: "Your role cannot publish reports." };

  const { error } = await supabase.rpc("publish_report_result", {
    p_lab_id: membership.labId,
    p_report_result_id: reportResultId.data,
    p_token_hash: tokenHash,
  });
  if (error) {
    console.error("Could not publish report:", error);
    return { ...emptyState, error: getErrorMessage(error) };
  }

  revalidatePath("/lab/reports");
  return {
    ...emptyState,
    success: "Report published. Share this private link only with the patient.",
    link: new URL(`/r/${token}`, baseUrl).toString(),
  };
}
