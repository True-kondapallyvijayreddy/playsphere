/**
 * Squad eligibility — the decision, not the Firestore around it.
 *
 * Run: `node --test functions/team_eligibility.test.mjs`
 */

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { ageOn, categoryRestricts, teamProblems } from './team_eligibility.js';

// A local midnight in India, which is how the app stores every date.
const ist = (y, m, d) => new Date(Date.UTC(y, m - 1, d) - 330 * 60 * 1000);

const u19Boys = {
  label: 'U-19 Boys',
  dimensions: ['age', 'gender'],
  maxAge: 19,
  ageCutOffDate: ist(2026, 10, 1),
  allowedGenders: ['male'],
};

const player = (name, dob, gender = 'male') => ({
  uid: name.toLowerCase().replace(/\s/g, '_'),
  name,
  dateOfBirth: dob,
  gender,
});

describe('ageOn', () => {
  test('reads IST calendar days, not UTC ones', () => {
    // Born 1 Oct 2007 IST, which is 30 Sep in UTC.
    assert.equal(ageOn(ist(2007, 10, 1), ist(2026, 10, 1)), 19);
    assert.equal(ageOn(ist(2007, 10, 2), ist(2026, 10, 1)), 18);
  });
});

describe('teamProblems', () => {
  test('a squad inside the band passes', () => {
    const squad = [player('Arjun', ist(2008, 5, 4)), player('Kiran', ist(2007, 10, 1))];
    assert.deepEqual(teamProblems(u19Boys, null, squad), []);
  });

  test('names the over-age player and their age', () => {
    const squad = [player('Arjun', ist(2008, 5, 4)), player('Ravi Kumar', ist(2006, 3, 12))];
    const problems = teamProblems(u19Boys, null, squad);
    assert.equal(problems.length, 1);
    assert.equal(problems[0].name, 'Ravi Kumar');
    assert.match(problems[0].reason, /Ravi Kumar is 20 on 01\/10\/2026/);
    assert.match(problems[0].reason, /allows 19 or under/);
  });

  test('a missing birth date fails an age-bound event', () => {
    const problems = teamProblems(u19Boys, null, [player('Sai', null)]);
    assert.equal(problems.length, 1);
    assert.match(problems[0].reason, /no date of birth/);
  });

  test('gender limits are checked too', () => {
    const problems = teamProblems(u19Boys, null, [player('Meera', ist(2009, 1, 1), 'female')]);
    assert.equal(problems.length, 1);
    assert.match(problems[0].reason, /open to Male only/);
  });

  test('senior bands check the minimum', () => {
    const senior = { label: 'Senior Men', dimensions: ['age', 'gender'], minAge: 19, allowedGenders: ['male'] };
    const problems = teamProblems(senior, ist(2026, 10, 1), [player('Dev', ist(2010, 1, 1))]);
    assert.match(problems[0].reason, /Dev is 16 .* needs 19 or over/);
  });

  test('an open event checks nothing', () => {
    const open = { label: 'Open', dimensions: ['open'] };
    assert.equal(categoryRestricts(open), false);
    assert.deepEqual(teamProblems(open, null, [player('Sai', null)]), []);
  });
});
