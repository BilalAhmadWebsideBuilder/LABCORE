import { AlertCircle, CheckCircle2, Clock3 } from "lucide-react";

export default function DoctorDashboard() {
  const cases = [
    ["LN-2026-000123","Ayesha Khan","CBC","Overdue","text-[#DC2626]","bg-[#DC2626]/10"],
    ["LN-2026-000124","Muhammad Ali","Lipid Profile","Due today","text-[#D97706]","bg-[#D97706]/10"],
    ["LN-2026-000125","Sara Ahmed","LFT","In review","text-[#0284C7]","bg-[#0284C7]/10"],
  ];
  return (
    <main className="min-h-screen bg-[#F6F9FA] p-4 text-[#0A1A1F] lg:p-8">
      <div className="mx-auto max-w-6xl"><h1 className="font-heading text-3xl font-bold">Review queue</h1><p className="mt-2 text-sm text-[#4A5A60]">Cases assigned to you</p>
      <div className="mt-6 grid gap-3 sm:grid-cols-3">
        {[["Assigned","18",AlertCircle],["Overdue","3",Clock3],["Approved today","7",CheckCircle2]].map(([label,value,Icon]) => {
          const IconComponent = Icon as typeof AlertCircle;
          return <article key={String(label)} className="flex items-center justify-between rounded-xl border border-[#DCE6E8] bg-white p-5"><div><p className="text-sm text-[#4A5A60]">{String(label)}</p><p className="mono mt-1 text-2xl font-bold">{String(value)}</p></div><IconComponent size={22} /></article>;
        })}
      </div>
      <section className="mt-6 overflow-hidden rounded-xl border border-[#DCE6E8] bg-white"><div className="border-b border-[#EDF3F4] p-5 font-heading text-lg font-bold">My cases</div>{cases.map(([code,name,test,status,color,bg]) => <button key={code} className="grid w-full grid-cols-[1fr_auto] gap-3 border-b border-[#EDF3F4] p-5 text-left last:border-0 hover:bg-[#F6F9FA]"><div><p className="mono text-xs text-[#4A5A60]">{code}</p><p className="mt-1 font-semibold">{name}</p><p className="text-sm text-[#4A5A60]">{test}</p></div><span className={`h-fit rounded-full px-3 py-1 text-xs font-bold ${bg} ${color}`}>{status}</span></button>)}</section></div>
    </main>
  );
}
