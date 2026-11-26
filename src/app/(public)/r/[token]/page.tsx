import { createHash } from "node:crypto";
import type { Metadata } from "next";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;
export const metadata: Metadata = {
  robots: { index: false, follow: false },
  referrer: "no-referrer",
};

export default async function PublicReportPage({
  params,
}: PageProps<"/r/[token]">) {
  const { token } = await params;
  if (!/^[0-9a-f]{64}$/i.test(token)) {
    return <main className="public-report-page"><h1>Report unavailable</h1><p>This link is invalid or has expired.</p></main>;
  }
  const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
  const supabase = await createSupabaseServerClient();
  const { data: report, error } = await supabase.rpc("get_public_report", {
    p_token_hash: tokenHash,
  });
  if (error) {
    const message = getDatabaseSetupMessage(error);
    if (message) return <DatabaseSetupNotice message={message} />;
    throw new Error(`Could not load published report: ${error.message}`);
  }
  const publishedReport = report?.[0];
  if (!publishedReport) {
    return <main className="public-report-page"><h1>Report unavailable</h1><p>This link has expired, been revoked, or does not identify a published report.</p></main>;
  }

  return (
    <main className="public-report-page">
      <p className="workspace-eyebrow">Private patient report</p>
      <h1>{publishedReport.laboratory_name}</h1>
      <dl className="workspace-settings-list">
        <div><dt>Patient</dt><dd>{publishedReport.patient_name} · {publishedReport.patient_code}</dd></div>
        <div><dt>Test</dt><dd>{publishedReport.test_name}</dd></div>
        <div><dt>Published</dt><dd>{new Date(publishedReport.published_at).toLocaleString()}</dd></div>
      </dl>
      <section className="workspace-card">
        <h2>Result</h2>
        <pre className="workspace-result-text">{publishedReport.result_text}</pre>
      </section>
      <p className="workspace-page-description">
        This result is private. Do not forward this link. Contact the laboratory if you believe it was shared incorrectly.
      </p>
    </main>
  );
}
