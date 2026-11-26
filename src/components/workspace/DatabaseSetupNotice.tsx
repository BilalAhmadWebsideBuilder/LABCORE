export function DatabaseSetupNotice({ message }: { message: string }) {
  return (
    <aside className="workspace-setup-notice" role="status">
      <strong>Database setup incomplete</strong>
      <p>{message}</p>
    </aside>
  );
}
