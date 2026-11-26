"use client";

import { useActionState } from "react";
import Link from "next/link";
import { updatePassword, type PasswordActionState } from "@/app/actions/auth";

const initialState: PasswordActionState = { error: null, success: null };

export default function ResetPasswordPage() {
  const [state, formAction, pending] = useActionState(updatePassword, initialState);

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#F6F9FA] px-5">
      <section className="card w-full max-w-md rounded-2xl p-8">
        <h1 className="font-heading text-2xl font-bold">Set a new password</h1>
        <p className="mt-3 text-sm text-[#4A5A60]">Use at least 8 characters.</p>
        <form action={formAction} className="mt-6 grid gap-4">
          {state.error && <p role="alert" className="patient-form-message is-error">{state.error}</p>}
          {state.success && <p role="status" className="patient-form-message">{state.success}</p>}
          <label className="block text-sm font-semibold">
            New password
            <input
              name="password"
              type="password"
              autoComplete="new-password"
              required
              minLength={8}
              className="mt-2 h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 text-base outline-none"
            />
          </label>
          <label className="block text-sm font-semibold">
            Confirm password
            <input
              name="confirmation"
              type="password"
              autoComplete="new-password"
              required
              minLength={8}
              className="mt-2 h-11 w-full rounded-lg border border-[var(--border)] bg-white px-3 text-base outline-none"
            />
          </label>
          <button
            type="submit"
            disabled={pending}
            className="brand-gradient h-12 rounded-lg text-sm font-bold text-[#04222A] disabled:opacity-70"
          >
            {pending ? "Updating…" : "Update password"}
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
