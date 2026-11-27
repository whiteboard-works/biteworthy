import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  CLEAN_REVIEW_PHRASE,
  CODEX_GATE_CONTEXT,
  commitStatusForDecision,
  decideAutoMerge,
  extractReviewedCommit,
  freshHeadPendingStatus,
  hasP0OrP1Badge,
  inferDependabotUpdateType,
  postCommitStatus,
  shaMatches,
  statusDescription,
} from './codex-auto-merge-gate.mjs';

const HEAD = 'ffaa49c829f996eb8a211e121f913fab283ab7e7';
const OLD = '32186ef71f0647d5dc55d7bea99a7ca1ddbe5ce5';

function base(overrides = {}) {
  return {
    isDraft: false,
    baseRefName: 'master',
    headSha: HEAD,
    authorLogin: 'wbwSoftware',
    dependabotUpdateType: '',
    reviews: [],
    issueComments: [],
    reviewThreads: [],
    ...overrides,
  };
}

const cleanComment = {
  authorLogin: 'chatgpt-codex-connector',
  body: `<!-- codex-review-receipt:v1 -->\n\nCodex Review: ${CLEAN_REVIEW_PHRASE}. Hooray!\n\n**Reviewed commit:** \`ffaa49c829\`\n`,
};

const headReview = {
  authorLogin: 'chatgpt-codex-connector[bot]',
  commitOid: HEAD,
  state: 'COMMENTED',
};

test('shaMatches accepts full and prefix SHAs', () => {
  assert.equal(shaMatches(HEAD, HEAD), true);
  assert.equal(shaMatches(HEAD, 'ffaa49c829'), true);
  assert.equal(shaMatches(HEAD, OLD), false);
  assert.equal(shaMatches(HEAD, 'ffaa'), false);
});

test('extractReviewedCommit reads Codex receipt SHAs', () => {
  assert.equal(extractReviewedCommit(cleanComment.body), 'ffaa49c829');
  assert.equal(extractReviewedCommit('no sha here'), null);
});

test('hasP0OrP1Badge matches Codex severity badges only for P0/P1', () => {
  const p1 = '![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat)';
  const p0 = '![P0 Badge](https://img.shields.io/badge/P0-red?style=flat)';
  const p2 = '![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)';
  assert.equal(hasP0OrP1Badge(`**<sub><sub>${p1}</sub></sub>**`), true);
  assert.equal(hasP0OrP1Badge(p0), true);
  assert.equal(hasP0OrP1Badge(p2), false);
});

test('(a) no Codex review on head does not enable auto-merge', () => {
  const decision = decideAutoMerge(base());
  assert.equal(decision.enable, false);
  assert.match(decision.reason, /no Codex review on current head/);
});

test('(a) Codex review on an older SHA does not enable', () => {
  const decision = decideAutoMerge(
    base({
      reviews: [{ authorLogin: 'chatgpt-codex-connector', commitOid: OLD, state: 'COMMENTED' }],
      issueComments: [
        {
          authorLogin: 'chatgpt-codex-connector',
          body: `Codex Review: ${CLEAN_REVIEW_PHRASE}.\n\n**Reviewed commit:** \`32186ef71f\`\n`,
        },
      ],
    }),
  );
  assert.equal(decision.enable, false);
  assert.match(decision.reason, /no Codex review on current head/);
});

test('(b) pull_request_review on current head with no P0/P1 threads enables', () => {
  const decision = decideAutoMerge(base({ reviews: [headReview] }));
  assert.equal(decision.enable, true);
  assert.match(decision.reason, /Codex reviewed current head/);
});

test('(b) clean Codex issue comment on current head enables', () => {
  const decision = decideAutoMerge(base({ issueComments: [cleanComment] }));
  assert.equal(decision.enable, true);
  assert.match(decision.reason, /Codex reviewed current head/);
});

test('unresolved Codex P1 thread blocks even after a head review', () => {
  const decision = decideAutoMerge(
    base({
      reviews: [headReview],
      reviewThreads: [
        {
          isResolved: false,
          comments: [
            {
              authorLogin: 'chatgpt-codex-connector',
              body: '![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat) hide this',
            },
          ],
        },
      ],
    }),
  );
  assert.equal(decision.enable, false);
  assert.match(decision.reason, /unresolved Codex P0\/P1/);
});

test('resolved P1 or unresolved P2 does not block', () => {
  const resolved = decideAutoMerge(
    base({
      reviews: [headReview],
      reviewThreads: [
        {
          isResolved: true,
          comments: [
            {
              authorLogin: 'chatgpt-codex-connector',
              body: '![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat)',
            },
          ],
        },
      ],
    }),
  );
  assert.equal(resolved.enable, true);

  const p2 = decideAutoMerge(
    base({
      reviews: [headReview],
      reviewThreads: [
        {
          isResolved: false,
          comments: [
            {
              authorLogin: 'chatgpt-codex-connector',
              body: '![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)',
            },
          ],
        },
      ],
    }),
  );
  assert.equal(p2.enable, true);
});

test('(c) Dependabot patch and minor skip Codex', () => {
  const patch = decideAutoMerge(
    base({
      authorLogin: 'dependabot[bot]',
      dependabotUpdateType: 'version-update:semver-patch',
    }),
  );
  assert.equal(patch.enable, true);
  assert.match(patch.reason, /Dependabot version-update:semver-patch exemption/);

  const minor = decideAutoMerge(
    base({
      authorLogin: 'dependabot',
      dependabotUpdateType: 'version-update:semver-minor',
    }),
  );
  assert.equal(minor.enable, true);
  assert.match(minor.reason, /semver-minor/);
});

test('Dependabot patch/minor still block on unresolved Codex P0/P1 threads', () => {
  const decision = decideAutoMerge(
    base({
      authorLogin: 'dependabot[bot]',
      dependabotUpdateType: 'version-update:semver-patch',
      reviewThreads: [
        {
          isResolved: false,
          comments: [
            {
              authorLogin: 'chatgpt-codex-connector',
              body: '![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat)',
            },
          ],
        },
      ],
    }),
  );
  assert.equal(decision.enable, false);
  assert.match(decision.reason, /unresolved Codex P0\/P1/);
});

test('(c) Dependabot major still needs Codex on head', () => {
  const waiting = decideAutoMerge(
    base({
      authorLogin: 'dependabot[bot]',
      dependabotUpdateType: 'version-update:semver-major',
    }),
  );
  assert.equal(waiting.enable, false);
  assert.match(waiting.reason, /no Codex review on current head/);

  const reviewed = decideAutoMerge(
    base({
      authorLogin: 'dependabot[bot]',
      dependabotUpdateType: 'version-update:semver-major',
      reviews: [headReview],
    }),
  );
  assert.equal(reviewed.enable, true);
});

test('Dependabot without an update-type does not get the exemption', () => {
  const decision = decideAutoMerge(base({ authorLogin: 'dependabot[bot]' }));
  assert.equal(decision.enable, false);
});

test('issue_comment: empty fetch-metadata still reads Dependabot commit update-type', () => {
  // fetch-metadata needs github.event.pull_request, which issue_comment
  // does not have. The gate must recover the same update-type from the
  // Dependabot commit trailer (updated-dependencies / update-type).
  const commit = [
    'chore(deps): Bump actions/setup-node',
    '',
    '---',
    'updated-dependencies:',
    '- dependency-name: actions/setup-node',
    '  dependency-type: direct:production',
    '  update-type: version-update:semver-patch',
    '...',
    '',
    'Signed-off-by: dependabot[bot] <support@github.com>',
  ].join('\n');
  assert.equal(
    inferDependabotUpdateType('chore(deps): Bump actions/setup-node', '', [commit]),
    'version-update:semver-patch',
  );
  const decision = decideAutoMerge(
    base({
      authorLogin: 'dependabot[bot]',
      dependabotUpdateType: inferDependabotUpdateType('chore(deps): Bump actions/setup-node', '', [
        commit,
      ]),
    }),
  );
  assert.equal(decision.enable, true);
  assert.match(decision.reason, /semver-patch exemption/);
});

test('inferDependabotUpdateType reads from/to in title or body', () => {
  assert.equal(
    inferDependabotUpdateType('chore(deps): Bump puma from 8.0.2 to 8.1.2 in /apps/api', ''),
    'version-update:semver-minor',
  );
  assert.equal(
    inferDependabotUpdateType('Bump foo from 8.0.2 to 8.0.3', ''),
    'version-update:semver-patch',
  );
  assert.equal(
    inferDependabotUpdateType('Bump foo from 8.0.2 to 9.0.0', ''),
    'version-update:semver-major',
  );
  assert.equal(
    inferDependabotUpdateType(
      '',
      'Bumps [puma](https://github.com/puma/puma) from 8.0.2 to 8.1.2.',
    ),
    'version-update:semver-minor',
  );
});

test('inferDependabotUpdateType takes the highest YAML update-type in a group commit', () => {
  const commit = [
    'chore(deps): Bump the tanstack group',
    '',
    '---',
    'updated-dependencies:',
    '- dependency-name: "@tanstack/react-query"',
    '  update-type: version-update:semver-patch',
    '- dependency-name: "@tanstack/react-query-devtools"',
    '  update-type: version-update:semver-major',
    '...',
  ].join('\n');
  assert.equal(inferDependabotUpdateType('', '', [commit]), 'version-update:semver-major');
});

test('inferDependabotUpdateType takes the highest bump in a group PR', () => {
  const body = ['Bumps the tanstack group', 'from 5.108.2 to 5.108.3', 'from 5.1.0 to 6.0.0'].join(
    '\n',
  );
  assert.equal(
    inferDependabotUpdateType('Bump the tanstack group', body),
    'version-update:semver-major',
  );
  assert.equal(
    inferDependabotUpdateType('', 'from 1.0.0 to 1.0.1\nfrom 1.0.0 to 1.1.0'),
    'version-update:semver-minor',
  );
});

test('inferDependabotUpdateType is empty when there is no from/to', () => {
  assert.equal(
    inferDependabotUpdateType('chore(deps): Bump the actions group', 'digest update'),
    '',
  );
});

test('inferred patch/minor from title enables Dependabot without fetch-metadata', () => {
  const decision = decideAutoMerge(
    base({
      authorLogin: 'dependabot[bot]',
      dependabotUpdateType: inferDependabotUpdateType(
        'chore(deps): Bump puma from 8.0.2 to 8.1.2 in /apps/api',
        'Bumps [puma](https://github.com/puma/puma) from 8.0.2 to 8.1.2.',
      ),
    }),
  );
  assert.equal(decision.enable, true);
  assert.match(decision.reason, /semver-minor exemption/);
});

test('drafts and non-master bases never enable', () => {
  assert.equal(decideAutoMerge(base({ isDraft: true, reviews: [headReview] })).enable, false);
  assert.equal(decideAutoMerge(base({ baseRefName: 'main', reviews: [headReview] })).enable, false);
});

test('a non-Codex review on head is not enough', () => {
  const decision = decideAutoMerge(
    base({
      reviews: [{ authorLogin: 'cursor[bot]', commitOid: HEAD, state: 'COMMENTED' }],
    }),
  );
  assert.equal(decision.enable, false);
});

test('commitStatusForDecision: enable is success, including Dependabot patch/minor', () => {
  const reviewed = commitStatusForDecision(decideAutoMerge(base({ reviews: [headReview] })));
  assert.equal(reviewed.state, 'success');
  assert.equal(reviewed.context, CODEX_GATE_CONTEXT);
  assert.equal(reviewed.context, 'codex-gate');
  assert.match(reviewed.description, /Codex reviewed current head/);

  const dependabot = commitStatusForDecision(
    decideAutoMerge(
      base({
        authorLogin: 'dependabot[bot]',
        dependabotUpdateType: 'version-update:semver-patch',
      }),
    ),
  );
  assert.equal(dependabot.state, 'success');
  assert.match(dependabot.description, /exemption/);
});

test('commitStatusForDecision: waiting, unresolved P0/P1, drafts, and wrong base are pending not failure', () => {
  const waiting = commitStatusForDecision(decideAutoMerge(base()));
  assert.equal(waiting.state, 'pending');
  assert.equal(waiting.context, 'codex-gate');
  assert.match(waiting.description, /no Codex review on current head/);

  const p1 = commitStatusForDecision(
    decideAutoMerge(
      base({
        reviews: [headReview],
        reviewThreads: [
          {
            isResolved: false,
            comments: [
              {
                authorLogin: 'chatgpt-codex-connector',
                body: '![P1 Badge](https://img.shields.io/badge/P1-orange?style=flat)',
              },
            ],
          },
        ],
      }),
    ),
  );
  assert.equal(p1.state, 'pending');
  assert.match(p1.description, /unresolved Codex P0\/P1/);

  const draft = commitStatusForDecision(
    decideAutoMerge(base({ isDraft: true, reviews: [headReview] })),
  );
  assert.equal(draft.state, 'pending');
  assert.match(draft.description, /draft PR/);

  const wrongBase = commitStatusForDecision(
    decideAutoMerge(base({ baseRefName: 'main', reviews: [headReview] })),
  );
  assert.equal(wrongBase.state, 'pending');
  assert.notEqual(wrongBase.state, 'failure');
});

test('commitStatusForDecision: fork PRs fail closed as pending even when the gate would enable', () => {
  const decision = decideAutoMerge(base({ reviews: [headReview] }));
  assert.equal(decision.enable, true);
  const status = commitStatusForDecision(decision, { fork: true });
  assert.equal(status.state, 'pending');
  assert.equal(status.context, 'codex-gate');
  assert.match(status.description, /fork PR/);
});

test('statusDescription clips to GitHub commit-status 140-character limit', () => {
  assert.equal(statusDescription('short reason'), 'short reason');
  assert.equal(statusDescription('x'.repeat(140)).length, 140);
  const clipped = statusDescription('x'.repeat(200));
  assert.equal(clipped.length, 140);
  assert.equal(clipped.endsWith('...'), true);
});

test('freshHeadPendingStatus is pending on context codex-gate', () => {
  const status = freshHeadPendingStatus();
  assert.equal(status.state, 'pending');
  assert.equal(status.context, 'codex-gate');
  assert.match(status.description, /new head/i);
});

test('postCommitStatus POSTs context codex-gate on the given SHA', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return { ok: true, status: 201, text: async () => '', json: async () => ({}) };
  };
  await postCommitStatus(
    {
      token: 't',
      owner: 'whiteboard-works',
      repo: 'biteworthy',
      sha: HEAD,
      state: 'pending',
      description: 'waiting',
    },
    fetchImpl,
  );
  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    `https://api.github.com/repos/whiteboard-works/biteworthy/statuses/${HEAD}`,
  );
  assert.equal(calls[0].init.method, 'POST');
  const body = JSON.parse(calls[0].init.body);
  assert.equal(body.context, 'codex-gate');
  assert.equal(body.state, 'pending');
  assert.equal(body.description, 'waiting');
});

test('workflow marks the new head pending before checkout and grants statuses: write', () => {
  const yaml = readFileSync(new URL('../workflows/auto-merge.yml', import.meta.url), 'utf8');
  assert.match(yaml, /statuses:\s*write/);

  const gateStart = yaml.indexOf('\n  gate:');
  assert.ok(gateStart >= 0, 'gate job is present');
  const gateYaml = yaml.slice(gateStart);
  const markPending = gateYaml.indexOf('Mark new head pending');
  const gateCheckout = gateYaml.indexOf('uses: actions/checkout@v7');
  assert.ok(markPending >= 0, 'gate job marks the new head pending');
  assert.ok(
    markPending < gateCheckout,
    'pending status on the new head must be the first mutating step, before checkout',
  );
  assert.match(gateYaml, /context=codex-gate/);
  assert.match(gateYaml, /state=pending/);
});
