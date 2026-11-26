"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type CreateLabState = {
  error: string | null;
  success: string | null;
};

export async function createLab(
  _previousState: CreateLabState,
  formData: FormData,
): Promise<CreateLabState> {
  const supabase = await createSupabaseServerClient();
  const { data: claims, error: claimsError } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;

  if (claimsError || typeof userId !== "string") {
    redirect("/login");
  }

  const { data: isDeveloper, error: roleError } = await supabase.rpc(
    "is_platform_developer",
  );

  if (roleError) {
    throw new Error(`Could not verify platform developer access: ${roleError.message}`);
  }

  if (!isDeveloper) {
    redirect("/login");
  }

  const nameValue = formData.get("name");
  const slugValue = formData.get("slug");
  const currencyValue = formData.get("currency");
  const timezoneValue = formData.get("timezone");

  const name = typeof nameValue === "string" ? nameValue.trim() : "";
  const slug = typeof slugValue === "string" ? slugValue.trim() : "";
  const currency =
    typeof currencyValue === "string" ? currencyValue.trim().toUpperCase() : "";
  const timezone = typeof timezoneValue === "string" ? timezoneValue.trim() : "";

  if (name.length < 2 || name.length > 120) {
    return { error: "Lab name must be between 2 and 120 characters.", success: null };
  }

  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
    return {
      error: "Use a lowercase slug with letters, numbers, and hyphens only.",
      success: null,
    };
  }

  if (!/^[A-Z]{3}$/.test(currency)) {
    return { error: "Currency must be a three-letter code, such as PKR or USD.", success: null };
  }

  if (timezone.length === 0) {
    return { error: "Enter a valid timezone, such as Asia/Karachi.", success: null };
  }

  const { error } = await supabase.rpc("create_lab", {
    p_name: name,
    p_slug: slug,
    p_currency: currency,
    p_timezone: timezone,
  });

  if (error) {
    if (error.code === "23505") {
      return { error: "That lab slug is already in use.", success: null };
    }

    if (error.code === "22023") {
      return { error: error.message, success: null };
    }

    console.error("Could not create lab:", error);
    return { error: "Lab creation failed. Check the Supabase logs and try again.", success: null };
  }

  revalidatePath("/platform");
  return { error: null, success: "Laboratory created." };
}
