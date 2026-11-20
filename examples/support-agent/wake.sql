-- Wakes the support agent (front desk) and the fix agent (mechanic): a Postgres template for
-- Supabase, with pg_cron, pg_net and Vault. See README.md in this folder.
-- Assumes a `support_tickets` table with: id uuid, created_at timestamptz, email text,
-- resolved_at timestamptz, replied_at timestamptz. Rename to match yours.
--
-- One run per ticket. The ticket id travels in the fire payload, so a run never sees another
-- person's ticket, and an injection in one ticket can't reach the context of the next.

ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS handled_by text CHECK (handled_by IN ('admin', 'agent')),
  ADD COLUMN IF NOT EXISTS escalated_at timestamptz,
  ADD COLUMN IF NOT EXISTS admin_note text,
  -- Lease and retry budget: fired at most once per 30 minutes and at most 3 times.
  ADD COLUMN IF NOT EXISTS agent_fired_at timestamptz,
  ADD COLUMN IF NOT EXISTS agent_attempts integer NOT NULL DEFAULT 0,
  -- What the agent proposed when it escalated, and what the human chose with one tap.
  ADD COLUMN IF NOT EXISTS proposal_action text CHECK (proposal_action IN ('reply', 'fix')),
  ADD COLUMN IF NOT EXISTS proposal_reply text,
  ADD COLUMN IF NOT EXISTS founder_action text CHECK (founder_action IN ('reply', 'fix')),
  ADD COLUMN IF NOT EXISTS founder_action_at timestamptz;

-- Kill switch. Off until you've watched a few runs.
CREATE TABLE IF NOT EXISTS ops_flags (key text PRIMARY KEY, enabled boolean NOT NULL DEFAULT false);
ALTER TABLE ops_flags ENABLE ROW LEVEL SECURITY;
INSERT INTO ops_flags (key, enabled) VALUES ('support_agent', false) ON CONFLICT (key) DO NOTHING;

-- Every fire, with pg_net's request id, so a run that never started can be traced to its
-- HTTP response in net._http_response.
CREATE TABLE IF NOT EXISTS agent_fires (
  id         bigserial PRIMARY KEY,
  fired_at   timestamptz NOT NULL DEFAULT now(),
  agent      text NOT NULL CHECK (agent IN ('support', 'fix')),
  ticket_id  uuid NOT NULL REFERENCES support_tickets (id) ON DELETE CASCADE,
  request_id bigint
);
ALTER TABLE agent_fires ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON agent_fires FROM anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- POSTs {"text": <ticket id>} to a routine's fire URL. URL and token come from Vault
-- (<agent>_fire_url, <agent>_fire_token), never from this file. Null when either is missing.
CREATE OR REPLACE FUNCTION agent_fire(agent text, ticket uuid) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  fire_url text := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = agent || '_fire_url');
  fire_token text := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = agent || '_fire_token');
  req bigint;
BEGIN
  IF fire_url IS NULL OR fire_token IS NULL THEN
    RETURN NULL;
  END IF;
  req := net.http_post(
    url := fire_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || fire_token,
      'anthropic-version', '2023-06-01',
      'anthropic-beta', 'experimental-cc-routine-2026-04-01',
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('text', ticket::text),
    timeout_milliseconds := 8000
  );
  INSERT INTO agent_fires (agent, ticket_id, request_id) VALUES (agent, ticket, req);
  RETURN req;
END;
$$;

-- Front desk. Polling, not an insert trigger: it batches bursts, retries a run that died,
-- and needs no debounce state of its own.
CREATE OR REPLACE FUNCTION support_agent_wake() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  -- Spam can flood the form. Past this cap the daily loop is the backstop.
  daily_cap constant int := 30;
  budget int;
  t record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ops_flags WHERE key = 'support_agent' AND enabled) THEN
    RETURN;
  END IF;
  SELECT daily_cap - count(*) INTO budget
  FROM agent_fires WHERE agent = 'support' AND fired_at > now() - interval '24 hours';

  FOR t IN
    SELECT id FROM support_tickets
    WHERE handled_by IS NULL AND resolved_at IS NULL AND escalated_at IS NULL AND replied_at IS NULL
      AND agent_attempts < 3
      AND (agent_fired_at IS NULL OR agent_fired_at < now() - interval '30 minutes')
    ORDER BY created_at
    LIMIT greatest(budget, 0)
    FOR UPDATE SKIP LOCKED
  LOOP
    EXIT WHEN agent_fire('support', t.id) IS NULL;
    UPDATE support_tickets SET agent_fired_at = now(), agent_attempts = agent_attempts + 1 WHERE id = t.id;
  END LOOP;
END;
$$;

-- Mechanic. Called by the server when the human confirms "Fix it now"; at most 3 a day.
CREATE OR REPLACE FUNCTION support_fix_fire(ticket uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF (SELECT count(*) FROM agent_fires WHERE agent = 'fix' AND fired_at > now() - interval '24 hours') >= 3 THEN
    RETURN false;
  END IF;
  RETURN agent_fire('fix', ticket) IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION agent_fire(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION support_agent_wake() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION support_fix_fire(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION support_fix_fire(uuid) TO service_role;

SELECT cron.schedule('support-agent-wake', '*/5 * * * *', 'SELECT support_agent_wake()');
