import {
  defineConfig,
  BaseJudge,
  getJudgeRegistry,
  type JudgeContext,
  type JudgeResult,
  type JudgeType,
  type AgentResult,
} from "@poofnew/vibe-check";
import { readFileSync, readdirSync } from "fs";
import { execSync } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

// ---------------------------------------------------------------------------
// Claw-Empire API helpers
// ---------------------------------------------------------------------------

const API_BASE = "http://127.0.0.1:8790";
const PROJECT_ID = "02935290-0d63-4d29-b895-f31396dd661f";
const SANDBOX_DIR = "/Users/sam/Documents/Projects/gitaday/claw-sandbox";

/** Thin cookie-jar: we only need the session cookie + csrf token. */
interface Session {
  cookies: string[];
  csrfToken: string;
}

async function getSession(): Promise<Session> {
  const res = await fetch(`${API_BASE}/api/auth/session`, {
    method: "GET",
    headers: { Accept: "application/json" },
  });

  if (!res.ok) {
    throw new Error(
      `Failed to get session: ${res.status} ${await res.text()}`
    );
  }

  // Collect Set-Cookie headers
  const cookies: string[] = [];
  const setCookieHeaders = res.headers.getSetCookie?.() ?? [];
  for (const sc of setCookieHeaders) {
    // Keep only the cookie k=v portion
    cookies.push(sc.split(";")[0]);
  }

  const body = (await res.json()) as Record<string, unknown>;
  const csrfToken = (body.csrf_token ?? body.csrfToken ?? "") as string;

  return { cookies, csrfToken };
}

async function apiPost(
  session: Session,
  path: string,
  payload: unknown
): Promise<unknown> {
  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-csrf-token": session.csrfToken,
      Cookie: session.cookies.join("; "),
    },
    body: JSON.stringify(payload),
  });
  return res.json();
}

async function apiGet(
  session: Session,
  path: string
): Promise<unknown> {
  const res = await fetch(`${API_BASE}${path}`, {
    method: "GET",
    headers: {
      Accept: "application/json",
      "x-csrf-token": session.csrfToken,
      Cookie: session.cookies.join("; "),
    },
  });
  return res.json();
}

async function apiDelete(
  session: Session,
  path: string
): Promise<void> {
  await fetch(`${API_BASE}${path}`, {
    method: "DELETE",
    headers: {
      "x-csrf-token": session.csrfToken,
      Cookie: session.cookies.join("; "),
    },
  });
}

/** Get all current task IDs. */
async function getAllTaskIds(session: Session): Promise<Set<string>> {
  const tasksRes = (await apiGet(session, "/api/tasks")) as any;
  const tasks: any[] = Array.isArray(tasksRes)
    ? tasksRes
    : tasksRes?.tasks ?? tasksRes?.data ?? [];
  return new Set(tasks.map((t: any) => t.id));
}

/** Get all current subtask IDs. */
async function getAllSubtaskIds(session: Session): Promise<Set<string>> {
  const res = (await apiGet(session, "/api/subtasks")) as any;
  const subtasks: any[] = Array.isArray(res)
    ? res
    : res?.subtasks ?? res?.data ?? [];
  return new Set(subtasks.map((s: any) => s.id));
}

/**
 * Poll for NEW tasks (tasks that didn't exist before the directive was sent).
 *
 * Two modes:
 * - waitForTerminal=false: return as soon as we see at least one new task
 *   (good for "task-created" checks)
 * - waitForTerminal=true: wait until a new task reaches a terminal state
 *   (good for checking completion/artifacts)
 *
 * We always wait at least `initialDelayMs` to give the meeting time to create tasks.
 */
async function pollForNewTasks(
  session: Session,
  preExistingTaskIds: Set<string>,
  preExistingSubtaskIds: Set<string>,
  opts: {
    timeoutMs?: number;
    intervalMs?: number;
    initialDelayMs?: number;
    waitForTerminal?: boolean;
  } = {}
): Promise<{ tasks: any[]; subtasks: any[] }> {
  const {
    timeoutMs = 180_000,
    intervalMs = 5_000,
    initialDelayMs = 10_000,
    waitForTerminal = false,
  } = opts;

  const deadline = Date.now() + timeoutMs;
  let newTasks: any[] = [];
  let newSubtasks: any[] = [];

  // Initial delay to let the meeting/planning happen
  await new Promise((resolve) => setTimeout(resolve, initialDelayMs));

  while (Date.now() < deadline) {
    // Fetch current tasks
    const tasksRes = (await apiGet(session, "/api/tasks")) as any;
    const allTasks: any[] = Array.isArray(tasksRes)
      ? tasksRes
      : tasksRes?.tasks ?? tasksRes?.data ?? [];
    newTasks = allTasks.filter((t: any) => !preExistingTaskIds.has(t.id));

    // Fetch current subtasks
    const subtasksRes = (await apiGet(session, "/api/subtasks")) as any;
    const allSubtasks: any[] = Array.isArray(subtasksRes)
      ? subtasksRes
      : subtasksRes?.subtasks ?? subtasksRes?.data ?? [];
    newSubtasks = allSubtasks.filter((s: any) => !preExistingSubtaskIds.has(s.id));

    if (newTasks.length > 0) {
      if (!waitForTerminal) {
        // Just need to see a task was created
        return { tasks: newTasks, subtasks: newSubtasks };
      }

      // Check if any new task has reached a terminal state
      const hasTerminal = newTasks.some(
        (t: any) =>
          t.status === "completed" ||
          t.status === "failed" ||
          t.status === "done" ||
          t.status === "error" ||
          t.status === "review"
      );

      if (hasTerminal) {
        return { tasks: newTasks, subtasks: newSubtasks };
      }
    }

    // Wait before polling again
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }

  // Timed out -- return whatever new items we found
  return { tasks: newTasks, subtasks: newSubtasks };
}

/** Check what files exist under the sandbox dir. */
async function listSandboxFiles(): Promise<string[]> {
  try {
    const text = execSync(`find ${SANDBOX_DIR} -type f`, {
      encoding: "utf-8",
      timeout: 10_000,
    });
    return text
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((p) => p.replace(SANDBOX_DIR + "/", ""));
  } catch {
    return [];
  }
}

/** Clean up tasks created during a test run. */
async function cleanupTasks(session: Session, taskIds: string[]): Promise<void> {
  for (const id of taskIds) {
    try {
      await apiDelete(session, `/api/tasks/${id}`);
    } catch {
      // best-effort cleanup
    }
  }
}

/**
 * Load raw eval JSON by id to access custom fields that Zod strips.
 * Scans the __evals__ directory for a file matching the eval id.
 */
const __configDir = typeof import.meta.dir === "string"
  ? import.meta.dir
  : dirname(fileURLToPath(import.meta.url));
const EVALS_DIR = join(__configDir, "__evals__");
const rawEvalCache = new Map<string, Record<string, unknown>>();

function getRawEvalData(evalId: string): Record<string, unknown> {
  if (rawEvalCache.has(evalId)) return rawEvalCache.get(evalId)!;

  try {
    const files = readdirSync(EVALS_DIR).filter((f) => f.endsWith(".eval.json"));
    for (const file of files) {
      const data = JSON.parse(readFileSync(join(EVALS_DIR, file), "utf-8"));
      rawEvalCache.set(data.id, data);
    }
  } catch {
    // ignore
  }

  return rawEvalCache.get(evalId) ?? {};
}

// ---------------------------------------------------------------------------
// Custom Judges
// ---------------------------------------------------------------------------

/**
 * TaskCreatedJudge -- verifies that submitting a directive results in at least
 * one task being created in the system.
 */
class TaskCreatedJudge extends BaseJudge {
  id = "task-created";
  name = "Task Created Judge";
  type: JudgeType = "code";

  async evaluate(context: JudgeContext): Promise<JudgeResult> {
    const output = context.executionResult.output;
    let parsed: any;
    try {
      parsed = JSON.parse(output);
    } catch {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: "Could not parse agent output as JSON",
      });
    }

    const taskCount = parsed.tasks?.length ?? 0;

    if (taskCount === 0) {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: "No tasks were created from the directive",
        details: { directive_id: parsed.directive_id },
      });
    }

    return this.createResult({
      passed: true,
      score: 100,
      reasoning: `${taskCount} task(s) created successfully`,
      details: {
        taskCount,
        taskStatuses: parsed.tasks.map((t: any) => t.status),
      },
    });
  }
}

/**
 * ArtifactExistsJudge -- checks that expected files were created in the
 * sandbox worktree by the Claw-Empire agents.
 */
class ArtifactExistsJudge extends BaseJudge {
  id = "artifact-exists";
  name = "Artifact Exists Judge";
  type: JudgeType = "code";

  async evaluate(context: JudgeContext): Promise<JudgeResult> {
    const output = context.executionResult.output;
    let parsed: any;
    try {
      parsed = JSON.parse(output);
    } catch {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: "Could not parse agent output as JSON",
      });
    }

    const rawEval = getRawEvalData(context.evalCase.id);
    const expectedFiles: string[] =
      (rawEval.expectedArtifacts as string[]) ?? [];

    if (expectedFiles.length === 0) {
      return this.notApplicable("No expectedArtifacts specified");
    }

    const sandboxFiles = parsed.sandboxFiles ?? [];
    const found: string[] = [];
    const missing: string[] = [];

    for (const expected of expectedFiles) {
      const exists = sandboxFiles.some(
        (f: string) => f === expected || f.endsWith(`/${expected}`) || f.includes(expected)
      );
      if (exists) found.push(expected);
      else missing.push(expected);
    }

    const score = Math.round((found.length / expectedFiles.length) * 100);

    return this.createResult({
      passed: missing.length === 0,
      score,
      reasoning:
        missing.length === 0
          ? `All ${found.length} expected artifact(s) found`
          : `Missing artifacts: ${missing.join(", ")}`,
      details: { found, missing, allSandboxFiles: sandboxFiles },
    });
  }
}

/**
 * DepartmentRoutingJudge -- verifies that subtasks were routed to the
 * expected department (e.g. "dev", "research", "design").
 */
class DepartmentRoutingJudge extends BaseJudge {
  id = "department-routing";
  name = "Department Routing Judge";
  type: JudgeType = "code";

  async evaluate(context: JudgeContext): Promise<JudgeResult> {
    const output = context.executionResult.output;
    let parsed: any;
    try {
      parsed = JSON.parse(output);
    } catch {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: "Could not parse agent output as JSON",
      });
    }

    const rawEval = getRawEvalData(context.evalCase.id);
    const expectedDept: string | undefined =
      rawEval.expectedDepartment as string | undefined;

    if (!expectedDept) {
      return this.notApplicable("No expectedDepartment specified");
    }

    const subtasks: any[] = parsed.subtasks ?? [];
    // Also check tasks for department_id (tasks have department_id directly)
    const tasks: any[] = parsed.tasks ?? [];

    // Subtasks use target_department_id for delegation routing
    const relevantSubtasks = subtasks.filter(
      (st: any) =>
        st.target_department_id === expectedDept ||
        st.department === expectedDept ||
        st.assigned_department === expectedDept
    );

    // Tasks themselves have department_id
    const relevantTasks = tasks.filter(
      (t: any) => t.department_id === expectedDept
    );

    if (relevantSubtasks.length > 0 || relevantTasks.length > 0) {
      const total = relevantSubtasks.length + relevantTasks.length;
      return this.createResult({
        passed: true,
        score: 100,
        reasoning: `${total} item(s) routed to "${expectedDept}" department (${relevantSubtasks.length} subtask(s), ${relevantTasks.length} task(s))`,
        details: {
          expectedDept,
          subtaskIds: relevantSubtasks.map((st: any) => st.id),
          taskIds: relevantTasks.map((t: any) => t.id),
        },
      });
    }

    // Check if subtasks/tasks exist at all
    if (subtasks.length === 0 && tasks.length === 0) {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: `No subtasks or tasks found at all (expected routing to "${expectedDept}")`,
      });
    }

    const actualDepts = [
      ...new Set([
        ...subtasks.map(
          (st: any) =>
            st.target_department_id ?? st.department ?? st.assigned_department ?? "unknown"
        ),
        ...tasks.map((t: any) => t.department_id ?? "unknown"),
      ]),
    ];

    return this.createResult({
      passed: false,
      score: 25,
      reasoning: `No subtasks routed to "${expectedDept}". Found departments: ${actualDepts.join(", ")}`,
      details: { expectedDept, actualDepts },
    });
  }
}

/**
 * TaskStatusJudge -- checks that at least one task reached a given status.
 */
class TaskStatusJudge extends BaseJudge {
  id = "task-status";
  name = "Task Status Judge";
  type: JudgeType = "code";

  async evaluate(context: JudgeContext): Promise<JudgeResult> {
    const output = context.executionResult.output;
    let parsed: any;
    try {
      parsed = JSON.parse(output);
    } catch {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: "Could not parse agent output as JSON",
      });
    }

    const rawEval = getRawEvalData(context.evalCase.id);
    const expectedStatus: string =
      (rawEval.expectedTaskStatus as string) ?? "completed";
    const tasks: any[] = parsed.tasks ?? [];

    if (tasks.length === 0) {
      return this.createResult({
        passed: false,
        score: 0,
        reasoning: "No tasks found",
      });
    }

    const matching = tasks.filter((t: any) => t.status === expectedStatus);

    if (matching.length > 0) {
      return this.createResult({
        passed: true,
        score: 100,
        reasoning: `${matching.length} task(s) reached "${expectedStatus}" status`,
      });
    }

    const statuses = [...new Set(tasks.map((t: any) => t.status))];
    return this.createResult({
      passed: false,
      score: 50,
      reasoning: `No tasks reached "${expectedStatus}". Current statuses: ${statuses.join(", ")}`,
      details: { expectedStatus, actualStatuses: statuses },
    });
  }
}

// Register all custom judges
const registry = getJudgeRegistry();
const judges = [
  new TaskCreatedJudge(),
  new ArtifactExistsJudge(),
  new DepartmentRoutingJudge(),
  new TaskStatusJudge(),
];
for (const j of judges) {
  registry.register(j);
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

export default defineConfig({
  testDir: "./__evals__",
  outputDir: "./__evals__/results",

  // Claw-Empire is slow (LLM pipeline), so generous timeouts
  timeout: 240_000,
  maxRetries: 0,
  parallel: false,
  maxConcurrency: 1,
  preserveWorkspaces: true,
  verbose: true,

  judges,

  // The agent function wraps Claw-Empire's REST API
  agent: async (prompt, context): Promise<AgentResult> => {
    const start = Date.now();

    try {
      // 1. Authenticate
      const session = await getSession();

      // 2. Snapshot state BEFORE sending directive
      const filesBefore = await listSandboxFiles();
      const taskIdsBefore = await getAllTaskIds(session);
      const subtaskIdsBefore = await getAllSubtaskIds(session);

      // 3. Send directive
      const directiveRes = (await apiPost(session, "/api/directives", {
        content: prompt,
        project_id: PROJECT_ID,
      })) as any;

      const directiveId =
        directiveRes?.id ??
        directiveRes?.message?.id ??
        directiveRes?.data?.id ??
        directiveRes?.directive?.id;

      if (!directiveId) {
        return {
          output: JSON.stringify({
            error: "No directive ID returned",
            response: directiveRes,
            tasks: [],
            subtasks: [],
            sandboxFiles: [],
          }),
          success: false,
          duration: Date.now() - start,
        };
      }

      // 4. Poll for new tasks (comparing against pre-directive snapshot)
      //    Check raw eval data to decide if we need terminal state or just creation
      const rawEval = getRawEvalData(context.evalId);
      const needsArtifacts = Array.isArray(rawEval.expectedArtifacts) && rawEval.expectedArtifacts.length > 0;
      const needsRouting = typeof rawEval.expectedDepartment === "string";
      const needsTerminal = needsArtifacts || needsRouting;

      const { tasks, subtasks } = await pollForNewTasks(
        session,
        taskIdsBefore,
        subtaskIdsBefore,
        {
          timeoutMs: (context.timeout ?? 180_000) - 15_000, // Leave 15s buffer for cleanup
          waitForTerminal: needsTerminal,
          initialDelayMs: 10_000,
        }
      );

      // 5. Snapshot sandbox files AFTER
      const filesAfter = await listSandboxFiles();
      const newFiles = filesAfter.filter((f) => !filesBefore.includes(f));

      // 6. Build structured output for judges
      const result = {
        directive_id: directiveId,
        tasks,
        subtasks,
        sandboxFiles: filesAfter,
        newFiles,
        taskCount: tasks.length,
      };

      // 7. Clean up tasks so they don't pollute the next run
      const taskIds = tasks.map((t: any) => t.id).filter(Boolean);
      await cleanupTasks(session, taskIds);

      return {
        output: JSON.stringify(result, null, 2),
        success: true,
        duration: Date.now() - start,
      };
    } catch (err: any) {
      return {
        output: JSON.stringify({
          error: err.message,
          tasks: [],
          subtasks: [],
          sandboxFiles: [],
        }),
        success: false,
        error: err,
        duration: Date.now() - start,
      };
    }
  },
});
