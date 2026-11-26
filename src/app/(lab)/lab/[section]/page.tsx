import { notFound, redirect } from "next/navigation";
import { fromZonedTime } from "date-fns-tz";
import {
  AnalyticsCards,
  AppointmentsManager,
  DoctorsManager,
  ExpensesManager,
  InvoiceBuilder,
  InvoiceHistory,
  PrintRequests,
  ReagentsManager,
  ReportsWorkspace,
  RetentionPolicyForm,
  SampleQueue,
  ScheduleSettings,
  SettingsForm,
  StaffManager,
  TrashBin,
  type InvoiceRow,
  type AppointmentRow,
  type OrderChoice,
  type PatientChoice,
  type PrintRequestRow,
  type ResourceBookingRow,
  type RecordRow,
  type ReportRow,
  type ReportAttachmentRow,
  type ReagentMovementRow,
  type ScheduleResourceRow,
  type ScheduleStaffChoice,
  type SampleRow,
  type StaffRow,
  type StaffShiftRow,
  type TestChoice,
  type TrashRow,
  type WorkingHourRow,
} from "@/components/workspace/WorkspaceModules";
import { DatabaseSetupNotice } from "@/components/workspace/DatabaseSetupNotice";
import { requireMembership } from "@/lib/auth/authorization";
import { getDatabaseSetupMessage } from "@/lib/db/migration-status";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

const moduleDefinitions = {
  "test-billing": {
    page: "test_billing",
    title: "Test billing",
    description: "Register a visit, select tests, issue an invoice, and record a payment.",
    permissions: ["patients.read", "services.read", "orders.manage", "billing.manage"],
  },
  appointments: {
    page: "appointments",
    title: "Appointments",
    description: "Schedule and manage patient appointments in this laboratory.",
    permissions: ["appointments.read"],
  },
  scheduling: {
    page: "scheduling",
    title: "Scheduling",
    description: "Manage working hours, laboratory resources, resource bookings, and staff shifts.",
    permissions: ["scheduling.read"],
  },
  samples: {
    page: "samples",
    title: "Sample collection",
    description: "Track assigned samples by barcode and move orders through processing.",
    permissions: ["orders.read"],
  },
  reports: {
    page: "reports",
    title: "Reports",
    description: "Enter, independently review, and securely publish assigned results.",
    permissions: ["reports.read"],
  },
  "invoice-history": {
    page: "invoice_history",
    title: "Invoice history",
    description: "Review this laboratory’s invoices, balances, payments, and receipts.",
    permissions: ["billing.read"],
  },
  "referring-doctors": {
    page: "referring_doctors",
    title: "Referring doctors",
    description: "Maintain the laboratory’s referring doctor directory.",
    permissions: ["doctors.read"],
  },
  "reagent-stock": {
    page: "reagent_stock",
    title: "Reagent stock",
    description: "Track quantities, reorder thresholds, batches, and expiry dates.",
    permissions: ["inventory.read"],
  },
  expenses: {
    page: "expenses",
    title: "Expenses",
    description: "Record and review laboratory operating expenses.",
    permissions: ["expenses.read"],
  },
  analytics: {
    page: "analytics",
    title: "Analytics",
    description: "Review tenant-scoped activity and permitted financial indicators.",
    permissions: ["analytics.read"],
  },
  "manage-users": {
    page: "manage_users",
    title: "Manage users",
    description: "Invite laboratory staff and assign roles and page access.",
    permissions: ["staff.manage", "roles.manage"],
  },
  "print-requests": {
    page: "print_requests",
    title: "Print requests",
    description: "Review staff requests to print invoice copies.",
    permissions: ["print_requests.read", "print_requests.manage"],
  },
  "my-print-requests": {
    page: "my_print_requests",
    title: "My print requests",
    description: "Request and track printed invoice copies.",
    permissions: ["print_requests.read"],
  },
  settings: {
    page: "settings",
    title: "Laboratory settings",
    description: "Manage laboratory contact details, currency, timezone, and receipt layout.",
    permissions: ["settings.read"],
  },
  "trash-bin": {
    page: "trash_bin",
    title: "Trash bin",
    description: "Restore archived laboratory records.",
    permissions: [],
  },
  help: {
    page: "help",
    title: "Help and setup",
    description: "Guidance for safely configuring and testing LabCore.",
    permissions: [],
  },
} as const;

type ModuleSection = keyof typeof moduleDefinitions;

async function checkPermission(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  labId: string,
  permission: string,
) {
  return supabase.rpc("has_lab_permission", {
    target_lab: labId,
    target_permission: permission,
  });
}

function setupNotice(error: { code?: string; message: string }) {
  const message = getDatabaseSetupMessage(error);
  if (message) return <DatabaseSetupNotice message={message} />;
  throw new Error(error.message);
}

function dateKeyInTimezone(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const part = (type: string) => parts.find((value) => value.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

function PageHeading({ section }: { section: ModuleSection }) {
  const definition = moduleDefinitions[section];
  return (
    <div className="workspace-page-heading">
      <div>
        <p className="workspace-eyebrow">Laboratory workspace</p>
        <h1>{definition.title}</h1>
        <p className="workspace-page-description">{definition.description}</p>
      </div>
    </div>
  );
}

export default async function WorkspaceSectionPage({
  params,
}: PageProps<"/lab/[section]">) {
  const { section } = await params;
  if (section === "departments") redirect("/lab/tests#departments");
  if (!Object.hasOwn(moduleDefinitions, section)) notFound();

  const moduleKey = section as ModuleSection;
  const definition = moduleDefinitions[moduleKey];
  const membership = await requireMembership([
    "lab_admin", "lab_manager", "receptionist", "technician", "billing_staff", "reporting_doctor",
  ]);
  const supabase = await createSupabaseServerClient();

  const { data: hasPageAccess, error: pageAccessError } = await supabase.rpc("has_lab_page_access", {
    target_lab: membership.labId,
    target_page: definition.page,
  });
  if (pageAccessError) return setupNotice(pageAccessError);
  if (!hasPageAccess) redirect("/lab");

  if (moduleKey === "trash-bin") {
    const { data, error: trashError } = await supabase.rpc("get_lab_trash", {
      p_lab_id: membership.labId,
    });
    if (trashError) return setupNotice(trashError);
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <TrashBin items={(data ?? []) as TrashRow[]} />
      </div>
    );
  }

  const permissionResults = await Promise.all(
    definition.permissions.map((permission) => checkPermission(supabase, membership.labId, permission)),
  );
  const permissionError = permissionResults.find((result) => result.error)?.error;
  if (permissionError) return setupNotice(permissionError);
  if (permissionResults.some((result) => result.data !== true)) redirect("/lab");

  if (moduleKey === "help") {
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <section className="workspace-card">
          <h2>Safe setup checklist</h2>
          <ul className="workspace-help-list">
            <li>Apply the numbered SQL migrations in <code>docs/DATABASE.md</code> to a test project first.</li>
            <li>Use fictional patients and results while validating workflows.</li>
            <li>Invite staff through Manage users; each invitation receives its own laboratory role and page grants.</li>
            <li>Reports use one-time-to-share bearer links that expire after 90 days. Treat them like credentials.</li>
            <li>Before clinical use, configure privacy, result validation, retention, backups, SMTP, and local regulatory controls.</li>
          </ul>
        </section>
      </div>
    );
  }

  if (moduleKey === "test-billing") {
    const [{ data: patients, error: patientsError }, { data: tests, error: testsError }, { data: labSettings, error: settingsError }] =
      await Promise.all([
        supabase.from("patients").select("id, patient_code, full_name")
          .eq("lab_id", membership.labId).is("deleted_at", null).order("full_name").limit(500),
        supabase.from("services").select("id, code, name, price")
          .eq("lab_id", membership.labId).eq("active", true).is("deleted_at", null).order("name").limit(500),
        supabase.from("lab_settings").select("currency").eq("lab_id", membership.labId).maybeSingle(),
      ]);
    const error = patientsError ?? testsError ?? settingsError;
    if (error) return setupNotice(error);
    const patientOptions: PatientChoice[] = (patients ?? []).map((patient) => ({
      id: patient.id,
      label: `${patient.patient_code} · ${patient.full_name}`,
    }));
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <InvoiceBuilder
          patients={patientOptions}
          tests={(tests ?? []) as TestChoice[]}
        />
        {labSettings?.currency && <p className="workspace-page-description">Currency: {labSettings.currency}</p>}
      </div>
    );
  }

  if (moduleKey === "appointments") {
    const [
      { data: canManage, error: manageError },
      { data: labSettings, error: settingsError },
    ] = await Promise.all([
      checkPermission(supabase, membership.labId, "appointments.manage"),
      supabase.from("lab_settings").select("timezone").eq("lab_id", membership.labId).maybeSingle(),
    ]);
    const error = manageError ?? settingsError;
    if (error) return setupNotice(error);
    const timezone = labSettings?.timezone ?? "UTC";
    const startDate = dateKeyInTimezone(new Date(), timezone);
    const endAnchor = new Date(`${startDate}T12:00:00Z`);
    endAnchor.setUTCDate(endAnchor.getUTCDate() + 30);
    const endDate = endAnchor.toISOString().slice(0, 10);
    const [{ data: appointments, error: appointmentError }, { data: patientRows, error: patientError }] =
      await Promise.all([
        supabase.rpc("get_lab_appointments", {
          p_lab_id: membership.labId,
          p_from: fromZonedTime(`${startDate}T00:00:00`, timezone).toISOString(),
          p_to: fromZonedTime(`${endDate}T00:00:00`, timezone).toISOString(),
        }),
        canManage
          ? supabase.rpc("get_lab_patient_choices", { p_lab_id: membership.labId })
          : Promise.resolve({ data: [], error: null }),
      ]);
    const queryError = appointmentError ?? patientError;
    if (queryError) return setupNotice(queryError);
    let patients: PatientChoice[] = [];
    if (canManage) {
      const choices = patientRows as Array<{
        patient_id: string;
        patient_code: string;
        full_name: string;
      }> | null;
      patients = (choices ?? []).map((patient) => ({
        id: patient.patient_id,
        label: `${patient.patient_code} · ${patient.full_name}`,
      }));
    }
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <AppointmentsManager
          appointments={(appointments ?? []) as AppointmentRow[]}
          patients={patients}
          timezone={timezone}
          canManage={canManage === true}
        />
      </div>
    );
  }

  if (moduleKey === "scheduling") {
    const [
      { data: hours, error: hoursError },
      { data: canManage, error: manageError },
      { data: labSettings, error: settingsError },
    ] = await Promise.all([
      supabase.from("working_hours").select("weekday, opens_at, closes_at, closed")
        .eq("lab_id", membership.labId).order("weekday"),
      checkPermission(supabase, membership.labId, "scheduling.manage"),
      supabase.from("lab_settings").select("timezone").eq("lab_id", membership.labId).maybeSingle(),
    ]);
    const error = hoursError ?? manageError ?? settingsError;
    if (error) return setupNotice(error);
    const timezone = labSettings?.timezone ?? "UTC";
    const startDate = dateKeyInTimezone(new Date(), timezone);
    const endAnchor = new Date(`${startDate}T12:00:00Z`);
    endAnchor.setUTCDate(endAnchor.getUTCDate() + 30);
    const endDate = endAnchor.toISOString().slice(0, 10);
    const from = fromZonedTime(`${startDate}T00:00:00`, timezone).toISOString();
    const to = fromZonedTime(`${endDate}T00:00:00`, timezone).toISOString();
    const [
      { data: resources, error: resourcesError },
      { data: bookings, error: bookingsError },
      { data: shifts, error: shiftsError },
      { data: staff, error: staffError },
    ] = await Promise.all([
      supabase.rpc("get_lab_schedule_resources", { p_lab_id: membership.labId }),
      supabase.rpc("get_lab_resource_bookings", {
        p_lab_id: membership.labId,
        p_from: from,
        p_to: to,
      }),
      supabase.rpc("get_lab_staff_shifts", {
        p_lab_id: membership.labId,
        p_from: from,
        p_to: to,
      }),
      canManage
        ? supabase.rpc("get_lab_schedule_staff", { p_lab_id: membership.labId })
        : Promise.resolve({ data: [], error: null }),
    ]);
    const scheduleError = resourcesError ?? bookingsError ?? shiftsError ?? staffError;
    if (scheduleError) return setupNotice(scheduleError);
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <ScheduleSettings
          hours={(hours ?? []) as WorkingHourRow[]}
          resources={(resources ?? []) as ScheduleResourceRow[]}
          resourceBookings={(bookings ?? []) as ResourceBookingRow[]}
          staffChoices={(staff ?? []) as ScheduleStaffChoice[]}
          staffShifts={(shifts ?? []) as StaffShiftRow[]}
          timezone={timezone}
          canManage={canManage === true}
        />
      </div>
    );
  }

  if (moduleKey === "samples") {
    const [
      { data: sampleRows, error: sampleError },
      { data: canUpdate, error: updateError },
      { data: canAssign, error: assignError },
    ] = await Promise.all([
      supabase.rpc("get_lab_sample_board", { p_lab_id: membership.labId }),
      checkPermission(supabase, membership.labId, "orders.manage"),
      checkPermission(supabase, membership.labId, "orders.assign"),
    ]);
    const error = sampleError ?? updateError ?? assignError;
    if (error) return setupNotice(error);
    let assignableStaff: StaffRow[] = [];
    if (canAssign) {
      const { data: staff, error: staffError } = await supabase.rpc("get_lab_staff_access", {
        p_lab_id: membership.labId,
      });
      if (staffError) return setupNotice(staffError);
      assignableStaff = (staff ?? []) as StaffRow[];
    }
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <SampleQueue
          samples={(sampleRows ?? []) as SampleRow[]}
          assignableStaff={assignableStaff}
          canAssign={canAssign === true}
          canUpdate={canUpdate === true}
        />
      </div>
    );
  }

  if (moduleKey === "reports") {
    const [
      { data: reportRows, error: reportError },
      { data: canUpload, error: uploadError },
      { data: canReview, error: reviewError },
      { data: canPublish, error: publishError },
      { data: attachmentRows, error: attachmentError },
    ] = await Promise.all([
      supabase.rpc("get_lab_report_queue", { p_lab_id: membership.labId }),
      checkPermission(supabase, membership.labId, "reports.upload"),
      checkPermission(supabase, membership.labId, "reports.review"),
      checkPermission(supabase, membership.labId, "reports.publish"),
      supabase.rpc("get_lab_report_attachments", { p_lab_id: membership.labId, p_limit: 500 }),
    ]);
    const error = reportError ?? uploadError ?? reviewError ?? publishError ?? attachmentError;
    if (error) return setupNotice(error);
    const { data: orderRows, error: orderError } = canUpload
      ? await supabase.rpc("get_reportable_order_items", { p_lab_id: membership.labId })
      : { data: [], error: null };
    if (orderError) return setupNotice(orderError);
    const reportItems = (reportRows ?? []) as Array<{
      report_result_id: string;
      order_item_id: string;
      result_text: string;
      report_status: string;
      patient_name: string;
      patient_code: string;
      test_name: string;
      entered_by: string | null;
    }>;
    const attachments = (attachmentRows ?? []) as ReportAttachmentRow[];
    const attachmentsByReport = new Map<string, ReportAttachmentRow[]>();
    for (const attachment of attachments) {
      const current = attachmentsByReport.get(attachment.report_result_id) ?? [];
      current.push(attachment);
      attachmentsByReport.set(attachment.report_result_id, current);
    }
    const reports: ReportRow[] = reportItems.map((report) => ({
      id: report.report_result_id,
      order_item_id: report.order_item_id,
      result_text: report.result_text,
      status: report.report_status,
      patient_name: report.patient_name,
      patient_code: report.patient_code,
      test_name: report.test_name,
      entered_by: report.entered_by,
      attachments: attachmentsByReport.get(report.report_result_id) ?? [],
    }));
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <ReportsWorkspace
          reports={reports}
          eligibleOrders={(orderRows ?? []) as OrderChoice[]}
          canUpload={canUpload === true}
          canReview={canReview === true}
          canPublish={canPublish === true}
        />
      </div>
    );
  }

  if (moduleKey === "invoice-history") {
    const [
      { data: rawInvoices, error: invoiceError },
      { data: canPay, error: payError },
      { data: canPrint, error: printError },
    ] = await Promise.all([
      supabase.from("invoices")
        .select("id, invoice_number, patient_id, created_at, total, status")
        .eq("lab_id", membership.labId).order("created_at", { ascending: false }).limit(200),
      checkPermission(supabase, membership.labId, "billing.manage"),
      checkPermission(supabase, membership.labId, "print_requests.manage"),
    ]);
    const error = invoiceError ?? payError ?? printError;
    if (error) return setupNotice(error);
    const invoiceIds = (rawInvoices ?? []).map((invoice) => invoice.id);
    const patientIds = (rawInvoices ?? []).map((invoice) => invoice.patient_id);
    const [
      { data: payments, error: paymentError },
      { data: patients, error: patientError },
    ] = await Promise.all([
      invoiceIds.length
        ? supabase.from("payments").select("invoice_id, amount").eq("lab_id", membership.labId).in("invoice_id", invoiceIds).is("voided_at", null)
        : Promise.resolve({ data: [], error: null }),
      patientIds.length
        ? supabase.from("patients").select("id, full_name").eq("lab_id", membership.labId).in("id", patientIds)
        : Promise.resolve({ data: [], error: null }),
    ]);
    const dataError = paymentError ?? patientError;
    if (dataError) return setupNotice(dataError);
    const patientNames = new Map((patients ?? []).map((patient) => [patient.id, patient.full_name]));
    const paidAmounts = new Map<string, number>();
    for (const payment of payments ?? []) {
      paidAmounts.set(payment.invoice_id, (paidAmounts.get(payment.invoice_id) ?? 0) + Number(payment.amount));
    }
    const invoiceRows: InvoiceRow[] = (rawInvoices ?? []).map((invoice) => {
      const paid = paidAmounts.get(invoice.id) ?? 0;
      return {
        id: invoice.id,
        invoice_number: invoice.invoice_number,
        patient_name: patientNames.get(invoice.patient_id) ?? "Patient",
        created_at: invoice.created_at,
        total: Number(invoice.total),
        paid,
        balance: Math.max(Number(invoice.total) - paid, 0),
        status: invoice.status,
      };
    });
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <InvoiceHistory invoices={invoiceRows} canPay={canPay === true} canRequestPrint={canPrint === true} />
      </div>
    );
  }

  if (moduleKey === "referring-doctors" || moduleKey === "reagent-stock" || moduleKey === "expenses") {
    const permission = moduleKey === "referring-doctors" ? "doctors.manage" : moduleKey === "reagent-stock" ? "inventory.manage" : "expenses.manage";
    const { data: canManage, error: manageError } = await checkPermission(supabase, membership.labId, permission);
    if (manageError) return setupNotice(manageError);
    let rows: RecordRow[] = [];
    let movements: ReagentMovementRow[] = [];

    if (moduleKey === "referring-doctors") {
      const { data, error } = await supabase.from("referring_doctors")
        .select("id, full_name, clinic, phone, email, specialty, commission_percent, address")
        .eq("lab_id", membership.labId).is("deleted_at", null)
        .order("created_at", { ascending: false }).limit(500);
      if (error) return setupNotice(error);
      rows = (data ?? []).map((doctor) => ({
        id: doctor.id,
        kind: "doctor",
        label: doctor.full_name,
        secondary: [doctor.clinic, doctor.specialty, doctor.phone].filter(Boolean).join(" · "),
        fields: {
          name: doctor.full_name, clinic: doctor.clinic, phone: doctor.phone,
          email: doctor.email, specialty: doctor.specialty,
          commissionPercent: Number(doctor.commission_percent), address: doctor.address,
        },
      }));
    } else if (moduleKey === "reagent-stock") {
      const { data, error } = await supabase.from("reagent_stock")
        .select("id, name, quantity, reorder_level, expiry_date, supplier, batch_number, unit_price, storage")
        .eq("lab_id", membership.labId).is("deleted_at", null)
        .order("created_at", { ascending: false }).limit(500);
      if (error) return setupNotice(error);
      rows = (data ?? []).map((reagent) => ({
        id: reagent.id,
        kind: "reagent",
        label: reagent.name,
        secondary: `Qty ${reagent.quantity} · reorder at ${reagent.reorder_level}${reagent.expiry_date ? ` · expires ${reagent.expiry_date}` : ""}`,
        fields: {
          name: reagent.name, quantity: Number(reagent.quantity),
          reorderLevel: Number(reagent.reorder_level), expiryDate: reagent.expiry_date,
          supplier: reagent.supplier, batchNumber: reagent.batch_number,
          unitPrice: Number(reagent.unit_price), storage: reagent.storage,
        },
      }));
      const { data: movementRows, error: movementError } = await supabase.rpc("get_lab_reagent_movements", {
        p_lab_id: membership.labId,
        p_reagent_id: null,
        p_limit: 200,
      });
      if (movementError) return setupNotice(movementError);
      movements = (movementRows ?? []) as ReagentMovementRow[];
    } else {
      const { data, error } = await supabase.from("expenses")
        .select("id, category, note, expense_date, amount, paid_via, receipt_number")
        .eq("lab_id", membership.labId).is("deleted_at", null)
        .order("created_at", { ascending: false }).limit(500);
      if (error) return setupNotice(error);
      rows = (data ?? []).map((expense) => ({
        id: expense.id,
        kind: "expense",
        label: expense.category,
        secondary: `${expense.expense_date} · ${Number(expense.amount).toFixed(2)} · ${expense.note}`,
        fields: {
          name: expense.category, note: expense.note,
          expenseDate: expense.expense_date, amount: Number(expense.amount),
          paidVia: expense.paid_via, receiptNumber: expense.receipt_number,
        },
      }));
    }

    const recordsView = moduleKey === "referring-doctors"
      ? <DoctorsManager rows={rows} />
      : moduleKey === "reagent-stock"
        ? <ReagentsManager rows={rows} movements={movements} canManage={canManage === true} />
        : <ExpensesManager rows={rows} />;
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        {moduleKey === "reagent-stock" || canManage ? recordsView : (
          <section className="workspace-card">
            <div className="workspace-record-list">
              {rows.map((row) => (
                <div className="workspace-record-row" key={row.id}>
                  <span><strong>{row.label}</strong><small>{row.secondary}</small></span>
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    );
  }

  if (moduleKey === "analytics") {
    const today = new Date();
    const from = new Date(today.getTime() - 29 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    const to = today.toISOString().slice(0, 10);
    const { data, error } = await supabase.rpc("get_lab_analytics", {
      p_lab_id: membership.labId, p_from: from, p_to: to,
    });
    if (error) return setupNotice(error);
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <p className="workspace-page-description">Last 30 days · {from} through {to}</p>
        <AnalyticsCards values={(data ?? {}) as Record<string, string | number | null>} />
      </div>
    );
  }

  if (moduleKey === "manage-users") {
    const { data, error } = await supabase.rpc("get_lab_staff_access", { p_lab_id: membership.labId });
    if (error) return setupNotice(error);
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <StaffManager staff={(data ?? []) as StaffRow[]} />
      </div>
    );
  }

  if (moduleKey === "settings") {
    const [
      { data: lab, error: labError },
      { data: settings, error: settingsError },
      { data: canManage, error: manageError },
      { data: retention, error: retentionError },
    ] =
      await Promise.all([
        supabase.from("labs").select("name, city, phone, email, address, receipt_format, receipt_footer")
          .eq("id", membership.labId).maybeSingle(),
        supabase.from("lab_settings").select("currency, timezone")
          .eq("lab_id", membership.labId).maybeSingle(),
        checkPermission(supabase, membership.labId, "settings.manage"),
        supabase.rpc("get_lab_retention_policy", { p_lab_id: membership.labId }),
      ]);
    const error = labError ?? settingsError ?? manageError ?? retentionError;
    if (error) return setupNotice(error);
    const values = {
      name: lab?.name ?? "",
      city: lab?.city ?? "",
      phone: lab?.phone ?? "",
      email: lab?.email ?? "",
      address: lab?.address ?? "",
      currency: settings?.currency ?? "USD",
      timezone: settings?.timezone ?? "UTC",
      receipt_format: lab?.receipt_format ?? "thermal_80mm",
      receipt_footer: lab?.receipt_footer ?? "",
    };
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        {canManage ? <SettingsForm values={values} /> : (
          <section className="workspace-card"><dl className="workspace-settings-list">
            {Object.entries(values).map(([key, value]) => <div key={key}><dt>{key.replaceAll("_", " ")}</dt><dd>{value || "Not set"}</dd></div>)}
          </dl></section>
        )}
        <RetentionPolicyForm
          retentionDays={retention?.[0]?.retention_days ?? 2555}
          legalHoldEnabled={retention?.[0]?.legal_hold_enabled ?? false}
          canManage={canManage === true}
        />
      </div>
    );
  }

  if (moduleKey === "print-requests" || moduleKey === "my-print-requests") {
    const { data: rawRequests, error: requestError } = await supabase.from("print_requests")
      .select("id, invoice_id, requested_by, status, decision_reason, created_at")
      .eq("lab_id", membership.labId)
      .order("created_at", { ascending: false })
      .limit(200);
    if (requestError) return setupNotice(requestError);
    const requests = moduleKey === "my-print-requests"
      ? (rawRequests ?? []).filter((row) => row.requested_by === membership.userId)
      : rawRequests ?? [];
    const invoiceIds = requests.map((row) => row.invoice_id);
    const { data: invoices, error: invoiceError } = invoiceIds.length
      ? await supabase.from("invoices").select("id, invoice_number").eq("lab_id", membership.labId).in("id", invoiceIds)
      : { data: [], error: null };
    if (invoiceError) return setupNotice(invoiceError);
    const invoiceNumbers = new Map((invoices ?? []).map((invoice) => [invoice.id, invoice.invoice_number]));
    const rows: PrintRequestRow[] = requests.map((row) => ({
      ...row,
      invoice_number: invoiceNumbers.get(row.invoice_id) ?? "Invoice",
    }));
    const canReview = moduleKey === "print-requests" &&
      permissionResults.some((result) => result.data === true);
    return (
      <div className="workspace-page">
        <PageHeading section={moduleKey} />
        <PrintRequests requests={rows} canReview={canReview} />
      </div>
    );
  }

  return notFound();
}
