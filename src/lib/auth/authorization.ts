import "server-only";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getDashboardPath } from "./roles";

export async function requireMembership(allowedRoles: readonly string[]) {
  const supabase = await createSupabaseServerClient();
  const { data: claims, error: claimsError } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;

  if (claimsError || typeof userId !== "string") {
    redirect("/login");
  }

  const { data: memberships, error: membershipError } = await supabase
    .from("memberships")
    .select("lab_id, role")
    .eq("user_id", userId)
    .eq("active", true)
    .limit(2);

  if (membershipError) {
    throw new Error(`Could not verify laboratory access: ${membershipError.message}`);
  }

  if (memberships.length !== 1) {
    redirect("/login");
  }

  const membership = memberships[0];
  const dashboardPath = getDashboardPath(membership.role);

  if (!dashboardPath) {
    redirect("/login");
  }

  if (!allowedRoles.includes(membership.role)) {
    redirect(dashboardPath);
  }

  return { userId, labId: membership.lab_id, role: membership.role };
}

export async function requirePlatformDeveloper() {
  const supabase = await createSupabaseServerClient();
  const { data: claims, error: claimsError } = await supabase.auth.getClaims();
  const userId = claims?.claims?.sub;

  if (claimsError || typeof userId !== "string") {
    redirect("/login");
  }

  const { data: isDeveloper, error } = await supabase.rpc("is_platform_developer");

  if (error) {
    throw new Error(`Could not verify platform developer access: ${error.message}`);
  }

  if (!isDeveloper) {
    redirect("/login");
  }

  return { userId };
}
