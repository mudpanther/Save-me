// Paste your two Supabase values here (Supabase dashboard → Connect, or Project Settings → API Keys).
// For the key, use either the "anon public" key or the "publishable" key. Both are fine here.
// The anon key is meant to be public: row-level security in schema.sql is what keeps
// each person's kingdom private. Never put the service_role key in this file.
window.SAVE_ME_CONFIG = {
  url: "YOUR_SUPABASE_PROJECT_URL",      // looks like https://abcdefghijkl.supabase.co
  anonKey: "YOUR_SUPABASE_ANON_PUBLIC_KEY" // starts with eyJ... (anon) or sb_publishable_...
};
