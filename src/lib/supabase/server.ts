import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabaseEnvironment } from "./env";

export async function createSupabaseServerClient() {
  const environment = getSupabaseEnvironment();

  if (!environment) {
    throw new Error(
      "Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL and a publishable or anon key in the project-root .env.local file.",
    );
  }

  const cookieStore = await cookies();

  return createServerClient(environment.url, environment.key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        } catch (error) {
          if (
            error instanceof Error &&
            error.message.includes(
              "Cookies can only be modified in a Server Action or Route Handler",
            )
          ) {
            return;
          }

          throw error;
        }
      },
    },
  });
}
