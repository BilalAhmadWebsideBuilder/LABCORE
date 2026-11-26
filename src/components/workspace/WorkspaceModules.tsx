"use client";

import { useActionState, useState } from "react";
import {
  archiveLabItem,
  createPrintRequest,
  inviteLabStaff,
  restoreLabItem,
  reviewPrintRequest,
  saveLabSettings,
  saveRetentionPolicy,
  setStaffActive,
  updateStaffAccess,
  type AdminActionState,
} from "@/app/actions/workspace-admin";
import {
  assignOrder,
  cancelLabAppointment,
  cancelLabResourceBooking,
  cancelLabStaffShift,
  createLabResource,
  createLabAppointment,
  createLabInvoice,
  createLabResourceBooking,
  createLabStaffShift,
  publishReportResult,
  recordInvoicePayment,
  reviewReportResult,
  saveReportResult,
  saveWorkingHour,
  setLabResourceActive,
  transitionOrder,
  transitionSample,
  type WorkflowActionState,
} from "@/app/actions/workflows";
import {
  recordReagentMovement,
  saveLabCatalogItem,
  type CatalogActionState,
} from "@/app/actions/catalog";
import {
  uploadReportAttachment,
  type ReportFileActionState,
} from "@/app/actions/report-files";

const emptyWorkflow: WorkflowActionState = { error: null, success: null };
const emptyAdmin: AdminActionState = { error: null, success: null };
const emptyCatalog: CatalogActionState = { error: null, success: null };

function Feedback({ state }: { state: { error: string | null; success: string | null; link?: string | null } }) {
  return (
    <>
      {state.error && <p className="patient-form-message is-error" role="alert">{state.error}</p>}
      {state.success && <p className="patient-form-message" role="status">{state.success}</p>}
      {state.link && (
        <p className="patient-form-message">
          Patient link: <a href={state.link} target="_blank" rel="noreferrer">{state.link}</a>
        </p>
      )}
    </>
  );
}

export type PatientChoice = { id: string; label: string };
export type TestChoice = { id: string; code: string; name: string; price: number };
export type InvoiceRow = {
  id: string;
  invoice_number: string;
  patient_name: string;
  created_at: string;
  total: number;
  paid: number;
  balance: number;
  status: string;
};
export type SampleRow = {
  id: string;
  barcode: string;
  status: string;
  rejection_reason: string | null;
  order_item_id: string;
  assigned_technician_id: string | null;
  assigned_doctor_id: string | null;
  order_status: string;
  patient_name: string;
  patient_code: string;
  test_name: string;
};
export type OrderChoice = {
  id: string;
  patient_name: string;
  patient_code: string;
  test_name: string;
  status: string;
};
export type ReportRow = {
  id: string;
  order_item_id: string;
  result_text: string;
  status: string;
  patient_name: string;
  patient_code: string;
  test_name: string;
  entered_by: string | null;
  attachments: ReportAttachmentRow[];
};
export type ReportAttachmentRow = {
  file_id: string;
  report_result_id: string;
  file_name: string;
  mime_type: string;
  file_size_bytes: number;
  scanner_name: string;
  created_at: string;
};
export type RecordRow = {
  id: string;
  kind: "doctor" | "reagent" | "expense";
  label: string;
  secondary: string;
  fields: Record<string, string | number | null | undefined>;
};
export type StaffRow = {
  user_id: string;
  full_name: string;
  phone: string | null;
  role: string;
  active: boolean;
  page_keys: string[];
};
export type PrintRequestRow = {
  id: string;
  invoice_id: string;
  invoice_number: string;
  requested_by: string;
  status: string;
  decision_reason: string | null;
  created_at: string;
};
export type TrashRow = {
  item_id: string;
  item_kind: string;
  item_name: string;
  archived_at: string;
};
export type AppointmentRow = {
  appointment_id: string;
  patient_id: string;
  patient_name: string;
  patient_code: string;
  starts_at: string;
  ends_at: string;
  status: string;
  reason: string | null;
};
export type WorkingHourRow = {
  weekday: number;
  opens_at: string;
  closes_at: string;
  closed: boolean;
};
export type ScheduleResourceRow = {
  resource_id: string;
  name: string;
  resource_type: string;
  active: boolean;
};
export type ScheduleStaffChoice = {
  staff_id: string;
  full_name: string;
};
export type ResourceBookingRow = {
  booking_id: string;
  resource_id: string;
  resource_name: string;
  starts_at: string;
  ends_at: string;
};
export type StaffShiftRow = {
  shift_id: string;
  staff_id: string;
  staff_name: string;
  starts_at: string;
  ends_at: string;
  status: "scheduled" | "leave";
};
export type ReagentMovementRow = {
  movement_id: string;
  reagent_id: string;
  reagent_name: string;
  movement_type: string;
  quantity_delta: number;
  quantity_before: number;
  quantity_after: number;
  note: string;
  reference: string | null;
  created_by_name: string;
  created_at: string;
};

const availablePages = [
  ["dashboard", "Dashboard"], ["test_billing", "Test billing"], ["tests", "Tests"],
  ["departments", "Departments"], ["appointments", "Appointments"], ["scheduling", "Scheduling"],
  ["samples", "Samples"], ["patients", "Patients"],
  ["reports", "Reports"], ["invoice_history", "Invoice history"],
  ["referring_doctors", "Referring doctors"], ["reagent_stock", "Reagent stock"],
  ["expenses", "Expenses"], ["analytics", "Analytics"], ["manage_users", "Manage users"],
  ["print_requests", "Print requests"], ["my_print_requests", "My print requests"],
  ["settings", "Settings"], ["trash_bin", "Trash bin"], ["help", "Help"],
] as const;

const defaultPages: Record<string, string[]> = {
  lab_admin: availablePages.map(([key]) => key),
  lab_manager: ["dashboard", "tests", "departments", "appointments", "scheduling", "samples", "reports", "referring_doctors", "reagent_stock", "analytics", "help"],
  receptionist: ["dashboard", "test_billing", "patients", "appointments", "samples", "invoice_history", "my_print_requests", "help"],
  technician: ["dashboard", "samples", "reports", "help"],
  billing_staff: ["dashboard", "invoice_history", "patients", "expenses", "analytics", "help"],
  reporting_doctor: ["dashboard", "reports", "patients", "help"],
};

function ActionMessage({ state }: { state: { error: string | null; success: string | null } }) {
  return (
    <>
      {state.error && <p className="patient-form-message is-error" role="alert">{state.error}</p>}
      {state.success && <p className="patient-form-message" role="status">{state.success}</p>}
    </>
  );
}

export function InvoiceBuilder({
  patients,
  tests,
}: {
  patients: PatientChoice[];
  tests: TestChoice[];
}) {
  const [state, action, pending] = useActionState(createLabInvoice, emptyWorkflow);
  return (
    <section className="workspace-card">
      <p className="workspace-eyebrow">New visit</p>
      <h2>Create invoice</h2>
      {patients.length === 0 || tests.length === 0 ? (
        <p className="patient-empty">Add an active patient and catalog test before billing.</p>
      ) : (
        <form action={action} className="patient-form">
          <ActionMessage state={state} />
          <label className="patient-form-full">
            Patient
            <select name="patientId" required defaultValue="">
              <option value="" disabled>Select patient</option>
              {patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.label}</option>)}
            </select>
          </label>
          <fieldset className="workspace-choice-list patient-form-full">
            <legend>Tests</legend>
            {tests.map((test) => (
              <label className="workspace-choice-row" key={test.id}>
                <input type="checkbox" name="serviceIds" value={test.id} />
                <span>{test.name} ({test.code})</span>
                <strong>{Number(test.price).toFixed(2)}</strong>
              </label>
            ))}
          </fieldset>
          <label>
            Discount
            <input name="discount" type="number" min="0" step="0.01" defaultValue="0" />
          </label>
          <label>
            Discount reason
            <input name="discountReason" maxLength={240} />
          </label>
          <label>
            Initial payment
            <input name="initialPayment" type="number" min="0" step="0.01" defaultValue="0" />
          </label>
          <label>
            Payment method
            <select name="paymentMethod" defaultValue="cash">
              <option value="cash">Cash</option><option value="card">Card</option>
              <option value="bank_transfer">Bank transfer</option>
              <option value="mobile_wallet">Mobile wallet</option><option value="other">Other</option>
            </select>
          </label>
          <button type="submit" className="workspace-primary-button patient-form-full" disabled={pending}>
            {pending ? "Creating…" : "Create invoice"}
          </button>
        </form>
      )}
    </section>
  );
}

export function AppointmentsManager({
  appointments,
  patients,
  timezone,
  canManage,
}: {
  appointments: AppointmentRow[];
  patients: PatientChoice[];
  timezone: string;
  canManage: boolean;
}) {
  return (
    <div className="workspace-module-grid">
      {canManage && (
        <section className="workspace-card">
          <p className="workspace-eyebrow">Patient scheduling</p>
          <h2>New appointment</h2>
          <AppointmentForm patients={patients} />
        </section>
      )}
      <section className="workspace-card">
        <p className="workspace-eyebrow">Next 30 days</p>
        <h2>Appointments</h2>
        <div className="workspace-record-list">
          {appointments.length === 0 && <p className="patient-empty">No appointments in this date range.</p>}
          {appointments.map((appointment) => (
            <article className="workspace-record-card" key={appointment.appointment_id}>
              <div className="workspace-record-row">
                <span>
                  <strong>{appointment.patient_name} · {appointment.patient_code}</strong>
                  <small>
                    {new Intl.DateTimeFormat("en", {
                      dateStyle: "medium", timeStyle: "short", timeZone: timezone,
                    }).format(new Date(appointment.starts_at))}
                    {" – "}
                    {new Intl.DateTimeFormat("en", {
                      timeStyle: "short", timeZone: timezone,
                    }).format(new Date(appointment.ends_at))}
                  </small>
                </span>
                <span className="workspace-status">{appointment.status}</span>
              </div>
              {appointment.reason && <p className="workspace-page-description">{appointment.reason}</p>}
              {canManage && appointment.status === "scheduled" && (
                <CancelAppointmentForm appointmentId={appointment.appointment_id} />
              )}
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

function AppointmentForm({ patients }: { patients: PatientChoice[] }) {
  const [state, action, pending] = useActionState(createLabAppointment, emptyWorkflow);
  return (
    <form action={action} className="patient-form">
      <label className="patient-form-full">Patient
        <select name="patientId" required defaultValue="">
          <option value="" disabled>Select patient</option>
          {patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.label}</option>)}
        </select>
      </label>
      <label>Starts<input name="startsAt" type="datetime-local" required /></label>
      <label>Ends<input name="endsAt" type="datetime-local" required /></label>
      <label className="patient-form-full">Reason<input name="reason" maxLength={240} /></label>
      <ActionMessage state={state} />
      <button className="workspace-primary-button patient-form-full" type="submit" disabled={pending}>
        {pending ? "Scheduling…" : "Schedule appointment"}
      </button>
    </form>
  );
}

function CancelAppointmentForm({ appointmentId }: { appointmentId: string }) {
  const [state, action, pending] = useActionState(cancelLabAppointment, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="appointmentId" value={appointmentId} />
      <input name="reason" maxLength={240} minLength={2} placeholder="Cancellation reason" required />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Cancelling…" : "Cancel appointment"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function ScheduleSettings({
  hours,
  resources,
  resourceBookings,
  staffChoices,
  staffShifts,
  timezone,
  canManage,
}: {
  hours: WorkingHourRow[];
  resources: ScheduleResourceRow[];
  resourceBookings: ResourceBookingRow[];
  staffChoices: ScheduleStaffChoice[];
  staffShifts: StaffShiftRow[];
  timezone: string;
  canManage: boolean;
}) {
  const byWeekday = new Map(hours.map((hour) => [hour.weekday, hour]));
  return (
    <>
      <section className="workspace-card">
        <h2>Laboratory working hours</h2>
        <div className="workspace-record-list">
          {Array.from({ length: 7 }, (_, weekday) => (
            <WorkingHourForm key={weekday} weekday={weekday} value={byWeekday.get(weekday)} canManage={canManage} />
          ))}
        </div>
      </section>
      <section className="workspace-card">
        <h2>Resources</h2>
        {canManage && <ResourceCreateForm />}
        <div className="workspace-record-list">
          {resources.length === 0 ? <p className="patient-empty">No resources are configured.</p> : resources.map((resource) => (
            <div className="workspace-record-row" key={resource.resource_id}>
              <strong>{resource.name}</strong>
              <span>{resource.resource_type} · {resource.active ? "Active" : "Inactive"}</span>
              {canManage && <ResourceStatusForm resource={resource} />}
            </div>
          ))}
        </div>
        {canManage && <ResourceBookingForm resources={resources.filter((resource) => resource.active)} />}
        <div className="workspace-record-list">
          <h3>Upcoming resource bookings</h3>
          {resourceBookings.length === 0 ? <p className="patient-empty">No upcoming resource bookings.</p> : resourceBookings.map((booking) => (
            <div className="workspace-record-row" key={booking.booking_id}>
              <strong>{booking.resource_name}</strong>
              <span>{formatScheduleTime(booking.starts_at, timezone)} – {formatScheduleTime(booking.ends_at, timezone)}</span>
              {canManage && <ResourceBookingCancelForm bookingId={booking.booking_id} />}
            </div>
          ))}
        </div>
      </section>
      <section className="workspace-card">
        <h2>Staff shifts</h2>
        {canManage && <StaffShiftForm staff={staffChoices} />}
        <div className="workspace-record-list">
          {staffShifts.length === 0 ? <p className="patient-empty">No upcoming staff shifts.</p> : staffShifts.map((shift) => (
            <div className="workspace-record-row" key={shift.shift_id}>
              <strong>{shift.staff_name || "Staff member"}</strong>
              <span>{shift.status === "leave" ? "Leave" : "Scheduled"} · {formatScheduleTime(shift.starts_at, timezone)} – {formatScheduleTime(shift.ends_at, timezone)}</span>
              {canManage && <StaffShiftCancelForm shiftId={shift.shift_id} />}
            </div>
          ))}
        </div>
      </section>
    </>
  );
}

function formatScheduleTime(value: string, timezone: string) {
  return new Intl.DateTimeFormat("en", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone,
  }).format(new Date(value));
}

function ResourceCreateForm() {
  const [state, action, pending] = useActionState(createLabResource, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <label>Resource name<input name="name" maxLength={80} required /></label>
      <label>Type<input name="resourceType" maxLength={60} placeholder="Room, analyzer, collection station" required /></label>
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Adding…" : "Add resource"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function ResourceStatusForm({ resource }: { resource: ScheduleResourceRow }) {
  const [state, action, pending] = useActionState(setLabResourceActive, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="resourceId" value={resource.resource_id} />
      <input type="hidden" name="active" value={resource.active ? "false" : "true"} />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : resource.active ? "Deactivate" : "Activate"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function ResourceBookingForm({ resources }: { resources: ScheduleResourceRow[] }) {
  const [state, action, pending] = useActionState(createLabResourceBooking, emptyWorkflow);
  if (resources.length === 0) return <p className="patient-empty">Add an active resource before booking it.</p>;
  return (
    <form action={action} className="workspace-inline-form">
      <label>Resource
        <select name="resourceId" required defaultValue="">
          <option value="" disabled>Select resource</option>
          {resources.map((resource) => <option key={resource.resource_id} value={resource.resource_id}>{resource.name}</option>)}
        </select>
      </label>
      <label>Starts<input name="startsAt" type="datetime-local" required /></label>
      <label>Ends<input name="endsAt" type="datetime-local" required /></label>
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Booking…" : "Book resource"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function ResourceBookingCancelForm({ bookingId }: { bookingId: string }) {
  const [state, action, pending] = useActionState(cancelLabResourceBooking, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="bookingId" value={bookingId} />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Cancelling…" : "Cancel booking"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function StaffShiftForm({ staff }: { staff: ScheduleStaffChoice[] }) {
  const [state, action, pending] = useActionState(createLabStaffShift, emptyWorkflow);
  if (staff.length === 0) return <p className="patient-empty">Invite an active staff member before scheduling a shift.</p>;
  return (
    <form action={action} className="workspace-inline-form">
      <label>Staff member
        <select name="staffId" required defaultValue="">
          <option value="" disabled>Select staff</option>
          {staff.map((member) => <option key={member.staff_id} value={member.staff_id}>{member.full_name || member.staff_id}</option>)}
        </select>
      </label>
      <label>Starts<input name="startsAt" type="datetime-local" required /></label>
      <label>Ends<input name="endsAt" type="datetime-local" required /></label>
      <label>Type
        <select name="status" defaultValue="scheduled">
          <option value="scheduled">Scheduled shift</option>
          <option value="leave">Leave</option>
        </select>
      </label>
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : "Add shift"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function StaffShiftCancelForm({ shiftId }: { shiftId: string }) {
  const [state, action, pending] = useActionState(cancelLabStaffShift, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="shiftId" value={shiftId} />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Cancelling…" : "Cancel shift"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function WorkingHourForm({
  weekday,
  value,
  canManage,
}: {
  weekday: number;
  value?: WorkingHourRow;
  canManage: boolean;
}) {
  const [state, action, pending] = useActionState(saveWorkingHour, emptyWorkflow);
  const day = new Date(Date.UTC(2024, 0, 7 + weekday)).toLocaleDateString("en", { weekday: "long", timeZone: "UTC" });
  if (!canManage) {
    return (
      <div className="workspace-record-row">
        <strong>{day}</strong><span>{value?.closed ? "Closed" : `${value?.opens_at?.slice(0, 5) ?? "Not set"} – ${value?.closes_at?.slice(0, 5) ?? "Not set"}`}</span>
      </div>
    );
  }
  return (
    <form action={action} className="workspace-inline-form workspace-hours-form">
      <input type="hidden" name="weekday" value={weekday} />
      <strong>{day}</strong>
      <label>Open<input name="opensAt" type="time" defaultValue={value?.opens_at?.slice(0, 5) ?? "09:00"} /></label>
      <label>Close<input name="closesAt" type="time" defaultValue={value?.closes_at?.slice(0, 5) ?? "17:00"} /></label>
      <label className="workspace-check-row">
        <input name="closed" type="checkbox" value="true" defaultChecked={value?.closed ?? weekday > 4} />
        Closed
      </label>
      <input type="hidden" name="closed" value="false" />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function PaymentForm({ invoice }: { invoice: InvoiceRow }) {
  const [state, action, pending] = useActionState(recordInvoicePayment, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="invoiceId" value={invoice.id} />
      <input name="amount" type="number" min="0.01" max={invoice.balance} step="0.01" defaultValue={invoice.balance} required aria-label="Payment amount" />
      <select name="method" defaultValue="cash" aria-label="Payment method">
        <option value="cash">Cash</option><option value="card">Card</option>
        <option value="bank_transfer">Bank transfer</option><option value="mobile_wallet">Mobile wallet</option>
        <option value="other">Other</option>
      </select>
      <input name="reference" maxLength={120} placeholder="Reference (optional)" aria-label="Payment reference" />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : "Record payment"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function InvoiceHistory({
  invoices,
  canPay,
  canRequestPrint,
}: {
  invoices: InvoiceRow[];
  canPay: boolean;
  canRequestPrint: boolean;
}) {
  return (
    <section className="workspace-card">
      <div className="workspace-record-list">
        {invoices.length === 0 && <p className="patient-empty">No invoices found for this laboratory.</p>}
        {invoices.map((invoice) => (
          <article className="workspace-record-card" key={invoice.id}>
            <div className="workspace-record-row">
              <span>
                <strong>{invoice.invoice_number}</strong>
                <small>{invoice.patient_name} · {new Date(invoice.created_at).toLocaleDateString()}</small>
              </span>
              <span>
                <strong>{invoice.status}</strong>
                <small>Total {Number(invoice.total).toFixed(2)} · Paid {Number(invoice.paid).toFixed(2)} · Due {Number(invoice.balance).toFixed(2)}</small>
              </span>
            </div>
            {canPay && invoice.balance > 0 && <PaymentForm invoice={invoice} />}
            <a className="workspace-secondary-button print-link" href={`/lab/print/invoice/${invoice.id}`}>
              Print / Save as PDF
            </a>
            {canRequestPrint && <PrintRequestForm invoiceId={invoice.id} />}
          </article>
        ))}
      </div>
    </section>
  );
}

function PrintRequestForm({ invoiceId }: { invoiceId: string }) {
  const [state, action, pending] = useActionState(createPrintRequest, emptyAdmin);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="invoiceId" value={invoiceId} />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Submitting…" : "Request print"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function SampleQueue({
  samples,
  assignableStaff,
  canAssign,
  canUpdate,
}: {
  samples: SampleRow[];
  assignableStaff: StaffRow[];
  canAssign: boolean;
  canUpdate: boolean;
}) {
  return (
    <section className="workspace-card">
      <div className="workspace-record-list">
        {samples.length === 0 && <p className="patient-empty">No sample work is available for your role.</p>}
        {samples.map((sample) => (
          <article className="workspace-record-card" key={sample.id}>
            <div className="workspace-record-row">
              <span>
                <strong>{sample.barcode} · {sample.test_name}</strong>
                <small>{sample.patient_name} ({sample.patient_code}) · Order: {sample.order_status}</small>
              </span>
              <span className={`workspace-status status-${sample.status}`}>{sample.status.replaceAll("_", " ")}</span>
            </div>
            {canAssign && (
              <AssignOrderForm
                sample={sample}
                technicians={assignableStaff.filter((staff) => staff.role === "technician" && staff.active)}
                doctors={assignableStaff.filter((staff) => staff.role === "reporting_doctor" && staff.active)}
              />
            )}
            {sample.rejection_reason && <p className="workspace-page-description">Reason: {sample.rejection_reason}</p>}
            {canUpdate && sample.status === "pending" && <SampleTransitionForm sample={sample} options={["collected", "rejected"]} />}
            {canUpdate && sample.status === "rejected" && <SampleTransitionForm sample={sample} options={["recollected"]} />}
            {canUpdate && sample.status !== "pending" && sample.order_status === "sample_collected" && (
              <OrderTransitionForm orderItemId={sample.order_item_id} status="in_progress" label="Start processing" />
            )}
          </article>
        ))}
      </div>
    </section>
  );
}

function SampleTransitionForm({ sample, options }: { sample: SampleRow; options: string[] }) {
  const [state, action, pending] = useActionState(transitionSample, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="sampleId" value={sample.id} />
      <select name="status" defaultValue={options[0]} aria-label="Sample status">
        {options.map((option) => <option key={option} value={option}>{option.replaceAll("_", " ")}</option>)}
      </select>
      <input name="reason" placeholder="Reason if rejecting" maxLength={240} aria-label="Rejection reason" />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : "Update"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function OrderTransitionForm({
  orderItemId,
  status,
  label,
}: {
  orderItemId: string;
  status: string;
  label: string;
}) {
  const [state, action, pending] = useActionState(transitionOrder, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="orderItemId" value={orderItemId} />
      <input type="hidden" name="status" value={status} />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : label}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

function AssignOrderForm({
  sample,
  technicians,
  doctors,
}: {
  sample: SampleRow;
  technicians: StaffRow[];
  doctors: StaffRow[];
}) {
  const [state, action, pending] = useActionState(assignOrder, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="orderItemId" value={sample.order_item_id} />
      <select name="technicianId" defaultValue={sample.assigned_technician_id ?? ""} aria-label="Assign technician">
        <option value="">Unassigned technician</option>
        {technicians.map((staff) => <option key={staff.user_id} value={staff.user_id}>{staff.full_name}</option>)}
      </select>
      <select name="doctorId" defaultValue={sample.assigned_doctor_id ?? ""} aria-label="Assign reporting doctor">
        <option value="">Unassigned doctor</option>
        {doctors.map((staff) => <option key={staff.user_id} value={staff.user_id}>{staff.full_name}</option>)}
      </select>
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : "Assign"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function ReportsWorkspace({
  reports,
  eligibleOrders,
  canUpload,
  canReview,
  canPublish,
}: {
  reports: ReportRow[];
  eligibleOrders: OrderChoice[];
  canUpload: boolean;
  canReview: boolean;
  canPublish: boolean;
}) {
  return (
    <div className="workspace-module-grid">
      {canUpload && eligibleOrders.map((order) => order.status === "in_progress"
        ? <ResultEntryForm key={order.id} order={order} />
        : <section className="workspace-card" key={order.id}>
            <p className="workspace-eyebrow">Resume result entry</p>
            <h2>{order.test_name}</h2>
            <p className="workspace-page-description">{order.patient_name} ({order.patient_code})</p>
            <OrderTransitionForm
              orderItemId={order.id}
              status="in_progress"
              label="Resume processing"
            />
          </section>)}
      <section className="workspace-card">
        <p className="workspace-eyebrow">Clinical workflow</p>
        <h2>Results and review</h2>
        <div className="workspace-record-list">
          {reports.length === 0 && <p className="patient-empty">No report results are available for your assignments.</p>}
          {reports.map((report) => (
            <article className="workspace-record-card" key={report.id}>
              <div className="workspace-record-row">
                <span>
                  <strong>{report.test_name} · {report.status.replaceAll("_", " ")}</strong>
                  <small>{report.patient_name} ({report.patient_code})</small>
                </span>
              </div>
              <pre className="workspace-result-text">{report.result_text}</pre>
              {report.attachments.length > 0 && (
                <ul className="workspace-file-list">
                  {report.attachments.map((file) => (
                    <li key={file.file_id}>
                      <a href={`/lab/attachments/${file.file_id}`} rel="noreferrer">
                        {file.file_name}
                      </a>
                      <small>{(Number(file.file_size_bytes) / 1024 / 1024).toFixed(2)} MB · malware scan clean</small>
                    </li>
                  ))}
                </ul>
              )}
              {canUpload && report.status !== "published" && (
                <ReportAttachmentForm reportResultId={report.id} />
              )}
              {canReview && report.status === "entered" && (
                <ReviewForm reportResultId={report.id} />
              )}
              {canPublish && report.status === "approved" && (
                <PublishForm reportResultId={report.id} />
              )}
              {report.status === "published" && (
                <a className="workspace-secondary-button print-link" href={`/lab/print/report/${report.id}`}>
                  Print / Save as PDF
                </a>
              )}
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

function ReportAttachmentForm({ reportResultId }: { reportResultId: string }) {
  const [state, action, pending] = useActionState<ReportFileActionState, FormData>(
    uploadReportAttachment,
    { error: null, success: null },
  );
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="reportResultId" value={reportResultId} />
      <label>Attach report file
        <input name="file" type="file" accept="application/pdf,image/jpeg,image/png" required />
      </label>
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Scanning and uploading…" : "Scan and attach"}
      </button>
      {state.error && <p className="patient-form-message is-error" role="alert">{state.error}</p>}
      {state.success && <p className="patient-form-message" role="status">{state.success}</p>}
    </form>
  );
}

function ResultEntryForm({ order }: { order: OrderChoice }) {
  const [state, action, pending] = useActionState(saveReportResult, emptyWorkflow);
  return (
    <section className="workspace-card">
      <p className="workspace-eyebrow">Result entry</p>
      <h2>{order.test_name}</h2>
      <p className="workspace-page-description">{order.patient_name} ({order.patient_code})</p>
      <form action={action} className="patient-form">
        <input type="hidden" name="orderItemId" value={order.id} />
        <label className="patient-form-full">
          Result text
          <textarea name="resultText" minLength={1} maxLength={10000} required />
        </label>
        <ActionMessage state={state} />
        <button className="workspace-primary-button patient-form-full" type="submit" disabled={pending}>
          {pending ? "Submitting…" : "Send for review"}
        </button>
      </form>
    </section>
  );
}

function ReviewForm({ reportResultId }: { reportResultId: string }) {
  const [state, action, pending] = useActionState(reviewReportResult, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="reportResultId" value={reportResultId} />
      <button className="workspace-primary-button" name="decision" value="approved" disabled={pending}>Approve</button>
      <button className="workspace-secondary-button" name="decision" value="changes_required" disabled={pending}>Request changes</button>
      <ActionMessage state={state} />
    </form>
  );
}

function PublishForm({ reportResultId }: { reportResultId: string }) {
  const [state, action, pending] = useActionState(publishReportResult, emptyWorkflow);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="reportResultId" value={reportResultId} />
      <button className="workspace-primary-button" type="submit" disabled={pending}>
        {pending ? "Publishing…" : "Publish secure link"}
      </button>
      <Feedback state={state} />
    </form>
  );
}

type FieldDefinition = {
  name: string;
  label: string;
  type?: "text" | "number" | "date" | "email" | "textarea" | "select";
  options?: { value: string; label: string }[];
  required?: boolean;
  step?: string;
};

function RecordEditor({
  kind,
  fields,
  rows,
}: {
  kind: RecordRow["kind"];
  fields: FieldDefinition[];
  rows: RecordRow[];
}) {
  const [selected, setSelected] = useState<RecordRow | null>(null);
  const [state, action, pending] = useActionState(saveLabCatalogItem, emptyCatalog);
  return (
    <div className="workspace-module-grid">
      <section className="workspace-card">
        <div className="workspace-card-heading">
          <div><p className="workspace-eyebrow">Laboratory records</p><h2>{kind === "doctor" ? "Referring doctors" : kind === "reagent" ? "Reagent stock" : "Expenses"}</h2></div>
          <button type="button" className="workspace-secondary-button" onClick={() => setSelected(null)}>New</button>
        </div>
        <div className="workspace-record-list">
          {rows.length === 0 && <p className="patient-empty">No records yet.</p>}
          {rows.map((row) => (
            <article className="workspace-record-card" key={row.id}>
              <div className="workspace-record-row">
                <span><strong>{row.label}</strong><small>{row.secondary}</small></span>
                <div className="workspace-inline-buttons">
                  <button type="button" className="workspace-secondary-button" onClick={() => setSelected(row)}>Edit</button>
                  <ArchiveForm kind={kind} id={row.id} />
                </div>
              </div>
              {kind === "reagent" && <ReagentMovementForm reagentId={row.id} />}
            </article>
          ))}
        </div>
      </section>
      <section className="workspace-card">
        <p className="workspace-eyebrow">{selected ? "Edit record" : "New record"}</p>
        <h2>{kind === "doctor" ? "Doctor details" : kind === "reagent" ? "Reagent details" : "Expense details"}</h2>
        <form action={action} className="patient-form">
          <input type="hidden" name="kind" value={kind} />
          {selected && <input type="hidden" name="id" value={selected.id} />}
          <ActionMessage state={state} />
          {fields.map((field) => {
            const value = selected?.fields[field.name] ?? "";
            if (field.type === "select") {
              return (
                <label key={field.name}>
                  {field.label}
                  <select name={field.name} defaultValue={String(value || field.options?.[0]?.value || "")} required={field.required}>
                    {field.options?.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                  </select>
                </label>
              );
            }
            if (field.type === "textarea") {
              return <label className="patient-form-full" key={field.name}>{field.label}<textarea name={field.name} maxLength={500} defaultValue={String(value)} required={field.required} /></label>;
            }
            return (
              <label key={field.name}>
                {field.label}
                <input
                  name={field.name}
                  type={field.type ?? "text"}
                  min={field.type === "number" ? "0" : undefined}
                  step={field.step}
                  defaultValue={String(value)}
                  required={field.required}
                />
              </label>
            );
          })}
          <button className="workspace-primary-button patient-form-full" type="submit" disabled={pending}>
            {pending ? "Saving…" : selected ? "Update record" : "Add record"}
          </button>
        </form>
      </section>
    </div>
  );
}

function ArchiveForm({ kind, id }: { kind: string; id: string }) {
  const [state, action, pending] = useActionState(archiveLabItem, emptyAdmin);
  return (
    <form action={action}>
      <input type="hidden" name="kind" value={kind} />
      <input type="hidden" name="id" value={id} />
      <button className="workspace-secondary-button" type="submit" disabled={pending} aria-label="Archive record">
        {pending ? "…" : "Archive"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function DoctorsManager({ rows }: { rows: RecordRow[] }) {
  return <RecordEditor kind="doctor" rows={rows} fields={[
    { name: "name", label: "Full name", required: true },
    { name: "clinic", label: "Clinic" }, { name: "phone", label: "Phone" },
    { name: "email", label: "Email", type: "email" }, { name: "specialty", label: "Specialty" },
    { name: "commissionPercent", label: "Commission percent", type: "number", step: "0.01" },
    { name: "address", label: "Address" },
  ]} />;
}

export function ReagentsManager({
  rows,
  movements,
  canManage,
}: {
  rows: RecordRow[];
  movements: ReagentMovementRow[];
  canManage: boolean;
}) {
  return (
    <div className="workspace-module-grid">
      {canManage ? (
        <RecordEditor kind="reagent" rows={rows} fields={[
          { name: "name", label: "Reagent", required: true },
          { name: "reorderLevel", label: "Reorder level", type: "number", step: "0.01" },
          { name: "expiryDate", label: "Expiry date", type: "date" },
          { name: "supplier", label: "Supplier" }, { name: "batchNumber", label: "Batch number" },
          { name: "unitPrice", label: "Unit price", type: "number", step: "0.01" }, { name: "storage", label: "Storage" },
        ]} />
      ) : (
        <section className="workspace-card">
          <h2>Reagent stock</h2>
          <div className="workspace-record-list">
            {rows.length === 0 ? <p className="patient-empty">No reagent records are available.</p> : rows.map((row) => (
              <div className="workspace-record-row" key={row.id}>
                <strong>{row.label}</strong><span>{row.secondary}</span>
              </div>
            ))}
          </div>
        </section>
      )}
      <section className="workspace-card">
        <h2>Stock movement history</h2>
        <div className="workspace-record-list">
          {movements.length === 0 ? <p className="patient-empty">No stock movements have been recorded.</p> : movements.map((movement) => (
            <article className="workspace-record-card" key={movement.movement_id}>
              <div className="workspace-record-row">
                <span>
                  <strong>{movement.reagent_name} · {movement.movement_type.replaceAll("_", " ")}</strong>
                  <small>{movement.created_by_name || "Staff"} · {new Date(movement.created_at).toLocaleString()}</small>
                </span>
                <span>
                  <strong>{movement.quantity_delta > 0 ? "+" : ""}{Number(movement.quantity_delta).toFixed(2)}</strong>
                  <small>{Number(movement.quantity_before).toFixed(2)} → {Number(movement.quantity_after).toFixed(2)}</small>
                </span>
              </div>
              <p>{movement.note}{movement.reference ? ` · Ref: ${movement.reference}` : ""}</p>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}

function ReagentMovementForm({ reagentId }: { reagentId: string }) {
  const [state, action, pending] = useActionState(recordReagentMovement, emptyCatalog);
  return (
    <form action={action} className="workspace-inline-form reagent-movement-form">
      <input type="hidden" name="reagentId" value={reagentId} />
      <label>Movement
        <select name="movementType" defaultValue="received">
          <option value="received">Received</option>
          <option value="used">Used</option>
          <option value="adjustment_increase">Adjustment increase</option>
          <option value="adjustment_decrease">Adjustment decrease</option>
        </select>
      </label>
      <label>Quantity<input name="quantity" type="number" min="0.01" step="0.01" required /></label>
      <label>Note<input name="note" minLength={2} maxLength={240} required /></label>
      <label>Reference<input name="reference" maxLength={80} /></label>
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Recording…" : "Record movement"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function ExpensesManager({ rows }: { rows: RecordRow[] }) {
  return <RecordEditor kind="expense" rows={rows} fields={[
    { name: "name", label: "Category", required: true },
    { name: "note", label: "Description", type: "textarea", required: true },
    { name: "expenseDate", label: "Date", type: "date" },
    { name: "amount", label: "Amount", type: "number", step: "0.01", required: true },
    { name: "paidVia", label: "Paid via", type: "select", options: [
      { value: "cash", label: "Cash" }, { value: "bank_transfer", label: "Bank transfer" },
      { value: "card", label: "Card" }, { value: "other", label: "Other" },
    ] },
    { name: "receiptNumber", label: "Receipt number" },
  ]} />;
}

export function AnalyticsCards({ values }: { values: Record<string, string | number | null> }) {
  const metrics = [
    ["Patients", values.patients], ["Visits", values.visits], ["Pending samples", values.pending_samples],
    ["Pending reports", values.pending_reports], ["Revenue", values.revenue],
    ["Outstanding", values.outstanding], ["Expenses", values.expenses], ["Estimated margin", values.estimated_margin],
  ];
  return (
    <section className="workspace-stat-grid workspace-analytics-grid">
      {metrics.map(([label, value]) => (
        <article className="workspace-stat-card" key={String(label)}>
          <p>{label}</p>
          <strong>{value === null || value === undefined ? "Restricted" : typeof value === "number" ? value.toLocaleString() : value}</strong>
        </article>
      ))}
      <p className="workspace-page-description">{values.margin_note}</p>
    </section>
  );
}

export function StaffManager({ staff }: { staff: StaffRow[] }) {
  return (
    <div className="workspace-module-grid">
      <section className="workspace-card">
        <p className="workspace-eyebrow">Team administration</p>
        <h2>Invite staff</h2>
        <InviteStaffForm />
      </section>
      <section className="workspace-card">
        <p className="workspace-eyebrow">Memberships</p>
        <h2>Staff and access</h2>
        <div className="workspace-record-list">
          {staff.map((member) => <StaffAccessForm key={member.user_id} member={member} />)}
          {staff.length === 0 && <p className="patient-empty">No staff memberships found.</p>}
        </div>
      </section>
    </div>
  );
}

function InviteStaffForm() {
  const [state, action, pending] = useActionState(inviteLabStaff, emptyAdmin);
  const [role, setRole] = useState("receptionist");
  const [selectedPages, setSelectedPages] = useState(defaultPages.receptionist);

  function changeRole(value: string) {
    setRole(value);
    setSelectedPages(defaultPages[value] ?? []);
  }

  return (
    <form action={action} className="patient-form">
      <label>Full name<input name="fullName" minLength={2} maxLength={120} required /></label>
      <label>Email<input name="email" type="email" required /></label>
      <label>Phone<input name="phone" type="tel" maxLength={32} /></label>
      <label>Initial role
        <select name="role" value={role} onChange={(event) => changeRole(event.target.value)}>
          {Object.keys(defaultPages).map((value) => <option key={value} value={value}>{value.replaceAll("_", " ")}</option>)}
        </select>
      </label>
      <fieldset className="workspace-choice-list patient-form-full">
        <legend>Initial page access</legend>
        {availablePages.map(([key, label]) => (
          <label className="workspace-check-row" key={key}>
            <input
              type="checkbox"
              name="pageKeys"
              value={key}
              checked={selectedPages.includes(key)}
              onChange={(event) => setSelectedPages((current) =>
                event.target.checked
                  ? [...current, key]
                  : current.filter((page) => page !== key),
              )}
            />
            {label}
          </label>
        ))}
      </fieldset>
      <ActionMessage state={state} />
      <button className="workspace-primary-button patient-form-full" type="submit" disabled={pending}>
        {pending ? "Sending invitation…" : "Send invitation"}
      </button>
    </form>
  );
}

function StaffAccessForm({ member }: { member: StaffRow }) {
  const [state, action, pending] = useActionState(updateStaffAccess, emptyAdmin);
  const [activeState, activeAction, activePending] = useActionState(setStaffActive, emptyAdmin);
  const [role, setRole] = useState(member.role);
  const rolePages = defaultPages[member.role] ?? defaultPages.receptionist;
  return (
    <article className="workspace-record-card">
      <strong>{member.full_name || "Invited staff"}</strong>
      <small>{member.role.replaceAll("_", " ")} · {member.active ? "Active" : "Inactive"}{member.phone ? ` · ${member.phone}` : ""}</small>
      <form action={action} className="patient-form">
        <input type="hidden" name="userId" value={member.user_id} />
        <label>Role
          <select name="role" value={role} onChange={(event) => setRole(event.target.value)}>
            {Object.keys(defaultPages).map((value) => <option key={value} value={value}>{value.replaceAll("_", " ")}</option>)}
          </select>
        </label>
        <fieldset className="workspace-choice-list patient-form-full">
          <legend>Page access</legend>
          {availablePages.map(([key, label]) => (
            <label className="workspace-check-row" key={key}>
              <input type="checkbox" name="pageKeys" value={key} defaultChecked={member.page_keys.includes(key) || (member.page_keys.length === 0 && rolePages.includes(key))} />
              {label}
            </label>
          ))}
        </fieldset>
        <button className="workspace-secondary-button patient-form-full" type="submit" disabled={pending}>
          {pending ? "Saving…" : "Save access"}
        </button>
        <ActionMessage state={state} />
      </form>
      <form action={activeAction} className="workspace-inline-form">
        <input type="hidden" name="userId" value={member.user_id} />
        <input type="hidden" name="active" value={String(!member.active)} />
        <button className="workspace-secondary-button" type="submit" disabled={activePending}>
          {activePending ? "Updating…" : member.active ? "Deactivate" : "Activate"}
        </button>
        <ActionMessage state={activeState} />
      </form>
    </article>
  );
}

export function SettingsForm({
  values,
}: {
  values: {
    name: string;
    city: string;
    phone: string;
    email: string;
    address: string;
    currency: string;
    timezone: string;
    receipt_format: string;
    receipt_footer: string;
  };
}) {
  const [state, action, pending] = useActionState(saveLabSettings, emptyAdmin);
  return (
    <section className="workspace-card">
      <form action={action} className="patient-form">
        <ActionMessage state={state} />
        <label>Laboratory name<input name="name" defaultValue={values.name} required /></label>
        <label>City<input name="city" defaultValue={values.city} /></label>
        <label>Phone<input name="phone" defaultValue={values.phone} /></label>
        <label>Email<input name="email" type="email" defaultValue={values.email} /></label>
        <label className="patient-form-full">Address<input name="address" defaultValue={values.address} /></label>
        <label>Currency<input name="currency" defaultValue={values.currency} minLength={3} maxLength={3} required /></label>
        <label>Timezone<input name="timezone" defaultValue={values.timezone} required /></label>
        <label>Receipt format
          <select name="receiptFormat" defaultValue={values.receipt_format}>
            <option value="thermal_80mm">Thermal 80mm</option><option value="a4_lab_memo">A4 lab memo</option>
          </select>
        </label>
        <label className="patient-form-full">Receipt footer<textarea name="receiptFooter" maxLength={500} defaultValue={values.receipt_footer} /></label>
        <button className="workspace-primary-button patient-form-full" type="submit" disabled={pending}>
          {pending ? "Saving…" : "Save settings"}
        </button>
      </form>
    </section>
  );
}

export function RetentionPolicyForm({
  retentionDays,
  legalHoldEnabled,
  canManage,
}: {
  retentionDays: number;
  legalHoldEnabled: boolean;
  canManage: boolean;
}) {
  const [state, action, pending] = useActionState(saveRetentionPolicy, emptyAdmin);
  if (!canManage) {
    return (
      <section className="workspace-card">
        <h2>Data retention</h2>
        <p>Policy: {retentionDays} days · Legal hold {legalHoldEnabled ? "enabled" : "disabled"}</p>
        <p className="workspace-page-description">Clinical records are not automatically deleted by this policy.</p>
      </section>
    );
  }
  return (
    <section className="workspace-card">
      <h2>Data retention policy</h2>
      <p className="workspace-page-description">
        Set the laboratory’s retention target and legal hold. This setting does not automatically delete clinical records.
      </p>
      <form action={action} className="patient-form">
        <ActionMessage state={state} />
        <label>Retention period (days)
          <input name="retentionDays" type="number" min={365} max={36500} step={1} defaultValue={retentionDays} required />
        </label>
        <label className="workspace-check-row">
          <input name="legalHoldEnabled" type="checkbox" value="true" defaultChecked={legalHoldEnabled} />
          Legal hold enabled
        </label>
        <input type="hidden" name="legalHoldEnabled" value="false" />
        <button className="workspace-primary-button patient-form-full" type="submit" disabled={pending}>
          {pending ? "Saving…" : "Save retention policy"}
        </button>
      </form>
    </section>
  );
}

export function PrintRequests({
  requests,
  canReview,
}: {
  requests: PrintRequestRow[];
  canReview: boolean;
}) {
  return (
    <section className="workspace-card">
      <div className="workspace-record-list">
        {requests.length === 0 && <p className="patient-empty">No print requests found.</p>}
        {requests.map((request) => (
          <article className="workspace-record-card" key={request.id}>
            <div className="workspace-record-row">
              <span><strong>{request.invoice_number}</strong><small>Requested {new Date(request.created_at).toLocaleString()}</small></span>
              <strong>{request.status}</strong>
            </div>
            {request.decision_reason && <p>{request.decision_reason}</p>}
            {canReview && request.status === "pending" && (
              <PrintDecisionForm requestId={request.id} />
            )}
          </article>
        ))}
      </div>
    </section>
  );
}

function PrintDecisionForm({ requestId }: { requestId: string }) {
  const [state, action, pending] = useActionState(reviewPrintRequest, emptyAdmin);
  return (
    <form action={action} className="workspace-inline-form">
      <input type="hidden" name="requestId" value={requestId} />
      <select name="decision" defaultValue="approved">
        <option value="approved">Approve</option><option value="rejected">Reject</option>
      </select>
      <input name="reason" maxLength={240} placeholder="Reason if rejecting" />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save decision"}
      </button>
      <ActionMessage state={state} />
    </form>
  );
}

export function TrashBin({ items }: { items: TrashRow[] }) {
  return (
    <section className="workspace-card">
      <div className="workspace-record-list">
        {items.length === 0 && <p className="patient-empty">The trash bin is empty.</p>}
        {items.map((item) => (
          <article className="workspace-record-row" key={`${item.item_kind}:${item.item_id}`}>
            <span><strong>{item.item_name}</strong><small>{item.item_kind} · archived {new Date(item.archived_at).toLocaleDateString()}</small></span>
            <RestoreForm id={item.item_id} kind={item.item_kind} />
          </article>
        ))}
      </div>
    </section>
  );
}

function RestoreForm({ id, kind }: { id: string; kind: string }) {
  const [state, action, pending] = useActionState(restoreLabItem, emptyAdmin);
  return (
    <form action={action}>
      <input type="hidden" name="id" value={id} /><input type="hidden" name="kind" value={kind} />
      <button className="workspace-secondary-button" type="submit" disabled={pending}>Restore</button>
      <ActionMessage state={state} />
    </form>
  );
}
