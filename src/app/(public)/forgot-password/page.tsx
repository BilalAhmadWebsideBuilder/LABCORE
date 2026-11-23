import Link from "next/link";

export default function ForgotPasswordPage() {
  return <main className="flex min-h-screen items-center justify-center bg-[#F6F9FA] px-5"><form className="card w-full max-w-md rounded-2xl p-8"><h1 className="font-heading text-2xl font-bold">Reset your password</h1><p className="mt-2 text-sm text-[#4A5A60]">Enter your email and we’ll send you a secure reset link.</p><label className="mt-6 block text-sm font-semibold">Email address<input type="email" required className="mt-2 h-11 w-full rounded-lg border border-[#DCE6E8] px-3" /></label><button className="brand-gradient mt-5 h-11 w-full rounded-lg text-sm font-bold text-[#04222A]">Send reset link</button><Link href="/login" className="mt-5 block text-center text-sm font-bold text-[#0A7490]">Back to sign in</Link></form></main>;
}
