"use client";

export function PrintButton() {
  return (
    <button className="workspace-primary-button print-toolbar" type="button" onClick={() => window.print()}>
      Print / Save as PDF
    </button>
  );
}
