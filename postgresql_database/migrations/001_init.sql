-- 001_init.sql
-- Core schema for responsive event platform.
-- This migration is intended to be idempotent when applied once and tracked via schema_migrations.

BEGIN;

-- Enable extensions we may rely on.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========
-- Enums
-- =========
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE public.user_role AS ENUM ('user', 'admin', 'moderator');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_visibility') THEN
    CREATE TYPE public.event_visibility AS ENUM ('public', 'unlisted', 'private');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rsvp_status') THEN
    CREATE TYPE public.rsvp_status AS ENUM ('going', 'interested', 'not_going', 'waitlist');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
    CREATE TYPE public.notification_type AS ENUM (
      'event_created',
      'event_updated',
      'rsvp_changed',
      'comment_added',
      'message_received',
      'moderation_action',
      'system'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'moderation_status') THEN
    CREATE TYPE public.moderation_status AS ENUM ('pending', 'approved', 'rejected', 'removed');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'moderation_action') THEN
    CREATE TYPE public.moderation_action AS ENUM ('approve', 'reject', 'remove', 'ban_user', 'unban_user', 'warn_user');
  END IF;
END $$;

-- =========
-- Users
-- =========
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE,
  username text UNIQUE,
  full_name text,
  avatar_url text,
  bio text,
  role public.user_role NOT NULL DEFAULT 'user',
  is_active boolean NOT NULL DEFAULT true,
  is_banned boolean NOT NULL DEFAULT false,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON public.users(is_active);

-- =========
-- Events
-- =========
CREATE TABLE IF NOT EXISTS public.events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organizer_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  title text NOT NULL,
  description text,
  cover_image_url text,
  location_name text,
  address text,
  city text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  visibility public.event_visibility NOT NULL DEFAULT 'public',
  capacity integer,
  tags text[] NOT NULL DEFAULT '{}'::text[],
  is_cancelled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_event_time CHECK (ends_at IS NULL OR ends_at >= starts_at),
  CONSTRAINT chk_event_capacity CHECK (capacity IS NULL OR capacity >= 1)
);

CREATE INDEX IF NOT EXISTS idx_events_organizer ON public.events(organizer_user_id);
CREATE INDEX IF NOT EXISTS idx_events_starts_at ON public.events(starts_at);
CREATE INDEX IF NOT EXISTS idx_events_visibility ON public.events(visibility);
CREATE INDEX IF NOT EXISTS idx_events_geo ON public.events(latitude, longitude);

-- =========
-- RSVPs
-- =========
CREATE TABLE IF NOT EXISTS public.event_rsvps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status public.rsvp_status NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_event_rsvp UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_event_rsvps_event ON public.event_rsvps(event_id);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_user ON public.event_rsvps(user_id);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_status ON public.event_rsvps(status);

-- =========
-- Comments (on events)
-- =========
CREATE TABLE IF NOT EXISTS public.event_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  parent_comment_id uuid REFERENCES public.event_comments(id) ON DELETE CASCADE,
  body text NOT NULL,
  moderation_status public.moderation_status NOT NULL DEFAULT 'approved',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_event_comments_event ON public.event_comments(event_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_event_comments_user ON public.event_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_event_comments_parent ON public.event_comments(parent_comment_id);

-- =========
-- Conversations + Messages
-- =========
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group boolean NOT NULL DEFAULT false,
  title text,
  created_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.conversation_participants (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  last_read_at timestamptz,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_participants_user ON public.conversation_participants(user_id);

CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  body text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON public.messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON public.messages(sender_user_id);

-- =========
-- Notifications
-- =========
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type public.notification_type NOT NULL,
  title text,
  body text,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON public.notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON public.notifications(user_id) WHERE is_read = false;

-- =========
-- Moderation
-- =========
CREATE TABLE IF NOT EXISTS public.moderation_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  target_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  event_id uuid REFERENCES public.events(id) ON DELETE SET NULL,
  comment_id uuid REFERENCES public.event_comments(id) ON DELETE SET NULL,
  message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  reason text NOT NULL,
  details text,
  status public.moderation_status NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_moderation_reports_status ON public.moderation_reports(status);
CREATE INDEX IF NOT EXISTS idx_moderation_reports_created ON public.moderation_reports(created_at DESC);

CREATE TABLE IF NOT EXISTS public.moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  moderator_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  action public.moderation_action NOT NULL,
  target_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  event_id uuid REFERENCES public.events(id) ON DELETE SET NULL,
  comment_id uuid REFERENCES public.event_comments(id) ON DELETE SET NULL,
  message_id uuid REFERENCES public.messages(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_moderation_actions_created ON public.moderation_actions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_action ON public.moderation_actions(action);

-- =========
-- Analytics
-- =========
CREATE TABLE IF NOT EXISTS public.analytics_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  session_id text,
  event_name text NOT NULL,
  properties jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_name_time ON public.analytics_events(event_name, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_user_time ON public.analytics_events(user_id, occurred_at DESC);

COMMIT;
