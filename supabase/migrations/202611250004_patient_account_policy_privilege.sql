revoke all on public.patient_accounts from public, anon;
grant select on public.patient_accounts to authenticated;

drop policy if exists patient_account_read on public.patient_accounts;
create policy patient_account_read on public.patient_accounts
  for select to authenticated using (
    not public.is_platform_developer()
    and (
      public.has_lab_permission(lab_id, 'patients.read')
      or user_id = (select auth.uid())
    )
  );
