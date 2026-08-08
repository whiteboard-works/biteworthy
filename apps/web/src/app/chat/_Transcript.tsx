'use client';

import type { ReactElement } from 'react';
import type { ChatBlock, ChatMessage, PendingTool } from '../../lib/chat';

/** The assistant turn currently streaming, before it is persisted. */
export interface LiveTurn {
  thinking: string;
  text: string;
  tools: { name: string; ok?: boolean }[];
}

interface TranscriptProps {
  messages: ChatMessage[];
  live: LiveTurn | null;
  pending: PendingTool | null;
  busy: boolean;
  onAnswer: (approved: boolean) => void;
}

export function Transcript({
  messages,
  live,
  pending,
  busy,
  onAnswer,
}: TranscriptProps): ReactElement {
  const outcomes = toolOutcomes(messages);

  return (
    <div className="flex flex-col gap-bw-6" data-testid="chat-transcript">
      {messages.map((message) => (
        <MessageRow key={message.id} message={message} outcomes={outcomes} />
      ))}
      {live ? <LiveRow turn={live} /> : null}
      {pending ? <ConfirmPrompt tool={pending} busy={busy} onAnswer={onAnswer} /> : null}
    </div>
  );
}

/**
 * A tool call and its result arrive in different messages — the call in
 * the assistant's, the result in the tool-result message that answers it.
 * Pairing them up front lets each call render as one card.
 */
function toolOutcomes(messages: ChatMessage[]): Map<string, boolean> {
  const outcomes = new Map<string, boolean>();
  for (const message of messages) {
    for (const block of message.blocks) {
      if (block.type === 'tool_result') outcomes.set(block.tool_use_id, block.ok);
    }
  }
  return outcomes;
}

function MessageRow({
  message,
  outcomes,
}: {
  message: ChatMessage;
  outcomes: Map<string, boolean>;
}): ReactElement | null {
  // Tool results are carried on a user-role message because that is the
  // Messages API shape, not because a person typed them.
  const visible = message.blocks.filter((b) => b.type !== 'tool_result');
  if (visible.length === 0) return null;

  if (message.role === 'user') {
    const text = visible
      .filter((b): b is Extract<ChatBlock, { type: 'text' }> => b.type === 'text')
      .map((b) => b.text)
      .join('\n');
    return <UserBubble text={text} />;
  }

  return (
    <div className="flex flex-col gap-bw-2" data-testid="assistant-message">
      {visible.map((block, index) => (
        <AssistantBlock key={index} block={block} outcomes={outcomes} />
      ))}
    </div>
  );
}

function UserBubble({ text }: { text: string }): ReactElement {
  return (
    <div className="flex justify-end">
      <p
        data-testid="user-message"
        className="max-w-[85%] whitespace-pre-wrap rounded-bw-lg bg-bite px-bw-4 py-bw-3 text-bw-base text-white"
      >
        {text}
      </p>
    </div>
  );
}

function AssistantBlock({
  block,
  outcomes,
}: {
  block: ChatBlock;
  outcomes: Map<string, boolean>;
}): ReactElement | null {
  if (block.type === 'text') {
    return (
      <p className="whitespace-pre-wrap text-bw-base leading-relaxed text-zinc-800">{block.text}</p>
    );
  }
  if (block.type === 'thinking') return <Thinking text={block.text} />;
  if (block.type === 'tool_use') {
    return <ToolCard name={block.name} input={block.input} ok={outcomes.get(block.id)} />;
  }
  return null;
}

function Thinking({ text }: { text: string }): ReactElement {
  return (
    <details className="rounded-bw-md bg-zinc-50 px-bw-3 py-bw-2 text-bw-sm text-zinc-500">
      <summary className="cursor-pointer select-none">Thinking</summary>
      <p className="mt-bw-2 whitespace-pre-wrap">{text}</p>
    </details>
  );
}

/**
 * Every tool call is shown. The product's claim is that it can always say
 * why — hiding what it just did to a menu would undercut that.
 */
function ToolCard({
  name,
  input,
  ok,
  running,
}: {
  name: string;
  input?: Record<string, unknown>;
  ok?: boolean;
  running?: boolean;
}): ReactElement {
  const tone = running
    ? 'border-zinc-200 text-zinc-500'
    : ok === false
      ? 'border-danger/40 text-danger'
      : 'border-zinc-200 text-zinc-600';

  return (
    <div
      data-testid="tool-card"
      className={`rounded-bw-md border px-bw-3 py-bw-2 text-bw-sm ${tone}`}
    >
      <span className="font-medium">
        {running ? 'Running' : ok === false ? "Couldn't" : 'Did'} {humanize(name)}
      </span>
      {input && Object.keys(input).length > 0 ? (
        <details className="mt-bw-1">
          <summary className="cursor-pointer select-none text-zinc-400">Details</summary>
          <pre className="mt-bw-1 overflow-x-auto text-bw-xs text-zinc-500">
            {JSON.stringify(input, null, 2)}
          </pre>
        </details>
      ) : null}
    </div>
  );
}

function LiveRow({ turn }: { turn: LiveTurn }): ReactElement {
  return (
    <div className="flex flex-col gap-bw-2" data-testid="live-turn">
      {turn.thinking ? <Thinking text={turn.thinking} /> : null}
      {turn.tools.map((tool, index) => (
        <ToolCard key={index} name={tool.name} ok={tool.ok} running={tool.ok === undefined} />
      ))}
      {turn.text ? (
        <p className="whitespace-pre-wrap text-bw-base leading-relaxed text-zinc-800">
          {turn.text}
        </p>
      ) : null}
      {!turn.thinking && !turn.text && turn.tools.length === 0 ? (
        <p className="text-bw-sm text-zinc-400">Thinking…</p>
      ) : null}
    </div>
  );
}

/**
 * The human gate. Nothing that publishes, deletes, or changes what other
 * people are shown runs because a model decided to — the server parks the
 * call and this is where the person answers.
 */
function ConfirmPrompt({
  tool,
  busy,
  onAnswer,
}: {
  tool: PendingTool;
  busy: boolean;
  onAnswer: (approved: boolean) => void;
}): ReactElement {
  return (
    <div
      data-testid="confirm-prompt"
      className="rounded-bw-md border border-warn bg-warn/10 px-bw-4 py-bw-3"
    >
      {/* The tool's own sentence when it declared one. A generic
          "allow this?" over a JSON dump asks people to approve something
          they would have to parse to understand. */}
      <p className="text-bw-base font-medium text-zinc-900">
        {tool.prompt ?? (
          <>
            Allow this? <span className="font-bold">{humanize(tool.name)}</span>
          </>
        )}
      </p>
      {tool.prompt === null && Object.keys(tool.input ?? {}).length > 0 ? (
        <pre className="mt-bw-2 overflow-x-auto text-bw-xs text-zinc-600">
          {JSON.stringify(tool.input, null, 2)}
        </pre>
      ) : null}
      <div className="mt-bw-3 flex gap-bw-2">
        <button
          type="button"
          disabled={busy}
          onClick={() => onAnswer(true)}
          className="rounded-bw-md bg-bite px-bw-4 py-bw-2 text-bw-sm font-bold text-white hover:bg-bite-dark disabled:opacity-50"
        >
          Yes, do it
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={() => onAnswer(false)}
          className="rounded-bw-md border border-zinc-300 px-bw-4 py-bw-2 text-bw-sm font-medium text-zinc-700 hover:bg-zinc-50 disabled:opacity-50"
        >
          No
        </button>
      </div>
    </div>
  );
}

export function humanize(name: string): string {
  return name.replace(/_/g, ' ');
}
