# Lode Map

- [summary.md](summary.md)
- [terminology.md](terminology.md)
- [practices.md](practices.md)
- automation/
- [automation/summary.md](automation/summary.md)
- plans/
- tmp/

```ts
export const lodeIndex = [
  "summary.md",
  "terminology.md",
  "practices.md",
  "automation/",
  "automation/summary.md",
  "plans/",
  "tmp/",
];
```

```mermaid
flowchart TD
  Root[lode/] --> Summary[summary.md]
  Root --> Terms[terminology.md]
  Root --> Practices[practices.md]
  Root --> Automation[automation/]
  Automation --> AutomationSummary[summary.md]
  Root --> Plans[plans/]
  Root --> Tmp[tmp/]
```

Related: [summary.md](summary.md), [terminology.md](terminology.md), [practices.md](practices.md), [automation/summary.md](automation/summary.md)
