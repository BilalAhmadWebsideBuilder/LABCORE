import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const maximumBytes = 25 * 1024 * 1024;
const allowedTypes = new Map([
  ["application/pdf", "pdf"],
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
]);

function respond(body: Record<string, unknown>, status: number, origin: string | null) {
  const headers = new Headers({ "content-type": "application/json" });
  const appOrigin = Deno.env.get("APP_ORIGIN")?.replace(/\/$/, "");
  if (origin && appOrigin && origin === appOrigin) {
    headers.set("access-control-allow-origin", appOrigin);
    headers.set("vary", "Origin");
  }
  return new Response(status === 204 ? null : JSON.stringify(body), { status, headers });
}

function signatureMatches(bytes: Uint8Array, mimeType: string) {
  if (mimeType === "application/pdf") {
    return new TextDecoder().decode(bytes.slice(0, 1024)).includes("%PDF-");
  }
  if (mimeType === "image/jpeg") {
    return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  }
  if (mimeType === "image/png") {
    return bytes.length >= 8 &&
      bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
      bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a;
  }
  return false;
}

function cleanFileName(fileName: string) {
  return fileName
    .replace(/[\\/\u0000-\u001f\u007f]/g, "_")
    .trim()
    .slice(0, 180) || "report-file";
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  const appOrigin = Deno.env.get("APP_ORIGIN")?.replace(/\/$/, "");
  if (origin && appOrigin && origin !== appOrigin) {
    return respond({ error: "Origin is not allowed" }, 403, origin);
  }
  if (request.method === "OPTIONS") {
    const result = respond({}, 204, origin);
    result.headers.set("access-control-allow-methods", "POST, OPTIONS");
    result.headers.set("access-control-allow-headers", "authorization, apikey, content-type");
    return result;
  }
  if (request.method !== "POST") {
    return respond({ error: "Method not allowed" }, 405, origin);
  }

  const bearer = request.headers.get("authorization")?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!bearer) return respond({ error: "Authentication required" }, 401, origin);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const scannerUrl = Deno.env.get("MALWARE_SCANNER_URL");
  const scannerApiKey = Deno.env.get("MALWARE_SCANNER_API_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !appOrigin || !scannerUrl || !scannerApiKey) {
    return respond({ error: "Secure report upload is not configured. Contact the laboratory administrator." }, 503, origin);
  }

  let parsedScannerUrl: URL;
  try {
    parsedScannerUrl = new URL(scannerUrl);
  } catch {
    return respond({ error: "Secure report scanner is not configured correctly." }, 503, origin);
  }
  if (parsedScannerUrl.protocol !== "https:") {
    return respond({ error: "The malware scanner must use HTTPS." }, 503, origin);
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return respond({ error: "Upload form data is invalid." }, 400, origin);
  }

  const labId = form.get("labId");
  const reportResultId = form.get("reportResultId");
  const file = form.get("file");
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (
    typeof labId !== "string" || !uuidPattern.test(labId) ||
    typeof reportResultId !== "string" || !uuidPattern.test(reportResultId) ||
    !(file instanceof File)
  ) {
    return respond({ error: "Select a valid report and a file." }, 400, origin);
  }
  if (file.size < 1 || file.size > maximumBytes) {
    return respond({ error: "Report files must be no larger than 25 MB." }, 413, origin);
  }
  const extension = allowedTypes.get(file.type);
  const allowedExtension = file.type === "image/jpeg"
    ? /\.(jpg|jpeg)$/i.test(file.name)
    : extension ? file.name.toLowerCase().endsWith(`.${extension}`) : false;
  if (!extension || !allowedExtension) {
    return respond({ error: "Upload a PDF, JPEG, or PNG file with a matching file extension." }, 415, origin);
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  if (!signatureMatches(bytes, file.type)) {
    return respond({ error: "The file content does not match its declared type." }, 415, origin);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${bearer}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: caller, error: callerError } = await callerClient.auth.getUser(bearer);
  if (callerError || !caller.user) {
    return respond({ error: "Authentication could not be verified." }, 401, origin);
  }

  const [uploadPermission, readPermission, reportResult] = await Promise.all([
    callerClient.rpc("has_lab_permission", {
      target_lab: labId,
      target_permission: "reports.upload",
    }),
    callerClient.rpc("has_lab_permission", {
      target_lab: labId,
      target_permission: "reports.read",
    }),
    callerClient.from("report_results")
      .select("id, patient_id, status")
      .eq("lab_id", labId)
      .eq("id", reportResultId)
      .maybeSingle(),
  ]);
  if (uploadPermission.error || readPermission.error || reportResult.error) {
    return respond({ error: "Could not verify report upload permissions." }, 403, origin);
  }
  if (!uploadPermission.data || !readPermission.data) {
    return respond({ error: "Report upload permission required." }, 403, origin);
  }
  if (!reportResult.data || reportResult.data.status === "published") {
    return respond({ error: "This report is unavailable or already published." }, 404, origin);
  }

  const scanController = new AbortController();
  const scanTimeout = setTimeout(() => scanController.abort(), 45_000);
  let scanResponse: Response;
  try {
    scanResponse = await fetch(parsedScannerUrl, {
      method: "POST",
      headers: {
        authorization: `Bearer ${scannerApiKey}`,
        "content-type": "application/octet-stream",
        "x-file-mime-type": file.type,
      },
      body: bytes,
      signal: scanController.signal,
    });
  } catch {
    return respond({ error: "Malware scanning is unavailable; the file was not stored." }, 503, origin);
  } finally {
    clearTimeout(scanTimeout);
  }
  if (!scanResponse.ok) {
    return respond({ error: "Malware scanning failed; the file was not stored." }, 503, origin);
  }

  let scanResult: unknown;
  try {
    scanResult = await scanResponse.json();
  } catch {
    return respond({ error: "Malware scanner returned an invalid response; the file was not stored." }, 503, origin);
  }
  if (!scanResult || typeof scanResult !== "object" || !("status" in scanResult)) {
    return respond({ error: "Malware scanner returned an invalid response; the file was not stored." }, 503, origin);
  }
  const scanStatus = scanResult.status;
  if (scanStatus !== "clean") {
    const status = scanStatus === "infected" ? 422 : 503;
    return respond({
      error: status === 422
        ? "Malware was detected; the file was rejected."
        : "Malware scanner did not confirm a clean file; upload was rejected.",
    }, status, origin);
  }
  const scannerName = "engine" in scanResult && typeof scanResult.engine === "string"
    ? scanResult.engine.slice(0, 80)
    : "configured-malware-scanner";

  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  const sha256 = Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const filePath = `${labId}/${reportResult.data.patient_id}/${reportResultId}/${crypto.randomUUID()}.${extension}`;
  const { error: storageError } = await serviceClient.storage
    .from("report-attachments")
    .upload(filePath, bytes, {
      contentType: file.type,
      cacheControl: "60",
      upsert: false,
    });
  if (storageError) {
    console.error("Could not store scanned report attachment:", storageError.message);
    return respond({ error: "Could not store the scanned report file." }, 500, origin);
  }

  const { error: recordError } = await serviceClient.rpc("register_scanned_report_attachment", {
    p_lab_id: labId,
    p_report_result_id: reportResultId,
    p_file_name: cleanFileName(file.name),
    p_file_path: filePath,
    p_mime_type: file.type,
    p_file_size_bytes: file.size,
    p_sha256: sha256,
    p_scanner_name: scannerName || "configured-malware-scanner",
    p_uploaded_by: caller.user.id,
  });
  if (recordError) {
    const { error: cleanupError } = await serviceClient.storage
      .from("report-attachments").remove([filePath]);
    if (cleanupError) {
      console.error("Could not remove unregistered scanned report file:", cleanupError.message);
    }
    console.error("Could not register scanned report attachment:", recordError.message);
    return respond({ error: "The scanned file could not be attached to the report." }, 500, origin);
  }

  return respond({ uploaded: true }, 201, origin);
});
