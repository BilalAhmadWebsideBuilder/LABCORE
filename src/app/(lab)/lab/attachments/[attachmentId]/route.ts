import { createSupabaseServerClient } from "@/lib/supabase/server";
import { requireMembership } from "@/lib/auth/authorization";
import { LAB_DASHBOARD_ROLES } from "@/lib/auth/roles";

export const instant = false;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ attachmentId: string }> },
) {
  const { attachmentId } = await params;
  await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const { data: filePath, error } = await supabase.rpc("get_lab_report_attachment_path", {
    p_file_id: attachmentId,
  });
  if (error || typeof filePath !== "string") {
    return new Response("Report attachment not found or access denied.", {
      status: error?.code === "42501" ? 403 : 404,
      headers: { "cache-control": "no-store" },
    });
  }

  const { data, error: urlError } = await supabase.storage
    .from("report-attachments")
    .createSignedUrl(filePath, 60);
  if (urlError || !data.signedUrl) {
    console.error("Could not create report attachment URL:", urlError?.message);
    return new Response("Could not create a secure download link.", {
      status: 503,
      headers: { "cache-control": "no-store" },
    });
  }

  return new Response(null, {
    status: 302,
    headers: {
      location: data.signedUrl,
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
    },
  });
}
