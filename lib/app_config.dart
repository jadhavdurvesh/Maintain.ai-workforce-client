const String maintainApiUrl = String.fromEnvironment(
  'MAINTAIN_API_URL',
  defaultValue: 'https://maintain-ai-3.vercel.app',
);
const String maintainSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: '',
);
const String maintainSupabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: '',
);

const String maintainApplication = 'workforce';
