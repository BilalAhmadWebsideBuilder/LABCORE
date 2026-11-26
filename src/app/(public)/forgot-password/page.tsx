"use client";

import { useActionState } from "react";
import Link from "next/link";
import { requestPasswordReset, type PasswordActionState } from "@/app/actions/auth";

const initialState: PasswordActionState = { error: null, success: null };

export default function ForgotPasswordPage() {
  const [state, formAction, pending] = useActionState(requestPasswordReset, initialState);

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#F6F9FA] px-5">
      <section className="card w-full max-w-md rounded-2xl p-8">
        <h1 className="font-heading text-2xl font-bold">Password help</h1>
        <p className="mt-3 text-sm text-[#4A5A60]">
          Enter your registered email to request a password-reset link.
        </p>
        <form action={formAction} className="mt-6 grid gap-4">
          {state.error && <p role="alert" className="patient-form-message is-error">{state.error}</p>}
          {state.success && <p role="status" className="patient-form-message">{state.success}</p>}
          <label className="block text-sm font-semibold">
            Email address
            <input
              name="email"
              type="email"
              autoComplete="email"
              required
              className="mt-2 h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 text-base outline-none"
              placeholder="name@lab.com"
            />
          </label>
          <button
            type="submit"
            disabled={pending}
            className="brand-gradient h-12 rounded-lg text-sm font-bold text-[#04222A] disabled:opacity-70"
          >
            {pending ? "Sending…" : "Send reset link"}
          </button>
        </form>
        <Link
          href="/login"
          className="mt-6 block text-center text-sm font-bold text-[#0A7490]"
        >
          Back to sign in
        </Link>
      </section>
    </main>
  );
}
