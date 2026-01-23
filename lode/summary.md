This repository automates GitHub PR churn via a scheduled workflow that creates, updates, closes, and merges automation-scoped PRs on a 5-minute cadence using a TypeScript runner.

```ts
export type AutomationScope = {
  branchPrefix: string;
  label: string;
  heartbeatPath: string;
};
```

```mermaid
flowchart TD
  A[Scheduled Workflow] --> B[Run TS Automation]
  B --> C[Create PRs]
  B --> D[Update PRs]
  B --> E[Close PRs]
  B --> F[Rebase + Merge PRs]
```

Related: [terminology.md](terminology.md), [practices.md](practices.md), [lode-map.md](lode-map.md), [automation/summary.md](automation/summary.md)
