---
name: factory
description: Start a software factory for a project, meaning the scheduled Claude Code loops that run it and the rules they follow, by walking the factory playbook step by step. Use when the user says "start a software factory", "set up the night shift", "run this project on agents" or "where do I start with agent loops". Not for proposing loops for a project that already has its watchman and daily ops (that's plan-loops), or for checking loops that are already running (that's fleet).
---

# Factory

KIT is the agent-ops-kit folder: two levels up from this skill's base directory. The playbook is `KIT/docs/FACTORY_PLAYBOOK.md`. Read it first and follow its order. This skill only sequences the work. The detail lives in the files the playbook links, and in the `plan-loops` and `fleet` skills.

Nothing gets scheduled, and no crontab, routine or task gets written, without the user's yes.

## 1. Where the project stands

Find out which steps of "Start in this order" are already done: is there a ledger (`$AGENT_OPS_DIR/runs.jsonl`, default `~/.agent-ops`), a heartbeat job, a charter in the repo's `docs/`, a registry? Does the project have users or revenue? If it has neither, tell the user it hasn't earned a loop yet (playbook, "When work earns its own loop") and stop at the watchman.

Show the user what's done and the next step. Wait for their go.

## 2. The watchman

Follow the README's "Try it in 5 minutes" in the project: copy the kit in, run the tests, fill in the charter's placeholders and X surfaces, then run one loop and the heartbeat by hand. Offer the cloud watch if the heartbeat runs on a laptop.

## 3. Loops

Use the `plan-loops` skill to propose and build the project's loops. Daily ops comes first, and the user reads every grade for the first week before anything else is added.

## 4. The control room

As soon as there's more than one loop, use the `fleet` skill to set up the registry and the dashboard. If the user keeps a master queue, point `waiting.queue` in `fleet.json` at it.

## 5. The rules

Go through the playbook's Budgets, Fix or retire and Bets sections with the user. Write down their weekly cost ceiling and how they want to be reached when a loop is blocked on them. Once the product is past launch, add the strategy loop through `plan-loops`.

Report what's running now, what each loop costs per run from its hand run, and the next step in the playbook's order.
