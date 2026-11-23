import { CalendarDays, Download, FileCheck2, FlaskConical, MapPin } from "lucide-react";

export default function PatientPortal() {
  return (
    <main className="min-h-screen bg-[#F6F9FA] pb-24 text-[#0A1A1F]">
      <header className="deep-ocean px-5 pb-10 pt-7 text-[#F1FBFA]">
        <div className="mx-auto max-w-3xl">
          <p className="text-sm text-[#9FB8BC]">Welcome back</p>
          <h1 className="mt-1 font-heading text-2xl font-bold">Ayesha Khan</h1>
        </div>
      </header>
        <div className="mx-auto -mt-6 max-w-3xl px-4">
          <section className="rounded-xl border border-[#DCE6E8] bg-white p-5 shadow-sm">
            <div className="flex items-start gap-3"><div className="rounded-lg bg-[#ECFEFB] p-3 text-[#0891B2]"><CalendarDays size={22} /></div><div className="flex-1"><p className="text-xs font-bold uppercase tracking-wide text-[#0891B2]">Next appointment</p><h2 className="mt-1 font-heading text-lg font-bold">CBC + Lipid Profile</h2><p className="mt-2 text-sm text-[#4A5A60]">Today · 09:00 AM</p><p className="mt-1 flex items-center gap-1 text-sm text-[#4A5A60]"><MapPin size={14} />Central Lab, Reception</p></div></div>
            <button className="mt-5 h-11 w-full rounded-lg border border-[#DCE6E8] text-sm font-bold text-[#0A7490]">Reschedule request</button>
          </section>
          <section className="mt-6"><h2 className="font-heading text-lg font-bold">Test status</h2><div className="mt-3 rounded-xl border border-[#DCE6E8] bg-white p-5"><div className="flex items-center gap-3"><div className="rounded-full bg-[#ECFEFB] p-2 text-[#0891B2]"><FlaskConical size={20} /></div><div><p className="font-semibold">CBC</p><p className="text-sm text-[#4A5A60]">Your sample is being processed.</p></div></div><div className="mt-5 h-2 overflow-hidden rounded-full bg-[#EDF3F4]"><div className="h-full w-3/4 rounded-full bg-[#0891B2]" /></div></div></section>
          <section className="mt-6"><h2 className="font-heading text-lg font-bold">Reports</h2><article className="mt-3 flex items-center justify-between rounded-xl border border-[#DCE6E8] bg-white p-4"><div className="flex items-center gap-3"><div className="rounded-lg bg-[#16A34A]/10 p-2 text-[#16A34A]"><FileCheck2 size={20} /></div><div><p className="font-semibold">Lipid Profile</p><p className="text-xs text-[#4A5A60]">Available 21 Nov 2026</p></div></div><button aria-label="Download Lipid Profile report" className="brand-gradient flex h-11 w-11 items-center justify-center rounded-lg text-[#04222A]"><Download size={18} /></button></article></section>
        </div>
    </main>
  );
}
