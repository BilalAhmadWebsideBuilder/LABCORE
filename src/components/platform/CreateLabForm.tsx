"use client";

import { useActionState } from "react";
import { createLab, type CreateLabState } from "@/app/actions/platform";

const initialState: CreateLabState = { error: null, success: null };

export function CreateLabForm() {
  const [state, formAction, isPending] = useActionState(createLab, initialState);

  return (
    <form action={formAction} className="grid gap-4 sm:grid-cols-2">
      {state.error && (
        <p role="alert" className="sm:col-span-2 rounded-lg bg-red-500/10 p-3 text-sm text-red-200">
          {state.error}
        </p>
      )}
      {state.success && (
        <p role="status" className="sm:col-span-2 rounded-lg bg-emerald-500/10 p-3 text-sm text-emerald-200">
          {state.success}
        </p>
      )}
      <label className="text-sm font-semibold text-[#D6E7E8]">
        Laboratory name
        <input
          name="name"
          required
          minLength={2}
          maxLength={120}
          className="mt-2 h-11 w-full rounded-lg border border-[#1A4250] bg-[#10303A] px-3 text-base outline-none"
          placeholder="Northside Diagnostics"
        />
      </label>
      <label className="text-sm font-semibold text-[#D6E7E8]">
        Slug
        <input
          name="slug"
          required
          maxLength={80}
          pattern="[a-z0-9]+(-[a-z0-9]+)*"
          className="mt-2 h-11 w-full rounded-lg border border-[#1A4250] bg-[#10303A] px-3 text-base outline-none"
          placeholder="northside-diagnostics"
        />
      </label>
      <label className="text-sm font-semibold text-[#D6E7E8]">
        Currency
        <input
          name="currency"
          required
          minLength={3}
          maxLength={3}
          defaultValue="PKR"
          className="mt-2 h-11 w-full rounded-lg border border-[#1A4250] bg-[#10303A] px-3 text-base uppercase outline-none"
          placeholder="PKR"
        />
      </label>
      <label className="text-sm font-semibold text-[#D6E7E8]">
        Timezone
        <input
          name="timezone"
          required
          defaultValue="Asia/Karachi"
          className="mt-2 h-11 w-full rounded-lg border border-[#1A4250] bg-[#10303A] px-3 text-base outline-none"
          placeholder="Asia/Karachi"
        />
      </label>
      <button
        type="submit"
        disabled={isPending}
        className="brand-gradient mt-1 h-11 rounded-lg px-4 text-sm font-bold text-[#04222A] disabled:cursor-not-allowed disabled:opacity-70 sm:col-span-2 sm:justify-self-start"
      >
        {isPending ? "Creating laboratory…" : "Create laboratory"}
      </button>
    </form>
  );
}
