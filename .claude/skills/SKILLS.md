# Skills index

Every skill in BuyVanda lives in its own folder under `.claude/skills/`, and the folder name is the
command: `.claude/skills/review-migration/SKILL.md` is invoked as `/review-migration`.

Claude Code finds skills by scanning for `*/SKILL.md` — it does not read this file. This index is
for people, so keep it in step when a skill is added, renamed, or deleted.

## Layout

```
.claude/skills/
  SKILLS.md                  this index (not a skill)
  <skill-name>/
    SKILL.md                 frontmatter + instructions — required
    <anything-else>          templates, examples, scripts the skill points at — optional
```

## Skills

| Command | Folder | What it does | Invoked by |
| --- | --- | --- | --- |
| `/git-commit` | `git-commit/` | Paste-ready PowerShell commit block in the house format | Me, or Claude when offering a commit |
