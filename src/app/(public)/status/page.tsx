import { CheckCircle2 } from "lucide-react";

export default function StatusPage() {
  return <main className="flex min-h-screen items-center justify-center bg-[#F6F9FA] px-5"><section className="card w-full max-w-lg rounded-2xl p-8 text-center"><CheckCircle2 className="mx-auto text-[#16A34A]" size={40} /><h1 className="mt-4 font-heading text-2xl font-bold">All systems operational</h1><p className="mt-2 text-sm text-[#4A5A60]">LabCore services are healthy.</p></section></main>;
}
