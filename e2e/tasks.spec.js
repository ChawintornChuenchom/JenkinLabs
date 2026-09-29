// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('taskflow-lab API (E2E against Dockerized instance)', () => {
  test('list tasks', async ({ request }) => {
    const res = await request.get('/tasks');
    expect(res.status()).toBe(200);
    expect(Array.isArray(await res.json())).toBe(true);
  });

  test('create task', async ({ request }) => {
    const res = await request.post('/tasks', { data: { title: 'e2e task' } });
    expect(res.status()).toBe(201);
    const body = await res.json();
    expect(body.title).toBe('e2e task');
    expect(body.done).toBe(false);
  });

  test('mark task done', async ({ request }) => {
    const created = await request.post('/tasks', { data: { title: 'finish lab 05' } });
    const { id } = await created.json();
    const res = await request.patch(`/tasks/${id}/done`);
    expect(res.status()).toBe(200);
    const body = await res.json();
    expect(body.done).toBe(true);
  });
});
