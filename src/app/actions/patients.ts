"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/authorization";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type RegisterPatientState = {
  error: string | null;
  success: string | null;
};

const registerPatientSchema = z.object({
  fullName: z.string().trim().min(2).max(120),
  phone: z.string().trim().min(5).max(32),
  dateOfBirth: z.union([z.literal(""), z.iso.date()]),
  gender: z.enum(["", "female", "male", "other", "prefer_not_to_say"]),
  emergencyContact: z.string().trim().max(120),
});

export async function registerPatient(
  _previousState: RegisterPatientState,
  formData: FormData,
): Promise<RegisterPatientState> {
  const membership = await requireMembership(["lab_admin", "receptionist"]);
  const parsed = registerPatientSchema.safeParse({
    fullName: formData.get("fullName"),
    phone: formData.get("phone"),
    dateOfBirth: formData.get("dateOfBirth"),
    gender: formData.get("gender"),
    emergencyContact: formData.get("emergencyContact"),
  });

  if (!parsed.success) {
    return {
      error: parsed.error.issues[0]?.message ?? "Check the patient details and try again.",
      success: null,
    };
  }

  const supabase = await createSupabaseServerClient();
  const { data: canRegister, error: permissionError } = await supabase.rpc(
    "has_lab_permission",
    {
      target_lab: membership.labId,
      target_permission: "patients.write",
    },
  );

  if (permissionError) {
    throw new Error(`Could not verify patient registration permission: ${permissionError.message}`);
  }

  if (!canRegister) {
    return {
      error: "Your laboratory role does not allow patient registration.",
      success: null,
    };
  }

  const { error } = await supabase.rpc("register_patient", {
    p_lab_id: membership.labId,
    p_full_name: parsed.data.fullName,
    p_phone: parsed.data.phone,
    p_date_of_birth: parsed.data.dateOfBirth || null,
    p_gender: parsed.data.gender || null,
    p_emergency_contact: parsed.data.emergencyContact || null,
  });

  if (error) {
    if (error.code === "22023") {
      return { error: error.message, success: null };
    }

    if (error.code === "42501") {
      return {
        error: "Your laboratory role does not allow patient registration.",
        success: null,
      };
    }

    console.error("Could not register patient:", error);
    return {
      error: "Patient registration failed. Please try again or contact your administrator.",
      success: null,
    };
  }

  revalidatePath("/lab");
  revalidatePath("/lab/patients");
  return { error: null, success: "Patient registered." };
}
