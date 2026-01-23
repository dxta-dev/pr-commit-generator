The Lode is updated immediately after confirmed decisions so the repository always reflects the current system state, not a changelog.

```ts
export const recordDecision = (decision: string) => {
  return { decision, recordedInLode: true };
};
```

```mermaid
sequenceDiagram
  participant U as User
  participant A as AI
  participant L as Lode
  U->>A: Confirm decision
  A->>L: Update current-state docs
```

Related: [summary.md](summary.md), [terminology.md](terminology.md), [lode-map.md](lode-map.md)
