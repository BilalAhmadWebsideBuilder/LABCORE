import Link from "next/link";

export default function ResetPasswordPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-[#F6F9FA] px-5">
      <section className="card w-full max-w-md rounded-2xl p-8">
        <h1 className="font-heading text-2xl font-bold">
          Password reset is not connected yet
        </h1>
        <p className="mt-3 text-sm text-[#4A5A60]">
          Contact your laboratory administrator for help recovering your
          account.
        </p>
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
