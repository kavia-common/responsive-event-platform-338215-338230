-- seed.sql
-- Seed data for local development / demo. Applied once and tracked in seed_log.

BEGIN;

-- Create a few users with fixed UUIDs for predictable references.
INSERT INTO public.users (id, email, username, full_name, role)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'admin@example.com', 'admin', 'Admin User', 'admin'),
  ('00000000-0000-0000-0000-000000000002', 'mod@example.com',   'moderator', 'Moderator User', 'moderator'),
  ('00000000-0000-0000-0000-000000000003', 'alice@example.com', 'alice', 'Alice Johnson', 'user'),
  ('00000000-0000-0000-0000-000000000004', 'bob@example.com',   'bob', 'Bob Smith', 'user')
ON CONFLICT (id) DO NOTHING;

-- Seed a couple of events.
INSERT INTO public.events (
  id, organizer_user_id, title, description, city, country,
  starts_at, ends_at, visibility, tags
)
VALUES
  (
    '10000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000003',
    'Community Coffee Meetup',
    'Meet neighbors, discuss local projects, and enjoy coffee.',
    'San Francisco', 'US',
    now() + interval '3 days',
    now() + interval '3 days' + interval '2 hours',
    'public',
    ARRAY['community','coffee','meetup']
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000004',
    'Sunset Park Yoga',
    'Outdoor yoga session for all levels. Bring a mat.',
    'San Francisco', 'US',
    now() + interval '5 days',
    now() + interval '5 days' + interval '1 hour',
    'public',
    ARRAY['health','yoga','outdoors']
  )
ON CONFLICT (id) DO NOTHING;

-- Seed RSVPs.
INSERT INTO public.event_rsvps (event_id, user_id, status)
VALUES
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'going'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'interested')
ON CONFLICT (event_id, user_id) DO NOTHING;

-- Seed comments.
INSERT INTO public.event_comments (id, event_id, user_id, body)
VALUES
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'Looking forward to meeting everyone!'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 'Is this suitable for beginners?')
ON CONFLICT (id) DO NOTHING;

-- Seed a direct conversation and a couple of messages.
INSERT INTO public.conversations (id, is_group, title, created_by_user_id)
VALUES ('30000000-0000-0000-0000-000000000001', false, null, '00000000-0000-0000-0000-000000000003')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.conversation_participants (conversation_id, user_id)
VALUES
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003'),
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004')
ON CONFLICT (conversation_id, user_id) DO NOTHING;

INSERT INTO public.messages (id, conversation_id, sender_user_id, body)
VALUES
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'Hey Bob, are you going to the coffee meetup?'),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000004', 'Yep! See you there.')
ON CONFLICT (id) DO NOTHING;

-- Seed a couple notifications.
INSERT INTO public.notifications (user_id, type, title, body, data)
VALUES
  ('00000000-0000-0000-0000-000000000003', 'system', 'Welcome!', 'Thanks for joining the platform.', '{}'::jsonb),
  ('00000000-0000-0000-0000-000000000004', 'comment_added', 'New comment', 'Someone commented on an event you follow.', jsonb_build_object('event_id','10000000-0000-0000-0000-000000000001'))
ON CONFLICT DO NOTHING;

-- Seed a sample analytics event.
INSERT INTO public.analytics_events (user_id, session_id, event_name, properties)
VALUES
  ('00000000-0000-0000-0000-000000000003', 'demo-session-1', 'app_open', jsonb_build_object('source','seed'))
ON CONFLICT DO NOTHING;

COMMIT;
