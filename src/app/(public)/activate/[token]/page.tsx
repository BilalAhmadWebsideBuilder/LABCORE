import { ShieldCheck } from "lucide-react";

export default function ActivatePage() {
  return <main className="deep-ocean flex min-h-screen items-center justify-center px-5 text-[#F1FBFA]"><form className="w-full max-w-md rounded-2xl border border-white/10 bg-[#0B2229] p-8 shadow-2xl"><div className="mb-5 flex h-12 w-12 items-center justify-center rounded-full bg-[#A7F3D0]/10 text-[#A7F3D0]"><ShieldCheck /></div><h1 className="font-heading text-2xl font-bold">Activate your LabCore account</h1><p className="mt-2 text-sm text-[#9FB8BC]">Create a password to securely access your patient portal.</p><label className="mt-6 block text-sm font-semibold">New password<input type="password" autoComplete="new-password" required className="mt-2 h-11 w-full rounded-lg border border-[#1A4250] bg-[#10303A] px-3" /></label><button className="brand-gradient mt-5 h-11 w-full rounded-lg text-sm font-bold text-[#04222A]">Activate account</button></form></main>;
}
