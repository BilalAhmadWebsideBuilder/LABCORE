"use client";

import { useActionState, useState } from "react";
import Link from "next/link";
import {
  Activity,
  Check,
  Eye,
  EyeOff,
  HeartPulse,
  LockKeyhole,
  ShieldCheck,
  UserRound,
} from "lucide-react";
import { patientSignIn, signIn, type SignInState } from "@/app/actions/auth";
import { Logo } from "@/components/brand/Logo";

const initialState: SignInState = { error: null };

export default function LoginPage() {
  const [role, setRole] = useState<"staff" | "patient">("staff");
  const [showPassword, setShowPassword] = useState(false);
  const [state, formAction, isPending] = useActionState(signIn, initialState);
  const [patientState, patientFormAction, patientPending] = useActionState(patientSignIn, initialState);

  return (
    <main className="grid min-h-screen lg:grid-cols-[55%_45%]">
      <section className="deep-ocean relative hidden overflow-hidden p-12 text-[#F1FBFA] lg:flex lg:flex-col lg:justify-between">
        <div className="absolute -left-24 top-16 h-64 w-64 rounded-full border border-[#2DD4BF]/10" />
        <div className="absolute bottom-20 right-10 h-40 w-40 rounded-full border border-[#A7F3D0]/10" />
        <Logo variant="horizontal" theme="dark" className="max-w-[200px]" />
        <div className="mx-auto flex w-full max-w-xl flex-col items-center text-center">
          <div className="mb-8 w-44 drop-shadow-[0_0_18px_rgba(45,212,191,.25)]">
            <Logo loading className="w-full" />
          </div>
          <h1 className="font-heading text-4xl font-bold leading-tight">
            Accurate results.
            <br />
            Trusted care.
          </h1>
          <div className="mt-8 grid w-full grid-cols-3 gap-3 text-sm">
            <div className="rounded-xl border border-white/10 bg-white/[.04] p-4">
              <ShieldCheck className="mx-auto mb-2 text-[#A7F3D0]" size={20} />
              <span>Secure records</span>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/[.04] p-4">
              <Activity className="mx-auto mb-2 text-[#A7F3D0]" size={20} />
              <span>Faster reports</span>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/[.04] p-4">
              <HeartPulse className="mx-auto mb-2 text-[#A7F3D0]" size={20} />
              <span>Patient-friendly</span>
            </div>
          </div>
        </div>
        <div className="flex justify-between text-xs text-[#9FB8BC]">
          <span>LabCore v1.0</span>
          <Link className="hover:text-[#5EE0D1]" href="/status">
            System status
          </Link>
        </div>
      </section>

      <section className="flex min-h-screen items-center justify-center bg-[var(--background)] px-5 py-8 sm:px-10">
        <div className="card w-full max-w-md rounded-2xl p-6 shadow-xl sm:p-8">
          <div className="mb-7 lg:hidden">
            <Logo variant="horizontal" theme="light" />
          </div>
          <h2 className="font-heading text-3xl font-bold text-[#0A1A1F] dark:text-[#E8F6F5]">
            Welcome back
          </h2>
          <p className="mt-2 text-sm text-[#4A5A60] dark:text-[#9FB8BC]">
            Sign in to continue to LabCore.
          </p>

          <div
            className="mt-6 grid grid-cols-2 rounded-lg border border-[var(--border)] p-1"
            role="tablist"
            aria-label="Sign-in role"
          >
            <button
              type="button"
              role="tab"
              aria-selected={role === "staff"}
              onClick={() => setRole("staff")}
              className={`flex h-10 items-center justify-center gap-2 rounded-md text-sm font-semibold ${
                role === "staff"
                  ? "bg-[#ECFEFB] text-[#0A7490]"
                  : "text-[#4A5A60]"
              }`}
            >
              <LockKeyhole size={16} />
              Staff &amp; Doctors
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={role === "patient"}
              onClick={() => setRole("patient")}
              className={`flex h-10 items-center justify-center gap-2 rounded-md text-sm font-semibold ${
                role === "patient"
                  ? "bg-[#ECFEFB] text-[#0A7490]"
                  : "text-[#4A5A60]"
              }`}
            >
              <UserRound size={16} />
              Patients
            </button>
          </div>

          {role === "staff" ? (
            <form action={formAction} className="mt-6 space-y-5">
              {state.error && (
                <div
                  role="alert"
                  className="rounded-lg border border-[#DC2626]/20 bg-[#DC2626]/10 p-3 text-sm text-[#991B1B]"
                >
                  {state.error}
                </div>
              )}
              <label
                htmlFor="email"
                className="block text-sm font-semibold"
              >
                Email address
                <input
                  id="email"
                  name="email"
                  type="email"
                  autoFocus
                  autoComplete="username"
                  required
                  className="mt-2 h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 text-base outline-none dark:bg-[#10303A]"
                  placeholder="name@lab.com"
                />
              </label>
              <label
                htmlFor="password"
                className="block text-sm font-semibold"
              >
                Password
                <div className="relative mt-2">
                  <input
                    id="password"
                    name="password"
                    type={showPassword ? "text" : "password"}
                    autoComplete="current-password"
                    required
                    className="h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 pr-11 text-base outline-none dark:bg-[#10303A]"
                    placeholder="Enter your password"
                  />
                  <button
                    type="button"
                    aria-label={showPassword ? "Hide password" : "Show password"}
                    onClick={() => setShowPassword((value) => !value)}
                    className="absolute inset-y-0 end-0 flex w-11 items-center justify-center text-[#4A5A60]"
                  >
                    {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </label>
              <div className="text-right text-sm">
                <Link
                  href="/forgot-password"
                  className="font-semibold text-[#0A7490] dark:text-[#5EE0D1]"
                >
                  Forgot password?
                </Link>
              </div>
              <button
                type="submit"
                disabled={isPending}
                className="brand-gradient flex h-12 w-full items-center justify-center gap-2 rounded-lg text-sm font-bold text-[#04222A] shadow-[0_0_24px_rgba(45,212,191,.28)] disabled:cursor-not-allowed disabled:opacity-70"
              >
                {isPending ? (
                  <>
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-[#04222A]/30 border-t-[#04222A]" />
                    Signing in…
                  </>
                ) : (
                  <>
                    <Check size={18} />
                    Sign in
                  </>
                )}
              </button>
            </form>
          ) : (
            <form action={patientFormAction} className="mt-6 space-y-5" role="tabpanel">
              {patientState.error && (
                <div role="alert" className="rounded-lg border border-[#DC2626]/20 bg-[#DC2626]/10 p-3 text-sm text-[#991B1B]">
                  {patientState.error}
                </div>
              )}
              <p className="text-sm text-[#4A5A60] dark:text-[#9FB8BC]">
                Use the email and password provided when your laboratory activated your portal account.
              </p>
              <label htmlFor="patient-email" className="block text-sm font-semibold">
                Email address
                <input
                  id="patient-email"
                  name="email"
                  type="email"
                  autoComplete="username"
                  required
                  className="mt-2 h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 text-base outline-none dark:bg-[#10303A]"
                  placeholder="you@example.com"
                />
              </label>
              <label htmlFor="patient-password" className="block text-sm font-semibold">
                Password
                <div className="relative mt-2">
                  <input
                    id="patient-password"
                    name="password"
                    type={showPassword ? "text" : "password"}
                    autoComplete="current-password"
                    required
                    className="h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 pr-11 text-base outline-none dark:bg-[#10303A]"
                    placeholder="Enter your password"
                  />
                  <button
                    type="button"
                    aria-label={showPassword ? "Hide password" : "Show password"}
                    onClick={() => setShowPassword((value) => !value)}
                    className="absolute inset-y-0 end-0 flex w-11 items-center justify-center text-[#4A5A60]"
                  >
                    {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </div>
              </label>
              <div className="text-right text-sm">
                <Link href="/forgot-password" className="font-semibold text-[#0A7490] dark:text-[#5EE0D1]">
                  Forgot password?
                </Link>
              </div>
              <button
                type="submit"
                disabled={patientPending}
                className="brand-gradient flex h-12 w-full items-center justify-center gap-2 rounded-lg text-sm font-bold text-[#04222A] shadow-[0_0_24px_rgba(45,212,191,.28)] disabled:cursor-not-allowed disabled:opacity-70"
              >
                {patientPending ? "Signing in…" : "Sign in to patient portal"}
              </button>
            </form>
          )}
        </div>
      </section>
    </main>
  );
}
