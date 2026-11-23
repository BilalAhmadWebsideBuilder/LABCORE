# Assumptions

- Supabase is the production data and authentication backend; the repository does not contain live credentials.
- Seed and demo data must only run in development.
- The initial UI is a functional design/prototype shell. Live Supabase mutations require project-specific configuration and deployment of migrations.
- Patient activation tokens are implemented as opaque random tokens; only hashes may be stored.
