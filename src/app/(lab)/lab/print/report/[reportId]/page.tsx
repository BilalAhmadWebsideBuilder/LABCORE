import { notFound } from "next/navigation";
import { z } from "zod";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";
import { PageLoadErrorNotice } from "@/components/workspace/PageLoadErrorNotice";
import { PrintButton } from "@/components/workspace/PrintButton";
import { requireMembership } from "@/lib/auth/authorization";
import { LAB_DASHBOARD_ROLES } from "@/lib/auth/roles";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const metadata = { robots: { index: false, follow: false } };

const reportSchema = z.object({
  laboratory: z.object({
    name: z.string(),
    city: z.string().nullable(),
    address: z.string().nullable(),
    phone: z.string().nullable(),
    email: z.string().nullable(),
    timezone: z.string().nullable(),
  }),
  patient: z.object({ full_name: z.string(), patient_code: z.string() }),
  test: z.object({
    name: z.string(),
    method: z.string().nullable(),
    normal_range: z.string().nullable(),
  }),
  report: z.object({
    result_text: z.string(),
    published_at: z.string().nullable(),
  }),
});

export default async function ReportPrintPage({
  params,
}: {
  params: Promise<{ reportId: string }>;
}) {
  const { reportId } = await params;
  const membership = await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("get_lab_report_print", {
    p_lab_id: membership.labId,
    p_report_result_id: reportId,
  });
  if (error) {
    if (error.code === "42501") notFound();
    const setupMessage = getDatabaseSetupMessage(error);
    if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
    return (
      <div className="public-report-page">
        <PageLoadErrorNotice
          title="Report printout unavailable"
          message="We could not load this report. Please try again later or contact your laboratory administrator."
        />
      </div>
    );
  }
  const parsed = reportSchema.safeParse(data);
  if (!parsed.success) {
    if (data === null) notFound();
    return (
      <div className="public-report-page">
        <PageLoadErrorNotice
          title="Report printout unavailable"
          message="The report data could not be displayed. Please contact your laboratory administrator."
        />
      </div>
    );
  }

  const { laboratory, patient, test, report } = parsed.data;
  const timezone = laboratory.timezone || "UTC";
  const publishedAt = report.published_at
    ? new Intl.DateTimeFormat("en", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: timezone,
      }).format(new Date(report.published_at))
    : "—";

  return (
    <article className="print-document print-document-a4">
      <div className="print-toolbar">
        <PrintButton />
      </div>
      <header className="print-document-heading">
        <h1>{laboratory.name}</h1>
        {[laboratory.address, laboratory.city, laboratory.phone, laboratory.email].filter(Boolean).map((line, index) => (
          <p key={`${line}-${index}`}>{line}</p>
        ))}
        <h2>Laboratory Report</h2>
      </header>
      <dl className="print-document-meta">
        <div><dt>Patient</dt><dd>{patient.full_name}</dd></div>
        <div><dt>Patient ID</dt><dd>{patient.patient_code}</dd></div>
        <div><dt>Test</dt><dd>{test.name}</dd></div>
        <div><dt>Published</dt><dd>{publishedAt}</dd></div>
        {test.method && <div><dt>Method</dt><dd>{test.method}</dd></div>}
        {test.normal_range && <div><dt>Reference range</dt><dd>{test.normal_range}</dd></div>}
      </dl>
      <section className="print-document-result">
        <h2>Result</h2>
        <pre>{report.result_text}</pre>
      </section>
      <footer className="print-document-footer">
        This report was generated from the laboratory’s published result record.
      </footer>
    </article>
  );
}
