"use client";

import { useActionState, useEffect, useMemo, useState } from "react";
import { Plus, Search, UserRound, X } from "lucide-react";
import { registerPatient, type RegisterPatientState } from "@/app/actions/patients";

export type PatientListItem = {
  id: string;
  patient_code: string;
  full_name: string;
  phone: string | null;
  date_of_birth: string | null;
  gender: string | null;
  created_at: string;
};

const initialState: RegisterPatientState = { error: null, success: null };

function calculateAge(dateOfBirth: string | null) {
  if (!dateOfBirth) return null;
  const birthDate = new Date(`${dateOfBirth}T00:00:00`);
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  if (
    today.getMonth() < birthDate.getMonth() ||
    (today.getMonth() === birthDate.getMonth() && today.getDate() < birthDate.getDate())
  ) {
    age -= 1;
  }
  return age;
}

function PatientRegistrationForm({ onClose }: { onClose: () => void }) {
  const [state, formAction, isPending] = useActionState(registerPatient, initialState);

  useEffect(() => {
    if (state.success) onClose();
  }, [onClose, state.success]);

  return (
    <form action={formAction} className="patient-form">
      {state.error && <p className="patient-form-message is-error" role="alert">{state.error}</p>}
      <label>
        Full name <span aria-hidden="true">*</span>
        <input name="fullName" autoComplete="name" minLength={2} maxLength={120} required />
      </label>
      <label>
        Phone number <span aria-hidden="true">*</span>
        <input name="phone" type="tel" autoComplete="tel" minLength={5} maxLength={32} required />
      </label>
      <label>
        Date of birth
        <input name="dateOfBirth" type="date" />
      </label>
      <label>
        Gender
        <select name="gender" defaultValue="">
          <option value="">Not provided</option>
          <option value="female">Female</option>
          <option value="male">Male</option>
          <option value="other">Other</option>
          <option value="prefer_not_to_say">Prefer not to say</option>
        </select>
      </label>
      <label className="patient-form-full">
        Emergency contact
        <input name="emergencyContact" type="tel" maxLength={120} />
      </label>
      <p className="patient-form-note patient-form-full">
        Only collect information needed for care. National ID is not collected by this form.
      </p>
      <div className="patient-form-actions patient-form-full">
        <button type="button" className="workspace-secondary-button" onClick={onClose}>
          Cancel
        </button>
        <button type="submit" className="workspace-primary-button" disabled={isPending}>
          {isPending ? "Registering…" : "Register patient"}
        </button>
      </div>
    </form>
  );
}

export function PatientDirectory({
  patients,
  canRegister,
}: {
  patients: PatientListItem[];
  canRegister: boolean;
}) {
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState(patients[0]?.id ?? "");
  const [isFormOpen, setIsFormOpen] = useState(false);
  const visiblePatients = useMemo(() => {
    const search = query.trim().toLocaleLowerCase();
    if (!search) return patients;
    return patients.filter((patient) =>
      `${patient.full_name} ${patient.patient_code} ${patient.phone ?? ""}`
        .toLocaleLowerCase()
        .includes(search),
    );
  }, [patients, query]);
  const selectedPatient =
    visiblePatients.find((patient) => patient.id === selectedId) ?? visiblePatients[0];

  return (
    <>
      <section className="patient-directory">
        <div className="patient-list-panel">
          <div className="patient-list-toolbar">
            <label className="patient-search">
              <Search size={17} aria-hidden="true" />
              <span className="sr-only">Search patients</span>
              <input
                id="patient-search"
                type="search"
                placeholder="Search name, ID, or phone"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
              />
            </label>
            <span className="patient-result-count">{visiblePatients.length}</span>
          </div>
          <div className="patient-list" aria-label="Patient records">
            {visiblePatients.length === 0 ? (
              <p className="patient-empty">
                {patients.length === 0
                  ? "No patients are registered in this laboratory yet."
                  : "No patients match your search."}
              </p>
            ) : (
              visiblePatients.map((patient) => (
                <button
                  type="button"
                  key={patient.id}
                  className={`patient-list-item${patient.id === selectedPatient?.id ? " is-selected" : ""}`}
                  onClick={() => setSelectedId(patient.id)}
                >
                  <span className="patient-initial">
                    {patient.full_name.trim().charAt(0).toUpperCase() || <UserRound size={17} />}
                  </span>
                  <span className="patient-list-copy">
                    <strong>{patient.full_name}</strong>
                    <small>{patient.patient_code} · {patient.phone || "No phone"}</small>
                  </span>
                </button>
              ))
            )}
          </div>
        </div>

        <div className="patient-detail-panel">
          {selectedPatient ? (
            <>
              <div className="patient-detail-heading">
                <div>
                  <p className="workspace-eyebrow">Patient record</p>
                  <h2>{selectedPatient.full_name}</h2>
                </div>
                <span className="patient-code">{selectedPatient.patient_code}</span>
              </div>
              <dl className="patient-detail-grid">
                <div><dt>Phone</dt><dd>{selectedPatient.phone || "Not provided"}</dd></div>
                <div><dt>Age</dt><dd>{calculateAge(selectedPatient.date_of_birth) ?? "Not provided"}</dd></div>
                <div><dt>Gender</dt><dd>{selectedPatient.gender?.replaceAll("_", " ") || "Not provided"}</dd></div>
                <div><dt>Registered</dt><dd>{new Intl.DateTimeFormat("en", { dateStyle: "medium" }).format(new Date(selectedPatient.created_at))}</dd></div>
              </dl>
              <p className="patient-detail-note">
                Related visits, invoices, and published results are available in the workspace modules.
              </p>
            </>
          ) : (
            <div className="patient-no-selection">
              <UsersIcon />
              <h2>Select a patient</h2>
              <p>Choose a record from the list to see its details.</p>
            </div>
          )}
        </div>
      </section>

      {canRegister && (
        <button
          type="button"
          className="patient-floating-add workspace-primary-button"
          onClick={() => setIsFormOpen(true)}
        >
          <Plus size={18} />
          Register patient
        </button>
      )}

      {isFormOpen && (
        <div
          className="workspace-modal-backdrop"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setIsFormOpen(false);
          }}
        >
          <section
            className="workspace-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="register-patient-title"
          >
            <div className="workspace-modal-heading">
              <div>
                <p className="workspace-eyebrow">Patient intake</p>
                <h2 id="register-patient-title">Register patient</h2>
              </div>
              <button
                type="button"
                className="workspace-icon-button"
                aria-label="Close registration form"
                onClick={() => setIsFormOpen(false)}
              >
                <X size={18} />
              </button>
            </div>
            <PatientRegistrationForm onClose={() => setIsFormOpen(false)} />
          </section>
        </div>
      )}
    </>
  );
}

function UsersIcon() {
  return <UserRound size={28} aria-hidden="true" />;
}
