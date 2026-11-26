import { signOut } from "@/app/actions/auth";
import { CreateLabForm } from "@/components/platform/CreateLabForm";
import { requirePlatformDeveloper } from "@/lib/auth/authorization";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

export default async function PlatformDashboard() {
  await requirePlatformDeveloper();
  const supabase = await createSupabaseServerClient();
  const { data: labs, error } = await supabase
    .from("labs")
    .select("id, name, slug, status, created_at")
    .order("created_at", { ascending: false });

  if (error) {
    throw new Error(`Could not load laboratory directory: ${error.message}`);
  }

  return (
    <main className="min-h-screen bg-[#061519] p-4 text-[#E8F6F5] lg:p-8">
      <div className="mx-auto max-w-7xl">
        <header className="flex items-center justify-between gap-4">
          <div>
            <p className="text-sm text-[#9FB8BC]">Platform overview</p>
            <h1 className="mt-1 font-heading text-3xl font-bold">LabCore Operations</h1>
          </div>
          <form action={signOut}>
            <button className="h-11 rounded-lg border border-[#1A4250] px-4 text-sm font-bold">
              Sign out
            </button>
          </form>
        </header>

        <section className="mt-8 rounded-xl border border-[#1A4250] bg-[#0B2229] p-5 sm:p-6">
          <h2 className="font-heading text-xl font-bold">Create a laboratory</h2>
          <p className="mb-5 mt-2 text-sm text-[#9FB8BC]">
            Developer access is limited to laboratory metadata. Patient and clinical records are not
            available from this account.
          </p>
          <CreateLabForm />
        </section>

        <section className="mt-8">
          <div className="mb-4 flex items-end justify-between">
            <div>
              <p className="text-sm text-[#9FB8BC]">Metadata only</p>
              <h2 className="mt-1 font-heading text-2xl font-bold">Laboratories</h2>
            </div>
            <p className="text-sm text-[#9FB8BC]">{labs.length} total</p>
          </div>
          {labs.length === 0 ? (
            <p className="rounded-xl border border-[#1A4250] bg-[#0B2229] p-5 text-sm text-[#9FB8BC]">
              No laboratories yet. Create one above to get started.
            </p>
          ) : (
            <ul className="grid gap-3 md:grid-cols-2">
              {labs.map((lab) => (
                <li
                  key={lab.id}
                  className="rounded-xl border border-[#1A4250] bg-[#0B2229] p-5"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <h3 className="font-semibold">{lab.name}</h3>
                      <p className="mono mt-1 text-sm text-[#9FB8BC]">{lab.slug}</p>
                    </div>
                    <span className="rounded-full border border-[#1A4250] px-3 py-1 text-xs capitalize text-[#9FB8BC]">
                      {lab.status}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </main>
  );
}
