import { NextResponse } from "next/server";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const next = url.searchParams.get("next") === "/reset-password"
    ? "/reset-password"
    : "/login";

  if (!code) {
    return NextResponse.redirect(new URL("/forgot-password", url.origin));
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    return NextResponse.redirect(new URL("/forgot-password", url.origin));
  }

  return NextResponse.redirect(new URL(next, url.origin));
}
