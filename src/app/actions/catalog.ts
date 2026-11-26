"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/authorization";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type CatalogActionState = {
  error: string | null;
  success: string | null;
};

const initialError = (error: { code?: string; message: string }) =>
  getDatabaseSetupMessage(error) ?? "Could not save this item. Check the details and try again.";

const categorySchema = z.object({
  name: z.string().trim().min(1).max(80),
  sortOrder: z.coerce.number().int().min(0).max(10000),
});

const testSchema = z.object({
  code: z.string().trim().min(1).max(32).regex(/^[A-Za-z0-9_-]+$/),
  name: z.string().trim().min(1).max(120),
  categoryId: z.union([z.literal(""), z.uuid()]),
  description: z.string().trim().max(500),
  serviceType: z.enum(["laboratory", "xray", "ultrasound", "ecg", "other"]),
  price: z.coerce.number().finite().min(0).max(100000000),
  durationMinutes: z.coerce.number().int().min(1).max(10080),
  turnaroundMinutes: z.union([z.literal(""), z.coerce.number().int().min(1).max(10080)]),
  preparationInstructions: z.string().trim().max(500),
  fastingRequired: z.enum(["true", "false"]),
  method: z.string().trim().max(120),
  normalRange: z.string().trim().max(240),
  patientVisible: z.enum(["true", "false"]),
});

const doctorSchema = z.object({
  name: z.string().trim().min(2).max(120),
  clinic: z.string().trim().max(120),
  phone: z.string().trim().max(32),
  email: z.union([z.literal(""), z.email()]),
  specialty: z.string().trim().max(120),
  commissionPercent: z.coerce.number().finite().min(0).max(100),
  address: z.string().trim().max(240),
});

const reagentSchema = z.object({
  name: z.string().trim().min(1).max(120),
  reorderLevel: z.coerce.number().finite().min(0).max(100000000),
  expiryDate: z.union([z.literal(""), z.iso.date()]),
  supplier: z.string().trim().max(120),
  batchNumber: z.string().trim().max(80),
  unitPrice: z.coerce.number().finite().min(0).max(100000000),
  storage: z.string().trim().max(120),
});

const expenseSchema = z.object({
  name: z.string().trim().min(1).max(80),
  note: z.string().trim().min(2).max(500),
  expenseDate: z.union([z.literal(""), z.iso.date()]),
  amount: z.coerce.number().finite().positive().max(100000000),
  paidVia: z.enum(["cash", "bank_transfer", "card", "other"]),
  receiptNumber: z.string().trim().max(80),
});

export async function saveLabCatalogItem(
  _previousState: CatalogActionState,
  formData: FormData,
): Promise<CatalogActionState> {
  const kind = formData.get("kind");
  if (
    kind !== "category" && kind !== "test" && kind !== "doctor" &&
    kind !== "reagent" && kind !== "expense"
  ) {
    return { error: "Unsupported catalog item.", success: null };
  }

  const rawValues = {
    name: formData.get("name"),
    sortOrder: formData.get("sortOrder") || "0",
    code: formData.get("code"),
    categoryId: formData.get("categoryId") || "",
    description: formData.get("description") || "",
    serviceType: formData.get("serviceType") || "laboratory",
    price: formData.get("price") || "0",
    durationMinutes: formData.get("durationMinutes") || "15",
    turnaroundMinutes: formData.get("turnaroundMinutes") || "",
    preparationInstructions: formData.get("preparationInstructions") || "",
    fastingRequired: formData.get("fastingRequired") || "false",
    method: formData.get("method") || "",
    normalRange: formData.get("normalRange") || "",
    patientVisible: formData.get("patientVisible") || "true",
    clinic: formData.get("clinic") || "",
    phone: formData.get("phone") || "",
    email: formData.get("email") || "",
    specialty: formData.get("specialty") || "",
    commissionPercent: formData.get("commissionPercent") || "0",
    address: formData.get("address") || "",
    reorderLevel: formData.get("reorderLevel") || "0",
    expiryDate: formData.get("expiryDate") || "",
    supplier: formData.get("supplier") || "",
    batchNumber: formData.get("batchNumber") || "",
    unitPrice: formData.get("unitPrice") || "0",
    storage: formData.get("storage") || "",
    note: formData.get("note") || "",
    expenseDate: formData.get("expenseDate") || "",
    amount: formData.get("amount"),
    paidVia: formData.get("paidVia") || "cash",
    receiptNumber: formData.get("receiptNumber") || "",
  };
  let values: Record<string, string | number | boolean | null>;

  if (kind === "category") {
    const parsed = categorySchema.safeParse(rawValues);
    if (!parsed.success) {
      return {
        error: parsed.error.issues[0]?.message ?? "Check the department details.",
        success: null,
      };
    }
    values = { name: parsed.data.name, sort_order: parsed.data.sortOrder };
  } else if (kind === "test") {
    const parsed = testSchema.safeParse(rawValues);
    if (!parsed.success) {
      return {
        error: parsed.error.issues[0]?.message ?? "Check the test details.",
        success: null,
      };
    }
    values = {
      code: parsed.data.code.toUpperCase(),
      name: parsed.data.name,
      category_id: parsed.data.categoryId || null,
      description: parsed.data.description,
      service_type: parsed.data.serviceType,
      price: parsed.data.price,
      duration_minutes: parsed.data.durationMinutes,
      turnaround_minutes: parsed.data.turnaroundMinutes || null,
      preparation_instructions: parsed.data.preparationInstructions,
      fasting_required: parsed.data.fastingRequired === "true",
      method: parsed.data.method,
      normal_range: parsed.data.normalRange,
      patient_visible: parsed.data.patientVisible === "true",
    };
  } else if (kind === "doctor") {
    const parsed = doctorSchema.safeParse(rawValues);
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? "Check the doctor details.", success: null };
    }
    values = {
      name: parsed.data.name,
      clinic: parsed.data.clinic,
      phone: parsed.data.phone,
      email: parsed.data.email || null,
      specialty: parsed.data.specialty,
      commission_percent: parsed.data.commissionPercent,
      address: parsed.data.address,
    };
  } else if (kind === "reagent") {
    const parsed = reagentSchema.safeParse(rawValues);
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? "Check the reagent details.", success: null };
    }
    values = {
      name: parsed.data.name,
      reorder_level: parsed.data.reorderLevel,
      expiry_date: parsed.data.expiryDate || null,
      supplier: parsed.data.supplier,
      batch_number: parsed.data.batchNumber,
      unit_price: parsed.data.unitPrice,
      storage: parsed.data.storage,
    };
  } else {
    const parsed = expenseSchema.safeParse(rawValues);
    if (!parsed.success) {
      return { error: parsed.error.issues[0]?.message ?? "Check the expense details.", success: null };
    }
    values = {
      name: parsed.data.name,
      note: parsed.data.note,
      expense_date: parsed.data.expenseDate || null,
      amount: parsed.data.amount,
      paid_via: parsed.data.paidVia,
      receipt_number: parsed.data.receiptNumber,
    };
  }

  const permissionByKind = {
    category: "services.manage",
    test: "services.manage",
    doctor: "doctors.manage",
    reagent: "inventory.manage",
    expense: "expenses.manage",
  } as const;
  const membership = await requireMembership([
    "lab_admin", "lab_manager", "receptionist", "technician", "billing_staff", "reporting_doctor",
  ]);
  const supabase = await createSupabaseServerClient();
  const { data: canManage, error: permissionError } = await supabase.rpc(
    "has_lab_permission",
    {
      target_lab: membership.labId,
      target_permission: permissionByKind[kind],
    },
  );

  if (permissionError) {
    return { error: initialError(permissionError), success: null };
  }
  if (!canManage) {
    return { error: "Your laboratory role cannot manage this section.", success: null };
  }

  const itemId = typeof formData.get("id") === "string" && formData.get("id")
    ? String(formData.get("id"))
    : null;
  const { error } = kind === "reagent"
    ? await supabase.rpc("save_lab_reagent", {
        p_lab_id: membership.labId,
        p_id: itemId,
        p_values: values,
      })
    : await supabase.rpc("save_lab_catalog_item", {
        p_lab_id: membership.labId,
        p_kind: kind,
        p_id: itemId,
        p_values: values,
      });

  if (error) {
    console.error("Could not save catalog item:", error);
    return { error: initialError(error), success: null };
  }

  const pathByKind = {
    category: "/lab/tests",
    test: "/lab/tests",
    doctor: "/lab/referring-doctors",
    reagent: "/lab/reagent-stock",
    expense: "/lab/expenses",
  } as const;
  revalidatePath(pathByKind[kind]);
  revalidatePath("/lab/test-billing");
  return {
    error: null,
    success: kind === "category" ? "Department saved." : kind === "test" ? "Test saved." : "Record saved.",
  };
}

export async function recordReagentMovement(
  _previousState: CatalogActionState,
  formData: FormData,
): Promise<CatalogActionState> {
  const parsed = z.object({
    reagentId: z.uuid(),
    movementType: z.enum(["received", "used", "adjustment_increase", "adjustment_decrease"]),
    quantity: z.coerce.number().finite().positive().max(100000000)
      .refine((value) => Number.isInteger(value * 100), "Quantity must have at most two decimal places."),
    note: z.string().trim().min(2).max(240),
    reference: z.string().trim().max(80),
  }).safeParse({
    reagentId: formData.get("reagentId"),
    movementType: formData.get("movementType"),
    quantity: formData.get("quantity"),
    note: formData.get("note"),
    reference: formData.get("reference") || "",
  });
  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Check the stock movement details.",
      success: null,
    };
  }

  const membership = await requireMembership([
    "lab_admin", "lab_manager", "receptionist", "technician", "billing_staff", "reporting_doctor",
  ]);
  const supabase = await createSupabaseServerClient();
  const { data: canManage, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "inventory.manage",
  });
  if (permissionError) return { error: initialError(permissionError), success: null };
  if (!canManage) return { error: "Your laboratory role cannot change reagent stock.", success: null };

  const { error } = await supabase.rpc("record_lab_reagent_movement", {
    p_lab_id: membership.labId,
    p_reagent_id: parsed.data.reagentId,
    p_movement_type: parsed.data.movementType,
    p_quantity: parsed.data.quantity,
    p_note: parsed.data.note,
    p_reference: parsed.data.reference || null,
  });
  if (error) {
    console.error("Could not record reagent stock movement:", error);
    return { error: initialError(error), success: null };
  }
  revalidatePath("/lab/reagent-stock");
  return { error: null, success: "Stock movement recorded." };
}
