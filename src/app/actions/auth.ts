"use server";

import type { SupabaseClient } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { getDashboardPath } from "@/lib/auth/roles";
import { getSupabaseEnvironment } from "@/lib/supabase/env";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type SignInState = {
  error: string | null;
};

async function rejectSignIn(
  supabase: SupabaseClient,
  message: string,
): Promise<SignInState> {
  const { error } = await supabase.auth.signOut();

  if (error) {
    return {
      error: `${message} We could not clear the session; close this browser session and contact your administrator.`,
    };
  }

  return { error: message };
}

export async function signIn(
  _previousState: SignInState,
  formData: FormData,
): Promise<SignInState> {
  if (!getSupabaseEnvironment()) {
    return {
      error:
        "Supabase is not configured. Add the project URL and publishable or anon key to the root .env.local file, then restart the dev server.",
    };
  }

  const emailValue = formData.get("email");
  const passwordValue = formData.get("password");
  const email = typeof emailValue === "string" ? emailValue.trim() : "";
  const password = typeof passwordValue === "string" ? passwordValue : "";

  if (!email.includes("@") || password.length === 0) {
    return { error: "Enter a valid email address and password." };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error || !data.user) {
    return { error: "Sign-in failed. Check your email, password, and account status." };
  }

  const { data: isPlatformDeveloper, error: developerError } = await supabase.rpc(
    "is_platform_developer",
  );

  if (developerError) {
    return rejectSignIn(
      supabase,
      "We could not verify your platform access. Please try again.",
    );
  }

  if (isPlatformDeveloper) {
    redirect("/platform");
  }

  const { data: memberships, error: membershipError } = await supabase
    .from("memberships")
    .select("lab_id, role")
    .eq("user_id", data.user.id)
    .eq("active", true)
    .limit(2);

  if (membershipError) {
    return rejectSignIn(supabase, "We could not verify your laboratory access. Please try again.");
  }

  if (memberships.length === 0) {
    return rejectSignIn(
      supabase,
      "Your account has no active laboratory membership. Contact your administrator.",
    );
  }

  if (memberships.length > 1) {
    return rejectSignIn(
      supabase,
      "Your account has more than one active laboratory. Multi-lab sign-in is not set up yet; contact your administrator.",
    );
  }

  const dashboardPath = getDashboardPath(memberships[0].role);

  if (!dashboardPath) {
    return rejectSignIn(
      supabase,
      "Your account role is not configured for this application. Contact your administrator.",
    );
  }

  redirect(dashboardPath);
}

export async function patientSignIn(
  _previousState: SignInState,
  formData: FormData,
): Promise<SignInState> {
  if (!getSupabaseEnvironment()) {
    return {
      error:
        "Supabase is not configured. Add the project URL and publishable or anon key to the root .env.local file, then restart the dev server.",
    };
  }

  const emailValue = formData.get("email");
  const passwordValue = formData.get("password");
  const email = typeof emailValue === "string" ? emailValue.trim() : "";
  const password = typeof passwordValue === "string" ? passwordValue : "";
  if (!email.includes("@") || password.length === 0) {
    return { error: "Enter a valid email address and password." };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.user) {
    return { error: "Sign-in failed. Check your email, password, and account status." };
  }

  const { data: isPatient, error: patientError } = await supabase.rpc("is_patient_portal_user");
  if (patientError) {
    return rejectSignIn(supabase, "We could not verify your patient portal access. Please try again.");
  }
  if (!isPatient) {
    return rejectSignIn(supabase, "This account is not activated for the patient portal. Contact your laboratory.");
  }

  redirect("/portal");
}

export async function signOut() {
  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signOut();

  if (error) {
    throw new Error(`Could not sign out: ${error.message}`);
  }

  redirect("/login");
}
