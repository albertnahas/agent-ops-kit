Who watches the watchman? A second one, in the cloud.

`bin/heartbeat.py` logs its own pass line and pushes `$AGENT_OPS_DIR` to a private repo. Create a Claude Code cloud scheduled task (claude.ai/code/routines or /schedule) on that repo, once a day, a few hours after the heartbeat, with a mail connector or any other way to reach you. Use this as its prompt:

---

Read runs.jsonl in this repo. Find the last line whose loop is "heartbeat". If there is none, or its date is more than 26 hours ago, the machine that runs my loops is down or asleep: send me one short email saying when the heartbeat last ran. Otherwise do nothing. Change no files.
