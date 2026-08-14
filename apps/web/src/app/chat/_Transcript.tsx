'use client';

import { useState, type ReactElement } from 'react';
import type { ChatBlock, ChatMessage, PendingQuestion, PendingTool } from '../../lib/chat';
import { Markdown } from './_Markdown';

/** The assistant turn currently streaming, before it is persisted. */
export interface LiveTurn {
  thinking: string;
  text: string;
  tools: { name: string; ok?: boolean; doing?: string | null }[];
}

interface TranscriptProps {
  messages: ChatMessage[];
  live: LiveTurn | null;
  pending: PendingTool | null;
  question: PendingQuestion | null;
  onAnswerQuestion: (answer: { optionId?: string; text?: string }) => void;
  busy: boolean;
  /** Tool cards and their timestamps. Default on — see `useToolVisibility`. */
  showTools: boolean;
  onAnswer: (approved: boolean) => void;
}

export function Transcript({
  messages,
  live,
  pending,
  question,
  busy,
  showTools,
  onAnswer,
  onAnswerQuestion,
}: TranscriptProps): ReactElement {
  const outcomes = toolOutcomes(messages);

  return (
    <div className="flex flex-col gap-bw-6" data-testid="chat-transcript">
      {messages.map((message) => (
        <MessageRow key={message.id} message={message} outcomes={outcomes} showTools={showTools} />
      ))}
      {live ? <LiveRow turn={live} showTools={showTools} /> : null}
      {pending ? <ConfirmPrompt tool={pending} busy={busy} onAnswer={onAnswer} /> : null}
      {question ? (
        <QuestionPrompt question={question} busy={busy} onAnswer={onAnswerQuestion} />
      ) : null}
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
  showTools,
}: {
  message: ChatMessage;
  outcomes: Map<string, boolean>;
  showTools: boolean;
}): ReactElement | null {
  // Tool results are carried on a user-role message because that is the
  // Messages API shape, not because a person typed them.
  const visible = message.blocks
    .filter((b) => b.type !== 'tool_result')
    .filter((b) => showTools || b.type !== 'tool_use');
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
        <AssistantBlock key={index} block={block} outcomes={outcomes} at={message.created_at} />
      ))}
    </div>
  );
}

/**
 * Shown beside tool cards only, and only when tools are shown.
 *
 * A timestamp on every bubble is noise in a conversation you are having;
 * it earns its place next to the machinery, where the question is "when
 * did it do that" — and it is the tool view that gets read after the
 * fact, on a conversation reopened days later.
 */
function Timestamp({ at }: { at: string | undefined }): ReactElement | null {
  if (!at) return null;
  const when = new Date(at);
  if (Number.isNaN(when.getTime())) return null;

  return (
    <time dateTime={at} title={when.toLocaleString()} className="text-bw-xs text-zinc-400">
      {when.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
    </time>
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
  at,
}: {
  block: ChatBlock;
  outcomes: Map<string, boolean>;
  at?: string;
}): ReactElement | null {
  // Markdown, because the model writes it whether or not anything renders
  // it — lists, tables and emphasis were reaching people as asterisks.
  // The user's own bubble stays plain text: they typed what they typed.
  if (block.type === 'text') return <Markdown text={block.text} />;
  if (block.type === 'thinking') return <Thinking text={block.text} />;
  if (block.type === 'tool_use') {
    return <ToolCard name={block.name} input={block.input} ok={outcomes.get(block.id)} at={at} />;
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
  doing,
  at,
}: {
  name: string;
  input?: Record<string, unknown>;
  ok?: boolean;
  running?: boolean;
  /** When the message carrying this call was stored. */
  at?: string;
  /** The tool's own sentence, when it declared one. Never model-supplied —
   *  this is the only thing a person can read while a turn is working, so
   *  it says what is happening rather than what the model intends. */
  doing?: string | null;
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
      <span className="flex items-baseline justify-between gap-bw-2 font-medium">
        <span>
          {doing ? (
            running ? (
              <>{doing}…</>
            ) : ok === false ? (
              <>Could not: {doing.toLowerCase()}</>
            ) : (
              doing
            )
          ) : (
            <>
              {running ? 'Running' : ok === false ? "Couldn't" : 'Did'} {humanize(name)}
            </>
          )}
        </span>
        <Timestamp at={at} />
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

function LiveRow({ turn, showTools }: { turn: LiveTurn; showTools: boolean }): ReactElement {
  return (
    <div className="flex flex-col gap-bw-2" data-testid="live-turn">
      {turn.thinking ? <Thinking text={turn.thinking} /> : null}
      {showTools
        ? turn.tools.map((tool, index) => (
            <ToolCard
              key={index}
              name={tool.name}
              ok={tool.ok}
              doing={tool.doing}
              running={tool.ok === undefined}
            />
          ))
        : null}
      {/* Rendered as markdown while it streams too. A half-arrived list
          renders as a shorter list rather than as raw asterisks that
          rearrange themselves when the turn lands. */}
      {turn.text ? <Markdown text={turn.text} /> : null}
      {!turn.thinking && !turn.text && (!showTools || turn.tools.length === 0) ? (
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
// Real options rather than a sentence to reply to. The point is that
// what comes back is an id the server itself wrote down, so nothing
// downstream rests on the model reading "the first one" correctly.
function QuestionPrompt({
  question,
  busy,
  onAnswer,
}: {
  question: PendingQuestion;
  busy: boolean;
  onAnswer: (answer: { optionId?: string; text?: string }) => void;
}): ReactElement {
  const [typed, setTyped] = useState('');

  return (
    <div
      data-testid="question-prompt"
      className="rounded-bw-md border border-zinc-300 bg-zinc-50 px-bw-4 py-bw-3"
    >
      <p className="text-bw-base font-medium text-zinc-900">{question.question}</p>
      <div className="mt-bw-3 flex flex-col gap-bw-2">
        {question.options.map((option) => (
          <button
            key={option.id}
            type="button"
            disabled={busy}
            onClick={() => onAnswer({ optionId: option.id })}
            className="rounded-bw-sm border border-zinc-300 px-bw-3 py-bw-2 text-left text-bw-sm hover:bg-white disabled:opacity-50"
          >
            <span className="font-medium">{option.label}</span>
            {option.detail ? (
              <span className="block text-bw-xs text-zinc-600">{option.detail}</span>
            ) : null}
          </button>
        ))}
      </div>
      {/* Always available. An option list that misses the obvious answer
          is worse than no options at all. */}
      <form
        className="mt-bw-3 flex gap-bw-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (typed.trim()) onAnswer({ text: typed.trim() });
        }}
      >
        <input
          type="text"
          value={typed}
          onChange={(e) => setTyped(e.target.value)}
          disabled={busy}
          aria-label="Something else"
          placeholder="Something else…"
          className="flex-1 rounded-bw-sm border border-zinc-300 px-bw-2 py-bw-1 text-bw-sm"
        />
        <button
          type="submit"
          disabled={busy || !typed.trim()}
          className="rounded-bw-sm border border-zinc-300 px-bw-3 py-bw-1 text-bw-sm disabled:opacity-50"
        >
          Send
        </button>
      </form>
    </div>
  );
}

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
