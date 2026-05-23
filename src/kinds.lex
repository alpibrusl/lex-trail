# lex-trail — Standard event kind string constants
#
# Use these zero-argument functions instead of raw string literals at
# emit sites so a typo surfaces as a "function not found" error, not a
# mystery None result during replay.
#
# User code may define additional kinds; the standard set covers the
# lex-agent / lex-llm / lex-spec platform surface.
#
# Effects: none.
# ---- A2A protocol surface ----------------------------------------

fn a2a_task_received() -> Str
  examples {
    a2a_task_received() => "a2a.task.received"
  }
{
  "a2a.task.received"
}

fn a2a_task_sent() -> Str
  examples {
    a2a_task_sent() => "a2a.task.sent"
  }
{
  "a2a.task.sent"
}

fn a2a_msg_received() -> Str
  examples {
    a2a_msg_received() => "a2a.message.received"
  }
{
  "a2a.message.received"
}

fn a2a_msg_sent() -> Str
  examples {
    a2a_msg_sent() => "a2a.message.sent"
  }
{
  "a2a.message.sent"
}

fn a2a_task_state_change() -> Str
  examples {
    a2a_task_state_change() => "a2a.task.state_change"
  }
{
  "a2a.task.state_change"
}

# ---- Capability lifecycle ----------------------------------------
fn cap_invoked() -> Str
  examples {
    cap_invoked() => "cap.invoked"
  }
{
  "cap.invoked"
}

fn cap_completed() -> Str
  examples {
    cap_completed() => "cap.completed"
  }
{
  "cap.completed"
}

fn cap_failed() -> Str
  examples {
    cap_failed() => "cap.failed"
  }
{
  "cap.failed"
}

# ---- Spec evaluation ---------------------------------------------
fn spec_allowed() -> Str
  examples {
    spec_allowed() => "spec.allowed"
  }
{
  "spec.allowed"
}

fn spec_denied() -> Str
  examples {
    spec_denied() => "spec.denied"
  }
{
  "spec.denied"
}

# ---- LLM agent loop ----------------------------------------------
fn llm_step() -> Str
  examples {
    llm_step() => "llm.step"
  }
{
  "llm.step"
}

fn human_escalated() -> Str
  examples {
    human_escalated() => "human.escalated"
  }
{
  "human.escalated"
}

fn human_replied() -> Str
  examples {
    human_replied() => "human.replied"
  }
{
  "human.replied"
}

