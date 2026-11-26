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

const invoiceSchema = z.object({
  laboratory: z.object({
    name: z.string(),
    city: z.string().nullable(),
    address: z.string().nullable(),
    phone: z.string().nullable(),
    email: z.string().nullable(),
    receipt_format: z.string().nullable(),
    receipt_footer: z.string().nullable(),
    timezone: z.string().nullable(),
  }),
  patient: z.object({ full_name: z.string(), patient_code: z.string() }),
  invoice: z.object({
    invoice_number: z.string(),
    currency: z.string().length(3),
    subtotal: z.coerce.number(),
    discount: z.coerce.number(),
    tax: z.coerce.number(),
    total: z.coerce.number(),
    status: z.string(),
    created_at: z.string(),
  }),
  items: z.array(z.object({
    description: z.string(),
    quantity: z.coerce.number(),
    unit_price: z.coerce.number(),
    line_total: z.coerce.number(),
  })),
  payments: z.array(z.object({
    amount: z.coerce.number(),
    method: z.string(),
    received_at: z.string(),
    receipt_number: z.string().nullable(),
  })),
});

export default async function InvoicePrintPage({
  params,
}: {
  params: Promise<{ invoiceId: string }>;
}) {
  const { invoiceId } = await params;
  const membership = await requireMembership(LAB_DASHBOARD_ROLES);
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("get_lab_invoice_print", {
    p_lab_id: membership.labId,
    p_invoice_id: invoiceId,
  });
  if (error) {
    if (error.code === "42501") notFound();
    const setupMessage = getDatabaseSetupMessage(error);
    if (setupMessage) return <DatabaseSetupNotice message={setupMessage} />;
    return (
      <div className="public-report-page">
        <PageLoadErrorNotice
          title="Invoice printout unavailable"
          message="We could not load this invoice. Please try again later or contact your laboratory administrator."
        />
      </div>
    );
  }
  const parsed = invoiceSchema.safeParse(data);
  if (!parsed.success) {
    if (data === null) notFound();
    return (
      <div className="public-report-page">
        <PageLoadErrorNotice
          title="Invoice printout unavailable"
          message="The invoice data could not be displayed. Please contact your laboratory administrator."
        />
      </div>
    );
  }

  const { laboratory, patient, invoice, items, payments } = parsed.data;
  const timezone = laboratory.timezone || "UTC";
  const currency = new Intl.NumberFormat("en", { style: "currency", currency: invoice.currency });
  const formatDate = (value: string) => new Intl.DateTimeFormat("en", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone,
  }).format(new Date(value));

  return (
    <div className={`print-document ${laboratory.receipt_format === "thermal_80mm" ? "print-document-thermal" : "print-document-a4"}`}>
      <div className="print-toolbar">
        <PrintButton />
      </div>
      <header className="print-document-heading">
        <h1>{laboratory.name}</h1>
        {[laboratory.address, laboratory.city, laboratory.phone, laboratory.email].filter(Boolean).map((line, index) => (
          <p key={`${line}-${index}`}>{line}</p>
        ))}
        <h2>Invoice / Receipt</h2>
      </header>
      <dl className="print-document-meta">
        <div><dt>Invoice</dt><dd>{invoice.invoice_number}</dd></div>
        <div><dt>Date</dt><dd>{formatDate(invoice.created_at)}</dd></div>
        <div><dt>Status</dt><dd>{invoice.status.replaceAll("_", " ")}</dd></div>
        <div><dt>Patient</dt><dd>{patient.full_name} ({patient.patient_code})</dd></div>
      </dl>
      <table className="print-document-table">
        <thead><tr><th>Item</th><th>Qty</th><th>Unit</th><th>Total</th></tr></thead>
        <tbody>
          {items.map((item, index) => (
            <tr key={`${item.description}-${index}`}>
              <td>{item.description}</td>
              <td>{item.quantity}</td>
              <td>{currency.format(item.unit_price)}</td>
              <td>{currency.format(item.line_total)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <dl className="print-document-totals">
        <div><dt>Subtotal</dt><dd>{currency.format(invoice.subtotal)}</dd></div>
        {invoice.discount > 0 && <div><dt>Discount</dt><dd>−{currency.format(invoice.discount)}</dd></div>}
        {invoice.tax > 0 && <div><dt>Tax</dt><dd>{currency.format(invoice.tax)}</dd></div>}
        <div className="print-document-total"><dt>Total</dt><dd>{currency.format(invoice.total)}</dd></div>
      </dl>
      {payments.length > 0 && (
        <section>
          <h2>Payments</h2>
          <table className="print-document-table">
            <thead><tr><th>Received</th><th>Method</th><th>Receipt</th><th>Amount</th></tr></thead>
            <tbody>{payments.map((payment, index) => (
              <tr key={`${payment.received_at}-${index}`}>
                <td>{formatDate(payment.received_at)}</td>
                <td>{payment.method.replaceAll("_", " ")}</td>
                <td>{payment.receipt_number ?? "—"}</td>
                <td>{currency.format(payment.amount)}</td>
              </tr>
            ))}</tbody>
          </table>
        </section>
      )}
      {laboratory.receipt_footer && <footer className="print-document-footer">{laboratory.receipt_footer}</footer>}
    </div>
  );
}
