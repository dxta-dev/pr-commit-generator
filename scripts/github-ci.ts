import { execSync } from "node:child_process";
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { Octokit } from "octokit";

const token = process.env.GITHUB_TOKEN;
const repoFull = process.env.GITHUB_REPOSITORY ?? process.env.REPO_FULL;

if (!token) {
  throw new Error("GITHUB_TOKEN is required");
}

if (!repoFull) {
  throw new Error("GITHUB_REPOSITORY or REPO_FULL is required");
}

const [owner, repo] = repoFull.split("/");
if (!owner || !repo) {
  throw new Error(`Invalid GITHUB_REPOSITORY: ${repoFull}`);
}

const baseBranch = process.env.BASE_BRANCH ?? "main";
const branchPrefix = process.env.AUTOMATION_BRANCH_PREFIX ?? "auto";
const label = process.env.AUTOMATION_LABEL ?? "automation";
const heartbeatPath =
  process.env.AUTOMATION_FILE_PATH ?? "automation/heartbeat.txt";
const closeRatio = Number(process.env.CLOSE_RATIO ?? "0.2");
const mergeRatio = Number(process.env.MERGE_RATIO ?? "0.2");
const updateRatio = Number(process.env.UPDATE_RATIO ?? "0.2");

const octokit = new Octokit({ auth: token });

const run = (command: string) => {
  execSync(command, { stdio: "inherit" });
};

const ensureGitIdentity = () => {
  run('git config user.name "github-actions[bot]"');
  run('git config user.email "github-actions[bot]@users.noreply.github.com"');
};

const appendHeartbeat = (branchName: string) => {
  mkdirSync(dirname(heartbeatPath), { recursive: true });
  appendFileSync(
    heartbeatPath,
    `${new Date().toISOString()} ${branchName}\n`,
    "utf8",
  );
};

const randomInt = (min: number, max: number) => {
  return Math.floor(Math.random() * (max - min + 1)) + min;
};

const shuffle = <T>(items: T[]) => {
  const copy = [...items];
  for (let i = copy.length - 1; i > 0; i -= 1) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
};

const sample = <T>(items: T[], count: number) => {
  if (count <= 0) {
    return [] as T[];
  }
  return shuffle(items).slice(0, Math.min(count, items.length));
};

const ratioCount = (total: number, ratio: number) => {
  if (!Number.isFinite(ratio) || ratio <= 0) {
    return 0;
  }
  return Math.max(0, Math.floor(total * ratio));
};

const isAutomationPr = (pr: {
  head: { ref: string };
  labels?: Array<{ name?: string } | string>;
}) => {
  const hasLabel = pr.labels?.some((entry) =>
    typeof entry === "string" ? entry === label : entry.name === label,
  );
  return pr.head.ref.startsWith(`${branchPrefix}/`) || Boolean(hasLabel);
};

const listAutomationPulls = async () => {
  const pulls = await octokit.paginate(octokit.rest.pulls.list, {
    owner,
    repo,
    state: "open",
    per_page: 100,
  });

  return pulls.filter(isAutomationPr);
};

const createPullRequests = async (count: number) => {
  if (count <= 0) {
    return;
  }

  const runStamp = new Date().toISOString().replace(/[:.]/g, "-");
  for (let i = 0; i < count; i += 1) {
    const branchName = `${branchPrefix}/${runStamp}-${i + 1}`;
    run(`git checkout ${baseBranch}`);
    run(`git pull --ff-only origin ${baseBranch}`);
    run(`git checkout -b ${branchName}`);
    appendHeartbeat(branchName);
    run(`git add ${heartbeatPath}`);
    run(`git commit -m "chore: heartbeat ${branchName}"`);
    run(`git push -u origin ${branchName}`);

    const pr = await octokit.rest.pulls.create({
      owner,
      repo,
      head: branchName,
      base: baseBranch,
      title: `Automation: ${branchName}`,
      body: "Automated PR generated on schedule.",
    });

    await octokit.rest.issues.addLabels({
      owner,
      repo,
      issue_number: pr.data.number,
      labels: [label],
    });
  }
};

const closePullRequests = async (pulls: Array<{ number: number }>) => {
  for (const pr of pulls) {
    await octokit.rest.pulls.update({
      owner,
      repo,
      pull_number: pr.number,
      state: "closed",
    });
  }
};

const updatePullBranches = async (
  pulls: Array<{ number: number; head: { ref: string } }>,
) => {
  for (const pr of pulls) {
    const branchName = pr.head.ref;
    run(`git fetch origin ${branchName}`);
    run(`git checkout ${branchName}`);
    run(`git pull --ff-only origin ${branchName}`);
    appendHeartbeat(branchName);
    run(`git add ${heartbeatPath}`);
    run(`git commit -m "chore: update ${branchName}"`);
    run(`git push origin ${branchName}`);
  }
};

const rebaseAndMergePulls = async (pulls: Array<{ number: number }>) => {
  for (const pr of pulls) {
    try {
      await octokit.request(
        "PUT /repos/{owner}/{repo}/pulls/{pull_number}/update-branch",
        {
          owner,
          repo,
          pull_number: pr.number,
        },
      );
    } catch (error) {
      console.error(`Update branch failed for PR #${pr.number}`, error);
    }

    try {
      await octokit.rest.pulls.merge({
        owner,
        repo,
        pull_number: pr.number,
        merge_method: "squash",
      });
    } catch (error) {
      console.error(`Merge failed for PR #${pr.number}`, error);
    }
  }
};

const main = async () => {
  ensureGitIdentity();
  const createCount = randomInt(1, 3);
  await createPullRequests(createCount);

  const openPulls = await listAutomationPulls();
  const closeTargets = sample(
    openPulls,
    ratioCount(openPulls.length, closeRatio),
  );
  const closeSet = new Set(closeTargets.map((pr) => pr.number));
  await closePullRequests(closeTargets);

  const remainingAfterClose = openPulls.filter(
    (pr) => !closeSet.has(pr.number),
  );
  const updateTargets = sample(
    remainingAfterClose,
    ratioCount(remainingAfterClose.length, updateRatio),
  );
  const updateSet = new Set(updateTargets.map((pr) => pr.number));
  await updatePullBranches(updateTargets);

  const remainingAfterUpdate = remainingAfterClose.filter(
    (pr) => !updateSet.has(pr.number),
  );
  const mergeTargets = sample(
    remainingAfterUpdate,
    ratioCount(remainingAfterUpdate.length, mergeRatio),
  );
  await rebaseAndMergePulls(mergeTargets);

  run(`git checkout ${baseBranch}`);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
