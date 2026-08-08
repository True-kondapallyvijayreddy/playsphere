// One-off seed for launch-city Give collection centres.
//
// Talks to the Firestore REST API directly with a bearer token from the
// `gcloud` session already signed in as the project owner (verified with
// `gcloud auth list`), rather than firebase-admin — the Admin SDK's
// Firestore client refuses a plain access-token credential, it insists on a
// certificate or full ADC setup, neither of which exists on this machine and
// both of which are overkill for writing three documents once.
//
// Run once from this directory with:  node seed_give_centers.mjs
// Safe to re-run: each call is a PATCH (upsert), not a create.

import { execSync } from 'node:child_process';

const PROJECT_ID = 'playsphere-os';
const BASE =
  `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

const accessToken = execSync('gcloud auth print-access-token').toString().trim();

const str = (v) => ({ stringValue: v });
const num = (v) => ({ doubleValue: v });
const bool = (v) => ({ booleanValue: v });
const arr = (values) => ({ arrayValue: values.length ? { values } : {} });

const centers = [
  {
    id: 'hyderabad-hq',
    name: 'PlaySphere Give — Hyderabad Collection Centre',
    city: 'Hyderabad',
    cityKey: 'hyderabad',
    address: 'Gachibowli, Hyderabad, Telangana',
    latitude: 17.4401,
    longitude: 78.3489,
    notes: 'Launch centre — accepts every category.',
  },
  {
    id: 'bengaluru-hq',
    name: 'PlaySphere Give — Bengaluru Collection Centre',
    city: 'Bengaluru',
    cityKey: 'bengaluru',
    address: 'Koramangala, Bengaluru, Karnataka',
    latitude: 12.9352,
    longitude: 77.6146,
    notes: 'Launch centre — accepts every category.',
  },
  {
    id: 'warangal-hq',
    name: 'PlaySphere Give — Warangal Collection Centre',
    city: 'Warangal',
    cityKey: 'warangal',
    address: 'Hanamkonda, Warangal, Telangana',
    latitude: 18.0037,
    longitude: 79.5865,
    notes: 'Launch centre, closest to the rural clubs this feature is for.',
  },
];

for (const c of centers) {
  const body = {
    fields: {
      name: str(c.name),
      city: str(c.city),
      cityKey: str(c.cityKey),
      address: str(c.address),
      latitude: num(c.latitude),
      longitude: num(c.longitude),
      acceptedCategories: arr([]),
      isActive: bool(true),
      notes: str(c.notes),
    },
  };

  const res = await fetch(`${BASE}/giveCollectionCenters/${c.id}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    console.error(`Failed to seed ${c.id}: ${res.status} ${await res.text()}`);
    process.exit(1);
  }
  console.log(`Seeded ${c.id}`);
}

console.log(`Done — ${centers.length} collection centres seeded.`);
