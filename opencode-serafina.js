// OpenCode hook: stable session identity, small worker packets and live events
// for the Serafina local provider, plus the `agentd` tool that hands a
// verifiable task to the local orchestrator (any provider can call it).
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { tool } from '@opencode-ai/plugin';

const AGENTD = join(homedir(), 'bin', 'agentd');

const agentd = tool({
  description: [
    'Delegate a multi-step coding task to agentd, the local orchestrator running on the local model.',
    'It keeps working until the acceptance command exits 0 (with loop guards and fresh-context handoffs)',
    'and reports what it changed. Use it for implement/fix/refactor work that a test, build or script can verify;',
    'not for questions or exploration. Edits the project directly unless isolated is set.',
  ].join(' '),
  args: {
    goal: tool.schema.string().describe('Concrete outcome, including constraints such as "do not modify tests/"'),
    accept: tool.schema.string().describe('Shell command run in the project root; exit code 0 means the goal is met'),
    team: tool.schema.boolean().optional().describe("Plan and review with a second local model; acceptance command is required"),
    isolated: tool.schema.boolean().optional().describe('Work on a new git worktree and branch instead of the project files'),
  },
  async execute(args, ctx) {
    const dir = mkdtempSync(join(tmpdir(), 'agentd-opencode-'));
    const summaryPath = join(dir, 'summary.json');
    const argv = ['run', '--repo', ctx.directory, '--goal', args.goal, '--accept', args.accept, '--json-summary', summaryPath];
    if (args.team) argv.push("--team");
    if (!args.isolated) argv.push('--in-place');
    ctx.metadata({ title: 'agentd · starting' });
    const child = spawn(AGENTD, argv, { cwd: ctx.directory, stdio: ['ignore', 'pipe', 'pipe'] });
    const lines = [];
    const onData = (chunk) => {
      for (const line of chunk.toString().split('\n')) {
        if (!line.trim()) continue;
        lines.push(line);
        if (lines.length > 300) lines.shift();
        const round = line.match(/\[\w+ (s\d+) (r\d+)\] (.*?)(?: \| |$)/);
        if (round) ctx.metadata({ title: `agentd ${round[1]} ${round[2]} · ${round[3].slice(0, 90)}` });
        else if (/session \d+ ended/.test(line)) ctx.metadata({ title: 'agentd · ' + line.replace(/^\S+ /, '').slice(0, 90) });
      }
    };
    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    const stop = () => child.kill('SIGINT');
    ctx.abort.addEventListener('abort', stop, { once: true });
    const code = await new Promise((resolve) => {
      child.on('error', () => resolve(-1));
      child.on('close', resolve);
    });
    ctx.abort.removeEventListener('abort', stop);
    let s = null;
    try { s = JSON.parse(readFileSync(summaryPath, 'utf8')); } catch { /* reported below */ }
    rmSync(dir, { recursive: true, force: true });
    if (!s) return `agentd exited (code ${code}) without a result.\n` + lines.slice(-30).join('\n');
    const done = s.status === 'done';
    return [
      `agentd: ${s.status}${s.reason ? ` (${s.reason})` : ''} · run ${s.run_id}`,
      s.final_summary ? `Summary: ${s.final_summary}` : '',
      `Acceptance \`${args.accept}\`: ${done ? 'passed, verified by agentd' : 'not passing'}`,
      `Changes: ${s.diff || 'see the files listed in the summary'}`,
      s.branch ? `Work is on branch ${s.branch} in ${s.workspace}; review and merge it before relying on it.` : '',
      `Cost: ${s.sessions} session(s), ${s.rounds} rounds, ${s.wall_s}s.`,
      done ? '' : `Timeline: \`agentd show ${s.run_id}\`.`,
    ].filter(Boolean).join('\n');
  },
});

export const SerafinaGateway = async ({ directory, client }) => {
  const sessions = new Set();
  const agents = new Map();
  const event = async (kind, sessionID, tool = '', task = '', args = null, exitCode = null, output = '') => {
    if (!sessions.has(sessionID)) return;
    try {
      await fetch('http://127.0.0.1:8002/v1/gateway/events', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          kind,
          session_id: sessionID,
          agent_name: agents.get(sessionID) || '/root',
          tool,
          task,
          args,
          cwd: directory,
          exit_code: exitCode,
          output: typeof output === 'string' ? output.slice(0, 1000) : ''
        }),
        signal: AbortSignal.timeout(1500),
      });
    } catch { /* The provider request reports actual connection failures. */ }
  };
  return {
    tool: { agentd },
    'experimental.chat.system.transform': async (input, output) => {
      if (input.model?.providerID !== 'serafina') return;
      let enabled = false;
      try { enabled = JSON.parse(readFileSync(join(homedir(), '.local/state/mtplx-qwen38/runtime.json'), 'utf8')).agentd?.team_mode === true; } catch {}
      if (enabled) output.system.push('Local verified task mode is enabled. For implementation, bug fixes and refactoring, delegate with the agentd tool, team=true, a concrete goal and a meaningful acceptance command. Do not merely describe what you would do. Never claim completion without acceptance evidence. For questions answer normally; if no reliable acceptance can be established, ask for it.');
    },
    'chat.headers': async (input, output) => {
      if (input.model?.providerID !== 'serafina') return;
      sessions.add(input.sessionID);
      let agent = '/root';
      try {
        const response = await client.session.get({ path: { id: input.sessionID } });
        if (response.data?.parentID) {
          agent += '/' + (input.agent || 'worker');
          const parent = await client.session.get({ path: { id: response.data.parentID } });
          if (parent.data?.parentID) agent += '/nested';
        }
      } catch { /* Identity still uses the exact OpenCode session ID. */ }
      agents.set(input.sessionID, agent);
      output.headers['x-opencode-session'] = input.sessionID;
      output.headers['x-local-agent-name'] = agent;
      output.headers['x-local-cwd'] = directory;
      if (agent !== '/root') await event('child_started', input.sessionID, '', input.agent || 'worker');
    },
    'tool.execute.before': async (input, output) => {
      if (!sessions.has(input.sessionID)) return;
      if (input.tool === 'task' && typeof output.args?.prompt === 'string' && !output.args.prompt.includes('只处理本任务。')) {
        output.args.prompt += '\n只处理本任务。按需读取指定文件，返回结果、修改文件、验证证据和未解决事项。';
      }
      await event('tool_running', input.sessionID, input.tool, output.args?.description || output.args?.filePath || '', output.args);
    },
    'tool.execute.after': async (input) => {
      const exitCode = input.result?.exitCode ?? (input.error ? 1 : 0);
      const outText = input.result?.output ?? input.result?.stdout ?? (input.error ? String(input.error) : '');
      await event('tool_returned', input.sessionID, input.tool, '', null, exitCode, outText);
    },
  };
};
