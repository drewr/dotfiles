---
name: work-tracking
description: Covers how Datum tracks work across GitHub Projects — an enhancements board per product, monthly release milestones, and one Engineering Plan spanning both products. Use when asked what we're shipping, what a person is working on, how an item is tracked, whether a sprint or release is healthy, or when producing any roadmap, release, or sprint report.
---

# Work Tracking

This skill covers how work is tracked across Datum's GitHub Projects, and the
traps that make naive reports wrong. It exists because several confident-looking
reports turned out to be misleading in ways only visible after checking a second
source.

## Structure

Work lives at three levels, and **they are not reliably joined**. Treat each as
a separate source of truth.

| Layer | Where | Answers |
|---|---|---|
| **Enhancement** | One project per product | What have we committed to, to whom? |
| **Release** | Monthly milestones, per product | Which month does it land in? |
| **Execution** | Engineering Plan (project 60) | What is actually being done, this sprint? |

The separation is deliberate: **enhancements and milestones belong to their
product; engineering work is shared and lives in one plan.**

### Enhancement boards

One board per product, same shape:

| Product | Project | URL |
|---|---|---|
| Datum Cloud | Org project **22** "Enhancements" | `https://github.com/orgs/datum-cloud/projects/22` |
| Milo OS | Org project **2** "Enhancements" | `https://github.com/orgs/milo-os/projects/2` |

Both carry the same fields — `Status` (`Backlog` → `Planning` → `On Deck` →
`In progress` → `Done`), `Priority` (`P0`–`P2`), `Size` (`XS`–`XL`), and
`Start date`/`End date` — and the same default view name, **"Feedback &
Roadmap"**, a board layout with lanes grouped by `Status`. The datum-cloud board
adds a second view, **"Eng Timeline"** (roadmap layout).

- Items are **enhancement-sized**, not tickets: "Introduce Object Storage
  service", "Galactic VPC", "Per Region Network Load Balancer".
- `Status` is a **roadmap stage, not a sprint state**. `In progress` means
  committed and underway, not "in this sprint".
- **The boards have no Iteration field.** They cannot answer "what ships this
  sprint".
- Most items are `Done` — the board is largely history. Read status, not the
  item count.
- Dates are sparsely used. At the time of writing only 5 of 365 datum-cloud
  items carried any date, so its timeline view renders almost nothing.

### Releases: milestones

**Releases are monthly milestones**, named `<Month> <Year> - "<name>"` (for
example `October 2026 - "Hedy"`), each with a `due_on` date.

One release covers **one month of work = two sprints**. That ratio matters
because sprint names straddle calendar months (`Sprint 10.15.26` is Oct 15–29;
`Sprint 10.29.26` is Oct 29–Nov 12), so a month never aligns to a whole number of
sprints.

**Use milestones for releases. Do not add a Release field.** Milestones are
GitHub-native, already populated, dated, and have a clean history. A parallel
field would create two competing answers and more noise.

Milestones are **per repository**, so each product needs a home for them.
datum-cloud uses the `enhancements` repo. milo-os had no milestones and no
roadmap repo when this was written, so its board has no release dimension yet.

### Engineering Plan: project 60

`https://github.com/orgs/datum-cloud/projects/60` is the Engineering Plan and
the **only** board with an Iteration field in real use. It spans both products —
`datum-cloud/*` and `milo-os/*` items sit in the same plan, which is what makes
one engineering view possible.

- Very large — thousands of items, with historical sprints holding far more than
  the current one. Pull it once and index locally; never query per person.
- Iterations look like `Sprint 10.1.26`, `Sprint 10.15.26`, `Sprint 10.29.26`,
  alongside monthly buckets from before the sprint cadence (`August 2026`,
  `September 2026`).
- A sprint is a **record of completed work more than a forward plan** — a large
  share of any sprint's items are already `Done`.

## Linking work

The intended join from enhancement to execution is **sub-issues**:

```
Enhancement item (product board)
   └── sub-issues
          └── Engineering Plan items (sprint-scheduled)
```

In practice **this link is thin**. When first measured, only 8 of 27 open
datum-cloud enhancement items had any sub-issues, and only 2 pointed at
sprint-scheduled work. Measure the coverage every time; do not assume it.

Both linking mechanisms work across repositories and organizations:

- **Sub-issues** can span repositories — GitHub documents adding an issue "from
  another repository" under a parent.
- **Project items** can come from **any organization** — quoting the docs, "you
  can include issues and pull requests from any organization". This was verified
  by adding a `milo-os` issue to the `datum-cloud` enhancements project and
  removing it again.

So a product board and the engineering plan are not blocked by repo or org
boundaries; the gap is that links are rarely made, not that they are impossible.

### Repository visibility

- **Private:** `datum-cloud/infra`, `datum-cloud/engineering`
- **Public:** `enhancements`, `galactic`, `compute`, `network-services-operator`,
  `connect`, `cloud-portal`, `dns-operator`, `auth-ui`, `unikraft-provider`,
  and the `milo-os` repositories

`infra` and `engineering` carry most of the execution — `infra` alone can be
three-quarters of a sprint's items. Items from private repositories are only
visible to people with access to them.

The consequence for reporting is severe: **a report built only from enhancement
links will show private-backed work as "no work scheduled"**. State this blind
spot rather than reporting the gap as fact. Two questions get asked and need
different answers — what we ship to users, and where the engineering effort
actually sits — so produce an internal view that cites private repos freely and
an externally-safe view that covers public evidence only.

## Traps

These have all produced wrong reports.

1. **`assignee:` filters silently drop standalone pull requests.** A project
   filter like `iteration:@current assignee:<login>` can omit a PR with no
   parent issue even when the item is assigned and in the iteration. Verify with
   a direct item dump before quoting a count. Free-text search is worse:
   `iteration:@current <login>` matches any mention and returns unrelated items.

2. **Merged PRs look like assigned work.** Filtering a sprint by name matches PR
   authors, so a person can appear to have a dozen sprint items that are all
   merged PRs while having zero assigned issues. Check `__typename`.

3. **Iteration is unset almost everywhere outside project 60.** Work in other
   projects is real and often active, but carries no iteration. "No iteration"
   means "not scheduled", not "not happening".

4. **Some projects have no Iteration field at all** — nothing there can be
   sprint-stamped. Check the schema before concluding anything is missing.

5. **Statuses drift.** Enhancement items sit `In progress` with end dates in the
   past. Releases close on their due date with sub-issues still open, and those
   items quietly become historical with no record of the carryover. **A closed
   milestone is not evidence the work finished.**

6. **One effort, many boards and tickets.** The same issues appear across
   several projects and views, and a single effort is often filed as a dozen
   issues. Count efforts, not memberships, or you will overstate both spread and
   breadth. When a cluster of issues reads as one campaign, propose one
   enhancement item with sub-issues instead of many entries.

7. **Enhancements filed in the wrong product.** A board per product only stays
   honest if items land in their own product's board. Check the repository
   before adding, and keep cross-product engineering in project 60 rather than
   duplicating enhancement items.

8. **Reports age fast.** A snapshot written "9 days before a release" is wrong
   on release day. Stamp any report with the date of measurement.

## Working with people

- Before telling anyone what they are or aren't working on, **check every
  project, not just the Engineering Plan**. A message that says "you have no
  iteration work" to someone running five projects is wrong and gets noticed
  immediately.
- Prefer stating what you can see and asking, over asserting absence.
- Cross-project assignment is normal for infrastructure work, so the Engineering
  Plan alone never describes an individual's workload.
- Do not move someone's items on their behalf without telling them. Fixing a
  person's board as a favour is fine; doing it silently is not.

## Reporting checklist

Before publishing any roadmap, release, or sprint report:

- [ ] State which board, which product, and which milestone the numbers come
      from, plus the date of measurement.
- [ ] Confirm the sub-issue coverage — give a count, not an impression.
- [ ] List items with no execution link instead of implying they are idle.
- [ ] Call out the private-repo blind spot, especially for `infra`.
- [ ] Distinguish scheduled from unscheduled; do not treat unscheduled as absent.
- [ ] Verify any per-person count against a direct item dump.
- [ ] Check for projects that lack an Iteration field.
- [ ] For a release report, check the milestone's due date first — if it has
      passed, the report is history, not a forecast.

## Related Skills

These ship in `@datum-cloud/opencode-plugins` (installed globally under
`~/.config/opencode/skills/`):

- **`operational-review`** — weekly operational reporting for the edge; consumes
  similar data but answers runtime questions rather than planning ones.
- **`trends`** — longer-range analysis; shares the "check a second source"
  instinct.
- **`release`** — cutting and verifying a production release, which is where
  milestones and shipped work meet.
- **`pr-conventions`** — issue and PR body conventions, including the link
  syntax used to connect tracking items.
