export function PageLoadErrorNotice({
  title,
  message,
}: {
  title: string;
  message: string;
}) {
  return (
    <section className="workspace-card" role="alert">
      <h1>{title}</h1>
      <p className="workspace-page-description">{message}</p>
    </section>
  );
}
