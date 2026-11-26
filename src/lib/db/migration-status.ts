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
    return "Database permissions or required LabCore migrations are incomplete. Apply migrations 001–016 in order, then sign in again and verify that the authenticated account has an active lab membership and role grant.";
  }

  return "A required LabCore database migration is not installed. Apply the migrations in order from docs/DATABASE.md.";
}
