import { Activity, CalendarDays, CreditCard, FlaskConical, Plus, Search, UserPlus } from "lucide-react";

const metrics = [
  { label: "Appointments today", value: "24", change: "4 remaining", icon: CalendarDays, tone: "text-[#0891B2]" },
  { label: "Tests in progress", value: "18", change: "6 awaiting review", icon: FlaskConical, tone: "text-[#0284C7]" },
  { label: "Outstanding", value: "Rs. 42,750", change: "12 invoices", icon: CreditCard, tone: "text-[#D97706]" },
  { label: "Reports published", value: "31", change: "Today", icon: Activity, tone: "text-[#16A34A]" },
];

export default function LabDashboard() {
  return (
    <main className="min-h-screen bg-[#F6F9FA] p-4 text-[#0A1A1F] lg:p-8">
      <div className="mx-auto max-w-7xl">
        <header className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div><p className="text-sm text-[#4A5A60]">Monday, 23 November</p><h1 className="mt-1 font-heading text-3xl font-bold">Good morning, Lab team</h1></div>
          <div className="flex gap-2">
            <button className="flex h-11 items-center gap-2 rounded-lg border border-[#DCE6E8] bg-white px-4 text-sm font-bold"><Search size={18} />Search</button>
            <button className="brand-gradient flex h-11 items-center gap-2 rounded-lg px-4 text-sm font-bold text-[#04222A]"><Plus size={18} />New patient</button>
          </div>
        </header>
        <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {metrics.map(({ label, value, change, icon: Icon, tone }) => (
            <article key={label} className="rounded-xl border border-[#DCE6E8] bg-white p-5">
              <div className="flex items-start justify-between"><div><p className="text-sm text-[#4A5A60]">{label}</p><p className="mono mt-2 text-2xl font-bold">{value}</p></div><Icon className={tone} size={22} /></div>
              <p className="mt-3 text-xs text-[#4A5A60]">{change}</p>
            </article>
          ))}
        </section>
        <section className="mt-6 grid gap-6 lg:grid-cols-[2fr_1fr]">
          <article className="rounded-xl border border-[#DCE6E8] bg-white p-5">
            <div className="flex items-center justify-between"><h2 className="font-heading text-lg font-bold">Today&apos;s appointments</h2><button className="text-sm font-bold text-[#0A7490]">View calendar</button></div>
            <div className="mt-5 space-y-3">
              {[["09:00","Ayesha Khan","CBC + Lipid Profile","Checked in"],["09:30","Muhammad Ali","Ultrasound abdomen","Waiting"],["10:15","Sara Ahmed","X-ray chest","Scheduled"]].map(([time,name,test,status]) => (
                <div key={name} className="grid grid-cols-[60px_1fr_auto] items-center gap-3 rounded-lg border border-[#EDF3F4] p-3">
                  <span className="mono text-sm font-bold">{time}</span><div><p className="font-semibold">{name}</p><p className="text-xs text-[#4A5A60]">{test}</p></div><span className="rounded-full bg-[#ECFEFB] px-2 py-1 text-xs font-bold text-[#0A7490]">{status}</span>
                </div>
              ))}
            </div>
          </article>
          <aside className="rounded-xl border border-[#DCE6E8] bg-white p-5">
            <h2 className="font-heading text-lg font-bold">Quick actions</h2>
            <div className="mt-4 grid gap-2">
              {[["Register patient",UserPlus],["Search patients",Search],["Record payment",CreditCard],["New booking",CalendarDays]].map(([label, Icon]) => (
                <button key={String(label)} className="flex h-12 items-center gap-3 rounded-lg border border-[#DCE6E8] px-3 text-sm font-semibold hover:bg-[#F6F9FA]">{typeof Icon === "function" ? <Icon size={18} /> : null}<span>{String(label)}</span></button>
              ))}
            </div>
          </aside>
        </section>
      </div>
    </main>
  );
}
