"use client";

import { useActionState, useState } from "react";
import { saveLabCatalogItem, type CatalogActionState } from "@/app/actions/catalog";

type Department = { id: string; name: string; sort_order: number };
type Test = {
  id: string;
  category_id: string | null;
  code: string;
  name: string;
  description: string | null;
  service_type: string;
  price: number;
  duration_minutes: number;
  turnaround_minutes: number | null;
  preparation_instructions: string | null;
  fasting_required: boolean;
  method: string | null;
  normal_range: string | null;
  patient_visible: boolean;
};

const initialState: CatalogActionState = { error: null, success: null };

function CatalogFormMessage({ state }: { state: CatalogActionState }) {
  return (
    <>
      {state.error && <p className="patient-form-message is-error" role="alert">{state.error}</p>}
      {state.success && <p className="patient-form-message" role="status">{state.success}</p>}
    </>
  );
}

function DepartmentForm({
  selected,
  canManage,
}: {
  selected: Department | null;
  canManage: boolean;
}) {
  const [state, action, pending] = useActionState(saveLabCatalogItem, initialState);

  if (!canManage) return null;

  return (
    <form action={action} className="patient-form">
      <input type="hidden" name="kind" value="category" />
      {selected && <input type="hidden" name="id" value={selected.id} />}
      <CatalogFormMessage state={state} />
      <label>
        Department name
        <input name="name" defaultValue={selected?.name ?? ""} maxLength={80} required />
      </label>
      <label>
        Display order
        <input name="sortOrder" type="number" min="0" max="10000" defaultValue={selected?.sort_order ?? 0} />
      </label>
      <div className="patient-form-actions patient-form-full">
        <button type="submit" className="workspace-primary-button" disabled={pending}>
          {pending ? "Saving…" : selected ? "Update department" : "Add department"}
        </button>
      </div>
    </form>
  );
}

function TestForm({
  selected,
  departments,
  canManage,
}: {
  selected: Test | null;
  departments: Department[];
  canManage: boolean;
}) {
  const [state, action, pending] = useActionState(saveLabCatalogItem, initialState);

  if (!canManage) return null;

  return (
    <form action={action} className="patient-form">
      <input type="hidden" name="kind" value="test" />
      {selected && <input type="hidden" name="id" value={selected.id} />}
      <CatalogFormMessage state={state} />
      <label>
        Test code
        <input name="code" defaultValue={selected?.code ?? ""} maxLength={32} required />
      </label>
      <label>
        Test name
        <input name="name" defaultValue={selected?.name ?? ""} maxLength={120} required />
      </label>
      <label>
        Department
        <select name="categoryId" defaultValue={selected?.category_id ?? ""}>
          <option value="">Unassigned</option>
          {departments.map((department) => (
            <option key={department.id} value={department.id}>{department.name}</option>
          ))}
        </select>
      </label>
      <label>
        Test type
        <select name="serviceType" defaultValue={selected?.service_type ?? "laboratory"}>
          <option value="laboratory">Laboratory</option>
          <option value="xray">X-ray</option>
          <option value="ultrasound">Ultrasound</option>
          <option value="ecg">ECG</option>
          <option value="other">Other</option>
        </select>
      </label>
      <label>
        Price
        <input name="price" type="number" min="0" step="0.01" defaultValue={selected?.price ?? 0} required />
      </label>
      <label>
        Duration (minutes)
        <input name="durationMinutes" type="number" min="1" defaultValue={selected?.duration_minutes ?? 15} required />
      </label>
      <label>
        Turnaround (minutes)
        <input name="turnaroundMinutes" type="number" min="1" defaultValue={selected?.turnaround_minutes ?? ""} />
      </label>
      <label>
        Method
        <input name="method" maxLength={120} defaultValue={selected?.method ?? ""} />
      </label>
      <label className="patient-form-full">
        Description
        <textarea name="description" maxLength={500} defaultValue={selected?.description ?? ""} />
      </label>
      <label className="patient-form-full">
        Preparation instructions
        <textarea name="preparationInstructions" maxLength={500} defaultValue={selected?.preparation_instructions ?? ""} />
      </label>
      <label className="patient-form-full">
        Normal range
        <textarea name="normalRange" maxLength={240} defaultValue={selected?.normal_range ?? ""} />
      </label>
      <label>
        Fasting required
        <select name="fastingRequired" defaultValue={selected?.fasting_required ? "true" : "false"}>
          <option value="false">No</option>
          <option value="true">Yes</option>
        </select>
      </label>
      <label>
        Patient-visible
        <select name="patientVisible" defaultValue={selected?.patient_visible === false ? "false" : "true"}>
          <option value="true">Yes</option>
          <option value="false">No</option>
        </select>
      </label>
      <div className="patient-form-actions patient-form-full">
        <button type="submit" className="workspace-primary-button" disabled={pending}>
          {pending ? "Saving…" : selected ? "Update test" : "Add test"}
        </button>
      </div>
    </form>
  );
}

export function CatalogManager({
  departments,
  tests,
  canManage,
}: {
  departments: Department[];
  tests: Test[];
  canManage: boolean;
}) {
  const [selectedDepartment, setSelectedDepartment] = useState<Department | null>(null);
  const [selectedTest, setSelectedTest] = useState<Test | null>(null);

  return (
    <div className="workspace-module-grid">
      <section className="workspace-card">
        <div className="workspace-card-heading">
          <div>
            <p className="workspace-eyebrow">Organization</p>
            <h2>Departments</h2>
          </div>
          {canManage && (
            <button type="button" className="workspace-secondary-button" onClick={() => setSelectedDepartment(null)}>
              New department
            </button>
          )}
        </div>
        <div className="workspace-record-list">
          {departments.length === 0 && <p className="patient-empty">No departments yet.</p>}
          {departments.map((department) => (
            <div className="workspace-record-row" key={department.id}>
              <span><strong>{department.name}</strong><small>Display order {department.sort_order}</small></span>
              {canManage && (
                <button type="button" className="workspace-secondary-button" onClick={() => setSelectedDepartment(department)}>
                  Edit
                </button>
              )}
            </div>
          ))}
        </div>
        {canManage && (
          <DepartmentForm
            key={selectedDepartment?.id ?? "new-department"}
            selected={selectedDepartment}
            canManage={canManage}
          />
        )}
      </section>

      <section className="workspace-card">
        <div className="workspace-card-heading">
          <div>
            <p className="workspace-eyebrow">Service catalog</p>
            <h2>Tests and services</h2>
          </div>
          {canManage && (
            <button type="button" className="workspace-secondary-button" onClick={() => setSelectedTest(null)}>
              New test
            </button>
          )}
        </div>
        <div className="workspace-record-list">
          {tests.length === 0 && <p className="patient-empty">No active tests yet.</p>}
          {tests.map((test) => (
            <div className="workspace-record-row" key={test.id}>
              <span>
                <strong>{test.name} <small>({test.code})</small></strong>
                <small>{test.service_type} · {Number(test.price).toFixed(2)} · {test.duration_minutes} min</small>
              </span>
              {canManage && (
                <button type="button" className="workspace-secondary-button" onClick={() => setSelectedTest(test)}>
                  Edit
                </button>
              )}
            </div>
          ))}
        </div>
        {canManage && (
          <TestForm
            key={selectedTest?.id ?? "new-test"}
            selected={selectedTest}
            departments={departments}
            canManage={canManage}
          />
        )}
      </section>
    </div>
  );
}
