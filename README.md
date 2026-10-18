# Together: couples habit app

## Honest status
- Real Supabase sign-in is wired (config.js holds the public URL + publishable key and the two allowed emails; Person 1 = first email). Tested only against a mocked auth server, not your live project.
- Tasks, completions, points, notes and love notes now read/write your Supabase database (RLS enforced). Tested only against a mocked API, not your live project. Run supabase/migrations/001_init.sql and the provisioning SQL first.
- Reminder state and preferences (sound, theme, timezone) stay in the browser.
- `index.html` is the working demo (demo sign-in, tasks, reminders, calendar, notes, love notes). It uses browser localStorage only.
- It is NOT yet connected to Supabase. `supabase/migrations/001_init.sql` is the prepared schema + RLS, written but NOT tested on a live project.
- Not built: Weekly Reports, challenge upgrades, Our Little Wins, Surprise of the Day, Memories/photos, avatars, automated tests, Next.js rewrite.

## Deploy the demo to Vercel (works now, no build)
1. Extract the ZIP. Push the folder to a GitHub repo (or run `npx vercel` inside it).
2. In Vercel: Add New > Project > import the repo. Framework Preset: **Other**. Build command: empty. Output directory: empty (root).
3. Deploy. Anyone with the URL can use the demo sign-in, so do not store anything private yet.

## Supabase setup (for the next step)
1. Create a Supabase project.
2. Authentication > Sign In / Providers: turn OFF "Allow new users to sign up".
3. Authentication > Users > Add user: create the two accounts (set passwords there; never in code).
4. SQL editor: run `supabase/migrations/001_init.sql`, then edit and run the commented provisioning block at the bottom with your two emails.
5. Project Settings > API: copy the Project URL and the anon/publishable key. Share only those. Never share or commit the service_role key.
6. In Vercel > Settings > Environment Variables add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (public values; RLS protects the data).
