#!/usr/bin/env node
/**
 * Decides whether auto-merge.yml may enable GitHub auto-merge.
 *
 * Enable only when Codex (chatgpt-codex-connector) has reviewed the current
 * head SHA and no unresolved P0/P1 Codex threads remain — except Dependabot
 * patch/minor bumps, which may skip the Codex wait.
 *
 * This file is fetched from the default branch on pull_request_target (the
 * workflow checks out github.sha, not the PR head).
 */

import { appendFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { pathToFileURL } from 'node:url';

export const CODEX_LOGIN = 'chatgpt-codex-connector';
export const DEPENDABOT_LOGIN = 'dependabot';
export const CLEAN_REVIEW_PHRASE = "Didn't find any major issues";
export const REQUIRED_BASE = 'master';
export const EXEMPT_DEPENDABOT_UPDATE_TYPES = new Set([
  'version-update:semver-patch',
  'version-update:semver-minor',
]);

const P0_P1_BADGE = /!\[P[01] Badge\]/i;
const REVIEWED_COMMIT = /\*\*Reviewed commit:\*\*\s*`([0-9a-f]{7,40})`/i;
const BUMP_RANK = { major: 3, minor: 2, patch: 1 };

export function normalizeLogin(login) {
  return String(login || '')
    .toLowerCase()
    .replace(/\[bot\]$/, '');
}

export function isCodexLogin(login) {
  return normalizeLogin(login) === CODEX_LOGIN;
}

export function shaMatches(headSha, candidate) {
  if (!headSha || !candidate) return false;
  const a = String(headSha).toLowerCase();
  const b = String(candidate).toLowerCase();
  if (b.length < 7) return false;
  return a === b || a.startsWith(b) || b.startsWith(a);
}

export function extractReviewedCommit(body) {
  const match = String(body || '').match(REVIEWED_COMMIT);
  return match ? match[1] : null;
}

export function hasP0OrP1Badge(body) {
  return P0_P1_BADGE.test(String(body || ''));
}

function versionCore(value) {
  const match = String(value || '').match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!match) return null;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

function bumpKind(from, to) {
  const a = versionCore(from);
  const b = versionCore(to);
  if (!a || !b) return null;
  if (b[0] !== a[0]) return 'major';
  if (b[1] !== a[1]) return 'minor';
  if (b[2] !== a[2]) return 'patch';
  return null;
}

function highestUpdateType(kinds) {
  let worst = null;
  for (const kind of kinds) {
    if (!kind || !BUMP_RANK[kind]) continue;
    if (!worst || BUMP_RANK[kind] > BUMP_RANK[worst]) worst = kind;
  }
  return worst ? `version-update:semver-${worst}` : '';
}

/**
 * Same `update-type` fetch-metadata reads from a Dependabot commit trailer
 * (`updated-dependencies` / `update-type: version-update:semver-*`).
 */
export function updateTypeFromDependabotCommit(message) {
  return inferDependabotUpdateType('', '', [message]);
}

/**
 * Infer Dependabot fetch-metadata `update-type` when the action cannot run
 * (issue_comment / review events have no pull_request payload). Prefers the
 * commit trailer (same source as fetch-metadata), then `from X to Y` in the
 * title, body, or commit messages. Group PRs take the highest bump.
 *
 * @returns {'' | 'version-update:semver-patch' | 'version-update:semver-minor' | 'version-update:semver-major'}
 */
export function inferDependabotUpdateType(title, body, commitMessages = []) {
  const yamlKinds = [];
  for (const message of commitMessages || []) {
    for (const match of String(message || '').matchAll(
      /^\s*update-type:\s*(version-update:semver-(major|minor|patch))\s*$/gm,
    )) {
      yamlKinds.push(match[2]);
    }
  }
  const fromYaml = highestUpdateType(yamlKinds);
  if (fromYaml) return fromYaml;

  const text = [title, body, ...(commitMessages || [])].filter(Boolean).join('\n');
  const kinds = [];
  for (const match of text.matchAll(
    /\bfrom\s+v?(\d+\.\d+\.\d+[0-9A-Za-z.-]*)\s+to\s+v?(\d+\.\d+\.\d+[0-9A-Za-z.-]*)/gi,
  )) {
    kinds.push(bumpKind(match[1], match[2]));
  }
  return highestUpdateType(kinds);
}

function hasCodexReviewOnHead(headSha, reviews) {
  return (reviews || []).some(
    (review) =>
      isCodexLogin(review.authorLogin) &&
      review.state !== 'PENDING' &&
      shaMatches(headSha, review.commitOid),
  );
}

function hasCleanCodexCommentOnHead(headSha, issueComments) {
  return (issueComments || []).some((comment) => {
    if (!isCodexLogin(comment.authorLogin)) return false;
    if (!String(comment.body || '').includes(CLEAN_REVIEW_PHRASE)) return false;
    return shaMatches(headSha, extractReviewedCommit(comment.body));
  });
}

function unresolvedP0P1Threads(reviewThreads) {
  return (reviewThreads || []).filter((thread) => {
    if (thread.isResolved) return false;
    return (thread.comments || []).some(
      (comment) => isCodexLogin(comment.authorLogin) && hasP0OrP1Badge(comment.body),
    );
  });
}

/**
 * @param {object} input
 * @returns {{ enable: boolean, reason: string }}
 */
export function decideAutoMerge(input) {
  const isDraft = Boolean(input.isDraft);
  const baseRefName = input.baseRefName || '';
  const headSha = input.headSha || '';
  const authorLogin = input.authorLogin || '';
  const updateType = input.dependabotUpdateType || '';

  if (isDraft) {
    return { enable: false, reason: 'draft PR' };
  }
  if (baseRefName !== REQUIRED_BASE) {
    return { enable: false, reason: `base is ${baseRefName || '(empty)'}, not ${REQUIRED_BASE}` };
  }

  const blockers = unresolvedP0P1Threads(input.reviewThreads);
  if (blockers.length > 0) {
    return {
      enable: false,
      reason: `${blockers.length} unresolved Codex P0/P1 review thread(s)`,
    };
  }

  if (
    normalizeLogin(authorLogin) === DEPENDABOT_LOGIN &&
    EXEMPT_DEPENDABOT_UPDATE_TYPES.has(updateType)
  ) {
    return { enable: true, reason: `Dependabot ${updateType} exemption` };
  }

  const reviewedHead =
    hasCodexReviewOnHead(headSha, input.reviews) ||
    hasCleanCodexCommentOnHead(headSha, input.issueComments);
  if (!reviewedHead) {
    return {
      enable: false,
      reason: 'no Codex review on current head (waiting; fail closed)',
    };
  }

  return { enable: true, reason: 'Codex reviewed current head; no unresolved P0/P1 threads' };
}

async function githubGraphql(token, query, variables) {
  const response = await fetch('https://api.github.com/graphql', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'User-Agent': 'biteworthy-codex-auto-merge-gate',
    },
    body: JSON.stringify({ query, variables }),
  });
  const payload = await response.json();
  if (!response.ok || payload.errors) {
    const detail = JSON.stringify(payload.errors || payload, null, 2);
    throw new Error(`GitHub GraphQL error: ${detail}`);
  }
  return payload.data;
}

export async function loadPullRequestState({ token, owner, repo, number }) {
  const data = await githubGraphql(
    token,
    `
      query ($owner: String!, $name: String!, $number: Int!) {
        repository(owner: $owner, name: $name) {
          pullRequest(number: $number) {
            id
            number
            isDraft
            baseRefName
            headRefOid
            title
            body
            author { login }
            commits(first: 20) {
              nodes { commit { message } }
            }
          }
        }
      }
    `,
    { owner, name: repo, number: Number(number) },
  );
  const pull = data.repository?.pullRequest;
  if (!pull) {
    throw new Error(`PR ${owner}/${repo}#${number} not found`);
  }

  const reviews = [];
  const issueComments = [];
  const reviewThreads = [];

  let after = null;
  for (;;) {
    const page = await githubGraphql(
      token,
      `
        query ($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviews(first: 100, after: $after) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  state
                  author { login }
                  commit { oid }
                }
              }
            }
          }
        }
      `,
      { owner, name: repo, number: Number(number), after },
    );
    const connection = page.repository.pullRequest.reviews;
    reviews.push(...connection.nodes);
    if (!connection.pageInfo.hasNextPage) break;
    after = connection.pageInfo.endCursor;
  }

  after = null;
  for (;;) {
    const page = await githubGraphql(
      token,
      `
        query ($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              comments(first: 100, after: $after) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  author { login }
                  body
                }
              }
            }
          }
        }
      `,
      { owner, name: repo, number: Number(number), after },
    );
    const connection = page.repository.pullRequest.comments;
    issueComments.push(...connection.nodes);
    if (!connection.pageInfo.hasNextPage) break;
    after = connection.pageInfo.endCursor;
  }

  after = null;
  for (;;) {
    const page = await githubGraphql(
      token,
      `
        query ($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 50, after: $after) {
                pageInfo { hasNextPage endCursor }
                nodes {
                  isResolved
                  comments(first: 20) {
                    nodes {
                      author { login }
                      body
                    }
                  }
                }
              }
            }
          }
        }
      `,
      { owner, name: repo, number: Number(number), after },
    );
    const connection = page.repository.pullRequest.reviewThreads;
    reviewThreads.push(...connection.nodes);
    if (!connection.pageInfo.hasNextPage) break;
    after = connection.pageInfo.endCursor;
  }

  return {
    id: pull.id,
    number: pull.number,
    isDraft: pull.isDraft,
    baseRefName: pull.baseRefName,
    headSha: pull.headRefOid,
    title: pull.title || '',
    body: pull.body || '',
    authorLogin: pull.author?.login || '',
    commitMessages: (pull.commits?.nodes || []).map((node) => node.commit?.message || ''),
    reviews: reviews.map((review) => ({
      authorLogin: review.author?.login || '',
      commitOid: review.commit?.oid || '',
      state: review.state,
    })),
    issueComments: issueComments.map((comment) => ({
      authorLogin: comment.author?.login || '',
      body: comment.body || '',
    })),
    reviewThreads: reviewThreads.map((thread) => ({
      isResolved: thread.isResolved,
      comments: (thread.comments?.nodes || []).map((comment) => ({
        authorLogin: comment.author?.login || '',
        body: comment.body || '',
      })),
    })),
  };
}

export function formatDecision(state, decision) {
  return {
    enable: decision.enable,
    reason: decision.reason,
    number: state.number,
    headSha: state.headSha,
    authorLogin: state.authorLogin,
    baseRefName: state.baseRefName,
    isDraft: state.isDraft,
  };
}

function writeGithubOutput(path, decision) {
  if (!path) return;
  appendFileSync(path, `enable=${decision.enable}\n`);
  appendFileSync(path, `reason<<EOF\n${decision.reason}\nEOF\n`);
}

export async function main(argv = process.argv.slice(2), env = process.env) {
  const { values } = parseArgs({
    args: argv,
    options: {
      owner: { type: 'string' },
      repo: { type: 'string' },
      pr: { type: 'string' },
      'update-type': { type: 'string', default: '' },
      'github-output': { type: 'string', default: '' },
    },
  });

  const repoSlug = env.GITHUB_REPOSITORY || '';
  const [defaultOwner, defaultRepo] = repoSlug.split('/');
  const owner = values.owner || defaultOwner;
  const repo = values.repo || defaultRepo;
  const number = values.pr || env.PR_NUMBER;
  const token = env.GITHUB_TOKEN || env.GH_TOKEN;
  if (!owner || !repo || !number) {
    throw new Error('usage: codex-auto-merge-gate.mjs --owner <org> --repo <name> --pr <n>');
  }
  if (!token) {
    throw new Error('GITHUB_TOKEN (or GH_TOKEN) is required');
  }

  const state = await loadPullRequestState({ token, owner, repo, number });
  const providedType = values['update-type'] || env.DEPENDABOT_UPDATE_TYPE || '';
  const inferredType =
    !providedType && normalizeLogin(state.authorLogin) === DEPENDABOT_LOGIN
      ? inferDependabotUpdateType(state.title, state.body, state.commitMessages)
      : '';
  const decision = decideAutoMerge({
    ...state,
    dependabotUpdateType: providedType || inferredType,
  });
  const result = formatDecision(state, decision);
  console.log(JSON.stringify(result, null, 2));
  writeGithubOutput(values['github-output'] || env.GITHUB_OUTPUT, decision);
  return result;
}

const isCli = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isCli) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}
