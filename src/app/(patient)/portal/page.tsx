import { redirect } from "next/navigation";
import { z } from "zod";
import { signOut } from "@/app/actions/auth";
import { Logo } from "@/components/brand/Logo";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { robots: { index: false, follow: false } };
export const instant = false;

const patientReportsSchema = z.array(z.object({
  report_id: z.uuid(),
  laboratory_name: z.string(),
  patient_name: z.string(),
  patient_code: z.string(),
  test_name: z.string(),
  result_text: z.string(),
  published_at: z.string().nullable(),
}));

export default async function PatientPortal() {
  const supabase = await createSupabaseServerClient();
  const { data: claims, error: claimsError } = await supabase.auth.getClaims();
  if (claimsError || typeof claims?.claims?.sub !== "string") redirect("/login");

  const { data: isPatient, error: accessError } = await supabase.rpc("is_patient_portal_user");
  if (accessError) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#F6F9FA] px-5">
        <section className="card w-full max-w-lg rounded-2xl p-8 text-center">
          <h1 className="font-heading text-2xl font-bold">Patient portal setup is incomplete</h1>
          <p className="mt-3 text-sm text-[#4A5A60]">
            The database update for patient sign-in may not be applied yet. Contact your laboratory administrator.
          </p>
          <form action={signOut}><button className="mt-6 rounded-lg bg-[#ECFEFB] px-5 py-3 text-sm font-bold text-[#0A7490]">Sign out</button></form>
        </section>
      </main>
    );
  }
  if (!isPatient) redirect("/login");

  const { data: reports, error: reportsError } = await supabase.rpc("get_my_patient_reports");
  if (reportsError) {
    throw new Error(`Could not load your published reports: ${reportsError.message}`);
  }
  const parsedReports = patientReportsSchema.safeParse(reports);
  if (!parsedReports.success) {
    throw new Error("Published report data from the database is invalid.");
  }

  return (
    <main className="min-h-screen bg-[#F6F9FA] px-5 py-10">
      <section className="card mx-auto w-full max-w-3xl rounded-2xl p-6 sm:p-8">
        <header className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <Logo variant="horizontal" theme="light" />
            <h1 className="mt-2 font-heading text-2xl font-bold">Your published reports</h1>
            <p className="mt-2 text-sm text-[#4A5A60]">Only reports published by your laboratory are shown here.</p>
          </div>
          <form action={signOut}><button className="rounded-lg border border-[#DCE6E8] px-4 py-2 text-sm font-semibold">Sign out</button></form>
        </header>
        <div className="mt-8 space-y-4">
          {parsedReports.data.length === 0 ? (
            <p className="rounded-lg bg-[#F6F9FA] p-5 text-sm text-[#4A5A60]">There are no published reports linked to your account yet.</p>
          ) : parsedReports.data.map((report) => (
            <article key={report.report_id} className="rounded-xl border border-[#DCE6E8] p-5">
              <div className="flex flex-wrap justify-between gap-3">
                <div>
                  <h2 className="font-semibold">{report.test_name}</h2>
                  <p className="mt-1 text-sm text-[#4A5A60]">{report.laboratory_name} · {report.patient_name} ({report.patient_code})</p>
                </div>
                <time className="text-sm text-[#4A5A60]">
                  {report.published_at ? new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(new Date(report.published_at)) : "Published"}
                </time>
              </div>
              <pre className="mt-4 whitespace-pre-wrap break-words rounded-lg bg-[#F6F9FA] p-4 font-sans text-sm">{report.result_text}</pre>
            </article>
          ))}
        </div>
        <p className="mt-8 text-xs text-[#4A5A60]">
          Questions about a report? Contact the laboratory that issued it.
        </p>
      </section>
    </main>
  );
}
