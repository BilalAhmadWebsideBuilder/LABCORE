import "server-only";

type DatabaseError = {
  code?: string;
  message?: string;
};

const migrationErrorCodes = new Set([
  "42P01", "42703", "42883", "42501", "PGRST202", "PGRST204", "PGRST205",
]);

export function getDatabaseSetupMessage(error: DatabaseError): string | null {
  if (!error.code || !migrationErrorCodes.has(error.code)) return null;

  if (error.code === "42501") {
    return "Database permissions are incomplete. Apply the LabCore migrations in order, then check the Supabase grants.";
  }

  return "A required LabCore database migration is not installed. Apply the migrations in order from docs/DATABASE.md.";
}
