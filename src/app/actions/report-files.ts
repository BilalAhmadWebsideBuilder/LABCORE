"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireMembership } from "@/lib/auth/authorization";
import { getSupabaseEnvironment } from "@/lib/supabase/env";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type ReportFileActionState = { error: string | null; success: string | null };
const emptyState: ReportFileActionState = { error: null, success: null };
const maxFileSize = 25 * 1024 * 1024;
const mimeTypes = new Set(["application/pdf", "image/jpeg", "image/png"]);

export async function uploadReportAttachment(
  _previousState: ReportFileActionState,
  formData: FormData,
): Promise<ReportFileActionState> {
  const parsed = z.object({
    reportResultId: z.uuid(),
  }).safeParse({ reportResultId: formData.get("reportResultId") });
  const file = formData.get("file");
  if (!parsed.success || !(file instanceof File)) {
    return { ...emptyState, error: "Select a report and a supported file." };
  }
  if (file.size < 1 || file.size > maxFileSize) {
    return { ...emptyState, error: "Choose a non-empty PDF, JPEG, or PNG file up to 25 MB." };
  }
  if (!mimeTypes.has(file.type)) {
    return { ...emptyState, error: "Only PDF, JPEG, and PNG report files are accepted." };
  }

  const membership = await requireMembership([
    "lab_admin", "lab_manager", "receptionist", "technician", "billing_staff", "reporting_doctor",
  ]);
  const environment = getSupabaseEnvironment();
  if (!environment) {
    return { ...emptyState, error: "Supabase is not configured for secure uploads." };
  }
  const supabase = await createSupabaseServerClient();
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError || !sessionData.session?.access_token) {
    return { ...emptyState, error: "Your session could not be verified. Sign in again." };
  }
  const { data: allowed, error: permissionError } = await supabase.rpc("has_lab_permission", {
    target_lab: membership.labId,
    target_permission: "reports.upload",
  });
  if (permissionError) {
    return { ...emptyState, error: permissionError.message };
  }
  if (!allowed) {
    return { ...emptyState, error: "Your role cannot upload report files." };
  }

  const uploadForm = new FormData();
  uploadForm.set("labId", membership.labId);
  uploadForm.set("reportResultId", parsed.data.reportResultId);
  uploadForm.set("file", file);
  let response: Response;
  try {
    response = await fetch(`${environment.url}/functions/v1/scan-report-upload`, {
      method: "POST",
      headers: {
        apikey: environment.key,
        authorization: `Bearer ${sessionData.session.access_token}`,
      },
      body: uploadForm,
      cache: "no-store",
    });
  } catch {
    return { ...emptyState, error: "The secure upload service is unavailable. The file was not stored." };
  }

  let result: { error?: string; uploaded?: boolean };
  try {
    result = await response.json() as { error?: string; uploaded?: boolean };
  } catch {
    return { ...emptyState, error: "The secure upload service returned an invalid response." };
  }
  if (!response.ok || result.uploaded !== true) {
    return { ...emptyState, error: result.error ?? "The secure upload service rejected the file." };
  }

  revalidatePath("/lab/reports");
  return { ...emptyState, success: "File scanned and attached successfully." };
}
