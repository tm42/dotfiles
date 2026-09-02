// opencode → tmux, through the notifier Claude Code and Codex already use.
//
// opencode loads every file in ~/.config/opencode/plugins/ at startup, so this
// file is the whole wiring — there is no hooks file to declare and nothing to
// approve. What it does is translate the event bus into the JSON payload
// ~/.tmux/agent-notify.sh already reads on stdin:
//
//   message.updated, role user             → UserPromptSubmit  → Working
//   permission.asked / .v2.asked / .updated → PermissionRequest → Action Required
//   permission.replied / .v2.replied       → UserPromptSubmit  → Working
//   session.idle                           → Stop              → Ready
//
// A shim, not a second notifier. agent-notify.sh decides whether the pane is in
// the foreground, escapes the four things the status bar would otherwise eat,
// writes the pane-scoped notice, and raises a macOS banner only when the
// terminal is not the frontmost application. Reimplementing that here would mean
// opencode quietly missing every later fix to it, while building the payload it
// reads costs the four lines in notify().
//
// The pane title is no help: opencode publishes "OpenCode" until the session has
// a name and "OC | <session>" after that, so ~/.tmux.conf takes the name from the
// title when there is a session and from the pane's cwd before then.

import type { Plugin } from "@opencode-ai/plugin"

const NOTIFY = `${process.env.HOME}/.tmux/agent-notify.sh`

export const TmuxAgentPlugin: Plugin = async ({ $, directory }) => {
  // No pane means nothing to label, and a headless `opencode serve` would
  // otherwise raise macOS banners for a pane that does not exist. Read once, at
  // load: opencode reaches the event bus from its server process, which
  // inherits the environment of the pane that started it.
  if (!process.env.TMUX || !process.env.TMUX_PANE) return {}

  // directory, not worktree: worktree is "/" for a project that is not a git
  // checkout — measured on 1.18.20 — and the basename of "/" is nothing, which
  // reaches the status bar as "opencode w0.1   — finished" with a hole in it.
  const cwd = directory

  // Two events arrive more than once for one thing, both measured on 1.18.20:
  // message.updated fires two to four times for the user's own message, including
  // after the turn has ended, and session.idle twice about 3ms apart. Neither
  // duplicate is news and each one costs a process.
  //
  // Keyed by session, because the bus is global to the server: a subagent runs in
  // its own child session and a single flag let the child's idle stand in for the
  // parent's. A second PermissionRequest is deliberately not suppressed — that
  // one is a second approval, which is news.
  let lastPrompt: string | undefined
  const lastEvent = new Map<string, string>()

  // Sessions opencode started for a subagent. Their idle is not your turn ending.
  const children = new Set<string>()

  const notify = async (event: string, session: string, verb?: string) => {
    // Recorded before the await, not after: opencode dispatches the two idle
    // events without waiting for the first handler to return, so a flag set after
    // the shell call is still unset when the second one tests it. Measured — the
    // two invocations landed 7µs apart with the assignment at the bottom.
    lastEvent.set(session, event)
    // tool_name because the notifier reads .message, then .tool_input.description,
    // then .tool_name, then gives up on "waiting for input". Claude fills the
    // first and Codex the second; without this opencode would only ever reach the
    // fallback, and a notice that cannot say what is being asked cannot tell you
    // whether it is worth switching to.
    const payload = JSON.stringify(verb ? { hook_event_name: event, cwd, tool_name: verb }
                                        : { hook_event_name: event, cwd })
    // printf rather than echo, which eats a backslash in some shells. The
    // interpolation is one quoted argument, so a cwd with a space in it stays one
    // argument. nothrow() because a status-bar decoration must never fail a turn:
    // the notifier always exits 0 itself, and a missing symlink exits 1.
    await $`printf %s ${payload} | ${NOTIFY} opencode`.quiet().nothrow()
  }

  return {
    event: async ({ event }) => {
      // The event union's shape moves between opencode releases and Bun strips
      // these types rather than checking them, so the reads that are not in every
      // version's union are widened here rather than pinned to one.
      const type = event.type as string
      const props = (event as any).properties
      const session: string = props?.sessionID ?? props?.info?.sessionID ?? ""

      switch (type) {
        case "session.created":
          if (props?.info?.parentID) children.add(props.info.id)
          break

        case "session.idle":
          // A subagent finishing is not your turn ending, and a second idle with
          // no turn between it and the first says nothing the first did not — a
          // turn always sets Working before it can end again.
          if (children.has(session)) break
          if (lastEvent.get(session) === "Stop") break
          await notify("Stop", session)
          break

        // Three spellings for one thing, and only one of them can arrive. 1.18.20
        // emits permission.asked — 12 hits in the binary against 0 for
        // permission.updated — but its own SDK ships two event unions: the v1 one
        // declares permission.updated and no permission.asked, and v2 declares
        // both permission.asked and permission.v2.asked. Each label costs a line
        // and the alternative is a pane blocked on you that reads Working.
        // The verb is the permission name in the first two shapes and the action
        // in the v2 one; both are plain strings.
        case "permission.asked":
        case "permission.updated":
          await notify("PermissionRequest", session, props?.permission)
          break
        case "permission.v2.asked":
          await notify("PermissionRequest", session, props?.action)
          break

        // A question is not a permission. opencode has two ways to block on you and
        // they share no event: a permission asks whether a tool may run, a question
        // asks you to pick from options, and the log calls them per_ and que_. Both
        // leave the pane unable to move until you answer, so both are wait — without
        // this a question sat in the tab as "Working" and the freeze sweep in
        // status-tick.sh then retired even that after 30s of an unchanging screen,
        // leaving no state at all on the one pane that wanted you. Measured on
        // 1.18.20: question.asked, then question.replied when you choose and
        // question.rejected on Esc. Both spellings carry the same properties, unlike
        // the permission pair, so one case list covers them.
        // .header over .question because opencode declares it "very short label (max
        // 30 chars)" and the notice has 40 to spend on a verb; the first of several
        // questions stands for all of them, which is what the tab has room for.
        case "question.asked":
        case "question.v2.asked":
          await notify("PermissionRequest", session, props?.questions?.[0]?.header)
          break

        // Rejecting a question is still an answer: the tool returns the refusal and
        // the turn carries on, so the pane goes back to Working either way.
        case "question.replied":
        case "question.rejected":
        case "question.v2.replied":
        case "question.v2.rejected":
          await notify("UserPromptSubmit", session)
          break

        // Back to Working the moment you answer. Claude and Codex have no event
        // for this, so their "Action Required" stands until the turn ends — a
        // bounded lie this one does not have to tell, because answering is
        // exactly when the agent starts working again, allowed or rejected.
        case "permission.replied":
        case "permission.v2.replied":
          await notify("UserPromptSubmit", session)
          break

        case "message.updated": {
          const info = props?.info
          if (info?.role !== "user") break
          // By message id rather than by session, since the repeats are repeats of
          // one message; never deduplicated when the id is missing.
          if (info.id && info.id === lastPrompt) break
          lastPrompt = info.id
          await notify("UserPromptSubmit", session)
          break
        }
      }
    },
  }
}
