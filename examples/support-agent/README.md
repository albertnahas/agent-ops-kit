# Support agent and fix loop

A ticket lands. Within five minutes an agent answers it, or escalates it to you with a decision you make in one tap. If the answer is "it's a bug", a second agent opens the fix as a PR, the grader grades it, it merges on A, and the person hears back only once the fix is live.

This is a pattern, not a package. It ran on a Next.js and Supabase product; port it to your stack.

| File | What it is |
|---|---|
| `SUPPORT_AGENT.md` | The front desk's charter. One ticket, one action: reply, resolve or escalate. |
| `SUPPORT_FIX.md` | The mechanic's charter, plus the ship job that merges and answers. |
| `wake.sql` | Postgres template: the wake, the lease, the caps, the kill switch, the fire log. |

## How a ticket moves

1. **Wake.** `support_agent_wake()` runs every 5 minutes with pg_cron. For each open ticket nobody has handled, it POSTs the ticket id to the routine's fire URL with pg_net. Each ticket is fired at most once per 30 minutes and 3 times in all, and all tickets together at most 30 times a day. `FOR UPDATE SKIP LOCKED` keeps two ticks from firing the same ticket. Polling beats an insert trigger: it batches bursts and retries a run that died.
2. **Front desk.** A cloud routine with one ticket id. It reads and acts through one API on your site, and nothing else.
3. **Escalation.** You get an email with the agent's note, its drafted reply and up to two buttons: the proposal, and "Fix it now". The person gets a short acknowledgement.
4. **Mechanic.** "Fix it now" calls `support_fix_fire()` (3 a day), which wakes the fix routine. It opens a PR.
5. **Ship job.** A local job proves, grades and merges the PR, then replies once the merge is live.

## The door policy

The prompt isn't the security boundary. The API is.

- **The routine holds no keys.** Run it in its own cloud environment with network access limited to your host and no package managers. Put the API token in a network secret that the egress proxy adds to requests for that host, so the agent never sees it. No repo, no connectors, no database key.
- **The fire URL and token live in Vault,** never in a migration or the repo.
- **Kill switch:** `ops_flags.support_agent`. Off until you've watched a few runs.

### Route checklist: `/api/agent/support`

- [ ] `GET ?id=` returns the charter, that one ticket, earlier messages from the same address and what the person did in the product. `409` if the ticket is already handled.
- [ ] `POST` takes `reply`, `resolve` or `escalate`, and nothing else.
- [ ] Every reply, drafted reply and ack is checked on the server before anything is claimed, so the agent can fix a `422` and retry. Normalise Unicode and strip invisible characters first, then refuse: over the length cap, any link not on your host (parse anything with `//`, don't pattern-match it), bare hostnames, IP addresses, obfuscated dots, phone numbers and dial schemes, and any email address except the reporter's and yours.
- [ ] One action per ticket even when two runs race: a conditional update (`handled_by IS NULL AND resolved_at IS NULL AND escalated_at IS NULL AND replied_at IS NULL`) is the lock. `409` if it claims nothing.
- [ ] Replies go only to the ticket's own address, in plain text, without quoting the original.
- [ ] Escalation emails and acks share a daily cap (10 is plenty), so a spam flood can't fill your inbox.
- [ ] The public form has its own per-network rate limit. Store a hash of the IP, never the IP.
- [ ] In the escalation email, mark the agent's note and draft as untrusted, like the ticket.

One risk stays: whoever files a ticket chooses its address, so a reply can reach a stranger's inbox. The one-reply rule, the form limit and the daily cap bound it. Have your daily loop audit every agent reply.

### Founder action checklist: the one-tap links

- [ ] One signed link per action (HS256, 72 hours), with its own secret, so rotating it voids every link in your inbox without breaking anything else.
- [ ] Bind each link to the sha256 of the draft you read. A changed draft voids it.
- [ ] The link opens a confirm page whose own button acts. Mail scanners open links.
- [ ] A ticket takes one decision: a conditional update on `founder_action` is the lock.
- [ ] Every step is safe to repeat, so pressing again after a failure finishes what's left.
- [ ] Drafted replies go out as the agent's, through the same checks.
- [ ] If you add a refund button: the server chooses the payment, never the ticket or the agent, and checks it again at the tap (paid, inside the window, not refunded, the buyer's own money, the only candidate). Record the refund on the payment, claim it before the provider call and use an idempotency key, so a second ticket can't refund it twice. This is X under the merge policy.

### Ship job checklist

- [ ] A script, not the model, decides the queue and holds the gates. Claude runs only when the queue isn't empty.
- [ ] It runs from a clean worktree of `origin/main`, not your shared checkout.
- [ ] The same queue three times means a run can't finish it. Stop spending and let the check fail.
- [ ] `reply` refuses unless the ticket is a fix, still unanswered, and its PR is merged with `grade:A` and the merge commit is in the newest successful production deployment.
- [ ] `check` exits 1 while the queue isn't empty. End the run with `bin/ops-check -- <script> check`.
- [ ] `DRY_RUN=<pr>` runs every step on one PR and comments, labels, merges, uploads and sends nothing.

## Watching it

No alert fires when the front desk stops answering (an expired fire token, a broken deploy, the switch left off). Add an outcome check for the heartbeat: open tickets older than 45 minutes that nobody handled, plus any failed fire in `agent_fires` (join `net._http_response` on `request_id`).
